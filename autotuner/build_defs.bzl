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

"""Rules for running autotuner, a no-human-in-the-loop optimization flow"""

load("@rules_python//python:defs.bzl", "py_binary")

AUTOTUNER_PYTHON_VERSION = "3.14"

def _shell_quote(s):
    """Protect against shell tokenization while going from bazel to python"""
    return "'" + s.replace("'", "'\\''") + "'"

def run_autotuner_tune(
        name,
        config,
        algorithm = "hyperopt",
        deps = [],
        top = None,
        cells = None,
        perturbation = 25,
        ppa_coeff = None,
        sdc = None,
        samples = 1,
        stop_after_step = "detailed_routing",
        frontend = "yosys",
        parser_extra_commands = [],
        iterations = 1,
        jobs = 1,
        run_dir = None,
        server = None,
        port = None,
        **kwargs):
    """Run the autotuner `tune` function on a design. Launch with `bazel run`.

    Args:
        name: Name of the runnable target.
        config: Autotuner JSON search-space file.
        algorithm: which search algorithm to use
        deps: verilog_library targets of the design.
        top: Name of the RTL top-level.
        cells: Standard cells target to use.
        perturbation: PBT only. Number of iterations to start the perturbations
        ppa_coeff: coefficient to override default values of Performance, Power, Area. Given as integer triplet "performance,power,area"
        sdc: sdc file for the design.
        samples: Number of samples per iteration.
        stop_after_step: Stop step: detailed_routing(default), global_routing, global_placement, floorplan, synthesis
        frontend: Which frontend to use for synthesis
        parser_extra_commands: extra parameters for synthesis parser
        iterations: Number of successive iterations.
        jobs: number of maximum parallel jobs
        run_dir: Path to the execution directory
        server: remote server for Ray
        port: port for Ray remote server
        **kwargs: Forwarded to py_binary (visibility, tags, ...).
    """

    if run_dir == None:
        run_dir = "autotuner_runs/{}/{}".format(native.package_name(), name)
    rules_hdl = str(Label("//:BUILD"))[:-len("//:BUILD")]

    synth_extras = []

    # We hide the extra args arguments inside a JSON to avoid collision between arguments to the python script
    # and arguments to the synthesis script
    if parser_extra_commands:
        json_args = json.encode(parser_extra_commands)
        synth_extras = [
            "--parser_extra_commands",
            _shell_quote(json_args),
        ]

    # Pre compute the python script argument
    # Argument order has to be respected (hence the split in 3 parts)
    # the --deps need to be understood individually, one at the time
    script_args = [
        "--config",
        "$(rootpath %s)" % config,
        "--top %s" % top,
        "--cells %s" % str(native.package_relative_label(cells)),
        "--sdc %s" % str(native.package_relative_label(sdc)),
        "--stop_after_step %s" % stop_after_step,
        "" if frontend == None else "--frontend %s" % frontend,
        "" if server == None else "--server %s" % server,
        "" if port == None else "--port %s" % port,
        "" if ppa_coeff == None else "--ppa_coeff %s" % ppa_coeff,
        "--jobs %s" % str(jobs),
        "--run-dir %s" % run_dir,
        "--rules_hdl_repo",
        rules_hdl,
        "--samples",
        str(samples),
        "--iterations",
        str(iterations),
        "--perturbation",
        str(perturbation),
        "--algorithm %s" % algorithm,
    ]
    script_args += synth_extras
    for dep in deps:
        script_args += ["--deps", str(native.package_relative_label(dep))]

    py_binary(
        name = name,
        env = {
            "RAY_AUTH_MODE": "disabled",
        },
        srcs = [Label("//autotuner:distributed.py")],
        main = Label("//autotuner:distributed.py"),
        deps = [Label("//autotuner:autotuner_lib")],
        data = [config],
        args = script_args,
        python_version = AUTOTUNER_PYTHON_VERSION,
        legacy_create_init = 0,
        **kwargs
    )
