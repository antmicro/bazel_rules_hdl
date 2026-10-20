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

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load("@rules_cc//cc:action_names.bzl", "CPP_COMPILE_ACTION_NAME")
load("@rules_cc//cc:defs.bzl", "CcInfo")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("//common:providers.bzl", "LogInfo", "WaveformInfo")
load("//verilog:defs.bzl", "VerilogInfo")
load("providers.bzl", "RawCoverageInfo", "VerilatedBinaryInfo")

VERILATOR_PCH_SUFFIX = "__pch.h"
PCH_GCC_FLAGS = [
    "-fpch-deps",
    "-Winvalid-pch",
]

# The functions generates a precompiled header from a given header
# It returns the tupple with information required to properly use the precompiled header
def _precompile_header(ctx, cc_toolchain, cc_feature_configuration, hdr_basename, hdr_dirname, compilation_contexts):
    if cc_toolchain.compiler != "gcc":
        # The function only supports precompilation using GCC
        # Compilation of verilated files will be longer with other compilers
        # Clang is unsupported because uses absolute paths in .d files which Bazel treats as escaping a sandbox

        # buildifier: disable=print
        print("Precompilation of Verilator outputs is only supported with GCC. Compilation can be slower due to usage of the following cc_toolchain: " + cc_toolchain.compiler)
        return [], [], []

    # Prepare generic compile action arguments
    compiler_path = cc_common.get_tool_for_action(
        feature_configuration = cc_feature_configuration,
        action_name = CPP_COMPILE_ACTION_NAME,
    )
    compile_variables = cc_common.create_compile_variables(
        feature_configuration = cc_feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = _VERILATOR_DEFAULT_COPTS + ctx.fragments.cpp.cxxopts + ctx.fragments.cpp.copts,
    )
    command_line = cc_common.get_memory_inefficient_command_line(
        feature_configuration = cc_feature_configuration,
        action_name = CPP_COMPILE_ACTION_NAME,
        variables = compile_variables,
    )
    env = cc_common.get_environment_variables(
        feature_configuration = cc_feature_configuration,
        action_name = CPP_COMPILE_ACTION_NAME,
        variables = compile_variables,
    )

    # Build arguments for complier
    args = ctx.actions.args()
    args.add_all(command_line)

    # Collect args from compilation contexts
    headers = []
    for compilation_ctx in compilation_contexts:
        headers.append(compilation_ctx.headers)

        args.add_all(compilation_ctx.includes.to_list(), format_each = "-I%s")
        args.add_all(compilation_ctx.quote_includes.to_list(), before_each = "-iquote")
        args.add_all(compilation_ctx.system_includes.to_list(), before_each = "-isystem")
        args.add_all(compilation_ctx.defines.to_list(), format_each = "-D%s")

    # Unless -MD is specified while creating the precompiled file,
    # the .d file of the precompiled header will not show files included during the precompilation
    args.add("-MD")
    precompiled_hdr_d = ctx.actions.declare_file(hdr_basename + ".gch.d")
    args.add("-MF", precompiled_hdr_d.path)

    # Configure precompiling header
    args.add("-xc++-header")
    args.add(hdr_dirname + "/" + hdr_basename)

    precompiled_hdr = ctx.actions.declare_file(hdr_basename + ".gch")
    args.add("-o", precompiled_hdr.path)

    ctx.actions.run(
        executable = compiler_path,
        env = env,
        arguments = [args],
        mnemonic = "PrecompileHeader",
        progress_message = "Pre-compiling header: " + hdr_basename,
        inputs = depset(transitive = headers + [cc_toolchain.all_files]),
        outputs = [precompiled_hdr, precompiled_hdr_d],
    )

    return [precompiled_hdr], [precompiled_hdr.dirname], PCH_GCC_FLAGS

def _cc_configure_features(ctx, toolchain):
    return cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

def cc_compile(ctx, cc_toolchain, cc_feature_configuration, prefix, verilator_output, deps, extra_srcs = [], includes = [], defines = []):
    """Compile C++ sources

    Args:
        ctx: Context for rule.
        cc_toolchain: CC toolchain to compile with.
        cc_feature_configuration: CC toolchain features configuration.
        prefix: The prefix passed to Verilator.
        verilator_output: The Verilated files, mostly C++ and header files.
        deps: The additional C and C++ dependencies.
        extra_srcs: The additional C++ sources.
        includes: The includes for the verilator module to build.
        defines: Cpp defines to build with.
    Returns:
        A tuple with CompilationContext and CcComplilationOutputs, essentially tupple returned from cc_common.compile()
    """

    # Copy
    # All files are copied in a single action to avoid compilation of unchanged files by cc_common.compile()
    verilated_cpp = ctx.actions.declare_directory(ctx.label.name + "_cpp")
    verilated_hpp = ctx.actions.declare_directory(ctx.label.name + "_hpp")

    args = ctx.actions.args()
    args.add_all(verilator_output, map_each = _only_cpp, before_each = verilated_cpp.path)
    args.add_all(verilator_output, map_each = _only_hpp, before_each = verilated_hpp.path)

    ctx.actions.run(
        mnemonic = "VerilatorCopyTree",
        arguments = [args],
        inputs = verilator_output,
        outputs = [verilated_cpp, verilated_hpp],
        executable = ctx.executable._copy_tree,
    )

    compilation_contexts = [dep[CcInfo].compilation_context for dep in deps]

    compilation_contexts.append(cc_common.create_compilation_context(
        headers = depset([verilated_hpp]),
        includes = depset([verilated_hpp.path]),
    ))

    # Verilator outputs headers in the way optimized for precompilation
    # Most of generated Cpp files use a single header that includes almost all generated headers
    # That single header is perfect for precompilation
    # It speeds up compilation by skipping processing of included headers
    precompiled_files, precompiled_includes, precompiled_flags = _precompile_header(
        ctx,
        cc_toolchain,
        cc_feature_configuration,
        hdr_basename = prefix + VERILATOR_PCH_SUFFIX,
        hdr_dirname = verilated_hpp.path,
        compilation_contexts = compilation_contexts,
    )

    return cc_common.compile(
        name = ctx.label.name,
        actions = ctx.actions,
        feature_configuration = cc_feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = _VERILATOR_DEFAULT_COPTS + precompiled_flags + ctx.attr.copts,
        srcs = extra_srcs + [verilated_cpp],
        includes = precompiled_includes + includes,
        defines = defines,
        additional_inputs = precompiled_files,
        compilation_contexts = compilation_contexts,
    )

def cc_link_static_library(ctx, cc_toolchain, cc_feature_configuration, compilation_context, compilation_outputs, deps, runfiles):
    """Compile and link C++ source into a static library

    Args:
        ctx: Context for rule.
        cc_toolchain: CC toolchain to compile with.
        cc_feature_configuration: CC toolchain features configuration.
        compilation_context: CompilationContext to refer in CcInfo output.
        compilation_outputs: CcComplilationOutputs to link.
        deps: The additional C and C++ dependencies.
        runfiles: The runfiles to refer in DefaultInfo output.
    Returns:
        CcInfo and DefaultInfo with the compiled library.
    """

    linking_contexts = [dep[CcInfo].linking_context for dep in deps]
    linking_context, linking_output = cc_common.create_linking_context_from_compilation_outputs(
        actions = ctx.actions,
        feature_configuration = cc_feature_configuration,
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

def cc_link_binary(ctx, cc_toolchain, cc_feature_configuration, compilation_outputs, deps, runfiles):
    """Compile and link C++ source into a binary executable

    Args:
        ctx: Context for rule.
        cc_toolchain: CC toolchain to compile with.
        cc_feature_configuration: CC toolchain features configuration.
        compilation_outputs: CcComplilationOutputs to link.
        deps: The additional C and C++ dependencies.
        runfiles: The runfiles to refer in DefaultInfo output.
    Returns:
        DefaultInfo with the compiled binary.
    """

    linking_contexts = [dep[CcInfo].linking_context for dep in deps]
    linking_output = cc_common.link(
        actions = ctx.actions,
        name = ctx.label.name,
        feature_configuration = cc_feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = compilation_outputs,
        linking_contexts = linking_contexts,
    )

    return [
        DefaultInfo(
            files = depset([linking_output.executable]),
            executable = linking_output.executable,
            runfiles = ctx.runfiles(files = runfiles),
        ),
    ]

_CPP_SRC = ["cc", "cpp", "cxx", "c++"]
_HPP_SRC = ["h", "hh", "hpp"]
_RUNFILES = ["dat", "mem"]

def _only_cpp(f):
    """Filter for just C++ source"""
    if f.extension in _CPP_SRC:
        return f.path
    return None

def _only_hpp(f):
    """Filter for just C++ headers"""
    if f.extension in _HPP_SRC:
        return f.path
    return None

def _verilator_prefix(module_top):
    return "V" + module_top

def _verilator_toolchain_env(toolchain):
    root_files = toolchain.root.files.to_list()
    if len(root_files) != 1:
        fail("It's expected to have only one File (path to directory) as the root attribute of VerilatorToolchain")

    return {
        "VERILATOR_ROOT": root_files[0].path,
    }

def _verilator_args(ctx, srcs, vopts = [], config_files = [], user_vopts = []):
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

    # Base include directories
    base_include_dirs = depset([f.dirname for f in (verilog_files + all_hdrs)]).to_list()

    # For each include directory traverse it back to root and add all intermediate
    # directories as potential locations of include files. Deduplicate the final
    # list via depset()
    include_dirs = []
    for dirname in base_include_dirs:
        parts = dirname.split("/")
        for i in range(len(parts)):
            include_dirs.append("/".join([parts[j] for j in range(0, i + 1)]))
    include_dirs = depset(include_dirs).to_list()

    # Args
    args = ctx.actions.args()
    args.add(verilator_toolchain.verilator)
    args.add_all(vopts)
    args.add_all(verilator_toolchain.extra_vopts)
    args.add_all(user_vopts, expand_directories = False)

    # Configuration files are passed like source files.
    # It's recommended to pass them before source files,
    # because they can refer only to files passed after them.
    verilog_files += config_files

    for pth in include_dirs:
        args.add("-I" + pth)

    for verilog_file in verilog_files:
        args.add(verilog_file.path)

    # Return args, sources, headers and runfiles
    return args, verilog_files, all_hdrs, runfiles

def verilator_generate_cc(ctx, verilator_toolchain, verilog_dags, module_top, prefix, trace = "none", coverage = "none", opts = [], user_vopts = []):
    """Generate C++ sources for a Verilog design using the Verilator toolchain.

    Args:
      ctx: Rule context used to declare and run the Verilator actions.
      verilator_toolchain: The toolchain used to verilate.
      verilog_dags: Verilog dependency DAGs containing the design sources.
      module_top: Name of the top-level Verilog module.
      trace: Waveform format (`none`, `vcd`, or `fst`).
      coverage: Coverage instrumentation mode.
      opts: Verilator options controlled by the calling rule.
      user_vopts: Additional Verilator options supplied by the user.
      prefix: Optional prefix for generated model classes and files.

    Returns:
      A tuple containing the generated C++ sources, generated headers, and
      runtime files required by the design.
    """

    # Sources
    srcs = depset([], transitive = verilog_dags).to_list()

    # Options
    vopts = list(opts)

    verilator_output = ctx.actions.declare_directory(ctx.label.name + "-gen")
    vopts.extend(["--cc"])
    vopts.extend(["--Mdir", verilator_output.path])
    vopts.extend(["--top-module", module_top])
    vopts.extend(["--prefix", prefix])

    if trace not in ["none", "vcd", "fst"]:
        fail("Unsupported trace format '{}'; expected 'none', 'vcd', or 'fst'".format(trace))
    if trace != "none":
        vopts.append("--trace-{}".format(trace))

    if coverage == "all":
        vopts.extend(["--coverage"])
    if coverage == "line":
        vopts.extend(["--coverage-line"])
    if coverage == "toggle":
        vopts.extend(["--coverage-toggle"])

    # Assemble Verilator args
    args, vlog_srcs, vlog_hdrs, runfiles = _verilator_args(
        ctx,
        srcs,
        vopts,
        user_vopts = user_vopts,
    )

    env = _verilator_toolchain_env(verilator_toolchain)
    if verilator_toolchain._avoid_nondeterministic_outputs:
        env["VERILATOR_AVOID_NONDETERMINISTIC_OUTPUTS"] = "1"

    # Run the action
    ctx.actions.run(
        arguments = [args],
        mnemonic = "VerilatorCompile",
        executable = ctx.executable._process_wrapper,
        tools = verilator_toolchain.all_files,
        inputs = vlog_srcs + vlog_hdrs,
        outputs = [verilator_output],
        progress_message = "[Verilator] Compiling {}".format(ctx.label),
        env = env,
    )

    output = depset([verilator_output], transitive = [verilator_toolchain.shared[DefaultInfo].files])

    return output, runfiles

def verilator_build_binary(
        ctx,
        verilog_dags,
        module_top,
        prefix,
        extra_srcs = [],
        extra_deps = [],
        extra_runfiles = [],
        trace = "none",
        coverage = "none",
        opts = [],
        user_vopts = [],
        defines = []):
    """Generate a Verilated model and link it into an executable.

    Args:
      ctx: Rule context used to declare the generation and linking actions.
      verilog_dags: Verilog dependency DAGs containing the design sources.
      module_top: Name of the top-level Verilog module.
      extra_srcs: Additional C++ sources to compile into the executable.
      extra_deps: Additional C++ dependencies to link into the executable.
      extra_runfiles: Additional files required by the executable at runtime.
      trace: Waveform format (`none`, `vcd`, or `fst`).
      coverage: Coverage instrumentation mode.
      opts: Verilator options controlled by the calling rule.
      user_vopts: Additional Verilator options supplied by the user.
      prefix: Optional prefix for generated model classes and files.
      defines: C++ preprocessor definitions used when compiling the model.

    Returns:
      Providers for the linked Verilator executable.
    """
    verilator_toolchain = ctx.toolchains["@rules_hdl//verilator:toolchain_type"]
    cc_toolchain = find_cpp_toolchain(ctx)
    cc_feature_configuration = _cc_configure_features(ctx, cc_toolchain)

    verilator_output, design_runfiles = verilator_generate_cc(
        ctx,
        verilator_toolchain,
        verilog_dags = verilog_dags,
        module_top = module_top,
        trace = trace,
        coverage = coverage,
        opts = opts,
        user_vopts = user_vopts,
        prefix = prefix,
    )

    deps = verilator_toolchain.deps + extra_deps

    _, compilation_outputs = cc_compile(
        ctx,
        cc_toolchain,
        cc_feature_configuration,
        prefix = prefix,
        verilator_output = verilator_output,
        extra_srcs = extra_srcs,
        deps = deps,
        defines = defines,
    )

    return cc_link_binary(
        ctx,
        cc_toolchain,
        cc_feature_configuration,
        compilation_outputs = compilation_outputs,
        deps = deps,
        runfiles = design_runfiles + extra_runfiles,
    )

# Options from verilator/include/verilated.mk
_VERILATOR_DEFAULT_COPTS = [
    "-std=c++20",
    "-faligned-new",
    "-fcf-protection=none",
    "-Wextra",
    "-Wfloat-conversion",
    "-Wno-bool-operation",
    "-Wno-shadow",
    "-Wno-sign-compare",
    "-Wno-tautological-compare",
    "-Wno-uninitialized",
    "-Wno-unused-but-set-parameter",
    "-Wno-unused-but-set-variable",
    "-Wno-unused-parameter",
    "-Wno-unused-variable",
]

def _verilator_cc_library(ctx):
    verilator_toolchain = ctx.toolchains["@rules_hdl//verilator:toolchain_type"]
    cc_toolchain = find_cpp_toolchain(ctx)
    cc_feature_configuration = _cc_configure_features(ctx, cc_toolchain)

    prefix = _verilator_prefix(ctx.attr.module_top)

    verilator_output, design_runfiles = verilator_generate_cc(
        ctx,
        verilator_toolchain,
        verilog_dags = [ctx.attr.module[VerilogInfo].dag],
        module_top = ctx.attr.module_top,
        trace = ctx.attr.trace,
        coverage = ctx.attr.coverage,
        user_vopts = ctx.attr.vopts,
        prefix = prefix,
    )

    # Do actual compile
    defines = ["VM_TRACE"] if ctx.attr.trace != "none" else []

    cc_compilation_context, compilation_outputs = cc_compile(
        ctx,
        cc_toolchain,
        cc_feature_configuration,
        prefix,
        verilator_output,
        deps = verilator_toolchain.deps,
        defines = defines,
    )

    return cc_link_static_library(
        ctx,
        cc_toolchain,
        cc_feature_configuration,
        cc_compilation_context,
        compilation_outputs,
        deps = [],
        runfiles = design_runfiles,
    )

verilator_cc_library = rule(
    implementation = _verilator_cc_library,
    attrs = {
        "copts": attr.string_list(
            doc = "Additional compilation flags appended after the Verilator defaults",
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
        "trace": attr.string(
            doc = "Waveform format (`none`, `vcd`, or `fst`)",
            default = "none",
            values = ["none", "vcd", "fst"],
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
        "_process_wrapper": attr.label(
            doc = "The Verilator process wrapper binary.",
            executable = True,
            cfg = "exec",
            default = Label("//verilator/private:verilator_process_wrapper"),
        ),
    },
    provides = [
        CcInfo,
        DefaultInfo,
    ],
    toolchains = [
        "@bazel_tools//tools/cpp:toolchain_type",
        "//verilator:toolchain_type",
    ],
    fragments = ["cpp"],
)

def _z3_executable_impl(ctx):
    z3_files = ctx.attr.z3[DefaultInfo].files.to_list()

    z3 = None
    for f in z3_files:
        if f.basename == "z3" and f.path.endswith("/bin/z3"):
            z3 = f
            break

    if z3 == None:
        fail("Could not find bin/z3 in @z3//:z3_static")

    executable = ctx.actions.declare_file("z3")

    ctx.actions.symlink(
        output = executable,
        target_file = z3,
    )

    return DefaultInfo(
        executable = executable,
        files = depset([executable]),
    )

z3_executable = rule(
    implementation = _z3_executable_impl,
    executable = True,
    attrs = {
        "z3": attr.label(
            mandatory = True,
            cfg = "exec",
        ),
    },
)

def _verilator_cc_binary(ctx):
    defines = ["VM_TRACE"] if ctx.attr.trace != "none" else []
    if ctx.attr.coverage != "none":
        defines.append("VM_COVERAGE")

    result = verilator_build_binary(
        ctx,
        verilog_dags = [ctx.attr.module[VerilogInfo].dag],
        module_top = ctx.attr.module_top,
        prefix = _verilator_prefix(ctx.attr.module_top),
        trace = ctx.attr.trace,
        coverage = ctx.attr.coverage,
        opts = ["--main"],
        user_vopts = ctx.attr.vopts,
        defines = defines,
    )

    return result + [VerilatedBinaryInfo(
        coverage = ctx.attr.coverage,
        trace = ctx.attr.trace,
    )]

verilator_cc_binary = rule(
    implementation = _verilator_cc_binary,
    attrs = {
        "copts": attr.string_list(
            doc = "Additional compilation flags appended after the Verilator defaults",
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
        "trace": attr.string(
            doc = "Waveform format (`none`, `vcd`, or `fst`)",
            default = "none",
            values = ["none", "vcd", "fst"],
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
        "_process_wrapper": attr.label(
            doc = "The Verilator process wrapper binary.",
            executable = True,
            cfg = "exec",
            default = Label("//verilator/private:verilator_process_wrapper"),
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

def _verilator_preprocess_impl(ctx):
    verilator_toolchain = ctx.toolchains["@rules_hdl//verilator:toolchain_type"]

    # Sources
    srcs = depset([], transitive = [ctx.attr.module[VerilogInfo].dag]).to_list()

    output = ctx.actions.declare_file(paths.join(ctx.label.name, ctx.attr.out))

    # Options
    vopts = []
    vopts.extend(["-E"])
    vopts.extend(["-P"])

    # Assemble Verilator args
    args, vlog_srcs, vlog_hdrs, _ = _verilator_args(
        ctx,
        srcs,
        vopts,
        user_vopts = ctx.attr.vopts,
    )

    args.add("--stdout")
    args.add(output.path)

    ctx.actions.run(
        outputs = [output],
        inputs = vlog_srcs + vlog_hdrs,
        tools = [verilator_toolchain.all_files, ctx.executable._run_wrapper],
        env = _verilator_toolchain_env(verilator_toolchain),
        executable = ctx.executable._run_wrapper,
        arguments = [args],
        mnemonic = "VerilatorPreprocess",
        progress_message = "[Verilator] Preprocessing {}".format(ctx.label),
    )

    return [DefaultInfo(files = depset([output]))]

verilator_preprocess = rule(
    implementation = _verilator_preprocess_impl,
    attrs = {
        "module": attr.label(
            doc = "The top level module target to verilate.",
            providers = [VerilogInfo],
            mandatory = True,
        ),
        "out": attr.string(
            doc = "Name of the generated preprocessed output file.",
            default = "preprocessed.v",
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
    ],
    toolchains = [
        "@rules_hdl//verilator:toolchain_type",
    ],
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
    trace = ctx.attr.binary[VerilatedBinaryInfo].trace
    if trace != "none":
        trace_file = ctx.actions.declare_file(ctx.label.name + "." + trace)
        outputs.append(trace_file)
        args.append("+" + ctx.attr.trace_plusarg + "=" + trace_file.path)

        if trace == "fst":
            result.append(WaveformInfo(fst_files = [trace_file]))
        else:
            result.append(WaveformInfo(vcd_files = [trace_file]))

    # Target runfiles
    runfiles = ctx.attr.binary[DefaultInfo].default_runfiles.files.to_list()
    runfiles = runfiles + ctx.attr._smt_solver[DefaultInfo].default_runfiles.files.to_list()

    # Run
    ctx.actions.run(
        outputs = outputs,
        inputs = runfiles,
        tools = [ctx.executable._run_wrapper, ctx.executable._smt_solver],
        executable = ctx.executable._run_wrapper,
        env = {
            "Z3_DIR": ctx.executable._smt_solver.dirname,
        },
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
        "_smt_solver": attr.label(
            doc = "SMT solver for constrained randomization",
            cfg = "exec",
            executable = True,
            default = Label(":z3"),
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
    args, vlog_srcs, vlog_hdrs, _ = _verilator_args(
        ctx,
        srcs,
        vopts,
        ctx.files.config_files,
        user_vopts = ctx.attr.vopts,
    )

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
        arguments = [args],
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
        "config_files": attr.label_list(
            doc = "Configuration files passed to Verilator",
            allow_files = True,
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
        _avoid_nondeterministic_outputs = ctx.attr.avoid_nondeterministic_outputs[BuildSettingInfo].value,
    )]

verilator_toolchain = rule(
    doc = "Define a Verilator toolchain.",
    implementation = _verilator_toolchain_impl,
    attrs = {
        "avoid_nondeterministic_outputs": attr.label(
            default = Label("//verilator/settings:avoid_nondeterministic_outputs"),
        ),
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
