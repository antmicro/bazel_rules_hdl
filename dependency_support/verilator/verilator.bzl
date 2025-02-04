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
#
# Original implementation by Kevin Kiningham (@kkiningh) in kkiningh/rules_verilator.
# Ported to bazel_rules_hdl by Stephen Tridgell (@stridge-cruxml)
"""Download and build verilator"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def verilator():
    maybe(
        http_archive,
        name = "verilator",
        build_file = Label("@rules_hdl//dependency_support/verilator:verilator.BUILD.bazel"),
        urls = ["https://github.com/verilator/verilator/archive/refs/tags/v5.032.tar.gz"],
        sha256 = "5a262564b10be8bdb31ff4fb67d77bcf5f52fc1b4e6c88d5ca3264fb481f1e41",
        strip_prefix = "verilator-5.032",
    )
