"""Rules for running autotuner, a no-human-in-the-loop optimization flow"""

load("@rules_python//python:defs.bzl", "py_binary")

AUTOTUNER_PYTHON_VERSION = "3.10"

def run_autotuner_tune(
        name,
        config,
        deps = [],
        top = None,
        cells = None,
        sdc = None,
        samples = 1,
        iterations = 1,
        run_dir = None,
        **kwargs):
    """Run the autotuner `tune` function on a design. Launch with `bazel run`.

    Args:
        name: Name of the runnable target.
        config: Autotuner JSON search-space file.
        deps: verilog_library targets of the design.
        top: Name of the RTL top-level.
        cells: Standard cells target to use.
        sdc: sdc file for the design.
        samples: Number of samples per iteration.
        iterations: Number of successive iterations.
        run_dir: Path to the execution directory
        **kwargs: Forwarded to py_binary (visibility, tags, ...).
    """

    if run_dir == None:
        run_dir = "autotuner_runs/{}/{}".format(native.package_name(), name)
    rules_hdl = str(Label("//:BUILD"))[:-len("//:BUILD")]

    # Pre compute the python script argument
    # Argument order has to be respected (hence the split in 3 parts)
    # the --deps need to be understood individually, one at the time
    script_args = [
        "--config",
        "$(rootpath %s)" % config,
        "--top %s" % top,
        "--cells %s" % str(native.package_relative_label(cells)),
        "--sdc %s" % str(native.package_relative_label(sdc)),
        "--run-dir %s" % run_dir,
        "--rules_hdl_repo",
        rules_hdl,
    ]
    for dep in deps:
        script_args += ["--deps", str(native.package_relative_label(dep))]
    script_args += [
        "tune",
        "--samples",
        str(samples),
        "--iterations",
        str(iterations),
    ]

    py_binary(
        name = name,
        srcs = [Label("//autotuner:distributed.py")],
        main = Label("//autotuner:distributed.py"),
        deps = [Label("//autotuner:autotuner_lib")],
        data = [config],
        args = script_args,
        python_version = AUTOTUNER_PYTHON_VERSION,
        legacy_create_init = 0,
        **kwargs
    )
