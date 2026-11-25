source {{TRANSLATE_COMMON_TCL}}

# Process liberty files
foreach lib $liberty {
    read_liberty -lib $lib
}
write_verilog -blackboxes $stdcell_blackbox_file

source {{TRANSLATE_TCL}}

hierarchy -check -top $top
write_rtlil $rtlil_netlist

