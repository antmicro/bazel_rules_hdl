#############################################################################
##
## BSD 3-Clause License
##
## Copyright (c) 2019, The Regents of the University of California
## All rights reserved.
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions are met:
##
## * Redistributions of source code must retain the above copyright notice, this
##   list of conditions and the following disclaimer.
##
## * Redistributions in binary form must reproduce the above copyright notice,
##   this list of conditions and the following disclaimer in the documentation
##   and/or other materials provided with the distribution.
##
## * Neither the name of the copyright holder nor the names of its
##   contributors may be used to endorse or promote products derived from
##   this software without specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
## AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
## IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
## ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
## LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
## CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
## SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
## INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
## CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
## ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
## POSSIBILITY OF SUCH DAMAGE.
##
###############################################################################

import json
import os
import re
import sys
from datetime import datetime

import ray

# Default scheme of a SDC constraints file
SDC_TEMPLATE = """
set clk_name  core_clock
set clk_port_name clk
set clk_period 2000
set clk_io_pct 0.2

set clk_port [get_ports $clk_port_name]

create_clock -name $clk_name -period $clk_period $clk_port

set non_clock_inputs [lsearch -inline -all -not -exact [all_inputs] $clk_port]

set_input_delay  [expr $clk_period * $clk_io_pct] -clock $clk_name $non_clock_inputs
set_output_delay [expr $clk_period * $clk_io_pct] -clock $clk_name [all_outputs]
"""
# Name of the SDC file with constraints
CONSTRAINTS_SDC = "constraint.sdc"
# Name of the TCL script run before routing
FASTROUTE_TCL = "fastroute.tcl"
DATE = datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
# The worst of optimized metric
ERROR_METRIC = 9e99


def calculate_score(metrics, step=1):
    """Calculate optimization score from metrics."""
    error = "ERR" in metrics.values()
    not_found = "N/A" in metrics.values()

    if error or not_found:
        return (ERROR_METRIC, ERROR_METRIC, ERROR_METRIC, ERROR_METRIC)

    effective_clk_period = metrics["clk_period"] - metrics["worst_slack"]
    num_drc = metrics["num_drc"]
    gamma = effective_clk_period / 10
    score = effective_clk_period * (100 / step) + gamma * num_drc

    return (score, effective_clk_period, num_drc, metrics["die_area"])


def write_sdc(variables, path, sdc_original, constraints_sdc):
    """
    Create a SDC file with parameters for current tuning iteration.
    """
    # Handle case where the reference file does not exist
    if sdc_original == "":
        print("[ERROR TUN-0020] No SDC reference file provided.")
        sys.exit(1)
    new_file = sdc_original
    for key, value in variables.items():
        if key == "CLK_PERIOD":
            if new_file.find("set clk_period") != -1:
                new_file = re.sub(
                    r"set clk_period .*\n(.*)", f"set clk_period {value}\n\\1", new_file
                )
            else:
                new_file = re.sub(
                    r"-period [0-9\.]+ (.*)", f"-period {value} \\1", new_file
                )
                new_file = re.sub(r"-waveform [{}\s0-9\.]+[\s|\n]", "", new_file)
        elif key == "UNCERTAINTY":
            if new_file.find("set uncertainty") != -1:
                new_file = re.sub(
                    r"set uncertainty .*\n(.*)",
                    f"set uncertainty {value}\n\\1",
                    new_file,
                )
            else:
                new_file += f"\nset uncertainty {value}\n"
        elif key == "IO_DELAY":
            if new_file.find("set io_delay") != -1:
                new_file = re.sub(
                    r"set io_delay .*\n(.*)", f"set io_delay {value}\n\\1", new_file
                )
            else:
                new_file += f"\nset io_delay {value}\n"
        else:
            print(
                f"[WARN TUN-0025] {key} variable not supported in context of SDC files"
            )
            continue
    file_name = path + f"/{constraints_sdc}"
    with open(file_name, "w") as file:
        file.write(new_file)
    return file_name

METRIC_KEYS = (
    "clk_period",
    "worst_slack",
    "total_power",
    "final_util",
    "die_area",
    "num_drc",
)

VALID_STAGES = (
    "detailed_routing",
    "global_routing",
    "floorplan",
)

def read_metrics(reports_dict, stop_after_step="detailed_routing", fake=False):
    """Read the JSON reports from a single experiment (BazelFlow class)
 
    Returns a dict with the keys in METRIC_KEYS. If the file is missing or
    cannot be trusted, every value is "ERR", which the evaluate functions
    already turn into a failed trial.
 
    stop_after_step: Last step run. Valid values are: detailed_routing(default), global_routing
    """
    if fake:
        return {
            "clk_period": 10000,
            "worst_slack": 13,
            "total_power": 1e-6,
            "final_util": 42.0,
            "die_area": 123.4,
            "num_drc": 0,
        }
    if stop_after_step not in VALID_STAGES:
        print("ERROR: stop_after_step not a valid values: %s" % stop_after_step)
        sys.exit(1)

    if stop_after_step not in reports_dict:
        print("WARNING: missing %s reports" % stop_after_step)
        return {
            "clk_period": "ERR",
            "worst_slack": "ERR",
            "total_power": "ERR",
            "final_util": "ERR",
            "die_area": "ERR",
            "num_drc": "ERR",
        }

    with open(reports_dict[stop_after_step], "r") as filehandler:
        data = json.load(filehandler)[stop_after_step]
    if stop_after_step == "detailed_routing":
        worst_slack = data["timing"]["setup"]["wns"]
    else:
        worst_slack = 0.0
    if (worst_slack < 0.0):
        print("ERROR: worst slack must be a positive number, 0.0 is no violation")
        sys.exit(1)
    total_power = data["power"]["Total"]["total"]
    total_area = data["area"]["design_area"]
    utilization = data["area"]["utilization"]
    if stop_after_step == "detailed_routing":
        num_drc = data["drc"]["count"]
    else:
        num_drc = 0
    ## FIXME: clock and timing mismatch
    ## Only 1 clock period can be reported, which will be the fasted clock
    ## worst_slack is across all clocks, thus when there is more than 1 clock in the design
    ## this does not guarantee the wns does match the associated clock
    if stop_after_step == "detailed_routing":
        min_period = ERROR_METRIC
        for clk in data["timing"]["clocks"]:
            period = data["timing"]["clocks"][clk]
            if period == 0.0:
                print(f"WARNING: got clock period of 0.0 for clock {clk}")
                period = ERROR_METRIC
            if (period < min_period):
                min_period = period
    else:
        min_period = 1.0

    return {
        "clk_period": min_period,
        "worst_slack": worst_slack,
        "total_power": total_power,
        "final_util": utilization,
        "die_area": total_area,
        "num_drc": num_drc,
    }

def read_config(file_name, algorithm):
    """
    Please consider inclusive, exclusive
    Most type uses [min, max)
    But, Quantization makes the upper bound inclusive.
    e.g., qrandint and qlograndint uses [min, max]
    """

    def read_tune(this):
        from ray import tune

        # Constant cases
        if "choices" in this:
            if len(this["choices"]) == 1:
                return tune.choice([this["choices"][0],this["choices"][0]])

        if this["type"] == "bool":
            return tune.choice([0, 1])
        # All non constant choices
        if "choices" in this:
            return tune.choice(this["choices"])
        # Ranges only, valid for int or float
        if "minmax" in this:
            min_, max_ = this["minmax"]
            if this["type"] == "int":
                return tune.randint(min_, max_)
            if this["type"] == "float":
                return tune.uniform(min_, max_)
        print("ERROR: failed to understand config parameter")
        print(this)
        sys.exit(1)

    def read_tune_ax(name, this):
        """
        Ax format: https://ax.dev/versions/0.3.7/api/service.html
        Check also https://ax.dev/docs/0.5.0/tutorials/gpei_hartmann_service/
        Need to convert dict to list of dict, one dict per parameter
        """

        elm = {
                "name": name,
                "value_type": this["type"] ## Type in JSON matches Ax value type
                }
        # Ax differentiate value and values, this is not a typo
        if "choices" in this:
            if len(this["choices"]) == 1: # Constant
                elm["type"] = "fixed"
                elm["value"] = this["choices"][0]
            else:
                elm["type"] = "choice"
                elm["values"] = this["choices"]
        ## Range
        else:
            elm["type"] = "range"
            elm["bounds"] = this["minmax"]
        return elm

    # Check file exists and whether it is a valid JSON file.
    assert os.path.isfile(file_name), f"File {file_name} not found."
    try:
        with open(file_name) as file:
            data = json.load(file)
    except json.JSONDecodeError:
        raise ValueError(f"Invalid JSON file: {file_name}")
    # Ax algorithm expect parameters in a different format
    if algorithm != "ax":
        config = dict()
    else:
        config = []
    for key, value in data.items():
        if algorithm == "ax":
            config.append(read_tune_ax(key, value))
        else:
            config[key] = read_tune(value)
    return config
