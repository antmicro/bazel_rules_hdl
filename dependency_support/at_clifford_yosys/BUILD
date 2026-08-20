# Copyright 2020-2026 bazel_rules_hdl Authors
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

load(":oss_cad_sh.bzl", "oss_cad_sh")

package(
    default_applicable_licenses = ["//:package_license"],
    default_visibility = ["//visibility:public"],
)

oss_cad_sh(
    name = "yosys",
    data = [
        "@at_clifford_yosys_data//:bin",
        "@at_clifford_yosys_data//:lib",
        "@at_clifford_yosys_data//:libexec",
        "@at_clifford_yosys_data//:share_yosys",
    ],
    script = "@at_clifford_yosys_data//:bin/yosys",
)

oss_cad_sh(
    name = "yosys_abc",
    data = [
        "@at_clifford_yosys_data//:bin",
        "@at_clifford_yosys_data//:lib",
        "@at_clifford_yosys_data//:libexec",
    ],
    script = "@at_clifford_yosys_data//:bin/yosys-abc",
)

oss_cad_sh(
    name = "yosys_config",
    data = [
        "@at_clifford_yosys_data//:bin",
        "@at_clifford_yosys_data//:lib",
        "@at_clifford_yosys_data//:libexec",
    ],
    script = "@at_clifford_yosys_data//:bin/yosys-config",
)

oss_cad_sh(
    name = "yosys_filterlib",
    data = [
        "@at_clifford_yosys_data//:bin",
        "@at_clifford_yosys_data//:lib",
        "@at_clifford_yosys_data//:libexec",
    ],
    script = "@at_clifford_yosys_data//:bin/yosys-filterlib",
)

oss_cad_sh(
    name = "yosys_smtbmc",
    data = [
        "@at_clifford_yosys_data//:bin",
        "@at_clifford_yosys_data//:lib",
        "@at_clifford_yosys_data//:libexec",
    ],
    script = "@at_clifford_yosys_data//:bin/yosys-smtbmc",
)

oss_cad_sh(
    name = "yosys_witness",
    data = [
        "@at_clifford_yosys_data//:bin",
        "@at_clifford_yosys_data//:lib",
        "@at_clifford_yosys_data//:libexec",
    ],
    script = "@at_clifford_yosys_data//:bin/yosys-witness",
)

oss_cad_sh(
    name = "eqy",
    data = [
        "@at_clifford_yosys_data//:bin",
        "@at_clifford_yosys_data//:lib",
        "@at_clifford_yosys_data//:libexec",
        "@at_clifford_yosys_data//:share_yosys",
    ],
    script = "@at_clifford_yosys_data//:bin/eqy",
)

oss_cad_sh(
    name = "sby",
    data = [
        "@at_clifford_yosys_data//:bin",
        "@at_clifford_yosys_data//:lib",
        "@at_clifford_yosys_data//:libexec",
        "@at_clifford_yosys_data//:share_yosys",
    ],
    script = "@at_clifford_yosys_data//:bin/sby",
)
