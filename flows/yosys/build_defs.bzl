# Copyright 2022 Google LLC
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

"""Reimplementing place-and-route using composable and externalizable pieces"""

load("//flows:flows.bzl", "FlowStepInfo", "get_rlocation_path", "script_prefix")
load("//pdk:build_defs.bzl", "StandardCellInfo")

def _yosys_synth_file_step_impl(ctx):
    yosys_runfiles = ctx.attr._yosys[DefaultInfo].default_runfiles
    abc_runfiles = ctx.attr._abc[DefaultInfo].default_runfiles
    runfiles_lib_runfiles = ctx.attr._runfiles_lib[DefaultInfo].default_runfiles

    yosys_wrapper = ctx.actions.declare_file(ctx.attr.name)

    standard_cells = ctx.attr.standard_cells[StandardCellInfo]
    liberty = standard_cells.default_corner.liberty
    synth_tcl = ctx.file.synth_tcl

    yosys_share_root = ""
    tcl_library_dir = ""
    for f in ctx.attr._yosys[DefaultInfo].default_runfiles.files.to_list():
        if not yosys_share_root and f.path.endswith("techmap.v"):
            yosys_share_root = f.dirname + "/"
        if not tcl_library_dir and f.path.endswith("library/init.tcl"):
            tcl_library_dir = f.dirname

    commands = [
        script_prefix,
        "# Use rlocation to find all necessary tools and files",
        'YOSYS=$(rlocation "%s")' % get_rlocation_path(ctx, ctx.executable._yosys),
        'export YOSYS_DATDIR=$(dirname "$YOSYS")/',
        'export TCL_LIBRARY="%s"' % tcl_library_dir,
        'ABC_BIN=$(rlocation "abc/abc_bin")',
        'LIBERTY_FILE=$(rlocation "%s")' % get_rlocation_path(ctx, liberty),
        'SYNTH_TCL=$(rlocation "%s")' % get_rlocation_path(ctx, synth_tcl),
        'export ABC="$ABC_BIN"',
        'export LIBERTY="$LIBERTY_FILE"',
        'export PATH="$YOSYS_DATDIR:$PATH"',
        "# Exec yosys using its resolved path",
        'exec "$YOSYS" -q -q -Q -T -c "$SYNTH_TCL" "$@"',
    ]

    ctx.actions.write(
        output = yosys_wrapper,
        content = "\n".join(commands) + "\n",
        is_executable = True,
    )

    return [
        FlowStepInfo(
            inputs = ["rtl"],
            outputs = ["netlist"],
            constants = ["top"],  # , "clock_period"],
            executable_type = "yosys",
            arguments = [],
        ),
        DefaultInfo(
            executable = yosys_wrapper,
            # TODO(amfv): Switch to runfiles.merge_all once our minimum Bazel version provides it.
            runfiles = ctx.runfiles(files = [synth_tcl, liberty, yosys_wrapper])
                .merge(yosys_runfiles)
                .merge(abc_runfiles)
                .merge(runfiles_lib_runfiles),
        ),
    ]

yosys_synth_file_step = rule(
    implementation = _yosys_synth_file_step_impl,
    attrs = {
        "standard_cells": attr.label(
            doc = "Standard cells to use in yosys synthesis step",
            providers = [StandardCellInfo],
        ),
        "synth_tcl": attr.label(
            default = Label("//flows/yosys:synth.tcl"),
            allow_single_file = True,
            doc = "Tcl script controlling Yosys synthesis, using the Flow Step API environment variables",
        ),
        "_abc": attr.label(
            default = Label("@abc//:abc_bin"),
            executable = True,
            cfg = "exec",
        ),
        "_runfiles_lib": attr.label(
            default = Label("@bazel_tools//tools/bash/runfiles"),
        ),
        "_yosys": attr.label(
            default = Label("@at_clifford_yosys//:yosys"),
            executable = True,
            cfg = "exec",
        ),
    },
)
