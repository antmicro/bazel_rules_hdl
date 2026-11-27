#############################################################################
##
## BSD 3-Clause License
##
## Copyright (c) 2019, The Regents of the University of California
## All rights reserved.
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions are met:
##
## * Redistributions of source code must retain the above copyright notice, this
##   list of conditions and the following disclaimer.
##
## * Redistributions in binary form must reproduce the above copyright notice,
##   this list of conditions and the following disclaimer in the documentation
##   and/or other materials provided with the distribution.
##
## * Neither the name of the copyright holder nor the names of its
##   contributors may be used to endorse or promote products derived from
##   this software without specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
## AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
## IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
## ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
## LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
## CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
## SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
## INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
## CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
## ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
## POSSIBILITY OF SUCH DAMAGE.
##
###############################################################################

"""
Python wrapper around Ray to manage parameter tuning of the PnR flow from bazel_rules_hdl
"""

import argparse
import json
import os
import sys
import shutil
import random
from collections import namedtuple
from multiprocessing import cpu_count

import numpy as np
import torch

import ray
from ray import tune
from ray.tune.schedulers import AsyncHyperBandScheduler
from ray.tune.schedulers import PopulationBasedTraining
from ray.tune.search import ConcurrencyLimiter
from ray.tune.search.ax import AxSearch
from ray.tune.search.basic_variant import BasicVariantGenerator
from ray.tune.search.hyperopt import HyperOptSearch
from ray.tune.search.optuna import OptunaSearch
from ray.tune.search.sample import Categorical, Float, Integer

from ax.service.ax_client import AxClient

from autotuner.utils import (
    read_config,
    read_metrics,
    calculate_score,
    ERROR_METRIC,
    CONSTRAINTS_SDC,
)
from autotuner.tensorboard_logger import TensorBoardLogger

from autotuner.bazel_flow import BazelFlow, validate_search_space

# Name of the final metric
METRIC = "metric"
# Global variable for args
args = None


class AutoTunerBase(tune.Trainable):
    """
    AutoTuner base class for experiments.
    """

    def setup(self, config):
        """
        Setup current experiment step.
        """
        self.params = dict(config)
        self.step_ = 0
        self.is_valid_config = self._is_valid_config(config)
        self.flow = make_flow(args.jobs)

    def step(self):
        """
        Run step experiment and compute its score.
        """

        # if not a valid config, then don't run and pass back an error
        if not self.is_valid_config:
            return {
                METRIC: ERROR_METRIC,
                "effective_clk_period": ERROR_METRIC,
                "num_drc": ERROR_METRIC,
                "die_area": ERROR_METRIC,
            }
        ## self.training_iteration is defined by Ray's Trainable
        ## It follows the ongoing iteration counter
        experiment_dir = os.path.join(RUN_DIR, self.trial_name, f"iteration{self.training_iteration}")
        try:
            result = self.flow.run_trial(self.params, experiment_dir=experiment_dir, stop_after_step=args.stop_after_step, parser_extra_commands=args.parser_extra_commands, frontend=args.frontend, save_logs=DEBUG)
        except (RuntimeError, ValueError) as err:
            print(f"[ERROR TUN-0100] {err}")
            return {METRIC: ERROR_METRIC, "effective_clk_period": ERROR_METRIC,
                    "num_drc": ERROR_METRIC, "die_area": ERROR_METRIC}
        self.step_ += 1
        if args.dry_run:
            ## Fake metrics
            return {METRIC: 1.0, "effective_clk_period": 0, "num_drc": 0, "die_area": 0}
        metrics = read_metrics(result["reports"], stop_after_step=args.stop_after_step)
        score, effective_clk_period, num_drc, die_area = self.evaluate(metrics)
        return {METRIC: score, "effective_clk_period": effective_clk_period, "num_drc": num_drc, "die_area": die_area}

    def evaluate(self, metrics):
        """
        User-defined evaluation function.
        It can change in any form to minimize the score (return value).
        Default evaluation function optimizes effective clock period.
        """
        return calculate_score(metrics, step=self.step_)

    def _is_valid_config(self, config):
        """
        Checks dependent parameters and returns False if we violate
        a dependency. That way, we don't end up running an incompatible run
        """

        ret_val = True
        ret_val &= self._is_valid_padding(config)
        return ret_val

    def _is_valid_padding(self, config):
        """Returns True if global padding >= detail padding"""

        if (
            "CELL_PAD_IN_SITES_GLOBAL_PLACEMENT" in config
            and "CELL_PAD_IN_SITES_DETAIL_PLACEMENT" in config
        ):
            global_padding = config["CELL_PAD_IN_SITES_GLOBAL_PLACEMENT"]
            detail_padding = config["CELL_PAD_IN_SITES_DETAIL_PLACEMENT"]
            if global_padding < detail_padding:
                print(
                    f"[WARN TUN-0032] CELL_PAD_IN_SITES_DETAIL_PLACEMENT ({detail_padding}) cannot be greater than CELL_PAD_IN_SITES_GLOBAL_PLACEMENT ({global_padding})"
                )
                return False
        return True

    # Checkpoint for PBT
    def save_checkpoint(self, checkpoint_dir):
        return {"step": self.step_}
    
    def load_checkpoint(self, checkpoint):
        self.step_ = checkpoint["step"]

class PPAImprov(AutoTunerBase):
    """
    PPAImprov
    """

    @classmethod
    def get_ppa(cls, metrics):
        """
        Compute PPA term for evaluate.
        """
        ## coeff_ppa comes as a string like (32,55,111)
        if args.ppa_coeff is not None:
            coeff_list = [int(x.strip()) for x in args.ppa_coeff.split(',')]
            coeff_perform, coeff_power, coeff_area = coeff_list
        else:
            coeff_perform, coeff_power, coeff_area = 10000, 100, 100

        eff_clk_period = metrics["clk_period"]
        # worst_slack is a positive value on failure, 0.0 if timing met
        if metrics["worst_slack"] > 0:
            eff_clk_period += metrics["worst_slack"]

        eff_clk_period_ref = reference_metrics["clk_period"]
        if reference_metrics["worst_slack"] > 0:
            eff_clk_period_ref += reference_metrics["worst_slack"]

        def percent(x_1, x_2):
            # Failsafe for divide by 0
            if x_1 == 0:
                return 100
            return (x_1 - x_2) / x_1 * 100

        performance = percent(eff_clk_period_ref, eff_clk_period)
        power = percent(reference_metrics["total_power"], metrics["total_power"])
        area = percent(100 - reference_metrics["final_util"], 100 - metrics["final_util"])

        # Lower values of PPA are better.
        ppa_upper_bound = (coeff_perform + coeff_power + coeff_area) * 100
        ppa = performance * coeff_perform
        ppa += power * coeff_power
        ppa += area * coeff_area
        return ppa_upper_bound - ppa

    def evaluate(self, metrics):
        error = "ERR" in metrics.values() or "ERR" in reference_metrics.values()
        not_found = "N/A" in metrics.values() or "N/A" in reference_metrics.values()
        if error or not_found:
            return (ERROR_METRIC, ERROR_METRIC, ERROR_METRIC, ERROR_METRIC)
        ppa = self.get_ppa(metrics)
        gamma = ppa / 10
        score = ppa * (self.step_ / 100) ** (-1) + (gamma * metrics["num_drc"])
        effective_clk_period = metrics["clk_period"] + metrics["worst_slack"]
        num_drc = metrics["num_drc"]
        return (score, effective_clk_period, num_drc, metrics["die_area"])


def parse_arguments():
    """
    Parse arguments from command line.
    """
    parser = argparse.ArgumentParser()

    # DUT
    parser.add_argument(
        "--deps",
        type=str,
        metavar="<[:my_module]>",
        required=True,
        action="append",
        help="Verilog structure for bazel_rules_hdl.",
    )
    parser.add_argument(
        "--cells",
        type=str,
        metavar="<@asap7//:pdk>",
        required=True,
        help="Tag to cell library",
    )
    parser.add_argument(
        "--top",
        type=str,
        metavar="<top_wrapper>",
        required=True,
        help="Name of the RTL top-level",
    )
    parser.add_argument(
        "--sdc",
        type=str,
        metavar="<sdc>",
        required=True,
        help="Timing constraints in SDC format",
    )
    parser.add_argument(
        "--rules_hdl_repo",
        type=str,
        metavar="<@bazel_rules_hdl>",
        default="@@",
        help="Name of the bazel_rules_hdl. Switchable for testing purposes",
    )
    parser.add_argument(
        "--frontend",
        type=str,
        choices=["yosys", "slang", "surelog"],
        default="yosys",
        help="Synthesis parser.",
    )
    parser.add_argument(
        "--parser_extra_commands",
        type=json.loads,
        default=None,
        help="Extra commands for synthesis parser in a JSON string",
    )
    # Experiment Setup
    parser.add_argument(
        "--config",
        type=str,
        metavar="<path>",
        required=True,
        help="Configuration file that sets which knobs to use for Autotuning.",
    )
    parser.add_argument(
        "--stop_after_step",
        type=str,
        metavar="<str>",
        choices=["synthesis", "floorplan", "global_placement", "global_routing", "detailed_routing"],
        default="detailed_routing",
        help="Name of the stage to stop after. Default is finish.",
    )
    # ML
    parser.add_argument(
        "--algorithm",
        type=str,
        choices=["hyperopt", "ax", "optuna", "pbt", "random"],
        default="hyperopt",
        help="Search algorithm to use for Autotuning.",
    )
    parser.add_argument(
        "--samples",
        type=int,
        metavar="<int>",
        default=10,
        help="Number of samples for tuning.",
    )
    parser.add_argument(
        "--iterations",
        type=int,
        metavar="<int>",
        default=1,
        help="Number of iterations for tuning.",
    )
    parser.add_argument(
        "--perturbation",
        type=int,
        metavar="<int>",
        default=25,
        help="Perturbation interval for PopulationBasedTraining.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        metavar="<int>",
        default=42,
        help="Random seed. (0 means no seed.)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Generate bazel files but do not call the tools, mock the result instead.",
    )

    # Workload
    parser.add_argument(
        "--jobs",
        type=int,
        metavar="<int>",
        default=int(np.floor(cpu_count() / 2)),
        help="Max number of concurrent jobs.",
    )
    parser.add_argument(
        "--server",
        type=str,
        metavar="<ip|servername>",
        default=None,
        help="The address of Ray server to connect.",
    )
    parser.add_argument(
        "--port",
type=int,
        metavar="<int>",
        default=10001,
        help="The port of Ray server to connect.",
    )
    parser.add_argument(
        "--run-dir",
        type=str,
        metavar="<path>",
        default=None,
        help="top level working directory",
    )
    parser.add_argument(
        "--ppa_coeff",
        type=str,
        default=None,
        help="Override for PPA coefficient",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Verbosity level",
    )

    args = parser.parse_args()
    args.algorithm = args.algorithm.lower()

    return args

def pbt_mutations(config):
    """Mutation spec for PBT.

    PBT multiplies the value of any non-list mutation by 0.8 or 1.2, which
    fails for strings and drifts constants and bools out of their set. A
    categorical domain is therefore given as the plain list of its choices,
    so PBT only resamples it or moves to a neighbouring choice.
    """
    return {
        key: list(domain.categories) if isinstance(domain, Categorical) else domain
        for key, domain in config.items()
    }


def pbt_explore_fn(config):
    """Returns a PBT custom_explore_fn keeping numeric values in their range."""

    def clamp(new_config):
        for key, domain in config.items():
            if isinstance(domain, (Float, Integer)):
                # tune.randint excludes its upper bound
                upper = domain.upper - 1 if isinstance(domain, Integer) else domain.upper
                new_config[key] = min(max(new_config[key], domain.lower), upper)
        return new_config

    return clamp


def set_algorithm(
    algorithm_name, experiment_name, reference_params, reference_result, seed, perturbation, jobs, config
):
    """
    Configure search algorithm.
    """
    # Pre-set seed if user sets seed to 0
    if seed == 0:
        print(
            "Warning: you have chosen not to set a seed. Do you wish to continue? (y/n)"
        )
        if input().lower() != "y":
            sys.exit(0)
        seed = None
    else:
        torch.manual_seed(seed)
        np.random.seed(seed)
        random.seed(seed)

    if algorithm_name != "pbt" and args.iterations != 1:
        print("Warning: Only PBT supports iterations different than 1. Successive iterations will have no effect")

    if algorithm_name == "hyperopt":
        algorithm = HyperOptSearch(
            points_to_evaluate=reference_params,
            random_state_seed=seed,
        )
    elif algorithm_name == "ax":
        ax_client = AxClient(
            enforce_sequential_optimization=False,
            random_seed=seed,
        )
        AxClientMetric = namedtuple("AxClientMetric", "minimize")
        ax_client.create_experiment(
            name=experiment_name,
            parameters=config,
            objectives={METRIC: AxClientMetric(minimize=True)},
        )
        algorithm = AxSearch(ax_client=ax_client, points_to_evaluate=reference_params)
    elif algorithm_name == "optuna":
        algorithm = OptunaSearch(points_to_evaluate=reference_params, evaluated_rewards=[reference_result], seed=seed)
    elif algorithm_name == "pbt":
        print("Warning: PBT does not support seed values. seed will be ignored.")
        if perturbation > args.iterations:
            print("Warning: perturbation is greater than iteration. PBT will have no effect !")
        algorithm = PopulationBasedTraining(
            time_attr="training_iteration",
            perturbation_interval=perturbation,
            hyperparam_mutations=pbt_mutations(config),
            custom_explore_fn=pbt_explore_fn(config),
            synch=True,
        )
    elif algorithm_name == "random":
        algorithm = BasicVariantGenerator(
            max_concurrent=jobs,
            random_state=seed,
        )

    # A wrapper algorithm for limiting the number of concurrent trials.
    if algorithm_name not in ["random", "pbt"]:
        algorithm = ConcurrencyLimiter(algorithm, max_concurrent=jobs)

    return algorithm

def set_reference_params(config_file):
    """
    Choose a set of parameters for the initial run.
    Take the reference value if given,
    or an arbitrary value in the set range otherwise
    """
    reference_parameters = {}
    with open(config_file, 'r') as filehandler:
        config = json.load(filehandler)
    for param, val in config.items():
        if "reference" in val:
            reference_parameters[param] = val["reference"]
        else:
            # Arbitrary : take the minimum value of each parameter
            if "minmax" in val:
                reference_parameters[param] = val["minmax"][0]
            elif "choices" in val:
                reference_parameters[param] = val["choices"][0]
    return reference_parameters

def set_training_class(function):
    """
    Set training class.
    """
    if function == "default":
        return AutoTunerBase
    if function == "ppa-improv":
        return PPAImprov
    return None


@ray.remote
def save_best(results):
    """
    Save best configuration of parameters found.
    """
    best_config = results.best_config
    best_config["best_result"] = results.best_result[METRIC]
    trial_id = results.best_trial.trial_id
    new_best_path = os.path.join(RUN_DIR, "autotuner-best.json")
    with open(new_best_path, "w") as new_best_file:
        json.dump(best_config, new_best_file, indent=4)
    print(f"[INFO TUN-0003] Best parameters written to {new_best_path}")

def make_flow(slots):
    bazel="echo" if args.dry_run else None
    return BazelFlow(
        workspace_root=WORKSPACE_ROOT,
        run_dir=RUN_DIR,
        rules_hdl_repo=args.rules_hdl_repo,
        bazel=bazel,
        cells=args.cells, top=args.top, sdc=args.sdc, deps=args.deps, slots=slots)

MARKER = ".autotuner_run"

def reset_run_dir(run_dir):
    marker = os.path.join(run_dir, MARKER)
    if os.path.isdir(run_dir):
        if os.listdir(run_dir) and not os.path.exists(marker):
            sys.exit(f"[ERROR] {run_dir} was not created by the autotuner; "
                     "refusing to delete it.")
        shutil.rmtree(run_dir)
    os.makedirs(run_dir)
    open(marker, "w").close()

def main():
    global args, config_dict, reference_params, reference_metrics
    global WORKSPACE_ROOT, RUN_DIR
    global DEBUG
    args = parse_arguments()
    DEBUG = args.verbose

    # WORKSPACE_ROOT is the root of the bazel project (containing MODULE.bazel) 
    WORKSPACE_ROOT = os.environ["BUILD_WORKSPACE_DIRECTORY"]
    if DEBUG:
        print(f"WORKSPACE_ROOT: {WORKSPACE_ROOT}")

    # Read config and original files before handling where to run in case we
    # need to upload the files.
    config_dict = read_config(
        os.path.abspath(args.config), getattr(args, "algorithm", None)
    )
    ## AX uses a list instead of a dict, thus bypass the check
    if args.algorithm != "ax":
        validate_search_space(config_dict)

    # Connect to remote Ray server if any, otherwise will run locally
    if args.server is not None:
        # Connect to ray server before first remote execution.
        ray.init(f"ray://{args.server}:{args.port}")
        print("[INFO TUN-0001] Connected to Ray server.")

    # RUN_DIR is the the top-level directory containing ALL the trials of autotuner
    RUN_DIR = os.path.normpath(args.run_dir)
    args.experiment = os.path.basename(RUN_DIR) # Name from Ray
    # Handle both absolute and relative path for RUN_DIR
    if WORKSPACE_ROOT not in RUN_DIR:
        RUN_DIR = os.path.join(WORKSPACE_ROOT,RUN_DIR)
    if DEBUG:
        print(f"RUN_DIR: {RUN_DIR}")
    assert os.path.commonpath([RUN_DIR, WORKSPACE_ROOT]) == WORKSPACE_ROOT
    # Clean old run dir if it exists to avoid mixing results
    reset_run_dir(RUN_DIR)
    reference_params = set_reference_params(os.path.abspath(args.config))
    if DEBUG:
        print(f"Reference run parameters:\n{reference_params}\n")
    ## Regardless of settings, perform a reference run
    ## This has 2 distincts purposes: have a single run to building all the tools with bazel
    ## So these can be cached
    ## And create a reference data point for all metrics so later runs can be improved upon
    if DEBUG:
        print("Starting reference run")
    if args.dry_run:
        reference_metrics = read_metrics(None, args.stop_after_step, fake=True)
    else:
        try:
            reference_experiment = make_flow(slots=1).run_trial(
                reference_params, experiment_dir=os.path.join(
                RUN_DIR, "reference"), stop_after_step=args.stop_after_step, parser_extra_commands=args.parser_extra_commands, frontend=args.frontend, save_logs=DEBUG)
            # Compute the score of the reference run
            reference_metrics = read_metrics(reference_experiment["reports"], args.stop_after_step)
        ## The reference run may fail, catch that error
        except RuntimeError:
            print("[WARNING]: reference run failed. Update the reference values in the autotuner config.")
            reference_metrics = {
                "clk_period": "ERR",
                "worst_slack": "ERR",
                "total_power": "ERR",
                "final_util": "ERR",
                "die_area": "ERR",
                "num_drc": "ERR",
            }
    reference_result = calculate_score(reference_metrics)[0]
    if DEBUG:
        print(f"reference_metrics:\n{reference_metrics}\n")
        print(f"Reference run result: {reference_result}")
    # Cleanup reference_metrics so it can be used as reference even on failure
    if "ERR" in reference_metrics.values() or "N/A" in reference_metrics.values():
        reference_metrics = {
            "clk_period": ERROR_METRIC,
            "worst_slack": ERROR_METRIC,
            "total_power": ERROR_METRIC,
            "final_util": 0.1,
            "die_area": ERROR_METRIC,
            "num_drc": ERROR_METRIC,
        }

    search_algo = set_algorithm(
        args.algorithm,
        args.experiment,
        [reference_params],
        reference_result,
        args.seed,
        args.perturbation,
        args.jobs,
        config_dict,
    )

    sample_names = {}
    def sample_name(trial):
        return sample_names.setdefault(trial.trial_id, f"sample{len(sample_names)}")

    tune_args = dict(
        name=args.experiment,
        metric=METRIC,
        mode="min",
        num_samples=args.samples,
        fail_fast=False,
        storage_path=os.path.dirname(RUN_DIR),
        stop={"training_iteration": args.iterations},
        resources_per_trial={"cpu": os.cpu_count() / args.jobs},
        log_to_file=["trail-out.log", "trail-err.log"],
        trial_name_creator=sample_name,
        trial_dirname_creator=sample_name,
    )
    if args.algorithm == "pbt":
        os.environ["TUNE_MAX_PENDING_TRIALS_PG"] = str(args.jobs)
        tune_args["scheduler"] = search_algo
    else:
        tune_args["search_alg"] = search_algo
        tune_args["scheduler"] = AsyncHyperBandScheduler()
    if args.algorithm != "ax":
        tune_args["config"] = config_dict
    TrainClass = PPAImprov
    analysis = tune.run(TrainClass, **tune_args)

    # if all runs have failed
    if analysis.best_result[METRIC] == ERROR_METRIC:
        print("[ERROR TUN-0016] No successful runs found.")
        sys.exit(16)

    task_id = save_best.remote(analysis)
    _ = ray.get(task_id)
    print(f"[INFO TUN-0002] Best parameters found: {analysis.best_config}")


if __name__ == "__main__":
    main()
