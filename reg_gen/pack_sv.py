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

"""Syntax-aware packing postprocessor for PeakRDL-generated RTL.

Unpacked structs become packed structs, and fixed-size unpacked declarator
dimensions such as ``items [4]`` become packed ranges such as
``[4-1:0] items``. The source is parsed before and after editing so comments,
expressions, and array references are never text-pattern rewrite candidates.
"""

from pathlib import Path

import pyslang


def _parse(text, source_name):
    tree = pyslang.SyntaxTree.fromText(text, name=source_name)
    diagnostics = [diagnostic for diagnostic in tree.diagnostics if diagnostic.isError()]
    if diagnostics:
        details = "\n".join(
            f"{diagnostic.code} at byte {diagnostic.location.offset}" for diagnostic in diagnostics
        )
        raise ValueError(f"pyslang could not parse {source_name}:\n{details}")
    return tree


def _collect_edits(tree, source):
    """Collect byte-range edits without changing expressions or references."""
    edits = []

    def visit(node):
        if isinstance(node, pyslang.StructUnionTypeSyntax):
            if node.keyword.kind == pyslang.TokenKind.StructKeyword and not node.packed:
                edits.append(
                    (node.keyword.range.end.offset, node.keyword.range.end.offset, b" packed")
                )

        if not isinstance(node, pyslang.DeclaratorSyntax):
            return

        packed_dimensions = []
        for dimension in node.dimensions:
            specifier = dimension.specifier
            if not isinstance(specifier, pyslang.RangeDimensionSpecifierSyntax):
                continue
            if not isinstance(specifier.selector, pyslang.BitSelectSyntax):
                continue

            size = str(specifier).strip()
            if not size.isascii() or not size.isdecimal():
                continue

            packed_dimensions.append(f"[{size}-1:0]")
            start = dimension.sourceRange.start.offset
            while start > node.name.range.end.offset and source[start - 1 : start] in (b" ", b"\t"):
                start -= 1
            edits.append((start, dimension.sourceRange.end.offset, b""))

        if packed_dimensions:
            replacement = ("".join(packed_dimensions) + " ").encode("ascii")
            name_offset = node.name.range.start.offset
            edits.append((name_offset, name_offset, replacement))

    tree.root.visit(visit)
    return edits


def transform_sv(text, source_name="generated SystemVerilog"):
    """Pack generated structs and fixed-size unpacked declarator dimensions."""
    tree = _parse(text, source_name)
    transformed = text.encode("utf-8")

    for start, end, replacement in sorted(_collect_edits(tree, transformed), reverse=True):
        transformed = transformed[:start] + replacement + transformed[end:]

    result = transformed.decode("utf-8")
    _parse(result, source_name)
    return result


def transform_sv_file(source_path, output_path):
    """Transform one input into a separately declared output file."""
    source_path = Path(source_path)
    output_path = Path(output_path)
    source = source_path.read_text(encoding="utf-8")
    output_path.write_text(transform_sv(source, str(source_path)), encoding="utf-8", newline="\n")


def main():
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-files", type=Path, nargs="+", required=True)
    parser.add_argument("--output-files", type=Path, nargs="+", required=True)
    args = parser.parse_args()
    if len(args.input_files) != len(args.output_files):
        parser.error("--input-files and --output-files must contain the same number of paths")

    for source_path, output_path in zip(args.input_files, args.output_files, strict=True):
        transform_sv_file(source_path, output_path)


if __name__ == "__main__":
    main()
