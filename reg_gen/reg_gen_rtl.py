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

"""Generate a SystemVerilog register block with explicit exporter options."""

import importlib

from peakrdl_regblock import RegblockExporter
from reg_gen_lib import build_arg_parser, run_product

# Map config CPU-interface names to peakrdl_regblock.cpuif classes. These are internal
# peakrdl APIs; the peakrdl version must be pinned (see the pip lock) and this
# table kept in sync with it.
CPUIF_CLASSES = {
    "apb3": "apb3.APB3_Cpuif",
    "apb3_flattened": "apb3.APB3_Cpuif_flattened",
    "apb4": "apb4.APB4_Cpuif",
    "apb4_flattened": "apb4.APB4_Cpuif_flattened",
    "avalon": "avalon.Avalon_Cpuif",
    "avalon_flattened": "avalon.Avalon_Cpuif_flattened",
    "axi4lite": "axi4lite.AXI4Lite_Cpuif",
    "axi4lite_flattened": "axi4lite.AXI4Lite_Cpuif_flattened",
    "obi": "obi.OBI_Cpuif",
    "obi_flattened": "obi.OBI_Cpuif_flattened",
    "passthrough": "passthrough.PassthroughCpuif",
    "wishbone": "wishbone.Wishbone_Cpuif",
    "wishbone_flattened": "wishbone.Wishbone_Cpuif_flattened",
}


def export_rtl(root, args):
    # Bazel declares the two output files; the regblock exporter insists on a
    # directory and names the files after the module/package identifiers, so
    # those identifiers are taken from the declared file stems.
    out_module, out_package = args.output
    out_dir = out_module.parent

    kwargs = dict(args.exporter_options)
    cpuif = kwargs.pop("cpuif", "passthrough")
    mod, cls = CPUIF_CLASSES[cpuif].rsplit(".", maxsplit=1)
    cpuif_mod = importlib.import_module("peakrdl_regblock.cpuif." + mod)
    cpuif_cls = getattr(cpuif_mod, cls)

    kwargs.update(
        {
            "node": root,
            "module_name": out_module.stem,
            "package_name": out_package.stem,
            "output_dir": str(out_dir),
            "cpuif_cls": cpuif_cls,
        }
    )
    exporter = RegblockExporter(**args.constructor_options)
    exporter.export(**kwargs)
    print(f"Created: SystemVerilog files {out_module}, {out_package}")


def main():
    parser = build_arg_parser("reg_gen_rtl", output_nargs=2)
    run_product(parser, export_rtl)


if __name__ == "__main__":
    main()
