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

# dvlib-compatible RAL templates layered over PeakRDL-uvm's base templates.
#
# Exposed as a filegroup (not via a py_binary's `data`) so the generic
# reg_gen_ral rule can add them to its action inputs directly and pass the
# directory to the tool. A `py_binary`'s `data` files land in its runfiles, not in
# `DefaultInfo.files`, so they would not be visible to `ctx.files` here.
package(
    default_visibility = ["//visibility:public"],
    licenses = ["notice"],
)

filegroup(
    name = "dvlib_templates",
    srcs = glob(["uvm/**"]),
)
