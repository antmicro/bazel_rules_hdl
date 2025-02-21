# Copyright 2025 Antmicro
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

load("@//dc:defs.bzl", "dc_binary", "dc_run")
load("//verilog:defs.bzl", "verilog_library")

package(
    default_applicable_licenses = ["//:package_license"],
    default_visibility = ["//visibility:private"],
)

verilog_library(
    name = "adder",
    srcs = ["adder.sv"],
)

dc_binary(
    name = "dc_adder",
    env_file = ":env.sh",
    module = ":adder",
    top = "adder",
)

dc_run(
    name = "dc_adder_synth",
    out = [
        "area.rpt",
        "power.rpt",
        "timing.rpt",
    ],
    data = [
        "additional.tcl",
    ],
    ddc = ":dc_adder",
    env_file = ":env.sh",
    tcl = ":adder.tcl",
)
