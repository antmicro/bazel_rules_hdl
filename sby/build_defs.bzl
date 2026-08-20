# Copyright 2026 Antmicro
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

"""Rules for formal verification of SystemVerilog designs using SBY."""

load("//verilog:defs.bzl", "VerilogInfo")

def _transitive_srcs(deps):
    return depset(
        [],
        transitive = [dep[VerilogInfo].dag for dep in deps],
    )

def _sby_formal_impl(ctx):
    task_names = ctx.attr.tasks  # Only bc supported for now
    transitive_srcs = _transitive_srcs(
        [dep for dep in ctx.attr.deps if VerilogInfo in dep],
    )
    verilog_srcs = [
        verilog_info_struct.srcs
        for verilog_info_struct in transitive_srcs.to_list()
    ]
    verilog_data = [
        verilog_info_struct.data
        for verilog_info_struct in transitive_srcs.to_list()
    ]
    verilog_files = [
        src
        for sub_tuple in (verilog_srcs + verilog_data)
        for src in sub_tuple
    ]
    verilog_hdrs = [
        verilog_info_struct.hdrs
        for verilog_info_struct in transitive_srcs.to_list()
    ]
    verilog_hdr_files = [hdr for sub_tuple in verilog_hdrs for hdr in sub_tuple]
    script_lines = ["[engines]\n{}\n[script]\n".format(ctx.attr.engine)]

    ## TODO: add option to use default read_verilog -sv -formal here, maybe UHDM as well
    ## Force FORMAL macro that is defined by default with regular read_verilog -formal
    default_compile_command = "read_slang --std 1800-2023 --define-macro FORMAL"
    script_lines.append("{} \\".format(default_compile_command))
    for opt in ctx.attr.extra_parser_opts:
        script_lines.append("{} \\".format(opt))

    ## These are copied in yosys running directory, thus taking file name only
    for h in verilog_hdr_files:
        script_lines.append("-I {} \\".format(h.path.split("/")[-1]))
    for f in verilog_files:
        script_lines.append("{} \\".format(f.path.split("/")[-1]))

    # Pass top-level info to slang
    script_lines.append("--top {}".format(ctx.attr.module_top))

    # Compilation with yosys
    script_lines.append("prep -top {}".format(ctx.attr.module_top))

    # Minimal optimizations
    for opt in ctx.attr.extra_compile_opts:
        script_lines.append("{}".format(opt))

    # Pass the file list
    script_lines.append("[files]")
    for h in verilog_hdr_files:
        script_lines.append("-I {}".format(h.path))
    for f in verilog_files:
        script_lines.append("{}".format(f.path))

    # Set a tasks
    script_lines.append("[tasks]")
    for t in task_names:
        script_lines.append("{}".format(t))
    script_lines.append("[options]")

    for t in task_names:
        if t == "bc":
            script_lines.append("{}: mode bmc".format(t))
        elif t == "prf":
            script_lines.append("{}: mode prove".format(t))
        elif t == "cov":
            script_lines.append("{}: mode cover".format(t))
        else:
            fail("Unsupported value for task. Given {}. Allowed : bc,prf, cov.".format(t))

    script_lines.append("depth {}".format(ctx.attr.depth))

    # Useful for easier debug to have extra cycles
    script_lines.append("append 3")

    ## Enable FST waveforms
    if (ctx.attr.fst):
        script_lines.append("fst on")

    sby_script = ctx.actions.declare_file("{}.sby".format(ctx.attr.name))
    ctx.actions.write(sby_script, "\n".join(script_lines) + "\n")

    # Main SBY workdir, as everything is done in tasks, everything happens in sub directory
    base_workdir = ctx.actions.declare_directory("{}_sby_workdir".format(ctx.attr.name))

    # Need to declare one workdir per task, as SBY does duplicate split workdir for each task
    task_workdirs = {
        t: ctx.actions.declare_directory("{}_sby_workdir_{}".format(ctx.attr.name, t))
        for t in task_names
    }
    log_files = {
        t: ctx.actions.declare_file("{}_{}_sby.log".format(ctx.attr.name, t))
        for t in task_names
    }
    compile_log_files = {
        t: ctx.actions.declare_file("{}_{}_design.log".format(ctx.attr.name, t))
        for t in task_names
    }
    sby_runfiles = ctx.attr._sby_tool[DefaultInfo].default_runfiles.files.to_list()

    inputs = depset(
        direct = [sby_script] + verilog_files + verilog_hdr_files + sby_runfiles,
    )

    ctx.actions.run_shell(
        outputs = [base_workdir] + task_workdirs.values(),
        inputs = inputs,
        tools = [ctx.executable._sby_tool],
        # SBY's partition step changes the working directory
        # Make sure to set the env up beforehand
        command = """
set -euo pipefail
export PATH="/usr/bin:/bin"
exec "{sby_path}" --prefix "{prefix}" -f "{sby_script}"
""".format(
            sby_path = ctx.executable._sby_tool.path,
            prefix = base_workdir.path,
            sby_script = sby_script.path,
        ),
        mnemonic = "SbyFormal",
        progress_message = "Running SBY Boundary Model Check %{label}",
    )

    ## Because the jobs are run in tasks, the log files are in separate directories as well
    for t in task_names:
        ctx.actions.run_shell(
            outputs = [log_files[t]],
            inputs = [task_workdirs[t]],
            command = "cp '{}/logfile.txt' '{}'".format(
                task_workdirs[t].path,
                log_files[t].path,
            ),
            mnemonic = "SBYCheckCollectLog",
            progress_message = "Collecting SBY log for %{label}",
        )

        ## FIXME: design.log is slang specific, need to support normal parser as well
        ctx.actions.run_shell(
            outputs = [compile_log_files[t]],
            inputs = [task_workdirs[t]],
            command = "cp '{}/model/design.log' '{}'".format(
                task_workdirs[t].path,
                compile_log_files[t].path,
            ),
            mnemonic = "SBYCheckCollectCompileLog",
            progress_message = "Collecting compile log for %{label}",
        )

    return [
        DefaultInfo(
            files = depset(
                [base_workdir] +
                task_workdirs.values() + log_files.values() + compile_log_files.values(),
            ),
        ),
    ]

sby_formal_attrs = {
    "deps": attr.label_list(
        providers = [[VerilogInfo]],
    ),
    "depth": attr.int(
        default = 20,
        doc = "Proof depth passed to the formal engine.",
    ),
    "engine": attr.string(
        default = "smtbmc",
        doc = "SBY BMC engine.",
    ),
    "extra_compile_opts": attr.string_list(
        doc = "Extra yosys compilation command to optimize analyzed RTL",
        default = [
            "opt_merge -share_all",
        ],
    ),
    "extra_parser_opts": attr.string_list(
        doc = "Extra options for the verilog parser",
        default = [],
    ),
    "fst": attr.bool(
        default = False,
        doc = "Generate waveforms in FST format instead of vcd",
    ),
    "module_top": attr.string(
        mandatory = True,
        doc = "Name of the top-level module to check.",
    ),
    # TODO: possibly provide a better naming
    "tasks": attr.string_list(default = ["bc"], doc = "SBY tasks: bc,prf,cov"),
    "_sby_tool": attr.label(
        default = Label("@at_clifford_yosys//:sby"),
        executable = True,
        cfg = "exec",
    ),
}

sby_formal = rule(
    doc = """Perform formal checking on a SystemVerilog design.

Generates a `.sby` script that reads the design and compile the top-level, then run tasks on it.
The check fails the build if SBY find a counter-example. Supports bounded model checking (bc),
proof (prf) and coverage (cov).

    """,
    implementation = _sby_formal_impl,
    attrs = sby_formal_attrs,
)
