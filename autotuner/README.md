# Autotuner

_AutoTuner_ is a "no-human-in-loop" parameter tuning framework for commercial and academic RTL-to-GDS flows.
AutoTuner provides a generic interface where users can define parameter configuration as JSON objects.

Autotuner provides an automated solution to improve RTL-to-GDS (hyper)parameters in order to extract improved PPA.
It exposes multiple search algorithms:
* Random/Grid Search
* Population Based Training ([PBT](https://www.deepmind.com/blog/population-based-training-of-neural-networks))
* Tree Parzen Estimator ([HyperOpt](https://hyperopt.github.io/hyperopt))
* Bayesian + Multi-Armed Bandit ([AxSearch](https://ax.dev/))
* Tree Parzen Estimator + Covariance Matrix Adaptation Evolution Strategy ([Optuna](https://optuna.org/))
* Evolutionary Algorithm ([Nevergrad](https://github.com/facebookresearch/nevergrad))


## Tool setup

In order to use Autotuner, add the following in you `.bazelrc` file:
```
build:autotuner --symlink_prefix=/
build:autotuner --disk_cache=autotuner_runs/.cache/disk_cache
build:autotuner --repository_cache=autotuner_runs/.cache/repository_cache
```

To enable it on your design, update your `BUILD` file following this example:
```
load("@rules_hdl//autotuner:build_defs.bzl", "run_autotuner_tune")

run_autotuner_tune(
    name = "veer-el2_tune",
    cells = "@org_theopenroadproject_asap7sc7p5t_28//:asap7-sc7p5t_rev28_rvt-ccs_tt",
    config = "//:autotuner.json",
    jobs = 2,
    samples = 2,
    sdc = "//:constraint_axi4",
    top = "el2_veer_wrapper",
    deps = [
        "//:veer_el2_axi4_verilog_lib",
    ],
)
```

| Argument                      | Description                                                                                           | Default |
|--------------------------------|---------------------------------------------------------------------------------------------------------|---------|
| `name`                        | Name of the bazel target                                                                              ||
| `config`                      | Configuration file that sets which knobs to use for Autotuning.                                       ||
| `algorithm`                   | Search algorithm to use for Autotuning.                                                               | hyperopt |
| `deps`                        | VerilogLibrary target of the design                                                                   ||
| `top`                         | Name of the RTL top level                                                                             ||
| `cells`                       | Standard cells targets to use                                                                         ||
| `perturbation`                | Perturbation interval for PopulationBasedTraining                                                     | 25 |
| `sdc`                         | Target for SDC file                                                                                   ||
| `samples`                     | Number of samples for tuning.                                                                         | 1 |
| `stop_after_step`             | Last PnR step to be performed                                                                         | detailed_routing |
| `synth_additional_args`       | Extra arguments for synthesis                                                                         ||
| `synth_tcl`                   | Alternative tcl script for synthesis                                                                  | None (use default) |
| `iterations`                  | Number of iterations for tuning.                                                                      | 1 |
| `jobs`                        | Max number of concurrent jobs.                                                                        | 1 |
| `run_dir`                     | Run directory                                                                                         | autotuner_runs/<DERIVED_FROM_PACKAGE> |
| `server`                      | Ray remote server IP                                                                                  ||
| `port`                        | Port for Ray's remote server                                                                          | 10001 |
| `ppa_coeff`                   | Override default PPA coefficient (Max Freq, Power, Area)                                              | 1000,100,100 |



## JSON configuration

The search space is configured using a JSON file. An example is given below

```json
{
    "synthesize_rtl.target_clock_period_pico_seconds": {
        "type": "int",
        "minmax": [
            1000,
            10000
        ],
        "reference": 4000
    },
    "place_and_route.placement_density": {
        "type": "float",
        "minmax": [
            20,
            50
        ],
        "reference": 40
    },
    "place_and_route.enable_improve_placement": {
        "type": "bool",
        "choices": [
            0,
            1
        ],
        "reference": 1
    },
    "place_and_route.target_die_utilization_percentage": {
        "type": "int",
        "minmax": [
            40,
            60
        ],
        "reference": 50
    },
    "place_and_route.core_padding_microns": {
        "type": "int",
        "minmax": [
            1,
            10
        ],
        "reference": 5
    }
}
```

* `"type"`: Parameter type: "float", "int", "bool", "string"
* `"minmax"`: Min-to-max range for parameter exploration. The unit follows the default value of each technology std cell library. Lower bound in inclusive, upper bound is exclusive
* `"choices"`: List of discrete values to export
* `"reference"`: Value used for the reference run

Constants can be set with `"choices": [<MYCONST>]`.
`minmax` and `choices` are incompatible
`string` and `bool` types only supports `choices`.

## Source
This has been extracted from (OpenROAD-flow-scripts)[https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/tree/master] commit 2aeb23bcc3b5aa925abb991c4347ce73827b8b82
It has been adapted to integrate with (bazel_rules_hdl)[https://github.com/hdl/bazel_rules_hdl]
Only the tuning functionality has been ported.

## Usage tips and tricks
* The flow can be run without triggering a true rtl2gds flow by using `-- --dry-run` after the `bazel run //:my_target` command.
* Individual logs can be retrieved with verbose mode; add `-- --verbose` after the `bazel run //:my_target` command.
* The tuning algorithms can make better guesses if the reference run is successfull.
* Only the PBT algorithm uses iterations, thus leave this parameter at 1 for other algorithm

## Dev notes
### Paths
3 big paths to distinguish what is going on :
* WORKSPACE_ROOT : this is the main project root path, where the user has its MODULE.bazel file (bazel_rules_hdl here).
  This is used by Bazel.
* RUN_DIR : this is top directory for a given autotuner target, that holds all of the iterations and samples (autotuner_runs/tests/verilog-counter-tune here).
  This is managed by autotuner's python code
* EXPERIMENT_DIR : hold a single experiment : one set of input parameter and one run of the flow (synthesis, PnR, STA)
  This is managed by generated bazel files
  There is a different one for each iterations and samples

### Program flow
The bazel tune target runs the `distributed.py` python script.
This script will generate bazel BUILD files on-the-fly for each experiment.
The first step of the python script is always a reference RTL2GDS run.
This reference run has 2 purposes : it builds all the tools (yosys, openroad, openSTA,...) once so it is in bazel cache for subsequent run and provide a reference points for the subsequent runs.
Due to this new behavior, the `ppa-improv` functionality that was exposed to the user has been removed.
At the end of an experiment, the resulting JSON report is read back, metrics extracted and computed and passed down to the tuner algorithm.

### TODO
* The reference run parameters may be rerun again by the optimizer, check how to pass `evaluated_rewards` to Ray to see if that can be prevented
* At least some of the algorithms like optuna and hyperopt could support conditional search space (x,y [0.10] with x > y), how to implement such a feature is TBD
* Logic around server/port arguments is untested
* The tensorboard GUI may be broken, but also likely unaccessible as it would be running inside the docker container
* The generation on-the-fly of BUILD files is not a properly-supported bazel workflow. An alternative approach would be welcome, but has to fullfill 2 fundamental requirements:
  1) Reuse of the `bazel_rules_hdl` synthesize_rtl and place_and_route targets
  2) Keep Ray's orchestration working
  3) Search algorithms must be able to generate their results based on previous experiments

### Algorithm managements
The different algorithms are not consistent in how they treat parameter search spaces, the functionality they exposes and so on...
It is therefore important to check all possible algorithm after an update.

## Citation

Please cite the following paper.

* J. Jung, A. B. Kahng, S. Kim and R. Varadarajan, "METRICS2.1 and Flow Tuning in the IEEE CEDA Robust Design Flow and OpenROAD", [(.pdf)](https://vlsicad.ucsd.edu/Publications/Conferences/388/c388.pdf), [(.pptx)](https://vlsicad.ucsd.edu/Publications/Conferences/388/c388.pptx), [(.mp4)](https://vlsicad.ucsd.edu/Publications/Conferences/388/c388.mp4), Proc. ACM/IEEE International Conference on Computer-Aided Design, 2021.

## Acknowledgments

AutoTuner has been developed by UCSD with the OpenROAD Project.
