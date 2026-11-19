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

""" Generates python register abstraction layer with peakrdl"""

def _pyral_gen(ctx):
    outputs = ctx.actions.declare_directory(ctx.attr.name)
    inputs = [ctx.file.src]

    ctx.actions.run(
        inputs = inputs,
        outputs = [outputs],
        executable = ctx.executable.tool,
        arguments = ["pyral", ctx.file.src.path, "-o", outputs.path],
    )

    return [
        DefaultInfo(
            files = depset([outputs]),
            runfiles = ctx.runfiles(files = [outputs]),
        ),
        PyInfo(
            transitive_sources = depset([outputs]),
            imports = depset([ctx.workspace_name + "/" + outputs.short_path]),
        ),
    ]

# TODO: Improve this rule to handle hierarchical RDLs
pyral_gen = rule(
    implementation = _pyral_gen,
    attrs = {
        "src": attr.label(allow_single_file = [".rdl"], mandatory = True),
        "tool": attr.label(
            doc = "pyral_gen tool",
            cfg = "exec",
            executable = True,
            default = Label("//pyral_gen:pyral_gen"),
        ),
    },
)
