# Copyright 2026 bazel_rules_hdl Authors
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

"""Rules for formal equivalence checking of SystemVerilog designs using EQY."""

load("@rules_foreign_cc//toolchains/native_tools:tool_access.bzl", "access_tool")
load("//sby:build_defs.bzl", "formal_tool_commands")
load("//verilog:defs.bzl", "VerilogInfo")

_MAKE_TOOLCHAIN_TYPE = Label("@rules_foreign_cc//toolchains:make_toolchain")

def _flatten_verilog_srcs(verilog_info):
    infos = verilog_info.dag.to_list()
    files = []
    for info in infos:
        files.extend(info.srcs)
        files.extend(info.hdrs)
    return files

def _eqy_check_impl(ctx):
    golden_flist = ctx.attr.gold[DefaultInfo].files.to_list()
    gate_flist = ctx.attr.gate[DefaultInfo].files.to_list()
    golden_srcs = _flatten_verilog_srcs(ctx.attr.gold[VerilogInfo])
    gate_srcs = _flatten_verilog_srcs(ctx.attr.gate[VerilogInfo])

    eqy_script = ctx.actions.declare_file("{}.eqy".format(ctx.attr.name))

    ctx.actions.expand_template(
        template = ctx.file.eqy_script_template,
        output = eqy_script,
        substitutions = {
            "{{DEPTH}}": str(ctx.attr.depth),
            "{{GATE_FLIST}}": gate_flist[0].path,
            "{{GOLD_FLIST}}": golden_flist[0].path,
            "{{MODULE_TOP}}": ctx.attr.module_top,
            "{{PREP_COMMANDS}}": "\n".join(ctx.attr.prep_commands),
            "{{STRATEGY_COMMANDS}}": "\n".join(ctx.attr.extra_strategy_commands),
            "{{STRATEGY_NAME}}": ctx.attr.strategy,
            "{{STRATEGY}}": ctx.attr.strategy,
        },
    )

    workdir = ctx.actions.declare_directory("{}_eqy_workdir".format(ctx.attr.name))

    log_file = ctx.actions.declare_file("{}_eqy.log".format(ctx.attr.name))

    make_data = access_tool(_MAKE_TOOLCHAIN_TYPE, ctx)
    toolchain_inputs = [make_data.target.files] if make_data.target else []
    eqy_runfiles = ctx.attr._eqy_tool[DefaultInfo].default_runfiles.files.to_list()
    inputs = depset(
        direct = [eqy_script] + golden_flist + gate_flist + golden_srcs + gate_srcs + eqy_runfiles,
        transitive = toolchain_inputs,
    )

    commands = [
        "set -euo pipefail",
        # Set make path
        'export PATH="$(pwd)/$(dirname "%s"):$PATH"' % make_data.path,
    ]

    commands += formal_tool_commands(ctx.executable._eqy_tool, eqy_runfiles)
    commands.append('exec "%s" -c -d "%s" "%s"' % (ctx.executable._eqy_tool.path, workdir.path, eqy_script.path))
    ctx.actions.run_shell(
        outputs = [workdir],
        inputs = inputs,
        tools = [ctx.attr._eqy_tool[DefaultInfo].files_to_run],
        # EQY's partition step changes the working directory
        # Make sure to set the env up beforehand
        command = "\n".join(commands) + "\n",
        mnemonic = "EqyCheck",
        progress_message = "Running EQY equivalence check %{label}",
    )

    ctx.actions.run_shell(
        outputs = [log_file],
        inputs = [workdir],
        command = "cp '{}/logfile.txt' '{}'".format(workdir.path, log_file.path),
        mnemonic = "EqyCheckCollectLog",
        progress_message = "Collecting EQY log for %{label}",
    )

    return [
        DefaultInfo(
            files = depset([workdir, log_file]),
        ),
    ]

eqy_check_attrs = {
    "depth": attr.int(
        default = 20,
        doc = "Proof depth passed to the equivalence-checking strategy.",
    ),
    "eqy_script_template": attr.label(
        doc = "The .eqy script template",
        default = "//eqy:script.eqy.tpl",
        allow_single_file = True,
    ),
    "extra_strategy_commands": attr.string_list(
        doc = "Extra lines appended to the end of the strategy section.",
    ),
    "gate": attr.label(
        mandatory = True,
        providers = [DefaultInfo, VerilogInfo],
        doc = "verilog_filelist for the design to check.",
    ),
    "gold": attr.label(
        mandatory = True,
        providers = [DefaultInfo, VerilogInfo],
        doc = "verilog_filelist for the known, good reference design.",
    ),
    "module_top": attr.string(
        mandatory = True,
        doc = "Name of the top-level module to check.",
    ),
    "prep_commands": attr.string_list(
        default = [
            "proc",
            "async2sync",
            "flatten",
            "opt_clean",
        ],
        doc = "Yosys commands run (in order) on both designs, after reading the sources.",
    ),
    "strategy": attr.string(
        default = "sat",
        doc = "EQY strategy.",
        values = ["sat", "sby", "dummy"],
    ),
    "_eqy_tool": attr.label(
        default = Label("@eqy"),
        executable = True,
        cfg = "exec",
    ),
}

eqy_check = rule(
    doc = """Formally checks that two Verilog/SystemVerilog designs are equivalent.

Generates a `.eqy` script that reads `gold` as the 'gold' design and `gate` as
the 'gate' design, checks both designs' hierarchy against `module_top`, runs
`prep_commands` on each, and then hands off to EQY's `strategy` to prove (or
disprove) that the two designs compute the same function. The check fails the
build if EQY does not report the designs equivalent.

    """,
    implementation = _eqy_check_impl,
    attrs = eqy_check_attrs,
    toolchains = [_MAKE_TOOLCHAIN_TYPE],
)
