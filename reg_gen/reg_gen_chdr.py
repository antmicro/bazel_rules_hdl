#!/usr/bin/env python3
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

"""Generate a C header with register/field accessors from a register block."""

from peakrdl_cheader.c_standards import CStandard
from peakrdl_cheader.exporter import CHeaderExporter
from reg_gen_lib import build_arg_parser, run_product


def export_chdr(root, args):
    output_file = args.output

    exporter = CHeaderExporter(**args.constructor_options)
    options = dict(args.exporter_options)
    if "std" in options:
        options["std"] = CStandard[options["std"]]
    options.update(
        {
            "node": root,
            "path": str(output_file),
        }
    )
    exporter.export(**options)
    print(f"Created: C-header file {output_file}")


def main():
    parser = build_arg_parser("reg_gen_chdr")
    run_product(parser, export_chdr)


if __name__ == "__main__":
    main()
