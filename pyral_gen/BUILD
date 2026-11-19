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
load("@rules_python//python:defs.bzl", "py_binary")

package(
    default_visibility = ["//visibility:public"],
    licenses = ["notice"],
)

py_binary(
    name = "pyral_gen",
    srcs = ["pyral_gen.py"],
    main = "pyral_gen.py",
    visibility = ["//visibility:public"],
    deps = [
        # peakrdl-cli provides the `peakrdl` module (peakrdl.main) imported above.
        requirement("peakrdl-cli"),
        requirement("peakrdl-pyral"),
    ],
)
