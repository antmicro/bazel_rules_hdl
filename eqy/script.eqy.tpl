[gold]
read_verilog_file_list -f {{GOLD_FLIST}}
hierarchy -check -top {{MODULE_TOP}}
{{PREP_COMMANDS}}

[gate]
read_verilog_file_list -f {{GATE_FLIST}}
hierarchy -check -top {{MODULE_TOP}}
{{PREP_COMMANDS}}

[strategy {{STRATEGY_NAME}}]
use {{STRATEGY}}
depth {{DEPTH}}
{{STRATEGY_COMMANDS}}