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

"""Rules for power analysis using activity from a simulation SAIF file."""

load("//common:providers.bzl", "WaveformInfo")
load("//pdk:open_road_configuration.bzl", "assert_has_open_road_configuration")
load("//place_and_route:open_road.bzl", "openroad_command")
load("//synthesis:defs.bzl", "SynthesisInfo")

def _post_sim_power_analysis_impl(ctx):
    synthesis_info = ctx.attr.synthesized_rtl[SynthesisInfo]
    assert_has_open_road_configuration(synthesis_info)

    standard_cell_info = synthesis_info.standard_cell_info
    tech_lef = standard_cell_info.tech_lef
    cell_lefs = standard_cell_info.cell_lef_definitions
    liberty = standard_cell_info.default_corner.liberty
    additional_liberties = [corner.liberty for corner in standard_cell_info.corners]
    netlist = synthesis_info.synthesized_netlist
    saif_files = ctx.attr.saif_file[WaveformInfo].saif_files
    if len(saif_files) != 1:
        fail("Expected exactly one SAIF file from {}".format(ctx.attr.saif_file.label))
    saif = saif_files[0]

    json_report = ctx.actions.declare_file("{}_report.json".format(ctx.label.name))
    commands = [
        "read_lef {}".format(tech_lef.path),
    ]
    commands.extend(["read_lef {}".format(lef.path) for lef in cell_lefs])
    commands.extend(["read_liberty {}".format(lib.path) for lib in [liberty] + additional_liberties])
    commands.extend([
        "read_verilog {}".format(netlist.path),
        "link_design {}".format(synthesis_info.top_module),
        "create_clock -name core_clock -period {} [get_ports {}]".format(ctx.attr.clock_period, ctx.attr.clock_port),
        "read_saif -scope {} {}".format(ctx.attr.saif_scope, saif.path),
        "tee -variable power_json -quiet { report_power -format json }",
        "set power_json [string trim $power_json]",
        "set power_json [string trimright [string range $power_json 0 end-1]]",
        "set power_json [string map [list \"\\n\" \"\\n    \"] $power_json]",
        "set fh [open {} w]".format(json_report.path),
        'puts $fh "{"',
        'puts $fh "  \\"post-synth\\": {"',
        'puts -nonewline $fh "    \\"power\\": $power_json"',
        'puts $fh ""',
        'puts $fh "    }"',
        'puts $fh "  },"',
        'puts $fh "  \\"units\\": {\\"power\\": \\"1W\\"}"',
        'puts $fh "}"',
        "close $fh",
    ])

    command_output = openroad_command(
        ctx,
        commands = commands,
        inputs = [tech_lef, netlist, saif] + cell_lefs + [liberty] + additional_liberties,
        outputs = [json_report],
        step_name = "post_sim_power_analysis",
    )
    command_file = ctx.actions.declare_file("{}.tcl".format(ctx.label.name))
    ctx.actions.write(command_file, content = "\n".join(commands))

    return [
        DefaultInfo(files = depset([json_report, command_file, command_output.log_file])),
        synthesis_info,
    ]

post_sim_power_analysis = rule(
    implementation = _post_sim_power_analysis_impl,
    attrs = {
        "clock_period": attr.string(
            mandatory = True,
            doc = "Clock period in the units used by the PDK; it must match the simulation that generated the SAIF.",
        ),
        "clock_port": attr.string(
            default = "clk",
            doc = "Top-level port used as the clock for power analysis.",
        ),
        "qt_qpa_platform": attr.string(
            default = "minimal",
            doc = "The Qt platform to use with OpenROAD.",
        ),
        "saif_file": attr.label(
            mandatory = True,
            providers = [WaveformInfo],
            doc = "Simulation target that provides one SAIF waveform.",
        ),
        "saif_scope": attr.string(
            mandatory = True,
            doc = "Hierarchy scope in the SAIF file corresponding to the synthesized design.",
        ),
        "synthesized_rtl": attr.label(
            mandatory = True,
            providers = [SynthesisInfo],
        ),
        "_openroad": attr.label(
            default = Label("@org_theopenroadproject//:openroad"),
            executable = True,
            cfg = "exec",
        ),
    },
)
