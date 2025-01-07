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

    # Format base command
    command = "source " + ctx.file.vcs_env.path + " && "
    command += "vcs"
    command += " -l " + vcs_log.path
    command += " -o " + vcs_out.path
    command += " -top " + ctx.attr.module_top
    command += " -debug_access -debug_region=cell+encrpt +v2k"

    for opt in ctx.attr.opts:
        command += " " + opt

    # Pass -sverilog option if needed
    if have_sv and "-sverilog" not in ctx.attr.opts:
        command += " -sverilog"

    # Include dirs
    command += " +incdir"
    for include_dir in include_dirs:
        command += "+" + include_dir

    # Sources
    for verilog_file in verilog_files:
        command += " " + verilog_file.path

    # Run VCS
    inputs = [ctx.file.vcs_env] + all_hdrs + verilog_files
    outputs = [vcs_log, vcs_out, vcs_runfiles]

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
    ]

vcs_binary = rule(
    implementation = _vcs_binary,
    attrs = {
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
    outputs = []
    result = []

    # Capture log
    run_log = ctx.actions.declare_file("{}.log".format(ctx.label.name))
    args.extend(["-l", run_log.path])
    outputs.append(run_log)

    # Waveform
    if ctx.attr.trace:
        trace_file = ctx.actions.declare_file("{}.vcd".format(ctx.label.name))
        args.extend(["+vcd="+trace_file.path])
        args.append("+vcs+dumpon+0+0")
        args.append("+vcs+dumparrays")
        outputs.append(trace_file)

        result.append(WaveformInfo(
            vcd_files = depset([trace_file]),
        ))

    # Target binary args
    for arg in ctx.attr.args:
        args.append(arg)

    # Target runfiles
    runfiles = ctx.attr.binary[DefaultInfo].default_runfiles.files.to_list()

    # Run
    ctx.actions.run(
        outputs = outputs,
        inputs = runfiles,
        executable = ctx.executable.binary,
        arguments = args,
        mnemonic = "RunVCSBinary",
        use_default_shell_env = False,
    )

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
        "trace": attr.bool(
            doc = "Enable trace output",
            default = False,
        ),
    },
    provides = [
        DefaultInfo,
        LogInfo,
    ],
)
