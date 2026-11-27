# 0.0.7 (dev)

# 0.0.6

Added:
  * `reg_gen`
    * Initial implementation of SystemRDL register generation
    * `reg_gen` macro generating RTL, a C header, HTML and Markdown documentation and a UVM RAL model from SystemRDL sources
    * Product-specific macros: `reg_gen_rtl`, `reg_gen_chdr`, `reg_gen_html`, `reg_gen_md`, `reg_gen_ral`
    * `rdl_library` rule for transitive SystemRDL sources and `pyral_gen` wrapping the PyRDL generator
  * `power_analysis`
    * New `post_sim_power_analysis` rule computing post-synthesis power from a simulation SAIF activity file with OpenROAD
    * `sim_build` and `sim_genrules` now support `trace = "saif"`
    * `sim_run` and `sim_genrules` gained `extra_verilator_run_data` for runtime files
  * `autotuner`
    * New framework for automated RTL-to-GDS parameter tuning (`run_autotuner_tune`)
    * Search algorithms: random/grid search, population based training, HyperOpt, AxSearch, Optuna and Nevergrad
    * Distributed execution with Ray and TensorBoard logging
  * `place_and_route`
    * `custom_openroad_script` rule and `custom_post_step_scripts` attribute to run custom TCL scripts after any flow step
  * `synthesis`
    * New rules: `translate` (RTL to RTLIL), `synth_opt` (RTLIL to netlist) and `reformat_json`
    * Optimization strategies for `synth_opt`: `basic`, `area`, `speed`, `lite`, `lms` (lazy man's synthesis) and `custom`
    * `target_clock_period_pico_seconds` attribute driving the timing constraints of the optimization

Changed:
  * `verilator`
    * Bumped Verilator to version `5.054-43872a4`
  * `openroad`
    * Updated OpenROAD to commit `11179215` and its toolchain (LLVM 20, Tcl 9)
  * `synthesis`
    * Reworked into a two-step `translate` + `synth_opt` flow; removed `synthesis_binary` and `ExternalSynthesisInfo`
    * Per-strategy ABC scripts with the target clock period substituted
  * `place_and_route`
    * Global routing now re-runs `repair_design` and `repair_timing` using the global-routing parasitics
    * Clock propagation enabled after global routing and in benchmark timing reports
    * Reduced global routing congestion iterations to 10 with `-allow_congestion`
  * `asap7`
    * ASAP7 packages and cell files are now publicly visible

Fixed:
  * `place_and_route`
    * Fixed power unit reporting in JSON reports

# 0.0.5

Added:
  * `uvm-overlay`
    * Target to provide the UVM library source code
  * `synthesis`
    * `slang` and `surelog` can now be selected as synthesis frontends
  * `place and route`
    * generation of JSON reports

Changed:
  * `verilator`
    * Bumped Verilator to version `5.052-0177067`
    * Improved precompilation of headers
    * Fixed PLI linking to enable UVM build with the DPI enabled
  * `synthesis`
    * Bumped Yosys to version `0.70`
    * Yosys is again built from sources once again

Fixed:
  * `synthesis`
    * Enabled include directives
  * `static_timing`
    * SDC files can now be passed to the OpenSTA flow

# 0.0.4

* Bumped `rules_python` to version 2.4.2

# 0.0.3

Added:
* `cocotb_test` now generates an additional binary target named like the regular test target, but suffixed with ".debug".
  It can be invoked with `bazel run`, and it allows for interactive debugging inside the cocotb test by e.g. using `breakpoint()` inside the code or setting the COCOTB_PDB_ON_EXCEPTION=1 environment variable.
* `verilator_package` is a new rule, which generates an archive useful for local reproduction
  * Example usage:
```
  bazel build //macros/sim_genrules_test:minimal_randomization_verilator_package
```
  * The expected output is a .tar archive, which contains:
    * All verilog sources needed to build the test
    * `run.sh` script which can be used to run the test with verilator (system installation)
  * The local reproduction is not a 1:1 reproduction of the bazel flow, but rather a quality of life improvement to be able to test with a different version of verilator, report bugs or minimize examples with `sv-bugpoint`
* `sim_genrules` now declares an implicit `verilator_package` target

Changed:
* Bumped `oss_cad_suite` version
* `cocotb/verilator` now outputs XML files in the desired format
* `verilator` tracing is now consistent with `cocotb/verilator` - arguments are: `trace = "fst"`
  * A hook to dump the traces is needed in your testbench, which should follow:
```
initial begin
    string trace_file;

    if ($value$plusargs("trace=%s", trace_file)) begin
      $dumpfile(trace_file);
      $dumpvars(0, tb);
    end
  end
```

Fixed:
* `sby` incorrectly processed include files
* `verilator` incorrect passing of trace arguments when used with sim_genrules

# 0.0.2

Changed:
* Bumped cocotb to 2.1.0
* Split cocotb Icarus and Verilator implementations
* Fixed bug in Verilator CPP copy which prevented caching
* Enabled waveform dumping for cocotb simulations
* Bumped yosys to 0.68 (non-hermetic)
* cocotb_test API changed:
  * Simplified simulator selection
  * Changed `waves` from boolean to string reflecting type of desired waveform

Instead of:
```
  sim = ["//cocotb:verilator"],
  sim_name = "verilator",
```
do:
```
  sim = "verilator",
```

Instead of:
```
  waves=True
```
do:
```
  waves = "fst" # or ["vcd", "none"]
```

Added:
* Support for Yosys SBY formal verification flow

# 0.0.1

Initial version of bazel_rules_hdl
