#!/usr/bin/env python3

# TODO: This is a temporary workaround since Verilator cannot simulate the original description
# of the DFFASRHQNx1 cell from the ASAP7 simulation models, since it relies on specify blocks
# to drive the signals of the cell's functional behavior description.
# Therefore, this script is used to replace the orignal description with a pure behavioral one.
"""Replace the generated ASAP7 async DFF model with the simulation model used here."""

from pathlib import Path
import re
import sys


path = Path(sys.argv[1])
text = path.read_text(encoding="utf8")
pattern = r"module\s+DFFASRHQNx1_ASAP7_75t_R\s*\(.*?endmodule"
replacement = """module DFFASRHQNx1_ASAP7_75t_R (QN, D, RESETN, SETN, CLK);
    output reg QN;
    input D, RESETN, SETN, CLK;
    always @(posedge CLK or negedge RESETN or negedge SETN) begin
        if (!SETN)        QN <= 1'b0;
        else if (!RESETN) QN <= 1'b1;
        else              QN <= ~D;
    end
endmodule"""

text, replacements = re.subn(pattern, lambda _: replacement, text, flags=re.S)
if replacements != 1:
    raise SystemExit(
        f"No DFFASRHQNx1_ASAP7_75t_R module instances; found {replacements}"
    )

# The ASAP7 altos_dff UDP table is interpreted as multiple clocked drivers
# by Verilator. Scope the waiver to that primitive definition only.
pattern = r"(primitive\s+altos_dff\s*\(.*?endprimitive)"
replacement = r"/* verilator lint_off MULTIDRIVEN */\n\1\n/* verilator lint_on MULTIDRIVEN */"
text, replacements = re.subn(pattern, replacement, text, count=1, flags=re.S)
if replacements != 1:
    raise SystemExit(
        f"No altos_dff primitive definition; found {replacements}"
    )

path.write_text(text, encoding="utf8")
