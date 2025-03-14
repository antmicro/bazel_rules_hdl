# Copyright 2025 bazel_rules_hdl Authors
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

load("//vcs:defs.bzl", "convert_vpd2vcd", "vcs_binary", "vcs_run")
load("//verilog:defs.bzl", "verilog_library")

package(
    default_applicable_licenses = ["//:package_license"],
    default_visibility = ["//visibility:private"],
)

verilog_library(
    name = "adder",
    srcs = [
        "adder.sv",
    ],
)

verilog_library(
    name = "tb",
    srcs = [
        "tb.sv",
    ],
    deps = [
        ":adder",
    ],
)

vcs_binary(
    name = "tb_vcs_fullcov",
    coverage = [
        "line",
        "cond",
        "fsm",
        "tgl",
        "branch",
    ],
    module = ":tb",
    module_top = "tb",
    opts = [
        "-full64",
        "+vcs+lic+wait",
        "+error+500",
        "+lint=all",
        "-error=all",
    ],
    opts_with_label = {
        "-msg_config=": "//vcs/tests:config.txt",
    },
    vcs_env = "//vcs/tests:vcs_env.sh",
    visibility = [
        "//visibility:public",
    ],
)

vcs_binary(
    name = "tb_vcs_nocov",
    module = ":tb",
    module_top = "tb",
    opts = [
        "-full64",
        "+vcs+lic+wait",
        "+error+500",
    ],
    vcs_env = "//vcs/tests:vcs_env.sh",
    visibility = [
        "//visibility:public",
    ],
)

# coverage in vcs_binary and vcs_run
vcs_run(
    name = "tb_vcs_run_fullcov",
    binary = ":tb_vcs_fullcov",
    coverage = [
        "line",
        "cond",
        "fsm",
        "tgl",
        "branch",
    ],
    trace_vcd = True,
    trace_vpd = True,
    visibility = [
        "//visibility:public",
    ],
)

# no coverage in vcs_binary and vcs_run
vcs_run(
    name = "tb_vcs_run_nocov",
    binary = ":tb_vcs_nocov",
    trace_vpd = True,
    visibility = [
        "//visibility:public",
    ],
)

convert_vpd2vcd(
    name = "tb_vcs_waveform_conversion",
    args = [
        "-full64",
        "+splitpacked",
    ],
    vcs_env = "//vcs/tests:vcs_env.sh",
    waveform = "tb_vcs_run_nocov",
)

# coverage in vcs_binary but no coverage in vcs_run
vcs_run(
    name = "tb_vcs_run_missing_run_cov",
    binary = ":tb_vcs_fullcov",
    trace_vcd = True,
    visibility = [
        "//visibility:public",
    ],
)

filegroup(
    name = "tb_vcs_run",
    srcs = [
        ":tb_vcs_run_fullcov",
        ":tb_vcs_run_missing_run_cov",
        ":tb_vcs_run_nocov",
        ":tb_vcs_waveform_conversion",
    ],
)
