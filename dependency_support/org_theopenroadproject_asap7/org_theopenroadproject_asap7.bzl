# Copyright 2022 Google LLC
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

"""Registers Bazel workspaces for the Boost C++ libraries."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def org_theopenroadproject_asap7():
    maybe(
        http_archive,
        name = "org_theopenroadproject_asap7",
        urls = [
            "https://github.com/antmicro/asap7/archive/8090e725a107c94e0d1ee7a466c113b8d8910867.tar.gz",
        ],
        strip_prefix = "asap7-8090e725a107c94e0d1ee7a466c113b8d8910867",
        sha256 = "4100d12ac4404065f9628a7dbd9600a4778c6dec8b92518ede6ab3c2f9b34ef5",
        build_file = Label("@rules_hdl//dependency_support/org_theopenroadproject_asap7:bundled.BUILD.bazel"),
    )
