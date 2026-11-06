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

"""Providers for PLI, VPI and DPI libraries"""

PliInfo = provider(
    doc = "A PLI, VPI or DPI library info",
    fields = {
        "hdrs": "Header files",
        "srcs": "Source files",
    },
)

def _pli_library_impl(ctx):
    """
    Constructs a PliInfo provider.
    """

    return [
        PliInfo(
            srcs = depset(direct = ctx.files.srcs),
            hdrs = depset(direct = ctx.files.hdrs),
        ),
    ]

pli_library = rule(
    doc = "Define a PLI, VPI or DPI library",
    implementation = _pli_library_impl,
    attrs = {
        "hdrs": attr.label_list(
            doc = "Header files",
            allow_files = True,
        ),
        "srcs": attr.label_list(
            doc = "Source files",
            allow_files = True,
        ),
    },
)
