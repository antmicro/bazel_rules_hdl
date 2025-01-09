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

load("//vcs:defs.bzl", "vcs_binary", "vcs_run")
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
    name = "tb_vcs",
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

vcs_run(
    name = "tb_vcs_run",
    binary = ":tb_vcs",
    trace = True,
    visibility = [
        "//visibility:public",
    ],
)
