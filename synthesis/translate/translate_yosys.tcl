source {{TRANSLATE_COMMON_TCL}}

# Helper
set include_dirs_arg [lmap elem $include_dirs {format "-I%s" $elem}]
set macro_arg [lmap n $macro_names v $macro_values {format "-D%s=%s" $n $v}]

# Process liberty files
foreach lib $liberty {
    read_liberty -lib $lib
}
write_verilog -blackboxes $stdcell_blackbox_file

# Read RTL
yosys read_verilog -sv \
{{PARSER_EXTRA_COMMANDS}} \
{*}$include_dirs_arg \
{*}$macro_arg \
{*}$rtl_files

hierarchy -check -top $top
write_rtlil $rtlil_netlist
