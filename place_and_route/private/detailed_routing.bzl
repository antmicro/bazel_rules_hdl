# Copyright 2021 Google LLC
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

"""Detailed Routing openROAD commands"""

load("//pdk:open_road_configuration.bzl", "DetailedRoutingInfo", "get_open_road_configuration")
load("//place_and_route:open_road.bzl", "OpenRoadInfo", "merge_open_road_info", "openroad_command")
load("//synthesis:defs.bzl", "SynthesisInfo")

def detailed_routing(ctx, open_road_info):
    """Performs detailed routing.

    Returns:
        OpenRoadInfo: the openROAD info provider containing required input files and
            and commands run.
    Args:
       ctx: Bazel rule ctx
       open_road_info: OpenRoadInfo provider from a previous step.

    """

    inputs = []

    output_drc = ctx.actions.declare_file("{}_output_drc".format(ctx.attr.name))
    output_power = ctx.actions.declare_file("{}_output_power".format(ctx.attr.name))
    routed_def = ctx.actions.declare_file("{}_detail_routed.def".format(ctx.attr.name))
    report_json = ctx.actions.declare_file("{}_detailed_routing_report.json".format(ctx.attr.name))
    report_checks = ctx.actions.declare_file("{}_detailed_routing_checks.json".format(ctx.attr.name))

    open_road_configuration = get_open_road_configuration(ctx.attr.synthesized_rtl[SynthesisInfo])

    detailed_routing_configs = None
    if open_road_configuration.detailed_routing_configuration:
        detailed_routing_configs = open_road_configuration.detailed_routing_configuration[DetailedRoutingInfo]

    detailed_routing_args = ""
    if detailed_routing_configs:
        if detailed_routing_configs.bottom_routing_layer:
            detailed_routing_args += " -bottom_routing_layer " + detailed_routing_configs.bottom_routing_layer
        if detailed_routing_configs.top_routing_layer:
            detailed_routing_args += " -top_routing_layer " + detailed_routing_configs.top_routing_layer
        if detailed_routing_configs.via_in_pin_bottom_layer:
            detailed_routing_args += " -via_in_pin_bottom_layer " + detailed_routing_configs.via_in_pin_bottom_layer
        if detailed_routing_configs.via_in_pin_top_layer:
            detailed_routing_args += " -via_in_pin_top_layer " + detailed_routing_configs.via_in_pin_top_layer
        if detailed_routing_configs.enable_via_gen:
            detailed_routing_args += " -disable_via_gen "

    open_road_commands = [
        "set_propagated_clock [all_clocks]",
        "detailed_route -output_drc {} {}".format(output_drc.path, detailed_routing_args),
    ]
    density_fill_config = None
    if open_road_configuration.density_fill_config:
        density_fill_config = open_road_configuration.density_fill_config.files.to_list()[0]
    if ctx.file.density_fill_config:
        density_fill_config = ctx.file.density_fill_config

    if density_fill_config:
        open_road_commands.append("set db [ord::get_db]")
        open_road_commands.append("set chip [$db getChip]")
        open_road_commands.append("set block [$chip getBlock]")
        open_road_commands.append("set obstructions [$block getObstructions]")

        open_road_commands.append("foreach obstruction $obstructions {\n" +
                                  "    odb::dbObstruction_destroy $obstruction" +
                                  "\n}")
        open_road_commands.append("density_fill -rules {}".format(density_fill_config.path))
        inputs.append(density_fill_config)

    open_road_commands.append("puts \"report_checks -path_delay min_max -format full_clock_expanded -fields \\\"input_pin slew capacitance\\\" -digits 3\"")
    open_road_commands.append("report_checks -path_delay min_max -format full_clock_expanded -fields \"input_pin slew capacitance\" -digits 3")
    open_road_commands.append("report_checks -path_delay min_max -format json -digits 4 > {}".format(report_checks.path))

    open_road_commands.append("puts \"report_wns\"")
    open_road_commands.append("report_wns")

    open_road_commands.append("puts \"report_tns\"")
    open_road_commands.append("report_tns")

    open_road_commands.append("puts \"report_check_types -max_slew -max_capacitance -max_fanout -violators\"")
    open_road_commands.append("report_check_types -max_slew -max_capacitance -max_fanout -violators")

    open_road_commands.append("puts \"report_floating_nets -verbose\"")
    open_road_commands.append("report_floating_nets -verbose")

    open_road_commands.append("puts \"report_units\"")
    open_road_commands.append("report_units")
    open_road_commands.append("write_def {}".format(routed_def.path))

    ## DRC count, placeholder until better is found
    drc_count_cmd = """
set fp [open "{}" r]
set drc_count 0
while {{[gets $fp line] >= 0}} {{ incr drc_count }}
close $fp
""".format(output_drc.path)
    open_road_commands.append(drc_count_cmd)

    # Timing reports
    timing_report_cmd = """
tee -variable report_wns_setup -quiet {report_wns -max}
tee -variable report_tns_setup -quiet {report_wns -max}
tee -variable report_wns_hold -quiet {report_wns -min}
tee -variable report_tns_hold -quiet {report_wns -min}
set wns_setup [lindex [split $report_wns_setup " "]  2]
set tns_setup [lindex [split $report_tns_setup " "] 2]
set wns_hold [lindex [split $report_wns_hold " "] 2]
set tns_hold [lindex [split $report_tns_hold " "] 2]
set json_timing "\\\"setup\\\": {\\n"
append json_timing "\\\"wns\\\": $wns_setup,\\n"
append json_timing "\\\"tns\\\": $tns_setup\\n"
append json_timing "}, \\\"hold\\\": {\\n"
append json_timing "\\\"wns\\\": $wns_hold,\\n"
append json_timing "\\\"tns\\\": $tns_hold\\n"
append json_timing "}"
"""
    open_road_commands.append(timing_report_cmd)

    # Area report
    area_report_cmd = """
report_design_area
set design_area [sta::format_area [rsz::design_area] 0]
"""
    open_road_commands.append(area_report_cmd)

    # Power report
    power_report_cmd = """
report_power -format json > {output_power}
set fp [open "{output_power}" r]
set power [read $fp]
""".format(output_power = output_power.path)
    open_road_commands.append(power_report_cmd)

    # Units
    unit_cmd = """
tee -variable content -quiet { report_units }
set json_unit ""
set separator ""
foreach line [split $content "\\n"] {
  set name  [lindex $line 0]
  set value [lindex $line end]
  if {[string trim $name] ne "" && [string trim $value] ne ""} {
    set json_line "\\\"$name\\\": \\\"$value\\\""
    append json_unit "$separator$json_line"
    set separator ",\\n"
  }
}
"""
    open_road_commands.append(unit_cmd)

    # Combine results
    json_report_cmd = """
set fp [open "{report_json}" w]
puts $fp "{{\\\"detailed_routing\\\": {{"
puts $fp "  \\\"drc\\\": {{"
puts $fp "    \\\"count\\\": $drc_count"
puts $fp "  }},"
puts $fp "  \\\"area\\\": {{"
puts $fp "    \\\"design_area\\\": $design_area"
puts $fp "  }},"
puts $fp "  \\\"power\\\": $power,"
puts $fp "  \\\"timing\\\": {{\n$json_timing"
puts $fp "  }},"
puts $fp "  \\\"units\\\": {{\\n$json_unit"
puts $fp "}}"
puts $fp "}}"
puts $fp "}}"
close $fp
""".format(report_json = report_json.path)
    open_road_commands.append(json_report_cmd)

    execution_requirements = {}
    if ctx.attr.local_detailed_routing_execution:
        execution_requirements["no-remote-exec"] = ""

    command_output = openroad_command(
        ctx,
        commands = open_road_commands,
        input_db = open_road_info.output_db,
        inputs = inputs,
        outputs = [
            routed_def,
            output_drc,
            output_power,
            report_checks,
            report_json,
        ],
        execution_requirements = execution_requirements,
        step_name = "detailed_routing",
    )

    current_action_open_road_info = OpenRoadInfo(
        commands = open_road_commands,
        input_files = depset(inputs),
        output_db = command_output.db,
        logs = depset([command_output.log_file, output_drc]),
        routed_def = routed_def,
        report_json = depset([report_json]),
    )

    return merge_open_road_info(open_road_info, current_action_open_road_info)
