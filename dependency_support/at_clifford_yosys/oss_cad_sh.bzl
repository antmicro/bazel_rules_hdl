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

"""
Wraps an OSS CAD Suite vendor script so it can be used as a Bazel executable target.
"""

_WRAPPER_TEMPLATE = """#!/usr/bin/env bash
set -euo pipefail

f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${{RUNFILES_DIR:-/dev/null}}/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "${{RUNFILES_MANIFEST_FILE:-/dev/null}}" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$0.runfiles/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  {{ echo >&2 "ERROR: cannot find $f"; exit 1; }}; f=; set -e

oss_cad_script="$(rlocation {rlocation_path})"
exec "$oss_cad_script" "$@"
"""

def _oss_cad_sh_impl(ctx):
    rlocation_path = ctx.file.script.short_path
    if rlocation_path.startswith("../"):
        rlocation_path = rlocation_path[len("../"):]

    oss_cad_sh = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(
        output = oss_cad_sh,
        content = _WRAPPER_TEMPLATE.format(rlocation_path = rlocation_path),
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = ctx.files.data + [ctx.file.script])
    runfiles = runfiles.merge(ctx.attr._runfiles_lib[DefaultInfo].default_runfiles)

    return [DefaultInfo(executable = oss_cad_sh, runfiles = runfiles)]

oss_cad_sh = rule(
    doc = "Defines an executable that correctly execs script from OSS CAD suite.",
    implementation = _oss_cad_sh_impl,
    executable = True,
    attrs = {
        "data": attr.label_list(
            allow_files = True,
            doc = "Additional runtime data.",
        ),
        "script": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The script to run.",
        ),
        "_runfiles_lib": attr.label(
            default = "@bazel_tools//tools/bash/runfiles",
        ),
    },
)
