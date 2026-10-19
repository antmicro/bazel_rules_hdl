# Autotuner flow
This has been extracted from (OpenROAD-flow-scripts)[https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/tree/master] commit 2aeb23bcc3b5aa925abb991c4347ce73827b8b82
The goal is to integrate this in a bazel native environment

# Workflow
The user has autotuner exposed as a bazel target.
Only `tune` is supported for now. It is parametrized with a `json` file that matches the parameters exposed by `bazel_rules_hdl` synthesis and PnR targets.

The flow can be run without triggering a true rtl2gds flow by using -- --dry-run after the `bazel run //:my_target` command

# Dev notes
## Paths
3 big paths to distinguish what is going on :
* WORKSPACE_ROOT : this is the main project root path, where the user has its MODULE.bazel file (bazel_rules_hdl here).
  This is used by Bazel.
* RUN_DIR : this is top directory for a given autotuner target, that holds all of the iterations and samples (autotuner_runs/tests/verilog-counter-tune here).
  This is managed by autotuner's python code
* EXPERIMENT_DIR : hold a single experiment : one set of input parameter and one run of the flow (synthesis, PnR, STA)
  This is managed by generated bazel files
  There is a different one for each iterations and samples
