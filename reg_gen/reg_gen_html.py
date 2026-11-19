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

"""Generate HTML documentation for a register block."""

from peakrdl_html import HTMLExporter
from reg_gen_lib import build_arg_parser, run_product


def export_html(root, args):
    output_dir = args.output
    output_dir.mkdir(parents=True, exist_ok=True)
    export_options = dict(args.exporter_options)
    constructor_options = dict(args.constructor_options)
    constructor_options.update(
        {
            "user_template_dir": args.template_dir or None,
            "user_static_dir": args.static_dir or None,
        }
    )
    exporter = HTMLExporter(**constructor_options)
    exporter.export(root, str(output_dir), **export_options)
    print(f"Created: HTML files in {output_dir}")


def main():
    parser = build_arg_parser("reg_gen_html")
    parser.add_argument("--template-dir", default="")
    parser.add_argument("--static-dir", default="")
    run_product(parser, export_html)


if __name__ == "__main__":
    main()
