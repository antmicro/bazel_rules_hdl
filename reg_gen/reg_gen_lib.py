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

"""Shared helpers for the per-product reg_gen tools.

All product tools use this module to parse their common CLI, register the
PeakRDL-regblock UDPs, compile and elaborate SystemRDL, and validate
parameter overrides. Exporter selection and product-specific arguments remain
in the individual entry points.
"""

import argparse
import json
import sys
from pathlib import Path

from peakrdl_regblock.udps import ALL_UDPS
from systemrdl import RDLCompiler
from systemrdl.messages import RDLCompileError


def parse_parameters(p_list):
    """Parse ``-P key=value`` SystemRDL parameters into a dict of ints."""
    parameters = {}
    for p in p_list:
        try:
            name, value = p.split("=")
        except ValueError as error:
            raise ValueError(
                f"Expected a SystemRDL parameter in key=value form; got {p!r}"
            ) from error

        valid_name = (
            name.isascii()
            and bool(name)
            and (name[0].isalpha() or name[0] == "_")
            and all(character.isalnum() or character == "_" for character in name[1:])
        )
        if not valid_name:
            raise ValueError(f"Invalid SystemRDL parameter name {name!r} in {p!r}")
        if name in parameters:
            raise ValueError(f"Duplicate SystemRDL parameter {name!r}")

        try:
            parameters[name] = int(value)
        except ValueError as error:
            raise ValueError(
                f"SystemRDL parameter {name!r} must have an integer value; got {value!r}"
            ) from error
    return parameters


def _parse_assignments(values, kind, value_parser=str):
    """Parse repeatable ``key=value`` arguments into a dictionary."""
    result = {}
    for value in values:
        try:
            name, raw_value = value.split("=", 1)
        except ValueError as error:
            raise ValueError(f"Expected {kind} in key=value form; got {value!r}") from error

        valid_name = (
            name.isascii()
            and bool(name)
            and (name[0].isalpha() or name[0] == "_")
            and all(character.isalnum() or character == "_" for character in name[1:])
        )
        if not valid_name:
            raise ValueError(f"Invalid {kind} name {name!r} in {value!r}")
        if name in result:
            raise ValueError(f"Duplicate {kind} {name!r}")

        try:
            result[name] = value_parser(raw_value)
        except ValueError as error:
            raise ValueError(f"Invalid value for {kind} {name!r}: {raw_value!r}") from error
    return result


def parse_defines(values):
    """Parse repeatable ``key=value`` SystemRDL preprocessor definitions."""
    return _parse_assignments(values, "SystemRDL definition")


def compile_rdl(input_files, include_paths, parameters, defines, top, instance_name):
    """Compile and elaborate the given SystemRDL files, returning the root node.

    ``include_paths`` are directories searched for SystemRDL ``include``
    statements. Bazel derives them from transitive ``RdlInfo`` dependencies.
    """
    rdlc = RDLCompiler()
    # Register the properties understood by PeakRDL-regblock consistently for
    # every product, so one valid input has the same meaning for all exporters.
    for udp in ALL_UDPS:
        rdlc.register_udp(udp)

    basepaths = [str(p) for p in include_paths] if include_paths else []

    try:
        for f in input_files:
            print(f"Compiling '{f}'...")
            rdlc.compile_file(f, incl_search_paths=basepaths, defines=defines)
        print("Elaborating...")
        return rdlc.elaborate(
            top_def_name=top or None,
            inst_name=instance_name or None,
            parameters=parameters,
        )
    except RDLCompileError as e:
        # RDLCompiler already printed the detailed compile error; fail with a
        # clean message and non-zero exit code instead of a raw traceback.
        sys.exit(f"RDL compilation failed: {e}")


def build_arg_parser(description, output_nargs=None):
    """Create a parser with the arguments shared by every reg_gen tool.

    ``output_nargs`` is the number of ``--output`` paths the tool expects: one
    (the default) for chdr/md/ral/html, two for rtl (module + package files).
    """
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument(
        "--input-files", type=Path, nargs="+", required=True, help="Input SystemRDL file(s)"
    )
    parser.add_argument(
        "--include-paths",
        type=Path,
        nargs="+",
        default=None,
        help="Include paths for SystemRDL file(s)",
    )
    parser.add_argument(
        "-P", action="append", default=[], help="SystemRDL parameters", metavar="key=value"
    )
    parser.add_argument(
        "-D",
        action="append",
        default=[],
        help="SystemRDL preprocessor definitions",
        metavar="key=value",
    )
    parser.add_argument("--top", default="", help="Top-level SystemRDL definition to elaborate")
    parser.add_argument(
        "--instance-name", default="", help="Override the elaborated top-level instance name"
    )
    parser.add_argument(
        "--exporter-options-json",
        default="{}",
        help="Unverified keyword arguments forwarded to the export() call",
    )
    parser.add_argument(
        "--constructor-options-json",
        default="{}",
        help="Unverified keyword arguments forwarded to the exporter constructor",
    )
    parser.add_argument(
        "--output",
        type=Path,
        nargs=output_nargs,
        required=True,
        help="Output path(s) declared by Bazel. A file for chdr/md/ral; two "
        "files (module, package) for rtl; a directory for html.",
    )
    return parser


def run_product(parser, export_fn):
    """Common entry logic: parse, compile, then run ``export_fn(root, args)``."""
    args = parser.parse_args()
    try:
        parameters = parse_parameters(args.P)
        defines = parse_defines(args.D)
        args.exporter_options = json.loads(args.exporter_options_json)
        args.constructor_options = json.loads(args.constructor_options_json)
        if not isinstance(args.exporter_options, dict):
            raise ValueError("exporter options must encode a JSON object")
        if not isinstance(args.constructor_options, dict):
            raise ValueError("constructor options must encode a JSON object")
    except ValueError as error:
        parser.error(str(error))
    root = compile_rdl(
        args.input_files,
        args.include_paths,
        parameters,
        defines,
        args.top,
        args.instance_name,
    )
    print("Generating output(s)...")
    export_fn(root, args)
