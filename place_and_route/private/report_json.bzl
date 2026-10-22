"""Helper functions for JSON reporting"""

def report_timing_json(var_name):
    """Return an openroad command generating JSON formatted timing results

    Returns:
        String with TCL commands to generate a JSON timing output

    Args:
        var_name: name of the TCL variable to store the result
    """

    cmd = """
tee -variable report_wns_setup -quiet {report_wns -max}
tee -variable report_tns_setup -quiet {report_wns -max}
tee -variable report_wns_hold -quiet {report_wns -min}
tee -variable report_tns_hold -quiet {report_wns -min}
set wns_setup [lindex [split $report_wns_setup " "]  2]
set tns_setup [lindex [split $report_tns_setup " "] 2]
set wns_hold [lindex [split $report_wns_hold " "] 2]
set tns_hold [lindex [split $report_tns_hold " "] 2]
tee -variable clock_properties -quiet {report_clock_properties}
set clock_properties_lines [lreplace [split $clock_properties "\\n"] 0 1]
set json_clks "\\n\\\"clocks\\\": {\\n"
set separator ""
foreach line $clock_properties_lines {
set content [regexp -inline -all -- {\\S+} $line]
set clk_name [lindex $content 0]
set clk_period [lindex $content 1]
if {[string trim $clk_name] ne "" && [string trim $clk_period] ne ""} {
append json_clks "$separator    \\\"$clk_name\\\": $clk_period"
set separator ",\\n"
}
}
append json_clks "}"
set json_timing "    \\\"setup\\\": {\\n"
append json_timing "        \\\"wns\\\": $wns_setup,\\n"
append json_timing "        \\\"tns\\\": $tns_setup\\n"
append json_timing "},\\n    \\\"hold\\\": {\\n"
append json_timing "        \\\"wns\\\": $wns_hold,\\n"
append json_timing "        \\\"tns\\\": $tns_hold\\n"
append json_timing "},"
append json_timing $json_clks\n""" + "set %s $json_timing" % var_name
    return cmd

def report_power_json(var_name):
    """Return an openroad command generating JSON formatted power results

    Returns:
        String with TCL commands to generate a JSON power output

    Args:
        var_name: name of the TCL variable to store the result
    """

    cmd = "tee -variable %s -quiet { report_power -format json }" % var_name
    return cmd

def report_area_json(var_name):
    """Return an openroad command generating JSON formatted area results

    Returns:
        String with TCL commands to generate a JSON area output

    Args:
        var_name: name of the TCL variable to store the result
    """

    cmd = """
tee -variable report_area -quiet {{report_design_area}}
set design_area [lindex [split $report_area " "] 2]
set area_util [string trim [lindex [split $report_area " "] 4] "%"]
set json_area "\\\"design_area\\\": $design_area,\\n"
append json_area "\\\"utilization\\\": $area_util\\n"
""" + "set %s $json_area" % var_name
    return cmd

def report_units_json(var_name):
    """Return an openroad command generating JSON formatted units report

    Returns:
        String with TCL commands to generate a JSON area output

    Args:
        var_name: name of the TCL variable to store the result
    """

    cmd = """
tee -variable content -quiet { report_units }
dict set unit_dict "percentage" "%"
foreach line [split $content "\\n"] {
  set name  [lindex $line 0]
  set value [lindex $line end]
  if {[string trim $name] ne "" && [string trim $value] ne ""} {
    dict set unit_dict $name $value
  }
}
dict set unit_dict area "[dict get $unit_dict distance]2"
set separator ""
foreach item [dict keys $unit_dict] {
    append json_unit "$separator\\\"$item\\\": \\\"[dict get $unit_dict $item]\\\""
    set separator ",\\n"
}
""" + "set %s $json_unit" % var_name

    return cmd
