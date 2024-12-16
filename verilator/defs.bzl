# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Original implementation by Kevin Kiningham (@kkiningh) in kkiningh/rules_verilator.
# Ported to bazel_rules_hdl by Stephen Tridgell (@stridge-cruxml)

"""Functions for verilator."""

load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load("@rules_cc//cc:defs.bzl", "CcInfo")
load("//common:providers.bzl", "LogInfo", "WaveformInfo")
load("//verilog:defs.bzl", "VerilogInfo")
load("providers.bzl", "RawCoverageInfo", "VerilatedBinaryInfo")

def cc_compile(ctx, srcs, hdrs, deps, includes = [], defines = []):
    """Compile C++ sources

    Args:
        ctx: Context for rule
        srcs: The cpp sources generated by verilator.
        hdrs: The headers generated by verilator.
        deps: Library dependencies to build with.
        includes: The includes for the verilator module to build.
        defines: Cpp defines to build with.

    Returns:
        A tuple with: toolchain, feature configuration, CompilationContext list
        and compilation outputs list.
    """

    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    compilation_contexts = [dep[CcInfo].compilation_context for dep in deps]
    compilation_context, compilation_outputs = cc_common.compile(
        name = ctx.label.name,
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = ctx.attr.copts,
        srcs = srcs,
        includes = includes,
        defines = defines,
        public_hdrs = hdrs,
        compilation_contexts = compilation_contexts,
    )

    return cc_toolchain, feature_configuration, compilation_context, compilation_outputs

def cc_compile_and_link_static_library(ctx, srcs, hdrs, deps, runfiles, includes = [], defines = []):
    """Compile and link C++ source into a static library

    Args:
        ctx: Context for rule
        srcs: The cpp sources generated by verilator.
        hdrs: The headers generated by verilator.
        deps: Library dependencies to build with.
        runfiles: Data dependencies that are read at runtime.
        includes: The includes for the verilator module to build.
        defines: Cpp defines to build with.

    Returns:
        CCInfo with the compiled library.
    """
    cc_toolchain, feature_configuration, compilation_context, compilation_outputs = cc_compile(
        ctx,
        srcs,
        hdrs,
        deps,
        includes,
        defines,
    )

    linking_contexts = [dep[CcInfo].linking_context for dep in deps]
    linking_context, linking_output = cc_common.create_linking_context_from_compilation_outputs(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = compilation_outputs,
        linking_contexts = linking_contexts,
        name = ctx.label.name,
        disallow_dynamic_library = True,
    )

    output_files = []
    if linking_output.library_to_link.static_library != None:
        output_files.append(linking_output.library_to_link.static_library)
    if linking_output.library_to_link.dynamic_library != None:
        output_files.append(linking_output.library_to_link.dynamic_library)

    return [
        DefaultInfo(
            files = depset(output_files),
            runfiles = ctx.runfiles(files = runfiles),
        ),
        CcInfo(
            compilation_context = compilation_context,
            linking_context = linking_context,
        ),
    ]

def cc_compile_and_link_binary(ctx, srcs, hdrs, deps, runfiles, includes = [], defines = []):
    """Compile and link C++ source into a binary executable

    Args:
        ctx: Context for rule
        srcs: The cpp sources generated by verilator.
        hdrs: The headers generated by verilator.
        deps: Library dependencies to build with.
        runfiles: Data dependencies that are read at runtime.
        includes: The includes for the verilator module to build.
        defines: Cpp defines to build with.

    Returns:
        CCInfo with the compiled binary.
    """
    cc_toolchain, feature_configuration, _, compilation_outputs = cc_compile(
        ctx,
        srcs,
        hdrs,
        deps,
        includes,
        defines,
    )

    linking_contexts = [dep[CcInfo].linking_context for dep in deps]
    linking_output = cc_common.link(
        actions = ctx.actions,
        name = ctx.label.name,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = compilation_outputs,
        linking_contexts = linking_contexts,
    )

    return [
        DefaultInfo(
            executable = linking_output.executable,
            runfiles = ctx.runfiles(files = runfiles),
        ),
    ]

_CPP_SRC = ["cc", "cpp", "cxx", "c++"]
_HPP_SRC = ["h", "hh", "hpp"]
_RUNFILES = ["dat", "mem"]

def _only_cpp(f):
    """Filter for just C++ source/headers"""
    if f.extension in _CPP_SRC + _HPP_SRC:
        return f.path
    return None

def _only_hpp(f):
    """Filter for just C++ headers"""
    if f.extension in _HPP_SRC:
        return f.path
    return None

def _copy_action(ctx, suffix, files, map_each):
    dir = ctx.actions.declare_directory(ctx.label.name + suffix)

    args = ctx.actions.args()
    args.add_all(files, map_each = map_each)
    args.add(dir.path)
    ctx.actions.run(
        mnemonic = "VerilatorCopyTree",
        arguments = [args],
        inputs = files,
        outputs = [dir],
        executable = ctx.executable._copy_tree,
    )

    return dir

def _verilator_toolchain_env(toolchain):
    root_files = toolchain.root.files.to_list()
    if len(root_files) != 1:
        fail("It's expected to have only one File (path to directory) as the root attribute of VerilatorToolchain")

    return {
        "VERILATOR_ROOT": root_files[0].path,
    }

def _verilator_args(ctx, srcs, vopts = []):
    """Given a depset of input files to Verilator returns invocation arguments and list of source, header and run files.
    """
    verilator_toolchain = ctx.toolchains["@rules_hdl//verilator:toolchain_type"]

    # Get sources and headers
    all_srcs = [verilog_info_struct.srcs for verilog_info_struct in srcs]
    all_hdrs = [verilog_info_struct.hdrs for verilog_info_struct in srcs]
    all_data = [verilog_info_struct.data for verilog_info_struct in srcs]

    all_files = [src for sub_tuple in (all_srcs + all_data) for src in sub_tuple]
    all_hdrs = [hdr for sub_tuple in all_hdrs for hdr in sub_tuple]

    # Filter out .dat files.
    runfiles = []
    verilog_files = []
    for file in all_files:
        if file.extension in _RUNFILES:
            runfiles.append(file)
        else:
            verilog_files.append(file)

    # Include directories
    include_dirs = depset([f.dirname for f in (verilog_files + all_hdrs)]).to_list()

    # Args
    args = ctx.actions.args()
    args.add_all(vopts)
    args.add_all(verilator_toolchain.extra_vopts)
    args.add_all(ctx.attr.vopts, expand_directories = False)

    for pth in include_dirs:
        args.add("-I" + pth)

    for verilog_file in verilog_files:
        args.add(verilog_file.path)

    # Return args, sources, headers and runfiles
    return args, verilog_files, all_hdrs, runfiles

def _verilator_cc(ctx, opts = []):
    verilator_toolchain = ctx.toolchains["@rules_hdl//verilator:toolchain_type"]

    # Sources
    srcs = depset([], transitive = [ctx.attr.module[VerilogInfo].dag]).to_list()

    output = ctx.actions.declare_directory(ctx.label.name + "-gen")
    prefix = "V" + ctx.attr.module_top

    # Options
    vopts = list(opts)

    vopts.extend(["--cc"])
    vopts.extend(["--Mdir", output.path])
    vopts.extend(["--top-module", ctx.attr.module_top])
    vopts.extend(["--prefix", prefix])

    if ctx.attr.trace:
        vopts.extend(["--trace"])

    if ctx.attr.coverage == "all":
        vopts.extend(["--coverage"])
    if ctx.attr.coverage == "line":
        vopts.extend(["--coverage-line"])
    if ctx.attr.coverage == "toggle":
        vopts.extend(["--coverage-toggle"])

    # Assemble Verilator args
    args, vlog_srcs, vlog_hdrs, runfiles = _verilator_args(ctx, srcs, vopts)

    # Run the action
    ctx.actions.run(
        arguments = [args],
        mnemonic = "VerilatorCompile",
        executable = verilator_toolchain.verilator,
        tools = verilator_toolchain.all_files,
        env = _verilator_toolchain_env(verilator_toolchain),
        inputs = vlog_srcs + vlog_hdrs,
        outputs = [output],
        progress_message = "[Verilator] Compiling {}".format(ctx.label),
    )

    # Copy
    copy_input = depset([output], transitive = [verilator_toolchain.shared[DefaultInfo].files])

    verilator_output_cpp = _copy_action(ctx, "_cpp", copy_input, _only_cpp)
    verilator_output_hpp = _copy_action(ctx, "_h", copy_input, _only_hpp)

    return verilator_output_cpp, verilator_output_hpp, runfiles

# Options from verilator/include/verilated.mk
_VERILATOR_DEFAULT_COPTS = [
    "-std=gnu++20",
    "-faligned-new",
    "-fcf-protection=none",
    "-Wno-bool-operation",
    "-Wno-shadow",
    "-Wno-sign-compare",
    "-Wno-tautological-compare",
    "-Wno-uninitialized",
    "-Wno-unused-but-set-parameter",
    "-Wno-unused-but-set-variable",
    "-Wno-unused-parameter",
    "-Wno-unused-variable",
    "-Wextra",
    "-Wfloat-conversion",
    "-Wlogical-op",
]

def _verilator_cc_library(ctx):
    verilator_toolchain = ctx.toolchains["@rules_hdl//verilator:toolchain_type"]

    # Do verilation
    verilator_output_cpp, verilator_output_hpp, runfiles = _verilator_cc(ctx)

    # Do actual compile
    defines = ["VM_TRACE"] if ctx.attr.trace else []

    return cc_compile_and_link_static_library(
        ctx,
        srcs = [verilator_output_cpp],
        hdrs = [verilator_output_hpp],
        defines = defines,
        runfiles = runfiles,
        includes = [verilator_output_hpp.path],
        deps = verilator_toolchain.deps,
    )

verilator_cc_library = rule(
    implementation = _verilator_cc_library,
    attrs = {
        "copts": attr.string_list(
            doc = "List of additional compilation flags",
            default = _VERILATOR_DEFAULT_COPTS,
        ),
        "coverage": attr.string(
            doc = "Enable coverage collection",
            default = "none",
            values = ["none", "all", "line", "toggle"],
        ),
        "module": attr.label(
            doc = "The top level module target to verilate.",
            providers = [VerilogInfo],
            mandatory = True,
        ),
        "module_top": attr.string(
            doc = "The name of the verilog module to verilate.",
            mandatory = True,
        ),
        "trace": attr.bool(
            doc = "Enable tracing for Verilator",
            default = False,
        ),
        "vopts": attr.string_list(
            doc = "Additional command line options to pass to Verilator",
            default = ["-Wall"],
        ),
        "_cc_toolchain": attr.label(
            doc = "CC compiler.",
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
        "_copy_tree": attr.label(
            doc = "A tool for copying a tree of files",
            cfg = "exec",
            executable = True,
            default = Label("//common:copy_tree"),
        ),
    },
    provides = [
        CcInfo,
        DefaultInfo,
    ],
    toolchains = [
        "@bazel_tools//tools/cpp:toolchain_type",
        "@rules_hdl//verilator:toolchain_type",
    ],
    fragments = ["cpp"],
)

def _verilator_cc_binary(ctx):
    verilator_toolchain = ctx.toolchains["@rules_hdl//verilator:toolchain_type"]

    # Do verilation
    verilator_output_cpp, verilator_output_hpp, runfiles = _verilator_cc(
        ctx,
        opts = ["--main"],
    )

    # Do actual compile
    defines = ["VM_TRACE"] if ctx.attr.trace else []

    if ctx.attr.coverage != "none":
        defines.append("VM_COVERAGE")

    result = cc_compile_and_link_binary(
        ctx,
        srcs = [verilator_output_cpp],
        hdrs = [verilator_output_hpp],
        defines = defines,
        runfiles = runfiles,
        includes = [verilator_output_hpp.path],
        deps = verilator_toolchain.deps,
    )

    return result + [VerilatedBinaryInfo(coverage = ctx.attr.coverage, trace = ctx.attr.trace)]

verilator_cc_binary = rule(
    implementation = _verilator_cc_binary,
    attrs = {
        "copts": attr.string_list(
            doc = "List of additional compilation flags",
            default = _VERILATOR_DEFAULT_COPTS,
        ),
        "coverage": attr.string(
            doc = "Enable coverage collection",
            default = "none",
            values = ["none", "all", "line", "toggle"],
        ),
        "module": attr.label(
            doc = "The top level module target to verilate.",
            providers = [VerilogInfo],
            mandatory = True,
        ),
        "module_top": attr.string(
            doc = "The name of the verilog module to verilate.",
            mandatory = True,
        ),
        "trace": attr.bool(
            doc = "Enable tracing for Verilator",
            default = False,
        ),
        "vopts": attr.string_list(
            doc = "Additional command line options to pass to Verilator",
            default = ["-Wall"],
        ),
        "_cc_toolchain": attr.label(
            doc = "CC compiler.",
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
        "_copy_tree": attr.label(
            doc = "A tool for copying a tree of files",
            cfg = "exec",
            executable = True,
            default = Label("//common:copy_tree"),
        ),
    },
    provides = [
        DefaultInfo,
        VerilatedBinaryInfo,
    ],
    executable = True,
    toolchains = [
        "@bazel_tools//tools/cpp:toolchain_type",
        "@rules_hdl//verilator:toolchain_type",
    ],
    fragments = ["cpp"],
)

def _verilator_run(ctx):
    result = []
    args = []
    outputs = list(ctx.outputs.outs)

    # Capture log
    log_file = ctx.actions.declare_file(ctx.label.name + ".log")
    outputs.append(log_file)
    args.extend(["--stdout", log_file.path])

    result.append(LogInfo(
        files = [log_file],
    ))

    # Move coverage data if applicable
    if ctx.attr.binary[VerilatedBinaryInfo].coverage != "none":
        dat_file = ctx.actions.declare_file(ctx.label.name + ".dat")
        outputs.append(dat_file)
        args.extend(["--coverage", dat_file.path])

        result.append(RawCoverageInfo(
            files = [dat_file],
        ))

    # Target binary name
    args.append(ctx.executable.binary.path)

    # Target binary args
    for arg in ctx.attr.args:
        args.append(arg)

    # Waveform trace. Use plusargs mechanism to tell the simulation where write
    # the trace to
    if ctx.attr.binary[VerilatedBinaryInfo].trace:
        trace_file = ctx.actions.declare_file(ctx.label.name + ".vcd")
        outputs.append(trace_file)
        args.append("+" + ctx.attr.trace_plusarg + "=" + trace_file.path)

        result.append(WaveformInfo(
            vcd_files = [trace_file],
        ))

    # Target runfiles
    runfiles = ctx.attr.binary[DefaultInfo].default_runfiles.files.to_list()

    # Run
    ctx.actions.run(
        outputs = outputs,
        inputs = runfiles,
        tools = [ctx.executable._run_wrapper],
        executable = ctx.executable._run_wrapper,
        arguments = args,
        mnemonic = "RunVerilatedBinary",
        use_default_shell_env = False,
    )

    result.append(DefaultInfo(
        files = depset(outputs),
        runfiles = ctx.runfiles(files = runfiles),
    ))

    return result

verilator_run = rule(
    implementation = _verilator_run,
    attrs = {
        "args": attr.string_list(
            doc = "Arguments to be passed to the binary (optional)",
        ),
        "binary": attr.label(
            doc = "Verilated binary to run",
            mandatory = True,
            executable = True,
            cfg = "exec",
            providers = [
                VerilatedBinaryInfo,
            ],
        ),
        "outs": attr.output_list(
            doc = "List of simulation products",
        ),
        "trace_plusarg": attr.string(
            doc = "Name of a plusarg parameter that will hold trace file name",
            default = "trace",
        ),
        "_run_wrapper": attr.label(
            doc = "A wrapper utility for running the binary",
            cfg = "exec",
            executable = True,
            default = Label("//verilator/private:verilator_run_wrapper"),
        ),
    },
    provides = [
        DefaultInfo,
        LogInfo,
    ],
)

def _verilator_lint(ctx):
    verilator_toolchain = ctx.toolchains["@rules_hdl//verilator:toolchain_type"]

    # Sources
    srcs = depset([], transitive = [ctx.attr.module[VerilogInfo].dag]).to_list()

    # Assemble Verilator args
    vopts = [
        "--lint-only",
    ]
    vopts.extend(["--top-module", ctx.attr.module_top])
    args, vlog_srcs, vlog_hdrs, _ = _verilator_args(ctx, srcs, vopts)

    # Capture stderr to the log file
    log_file = ctx.actions.declare_file(ctx.label.name + ".log")

    args.add("--stderr")
    args.add(log_file.path)

    # Run
    ctx.actions.run(
        outputs = [log_file],
        inputs = vlog_srcs + vlog_hdrs,
        tools = [verilator_toolchain.all_files, ctx.executable._run_wrapper],
        env = _verilator_toolchain_env(verilator_toolchain),
        executable = ctx.executable._run_wrapper,
        arguments = [verilator_toolchain.verilator.path, args],
        mnemonic = "VerilatorLint",
        progress_message = "[Verilator] Linting {}".format(ctx.label),
    )

    return [
        DefaultInfo(
            files = depset([log_file]),
            runfiles = ctx.runfiles(files = vlog_srcs + vlog_hdrs),
        ),
        LogInfo(
            files = [log_file],
        ),
    ]

verilator_lint = rule(
    implementation = _verilator_lint,
    attrs = {
        "module": attr.label(
            doc = "The top level module target to verilate.",
            providers = [VerilogInfo],
            mandatory = True,
        ),
        "module_top": attr.string(
            doc = "The name of the verilog module to verilate.",
            mandatory = True,
        ),
        "vopts": attr.string_list(
            doc = "Additional command line options to pass to Verilator",
            default = ["-Wall"],
        ),
        "_run_wrapper": attr.label(
            doc = "A wrapper utility for running verilator",
            cfg = "exec",
            executable = True,
            default = Label("//verilator/private:verilator_run_wrapper"),
        ),
    },
    provides = [
        DefaultInfo,
        LogInfo,
    ],
    toolchains = [
        "@rules_hdl//verilator:toolchain_type",
    ],
)

def _verilator_toolchain_impl(ctx):
    all_files = depset(transitive = [
        ctx.attr.verilator[DefaultInfo].default_runfiles.files,
        ctx.attr.root.files,
    ])

    return [platform_common.ToolchainInfo(
        verilator = ctx.executable.verilator,
        shared = ctx.attr.shared,
        root = ctx.attr.root,
        deps = ctx.attr.deps,
        extra_vopts = ctx.attr.extra_vopts,
        all_files = all_files,
    )]

verilator_toolchain = rule(
    doc = "Define a Verilator toolchain.",
    implementation = _verilator_toolchain_impl,
    attrs = {
        "deps": attr.label_list(
            doc = "Global Verilator dependencies to link into downstream targets.",
            providers = [CcInfo],
        ),
        "extra_vopts": attr.string_list(
            doc = "Extra flags to pass to Verilator compile actions.",
        ),
        "root": attr.label(
            doc = "Target generated using verilator_root rule",
            mandatory = True,
        ),
        "shared": attr.label(
            doc = "Verilator shared files",
            mandatory = True,
        ),
        "verilator": attr.label(
            doc = "The Verilator binary.",
            executable = True,
            cfg = "exec",
            mandatory = True,
        ),
    },
)
