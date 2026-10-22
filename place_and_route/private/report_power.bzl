# Copyright 2021 Google LLC
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

"""Report Power Commands"""

load("//synthesis:defs.bzl", "SynthesisInfo")

def generate_power_results(ctx, output_file, json = False):
    """
    Call the report_power command and write its results into a file, either in text or json format

    Args:
      ctx: rule context
      output_file: generated file with the results
      json: boolean. Text format by default, set to true to output in JSON format
    """
    netlist_target = ctx.attr.synthesized_rtl
    liberty = netlist_target[SynthesisInfo].standard_cell_info.default_corner.liberty
    if json:
        cmd = "report_power -format json"
    else:
        cmd = "report_power"

    return [
        cmd,
        "set power_result [sta::design_power [lindex [sta::get_scenes] 0]]",
        "set fp [open \"{output_file}\" w+]".format(
            output_file = output_file.path,
        ),
        "puts $fp \"total_package_power_watts: [lindex $power_result 3]\"",
        "puts $fp \"corner: \\\"{corner}\\\"\"".format(
            corner = liberty.basename[:-(len(liberty.extension) + 1)],
        ),
        "puts $fp \"power_maginitude: \\\"[sta::unit_scale_abbreviation \"power\"]\\\"\"",
        "close $fp",
    ]
