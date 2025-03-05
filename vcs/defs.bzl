# Copyright 2024 Antmicro
#
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

"""Functions for VCS."""

load("//common:providers.bzl", "LogInfo", "WaveformInfo")
load("//verilog:defs.bzl", "VerilogInfo")

_RUNFILES = ["dat", "mem"]
_SV_SRC = ["sv", "svh"]
_ALLOWED_COV_TYPES = ["line", "cond", "fsm", "tgl", "branch", "assert"]

CoverageInfo = provider(
    doc = "Coverage collected during a simulation run",
    fields = {
        "compiled_types": "Coverage types that the binary was compiled with",
        "cov_dir": "Coverage directory",
    },
)

def is_subset(superset, subset):
    """Checks if 'subset' (list) is a subset of 'superset' (list)

    Args:
        superset: list of arbitrary elements
        subset: list that is tested for being a subset

    Returns:
        boolean indicating whether 'subset' is subset of 'superset'
    """

    # emulate set with dict since it's not available prior to bazel 8
    sup = {k: True for k in superset}
    for elem in subset:
        if not sup.get(elem):
            return False
    return True

def fail_on_invalid_coverage_type(cov_types):
    for cov in cov_types:
        if cov not in _ALLOWED_COV_TYPES:
            fail("Unsupported coverage type '{}', must be one of: {}".format(cov, ", ".join(_ALLOWED_COV_TYPES)))

def _vcs_binary(ctx):
    transitive_srcs = depset([], transitive = [ctx.attr.module[VerilogInfo].dag]).to_list()

    # Get sources and headers
    all_srcs = [verilog_info_struct.srcs for verilog_info_struct in transitive_srcs]
    all_hdrs = [verilog_info_struct.hdrs for verilog_info_struct in transitive_srcs]
    all_data = [verilog_info_struct.data for verilog_info_struct in transitive_srcs]

    all_files = [src for sub_tuple in (all_srcs + all_data) for src in sub_tuple]
    all_hdrs = [hdr for sub_tuple in all_hdrs for hdr in sub_tuple]

    # Filter out .dat files. Check if we have SystemVerilog files.
    runfiles = []
    verilog_files = []
    have_sv = False
    for file in all_files:
        if file.extension in _RUNFILES:
            runfiles.append(file)
        else:
            verilog_files.append(file)
            if file.extension in _SV_SRC:
                have_sv = True

    # Check headers for SystemVerilog files
    for file in all_hdrs:
        if file.extension in _SV_SRC:
            have_sv = True
            break

    # Include directories
    include_dirs = depset([f.dirname for f in (verilog_files + all_hdrs)]).to_list()

    # Declare outputs
    vcs_log = ctx.actions.declare_file("{}.log".format(ctx.label.name))
    vcs_out = ctx.actions.declare_file(ctx.label.name)
    vcs_runfiles = ctx.actions.declare_directory(ctx.label.name + ".daidir")

    inputs = [ctx.file.vcs_env] + all_hdrs + verilog_files
    outputs = [vcs_log, vcs_out, vcs_runfiles]

    # Format base command
    command = "source " + ctx.file.vcs_env.path + " && "
    command += "vcs"
    command += " +warn=noLINX_KRNL"  # Assuming the warning about kernel version is always redundant
    command += " -l " + vcs_log.path
    command += " -o " + vcs_out.path
    command += " -top " + ctx.attr.module_top
    command += " -debug_access -debug_region=cell+encrypt +v2k"
    command += " +vcs+vcdpluson"

    for opt in ctx.attr.opts:
        command += " " + opt

    # Pass -sverilog option if needed
    if have_sv and "-sverilog" not in ctx.attr.opts:
        command += " -sverilog"

    # Coverage
    produce_coverage = len(ctx.attr.coverage) > 0
    fail_on_invalid_coverage_type(ctx.attr.coverage)
    vcs_cov_dir = ctx.actions.declare_directory("{}.vdb".format(ctx.label.name))
    outputs.append(vcs_cov_dir)

    if produce_coverage:
        command += " -cm " + "+".join(ctx.attr.coverage)

    # Include dirs
    command += " +incdir"
    for include_dir in include_dirs:
        command += "+" + include_dir

    # Sources
    for verilog_file in verilog_files:
        command += " " + verilog_file.path

    # Run VCS
    ctx.actions.run_shell(
        outputs = outputs,
        inputs = inputs,
        progress_message = "Running VCS: {}".format(ctx.label.name),
        command = command,
    )

    return [
        DefaultInfo(
            executable = vcs_out,
            runfiles = ctx.runfiles(files = runfiles + [vcs_runfiles]),
        ),
        LogInfo(
            files = [vcs_log],
        ),
        CoverageInfo(
            compiled_types = ctx.attr.coverage,
            cov_dir = vcs_cov_dir,
        ),
    ]

vcs_binary = rule(
    implementation = _vcs_binary,
    attrs = {
        "coverage": attr.string_list(
            doc = "Types of coverage to collect. Allowed values are: " +
                  ", ".join(_ALLOWED_COV_TYPES) + ". " +
                  "These get passed to the -cm flag",
        ),
        "module": attr.label(
            doc = "The top level build.",
            providers = [VerilogInfo],
            mandatory = True,
        ),
        "module_top": attr.string(
            doc = "The name of the top level verilog module.",
            mandatory = True,
        ),
        "opts": attr.string_list(
            doc = "Additional command line options to pass to VCS",
            default = [],
        ),
        "vcs_env": attr.label(
            doc = "A shell script to source the VCS environment and " +
                  "point to license server",
            mandatory = True,
            allow_single_file = [".sh"],
        ),
    },
    provides = [
        DefaultInfo,
        LogInfo,
    ],
)

def _vcs_run(ctx):
    args = []
    intermediate_outputs = []
    outputs = []
    result = []

    # Capture log
    run_log = ctx.actions.declare_file("{}.log".format(ctx.label.name))
    args.extend(["-l", run_log.path])
    outputs.append(run_log)

    # Target binary args
    for arg in ctx.attr.args:
        args.append(arg)

    # Waveform
    trace_vpd = []
    if ctx.attr.trace_vpd:
        file = ctx.actions.declare_file("{}.vpd".format(ctx.label.name))
        trace_vpd.append(file)
        args.append("+vpdfile+" + file.path)
        args.append("+dumpon")

    trace_vcd = []
    if ctx.attr.trace_vcd:
        file = ctx.actions.declare_file("{}.vcd".format(ctx.label.name))
        trace_vcd.append(file)
        args.append("+vcd=" + file.path)
        args.append("+vcs+dumpon+0+0")
        args.append("+vcs+dumparrays")

    outputs += trace_vcd + trace_vpd
    result.append(WaveformInfo(
        vpd_files = depset(trace_vpd),
        vcd_files = depset(trace_vcd),
    ))

    # Target runfiles
    runfiles = ctx.attr.binary[DefaultInfo].default_runfiles.files.to_list()

    # Coverage
    produce_coverage = len(ctx.attr.coverage) > 0
    fail_on_invalid_coverage_type(ctx.attr.coverage)
    cov_info = ctx.attr.binary[CoverageInfo]
    cov_dir = cov_info.cov_dir

    if not is_subset(cov_info.compiled_types, ctx.attr.coverage):
        fail("Design was compiled with VCS with incompatible set of coverage types: " +
             str(cov_info.compiled_types) + " is not a superset of coverage types passed for " +
             "running the compiled binary: " + str(ctx.attr.coverage) + ". Add missing types to " +
             "your vcs_binary rule.")

    cov_dir_intermediate = ctx.actions.declare_directory("{}_intermediate.vdb".format(ctx.label.name))

    # Input directory - contains 'auxiliary', 'design' and 'shape' subdirs
    runfiles.append(cov_dir)

    # Output directory - will contain only 'testdata' subdir
    intermediate_outputs.append(cov_dir_intermediate)

    if produce_coverage:
        args += ["-cm", "+".join(ctx.attr.coverage)]
        args += ["-cm_dir", cov_dir_intermediate.path]

    # Run
    ctx.actions.run(
        outputs = outputs + intermediate_outputs,
        inputs = runfiles,
        executable = ctx.executable.binary,
        arguments = args,
        mnemonic = "RunVCSBinary",
        use_default_shell_env = False,
    )

    if produce_coverage:
        # Merge cov_dir and cov_dir_intermediate to produce a directory
        # that contains all subdirs: 'auxiliary', 'design', 'shape' and 'testdata'
        cov_dir_final = ctx.actions.declare_directory("{}.vdb".format(ctx.label.name))
        ctx.actions.run_shell(
            inputs = [cov_dir, cov_dir_intermediate],
            outputs = [cov_dir_final],
            command = "cp -r {}/* {}/* {}".format(
                cov_dir.path,
                cov_dir_intermediate.path,
                cov_dir_final.path,
            ),
        )
        outputs.append(cov_dir_final)

    result.extend([
        DefaultInfo(
            files = depset(outputs),
            runfiles = ctx.runfiles(files = runfiles),
        ),
        LogInfo(
            files = [run_log],
        ),
    ])

    return result

vcs_run = rule(
    implementation = _vcs_run,
    attrs = {
        "args": attr.string_list(
            doc = "Arguments to be passed to the binary (optional)",
        ),
        "binary": attr.label(
            doc = "Compiled VCS binary to run",
            mandatory = True,
            executable = True,
            cfg = "exec",
        ),
        "coverage": attr.string_list(
            doc = "Types of coverage to collect. Allowed values are: " +
                  ", ".join(_ALLOWED_COV_TYPES) + ". " +
                  "These get passed to the -cm flag",
        ),
        "trace_vcd": attr.bool(
            doc = "Enable trace output in VCD format",
            default = False,
        ),
        "trace_vpd": attr.bool(
            doc = "Enable trace output in VPD format",
            default = False,
        ),
    },
    provides = [
        DefaultInfo,
        LogInfo,
    ],
)

def _convert_vpd2vcd(ctx):
    command_parts = [
        "source",
        ctx.file.vcs_env.path,
        "&&",
        "vpd2vcd",
    ]

    command_parts += ctx.attr.args
    command_common = " ".join(command_parts)
    all_vcds = []
    for vpd in ctx.attr.waveform[WaveformInfo].vpd_files.to_list():
        vcd_filename = vpd.basename.removesuffix(".vpd") + ".vcd"
        vcd = ctx.actions.declare_file(vcd_filename)
        all_vcds.append(vcd)

        ctx.actions.run_shell(
            outputs = [vcd],
            inputs = [ctx.file.vcs_env, vpd],
            progress_message = "Running VPD2VCS: {}".format(ctx.label.name),
            command = " ".join([command_common, vpd.path, vcd.path]),
        )

    out_depset = depset(all_vcds)
    return [
        DefaultInfo(
            files = out_depset,
        ),
        WaveformInfo(
            vcd_files = out_depset,
        ),
    ]

convert_vpd2vcd = rule(
    implementation = _convert_vpd2vcd,
    attrs = {
        "args": attr.string_list(
            doc = "Arguments to be passed to the converter",
        ),
        "vcs_env": attr.label(
            doc = "A shell script to source the VCS environment and " +
                  "point to license server",
            mandatory = True,
            allow_single_file = [".sh"],
        ),
        "waveform": attr.label(
            doc = "A target producing VPD waveforms",
            providers = [
                WaveformInfo,
            ],
        ),
    },
    provides = [
        DefaultInfo,
        WaveformInfo,
    ],
)
