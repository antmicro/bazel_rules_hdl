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

"""Registers Bazel workspaces for the lz4 library."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def net_lz4():
    maybe(
        http_archive,
        name = "net_lz4",
        urls = ["https://github.com/lz4/lz4/releases/download/v1.10.0/lz4-1.10.0.tar.gz"],
        strip_prefix = "lz4-1.10.0",
        sha256 = "537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b",
        build_file = "@rules_hdl//dependency_support/net_lz4:net_lz4.BUILD.bazel",
    )
