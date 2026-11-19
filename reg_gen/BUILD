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

load("@reggen_pip//:requirements.bzl", "requirement")
load("@rules_python//python:defs.bzl", "py_binary", "py_library")
load("@rules_python//python:pip.bzl", "compile_pip_requirements")

package(
    default_applicable_licenses = ["//:package_license"],
    default_visibility = ["//visibility:public"],
)

compile_pip_requirements(
    name = "requirements",
    src = "requirements.txt",
    python_version = "3.14",
    requirements_txt = "requirements_lock.txt",
)

# Shared SystemRDL compile/elaborate, supported UDPs, and argument scaffolding.
py_library(
    name = "reg_gen_lib",
    srcs = ["reg_gen_lib.py"],
    imports = ["."],
    deps = [
        requirement("peakrdl-regblock"),
        requirement("systemrdl-compiler"),
    ],
)

# Optional syntax-aware postprocessor. The generator rules do not depend on
# it unless a caller selects it through the RTL product config.
py_binary(
    name = "pack_sv",
    srcs = ["pack_sv.py"],
    imports = ["."],
    main = "pack_sv.py",
    deps = [requirement("pyslang")],
)

# One tool per product. Each is a thin entry point over reg_gen_lib that runs a
# single peakrdl exporter, so each Bazel rule can drive exactly one product in
# its own action.

py_binary(
    name = "reg_gen_rtl",
    srcs = ["reg_gen_rtl.py"],
    imports = ["."],
    main = "reg_gen_rtl.py",
    deps = [
        ":reg_gen_lib",
        requirement("peakrdl-regblock"),
    ],
)

py_binary(
    name = "reg_gen_chdr",
    srcs = ["reg_gen_chdr.py"],
    imports = ["."],
    main = "reg_gen_chdr.py",
    deps = [
        ":reg_gen_lib",
        requirement("peakrdl-cheader"),
    ],
)

py_binary(
    name = "reg_gen_html",
    srcs = ["reg_gen_html.py"],
    imports = ["."],
    main = "reg_gen_html.py",
    deps = [
        ":reg_gen_lib",
        requirement("peakrdl-html"),
    ],
)

py_binary(
    name = "reg_gen_md",
    srcs = ["reg_gen_md.py"],
    imports = ["."],
    main = "reg_gen_md.py",
    deps = [
        ":reg_gen_lib",
        requirement("peakrdl-markdown"),
    ],
)

py_binary(
    name = "reg_gen_ral",
    srcs = ["reg_gen_ral.py"],
    imports = ["."],
    main = "reg_gen_ral.py",
    deps = [
        ":reg_gen_lib",
        requirement("peakrdl-uvm"),
    ],
)
