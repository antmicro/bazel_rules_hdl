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

"""A launcher for exposing Bazel-built Verilator to cocotb."""

def _cocotb_verilator_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name)

    def rlocationpath(target):
        return ctx.expand_location(
            "$(rlocationpath {})".format(target.label),
            targets = [target],
        )

    ctx.actions.expand_template(
        output = executable,
        template = ctx.file._template,
        is_executable = True,
        substitutions = {
            "{BINARY}": rlocationpath(ctx.attr.binary),
            "{ROOT}": rlocationpath(ctx.attr.root),
        },
    )
    return [DefaultInfo(
        executable = executable,
        runfiles = ctx.runfiles(files = [
            ctx.executable.binary,
            ctx.file.root,
        ]),
    )]

cocotb_verilator = rule(
    doc = "Create a shell wrapper to expose verilator_executable as verialtor to cocotb.",
    implementation = _cocotb_verilator_impl,
    attrs = {
        "binary": attr.label(
            cfg = "target",
            executable = True,
            mandatory = True,
        ),
        "root": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "_template": attr.label(
            allow_single_file = True,
            default = Label("//cocotb:verilator/verilator_wrapper.sh.tpl"),
        ),
    },
    executable = True,
)
