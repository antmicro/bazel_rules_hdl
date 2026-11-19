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

load("@rules_python//python:defs.bzl", "py_test")
load("//reg_gen:defs.bzl", "reg_gen")

package(default_visibility = ["//visibility:private"])

reg_gen(
    name = "smoke_rdl",
    testonly = True,
    srcs = ["smoke.rdl"],
    config = {
        "chdr": {
            "testcase": True,
        },
        "html": {
            "title": "Register generator smoke test",
        },
        "md": {
            "depth": 1,
        },
        "ral": {
            "use_uvm_factory": True,
        },
        "rtl": {
            "cpuif": "apb3_flattened",
            "generate_hwif_report": True,
        },
    },
)

py_test(
    name = "smoke_test",
    srcs = ["smoke_test.py"],
    args = [
        "--rtl",
        "$(locations :smoke_rdl_rtl)",
        "--chdr",
        "$(locations :smoke_rdl_chdr)",
        "--html",
        "$(location :smoke_rdl_html)",
        "--markdown",
        "$(location :smoke_rdl_md)",
        "--ral",
        "$(location :smoke_rdl_ral)",
    ],
    data = [
        ":smoke_rdl_chdr",
        ":smoke_rdl_html",
        ":smoke_rdl_md",
        ":smoke_rdl_ral",
        ":smoke_rdl_rtl",
    ],
)
