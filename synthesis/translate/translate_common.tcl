yosys -import
set top {{TOP}}
set rtlil_netlist {{RTLIL_NETLIST}}
set stdcell_lib {{STDCELL_LIB}}
set liberty [list $stdcell_lib]
{{EXTRA_LIBS}}
set include_dirs [list {{INCDIR}}]
set stdcell_blackbox_file {{STDCELL_BLACKBOX}}
set macro_names [list {{MACRO_NAMES}}]
set macro_values [list {{MACRO_VALUES}}]
set rtl_files [list {{RTL_FILES}}]
