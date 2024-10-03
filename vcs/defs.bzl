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

load("//verilog:defs.bzl", "VerilogInfo")

_RUNFILES = ["dat", "mem"]

def _vcs_binary(ctx):
    transitive_srcs = depset([], transitive = [ctx.attr.module[VerilogInfo].dag])
    all_srcs = [verilog_info_struct.srcs for verilog_info_struct in transitive_srcs.to_list()]
    all_data = [verilog_info_struct.data for verilog_info_struct in transitive_srcs.to_list()]
    all_files = [src for sub_tuple in (all_srcs + all_data) for src in sub_tuple]

    # Filter out .dat files.
    runfiles = []
    verilog_files = []
    for file in all_files:
        if file.extension in _RUNFILES:
            runfiles.append(file)
        else:
            verilog_files.append(file)

    vcs_log = ctx.actions.declare_file("{}.log".format(ctx.label.name))
    vcs_out = ctx.actions.declare_file(ctx.label.name)

    command = "source " + ctx.file.vcs_env.path + " && "
    command += "vcs"
    command += " -l " + vcs_log.path
    command += " -o " + vcs_out.path

    for opt in ctx.attr.opts:
        command += " " + opt

    for verilog_file in verilog_files:
        command += " " + verilog_file.path

    inputs = [ctx.file.vcs_env] + verilog_files
    outputs = [vcs_log, vcs_out]

    ctx.actions.run_shell(
        outputs = outputs,
        inputs = inputs,
        progress_message = "Running VCS: {}".format(ctx.label.name),
        command = command,
    )

    return [
        DefaultInfo(
            executable = vcs_out,
            runfiles = ctx.runfiles(files = runfiles),
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
)
