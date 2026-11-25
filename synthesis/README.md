# Synthesis rules

Bazel rules for synthesis flow using [Yosys](https://yosyshq.readthedocs.io/en/latest/)

The following are defined in `//synthesis:defs.bzl`:

* `synthesize_rtl`: RTL sources to synthesized netlist, in a single target
* `translate`: RTL sources to yosys intermediate representation (RTLIL)
* `synth_opt`: RTLIL to synthesized netlist
* `benchmark_synth`: report the main metrics of a synthesized target
* `reformat_json`: convert the Yosys statistics JSON into the report JSON format
* `sdc_library`: convert raw SDC files to an SdcInfo (not directly part of the synthesis flow)

## Quickstart

`synthesize_rtl` creates a synthesized netlist from RTL sources. Example :

```
load("//synthesis:defs.bzl", "synthesize_rtl")

synthesize_rtl(
    name = "verilog_counter-synth",
    frontend = "slang",
    standard_cells = for_each_sky130_cells(
        "sc_hd",
        include_corners = ["ff"],
        include_temps = ["100C"],
        include_volts = ["1v65"],
    )[0][1],
    top_module = "verilog_counter",
    deps = [
        ":verilog_counter",
    ],
)
```

`bazel build :verilog_counter-synth` produces the synthesized netlist `verilog_counter-synth_netlist.v`.

`standard_cells` takes one standard cell library at one corner, which is what the selection in the example does (see [Standard cell libraries](#standard-cell-libraries)).

The optimization targets a clock period of 100000 ps (100 ns) unless `target_clock_period_pico_seconds` is set.

## Tips
* You can get the logs and reports by adding `--output_groups=+logs,+reports` to the bazel build command.
  Output groups differ slightly between rules, see [Outputs](#outputs).
* The `+` matters: without it, the listed groups *replace* the default outputs instead of adding to them.
* `synthesize_rtl` does not expose the intermediate RTLIL netlist. Use `translate` and `synth_opt` separately (see below) if you need it.

## Step-by-step flow

It is possible to run the synthesis flow step-by-step to inspect inputs/outputs or for further optimization.
The synthesis flow is composed the following steps :
* translate : Read all the RTL sources and write a netlist in intermediate representation (RTLIL) that is yosys specific. No optimization is applied
* synth_opt : Perform library mapping, synthesis optimization and write the resulting verilog netlist
* benchmark_synth : Report the main metrics of the synthesis steps

`synthesize_rtl` runs `translate` followed by `synth_opt`, plus the reporting steps (statistics report and benchmark).

Example, equivalent to the quickstart but split in steps :

```
load("//synthesis:defs.bzl", "benchmark_synth", "synth_opt", "translate")

STD_CELLS = for_each_sky130_cells(
    "sc_hd",
    include_corners = ["ff"],
    include_temps = ["100C"],
    include_volts = ["1v65"],
)[0][1]

translate(
    name = "verilog_counter-translate",
    frontend = "slang",
    standard_cells = STD_CELLS,
    top_module = "verilog_counter",
    deps = [":verilog_counter"],
)

synth_opt(
    name = "verilog_counter-opt",
    rtlil_netlist = ":verilog_counter-translate",
    standard_cells = STD_CELLS,
    target_clock_period_pico_seconds = 10000,
    top_module = "verilog_counter",
)

benchmark_synth(
    name = "verilog_counter-benchmark",
    synth_target = ":verilog_counter-opt",
)
```

```
bazel build :verilog_counter-translate                                  # RTLIL netlist only
bazel build :verilog_counter-opt --output_groups=+logs,+auxiliary       # netlist, log and Yosys statistics
bazel run   :verilog_counter-benchmark                                  # print the metrics
```

`rtlil_netlist` of `synth_opt` accepts a `translate` target or any single RTLIL file.

**Keep the settings consistent between steps.** `standard_cells`, `extra_libs` and `top_module` are set independently on each rule, and nothing checks that they match. A mismatch typically shows up late, as an error in the `synth_opt` step.

## Rules

### `translate`

Reads the RTL and writes an RTLIL netlist. The generated script also reads the liberty files, checks the hierarchy for `top_module` and writes the RTLIL.

| Attribute | Description |
|---|---|
| `deps` | RTL libraries (`VerilogInfo`) |
| `top_module` | Name of the RTL top module (default `top`) |
| `frontend` | `yosys` (default), `slang`, `surelog` or `custom`, see [Frontends](#frontends) |
| `verilog_defines` | List of strings `"NAME"` or `"NAME=VALUE"`. `NAME` alone is defined as `1` |
| `parser_extra_commands` | Extra arguments appended to the frontend read command. The user is responsible for the syntax |
| `translate_tcl` | Tcl script used when `frontend = "custom"` |
| `standard_cells` | The standard cell library of the design (`StandardCellInfo`), see [Standard cell libraries](#standard-cell-libraries) |
| `extra_libs` | Additional libraries (`StandardCellInfo`) the RTL may instantiate. Read as blackboxes only |
| `tool_extra_args` | Extra command-line arguments for yosys |
| `output_file_name` | Name of the RTLIL file (default `<name>_netlist.rtlil`) |

### `synth_opt`

Reads an RTLIL netlist, runs the optimization script and writes the synthesized verilog netlist and the Yosys statistics.

| Attribute | Description |
|---|---|
| `rtlil_netlist` | RTLIL netlist, usually a `translate` target |
| `top_module` | Name of the top module (default `top`) |
| `standard_cells`, `extra_libs` | As in `translate` |
| `strategy` | `basic` (default), `lms` or `custom`, see [Optimization strategies](#optimization-strategies) |
| `target_clock_period_pico_seconds` | Target clock period in picoseconds (default `100000`), passed to the optimization script as `period_ps` |
| `custom_synth_opt_tcl` | Main optimization script when `strategy = "custom"` |
| `custom_srcs` | Extra input files for the custom script |
| `tool_extra_args` | Extra command-line arguments for yosys |
| `verilog_netlist_name` | Name of the verilog netlist (default `<name>_netlist.v`) |

### `synthesize_rtl`

`translate` followed by `synth_opt`, then the statistics report and the benchmark. It accepts the attributes of both rules, except `rtlil_netlist` and `output_file_name`.

Note that `tool_extra_args` is used for both yosys invocations.

### `benchmark_synth`

Takes any target providing `SynthesisInfo` (`synth_opt` or `synthesize_rtl`) as `synth_target`. `bazel run` prints the area, longest topological path, flop count, liberty and CPU time lines found in the synthesis log.

### `reformat_json`

Converts the Yosys statistics JSON (`yosys_stats`, a single file) into the report JSON format. The statistics are in the `auxiliary` output group of `synth_opt` and `synthesize_rtl`. To use them, select the group with a `filegroup` :

```
filegroup(
    name = "verilog_counter-stats",
    srcs = [":verilog_counter-opt"],
    output_group = "auxiliary",
)

reformat_json(
    name = "verilog_counter-report",
    yosys_stats = ":verilog_counter-stats",
)
```

`synthesize_rtl` already produces this report, in its `reports` output group.

## Outputs

The main output of each rule is its default output. Everything else is in output groups, which are only built on request (`--output_groups=+<group>`).

| Rule | Default output | `logs` | `reports` | `auxiliary` | `blackbox` |
|---|---|---|---|---|---|
| `translate` | `<name>_netlist.rtlil` | `<name>_synthesis_translate.log` | | | `<name>_stdcells_blackbox.v` |
| `synth_opt` | `<name>_netlist.v` | `<name>_synthesis_opt.log` | | `<name>_yosys_stats.json` | |
| `synthesize_rtl` | `<name>_netlist.v` | translate and opt logs | `<name>_synthesis_report.json`, `<name>_report.textproto` | `<name>_yosys_stats.json` | `<name>_stdcells_blackbox.v` |

`synth_opt` and `synthesize_rtl` also return `SynthesisInfo` (netlist, top module, standard cells and log file) and `VerilogInfo`, so the netlist can be used as a verilog dependency of other rules.

## Standard cell libraries

The flow is built around a single standard cell library, `standard_cells`. It is the only library used for :
* mapping and the area and timing statistics (`stdcell_lib`)
* the PDK configuration : ABC constraints (driving cell and load), do-not-use cells, adder mapping and tie cells

`extra_libs` can load additional libraries (macros, IO cells...) that the RTL instantiates. They are read as blackboxes only, and are not used for mapping, statistics or constraints.

For each library, only the default corner (`default_corner.liberty`) is used.

## Frontends

| `frontend` | Reads the RTL with | `verilog_defines` |
|---|---|---|
| `yosys` | `read_verilog -sv` | `-DNAME=VALUE` |
| `slang` | `read_slang` | `--define-macro NAME=VALUE` |
| `surelog` | `read_systemverilog` | `+define+NAME=VALUE` |
| `custom` | your own script (`translate_tcl`) | not used |

Defines example :

```
verilog_defines = [
    "DEBUG_EN=1",
    "WITH_TRACE",
    "CACHE_SIZE_KB=32",
]
```

## Customization

### Custom frontend

Set `frontend = "custom"` and provide `translate_tcl`. The script is sourced after the generated header, which already did :
* set `top` (the top module), `stdcell_lib` (liberty file of `standard_cells`) and `liberty` (liberty files of `standard_cells` and `extra_libs`)
* read all the liberty files as blackboxes

The script must read the RTL. Afterwards the rule runs `hierarchy -check -top $top` and writes the RTLIL itself, so the script should not do it. `verilog_defines`, `parser_extra_commands` and the generated read command are not used.

### Optimization strategies

* `basic` (default): Basic optimization script from yosys and ABC
* `lms`: Use lazy mans synthesis strategy. Derived from (PULP Platform)[https://github.com/pulp-platform/croc/tree/main/yosys/scripts]
* `lite`: Less optimization for faster runtime, expect lower QoR
* `speed`: Strategy focused on reaching higher frequencies at the expanse of area. Uses ABC for sequential mapping
* `area`: Strategy focused on reaching lower area at the expanse of performance. Uses ABC for sequential mapping
* `custom`: sources your own script, given as `custom_synth_opt_tcl`. Additional files it needs go in `custom_srcs`

## Known limitations

* The `surelog` frontend is untested and does not take UhdmInfo into account
* This flow assumes all standard cells are provided in a single liberty file; `extra_libs` can be used to load extra liberty files but are not used for logic mapping
