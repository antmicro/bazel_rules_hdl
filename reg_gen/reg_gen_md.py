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

"""Generate a Markdown (README.md) document for a register block."""

from peakrdl_markdown import MarkdownExporter
from reg_gen_lib import build_arg_parser, run_product


def export_md(root, args):
    output_file = args.output
    exporter = MarkdownExporter(**args.constructor_options)
    options = dict(args.exporter_options)
    options.update(
        {
            "node": root,
            "output_path": str(output_file),
            "input_files": [str(path) for path in args.source_files],
            "rename": args.prefix,
        }
    )
    exporter.export(**options)
    print(f"Created: Markdown file {output_file}")


def main():
    parser = build_arg_parser("reg_gen_md")
    parser.add_argument(
        "--prefix",
        type=str,
        default="CSR",
        help="Name for the top-level node in the document body",
    )
    parser.add_argument("--source-files", nargs="*", default=[])
    run_product(parser, export_md)


if __name__ == "__main__":
    main()
