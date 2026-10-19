# Copyright 2026 bazel_rules_hdl Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("//autotuner:build_defs.bzl", "run_autotuner_tune")
load("//synthesis:defs.bzl", "sdc_library")
load("//verilog:defs.bzl", "verilog_library")

package(
    default_visibility = ["//visibility:public"],
)

verilog_library(
    name = "lfsr",
    srcs = [
        "lfsr.sv",
    ],
)

sdc_library(
    name = "constraint",
    srcs = ["constraint.sdc"],
)

run_autotuner_tune(
    name = "autotuner-test-pbt",
    algorithm = "pbt",
    cells = "@org_theopenroadproject_asap7sc7p5t_27//:asap7-sc7p5t_rev27_rvt_4x-ccs_ss",
    config = "lfsr_autotuner.json",
    iterations = 4,
    jobs = 4,
    perturbation = 2,
    samples = 4,
    sdc = ":constraint",
    top = "lfsr",
    deps = [
        ":lfsr",
    ],
)

run_autotuner_tune(
    name = "autotuner-test-ax",
    algorithm = "ax",
    cells = "@org_theopenroadproject_asap7sc7p5t_27//:asap7-sc7p5t_rev27_rvt_4x-ccs_ss",
    config = "lfsr_autotuner.json",
    jobs = 8,
    perturbation = 2,
    samples = 4,
    sdc = ":constraint",
    stop_after_step = "detailed_routing",
    top = "lfsr",
    deps = [
        ":lfsr",
    ],
)

run_autotuner_tune(
    name = "autotuner-test-optuna",
    algorithm = "optuna",
    cells = "@org_theopenroadproject_asap7sc7p5t_27//:asap7-sc7p5t_rev27_rvt_4x-ccs_ss",
    config = "lfsr_autotuner.json",
    jobs = 8,
    perturbation = 2,
    ppa_coeff = "100,100,100",
    samples = 4,
    sdc = ":constraint",
    stop_after_step = "global_routing",
    top = "lfsr",
    deps = [
        ":lfsr",
    ],
)

run_autotuner_tune(
    name = "autotuner-test-random",
    algorithm = "random",
    cells = "@org_theopenroadproject_asap7sc7p5t_27//:asap7-sc7p5t_rev27_rvt_4x-ccs_ss",
    config = "lfsr_autotuner.json",
    jobs = 8,
    perturbation = 2,
    samples = 4,
    sdc = ":constraint",
    stop_after_step = "floorplan",
    synth_additional_args = ["-booth"],
    top = "lfsr",
    deps = [
        ":lfsr",
    ],
)

run_autotuner_tune(
    name = "autotuner-test-hyperopt",
    algorithm = "hyperopt",
    cells = "@org_theopenroadproject_asap7sc7p5t_27//:asap7-sc7p5t_rev27_rvt_4x-ccs_ss",
    config = "lfsr_autotuner.json",
    jobs = 8,
    perturbation = 2,
    samples = 4,
    sdc = ":constraint",
    top = "lfsr",
    deps = [
        ":lfsr",
    ],
)
