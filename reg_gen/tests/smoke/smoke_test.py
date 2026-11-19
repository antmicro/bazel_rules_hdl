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

"""Hermetic semantic smoke test for every base reg_gen product."""

import argparse
import shlex
import sys
from pathlib import Path


def _arguments():
    argv = [token for argument in sys.argv[1:] for token in shlex.split(argument)]
    parser = argparse.ArgumentParser()
    parser.add_argument("--rtl", type=Path, nargs="+", required=True)
    parser.add_argument("--chdr", type=Path, nargs="+", required=True)
    parser.add_argument("--html", type=Path, required=True)
    parser.add_argument("--markdown", type=Path, required=True)
    parser.add_argument("--ral", type=Path, required=True)
    return parser.parse_args(argv)


def _require_file(path):
    assert path.is_file(), f"expected generated file: {path}"
    assert path.stat().st_size, f"generated file is empty: {path}"


def _read(paths):
    return "\n".join(path.read_text(encoding="utf-8") for path in paths)


def main():
    args = _arguments()

    for path in [*args.rtl, *args.chdr, args.markdown, args.ral]:
        _require_file(path)

    rtl_sv = [path for path in args.rtl if path.suffix == ".sv"]
    rtl_reports = [path for path in args.rtl if path.suffix == ".rpt"]
    assert len(rtl_sv) == 2, f"expected RTL module and package, got: {args.rtl}"
    assert len(rtl_reports) == 1, f"expected hardware-interface report, got: {args.rtl}"
    assert "smoke_ctrl" in _read(rtl_sv).lower()

    headers = [path for path in args.chdr if path.suffix == ".h"]
    testcases = [path for path in args.chdr if path.name.endswith(".h.test.c")]
    assert len(headers) == 1, f"expected one C header, got: {args.chdr}"
    assert len(testcases) == 1, f"expected one C testcase, got: {args.chdr}"
    assert "smoke_ctrl" in _read(headers).lower()

    assert args.html.is_dir(), f"expected generated HTML tree: {args.html}"
    index = args.html / "index.html"
    _require_file(index)
    html = "\n".join(path.read_text(encoding="utf-8") for path in args.html.rglob("*.html")).lower()
    assert "smoke_ctrl" in html
    assert "register generator smoke test" in html

    assert "smoke_ctrl" in args.markdown.read_text(encoding="utf-8").lower()
    ral = args.ral.read_text(encoding="utf-8").lower()
    assert "smoke_ctrl" in ral
    assert "uvm_reg_block" in ral
    assert "::type_id::create" in ral


if __name__ == "__main__":
    main()
