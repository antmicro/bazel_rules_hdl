"""
Runs one autotuner trial as a nested `bazel build` of a generated package.
"""

import contextlib
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import time
import uuid

# ---------------------------------------------------------------------------
# Parameter registry.
#
# Search-space keys are "<step>.<attribute>". Each entry converts the sampled
# value (Ray gives floats/ints) to the Python value emitted in the BUILD file.
# ---------------------------------------------------------------------------


def _int(v):
    return int(round(v))


def _float_str(v):
    # place_and_route takes these as strings (Bazel has no floats).
    return repr(round(float(v), 4))


def _bool(v):
    return bool(v)


PARAMS = {
    "synthesize_rtl.target_clock_period_pico_seconds": _int,
    "place_and_route.target_die_utilization_percentage": _float_str,
    "place_and_route.placement_density": _float_str,
    "place_and_route.core_padding_microns": _int,
    "place_and_route.enable_improve_placement": _bool,
}

# Attributes set on every trial unless a tuned parameter overrides them.
# PLACEHOLDERS: loosely taken from basic_asic_flow's defaults; adjust once the
# first real build shows what the rules need.
BASE = {
    "synthesize_rtl": {
        "target_clock_period_pico_seconds": 10000,
    },
    "place_and_route": {
        "core_padding_microns": 1,
        "placement_density": "0.65",
        "target_die_utilization_percentage": "40",
    },
}

_REPORT_RE = re.compile(r"^pnr_(?P<step>.+)_report\.json$")

def validate_search_space(keys):
    """Fail at startup, before Ray starts, on unsupported parameters."""
    unknown = sorted(k for k in keys if k not in PARAMS)
    if unknown:
        raise ValueError(
            "Unsupported search-space parameters: {}. Supported: {}".format(
                ", ".join(unknown), ", ".join(sorted(PARAMS))))


def _lit(v):
    """Python value -> Starlark literal."""
    if isinstance(v, bool):
        return "True" if v else "False"
    return json.dumps(v)  # ints and strings


def render_build(rules_hdl_repo, cells, top, sdc, deps, params):
    """Content of the BUILD file of one trial package."""
    attrs = {step: dict(base) for step, base in BASE.items()}
    for key, value in params.items():
        step, attr = key.split(".", 1)
        attrs[step][attr] = PARAMS[key](value)

    def fmt(step):
        return "".join(
            "    {} = {},\n".format(a, _lit(v))
            for a, v in sorted(attrs[step].items()))

    deps_str = "".join('        "{}",\n'.format(d) for d in deps)
    return '''load("{repo}//synthesis:defs.bzl", "synthesize_rtl")
load("{repo}//place_and_route:build_defs.bzl", "place_and_route")

synthesize_rtl(
    name = "synth",
    standard_cells = "{cells}",
    top_module = "{top}",
    deps = [
{deps}    ],
{synth_attrs}    tags = ["manual"],
)

place_and_route(
    name = "pnr",
    synthesized_rtl = ":synth",
    sdc = "{sdc}",
{pnr_attrs}    tags = ["manual"],
)
'''.format(
        repo=rules_hdl_repo,
        cells=cells,
        top=top,
        sdc=sdc,
        deps=deps_str,
        synth_attrs=fmt("synthesize_rtl"),
        pnr_attrs=fmt("place_and_route"),
    )


class BazelFlow:
    """Creates trial packages and builds them with nested bazel invocations.

    Parallel `bazel build`s in one output base serialize on the server lock, so
    each concurrent trial takes a "slot": a fixed output base that is reused
    across trials, guarded by a file lock. All slots share one disk cache.
    Only plain strings/ints are stored, so instances can be pickled to Ray
    workers.
    """

    def __init__(self, workspace_root, run_dir, rules_hdl_repo, cells, top, sdc, deps,
                 slots=4, bazel=None, cache_root=None):
        self.workspace_root = workspace_root
        self.run_dir = run_dir
        self.rules_hdl_repo = rules_hdl_repo
        self.cells = cells
        self.top = top
        self.sdc = sdc
        self.deps = list(deps)
        self.slots = slots
        self.bazel = (bazel or os.environ.get("AUTOTUNER_BAZEL")
                      or shutil.which("bazel") or shutil.which("bazelisk"))
        if not self.bazel:
            raise RuntimeError(
                "bazel not found in PATH (set AUTOTUNER_BAZEL to override)")
        tag = hashlib.md5(workspace_root.encode()).hexdigest()[:10]
        self.cache_root = cache_root or os.path.join(workspace_root, "autotuner_runs", ".cache")
        os.makedirs(self.cache_root, exist_ok=True)

    def _output_base(self, slot):
        return os.path.join(self.cache_root, "slot_{}".format(slot))

    @contextlib.contextmanager
    def _slot(self):
        while True:
            for k in range(self.slots):
                fd = os.open(
                    os.path.join(self.cache_root, "slot_{}.lock".format(k)),
                    os.O_CREAT | os.O_RDWR)
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    os.close(fd)
                    continue
                try:
                    yield k
                finally:
                    os.close(fd)  # closing the descriptor releases the lock
                return
            time.sleep(1)

    def run_trial(self, params, experiment_dir=None, stream=False):
        """Build one trial. Raises RuntimeError if the build fails.

        experiment_dir: absolute directory inside the workspace that becomes the
        trial's Bazel package. Defaults to a fresh one under run_dir.
        """
        if experiment_dir is None:
            experiment_dir = os.path.join(
                self.run_dir, "trial_{}".format(uuid.uuid4().hex[:8]))
        os.makedirs(experiment_dir, exist_ok=True)
        with open(os.path.join(experiment_dir, "BUILD"), "w") as f:
            f.write(render_build(
                self.rules_hdl_repo, self.cells, self.top, self.sdc, self.deps, params))

        rel = os.path.relpath(experiment_dir, self.workspace_root).replace(os.sep, "/")
        if rel.startswith(".."):
            raise ValueError("{} is outside the workspace_root {}".format(
                experiment_dir, self.workspace_root))
        label = "//{}:pnr".format(rel)
        log_path = os.path.join(experiment_dir, "bazel.log")

        with self._slot() as slot:
            cmd = [
                self.bazel,
                "--output_base=" + self._output_base(slot),
                "--max_idle_secs=600",
                "build",
                "--config=autotuner", ## TODO: this depends on .bazelrc, check if it can stay
                label,
            ]
            with open(log_path, "w") as log:
                proc = subprocess.run(
                    cmd,
                    cwd=self.workspace_root,
                    stdout=None if stream else log,
                    stderr=None if stream else subprocess.STDOUT,
                )
        if proc.returncode != 0:
            raise RuntimeError(
                "bazel build {} failed (exit {}); see {}".format(
                    label, proc.returncode, log_path))
        reports = self._collect_reports(slot, label, experiment_dir)
        return {"label": label, "experiment_dir": experiment_dir, "reports": reports}


    def _collect_reports(self, slot, label, experiment_dir):
        """Copies the report JSON files of the built pnr target into
        <trial_dir>/results and returns {step: path of the copy}.

        The step is the part of the file name between "pnr_" and "_report.json",
        e.g. {"cts": ..., "global_routing": ..., "detailed_routing": ...}.
        Only files that are default outputs of the target are found; a step
        whose report does not exist is simply missing from the dict.
        """
        base = [self.bazel, "--output_base=" + self._output_base(slot),
                "--max_idle_secs=600"]
        kwargs = dict(cwd=self.workspace_root, capture_output=True, text=True)
        files = subprocess.run(
            base + ["cquery", "--config=autotuner", label, "--output=files"], **kwargs)
        if files.returncode != 0:
            raise RuntimeError(
                "cannot list the outputs of {}: {}".format(
                    label, (info.stderr + files.stderr).strip()[-500:]))
        execution_root = os.path.join(self._output_base(slot), "execroot", "_main")

        reports = {}
        results_dir = os.path.join(experiment_dir, "results")
        for rel_path in files.stdout.splitlines():
            match = _REPORT_RE.match(os.path.basename(rel_path.strip()))
            source = os.path.join(execution_root, rel_path.strip())
            if match and os.path.isfile(source):
                os.makedirs(results_dir, exist_ok=True)
                reports[match.group("step")] = shutil.copy(source, results_dir)
        return reports

    def shutdown(self):
        """Stop the bazel servers of all slots (call at the end of a run)."""
        for k in range(self.slots):
            if os.path.isdir(self._output_base(k)):
                subprocess.run(
                    [self.bazel, "--output_base=" + self._output_base(k),
                     "shutdown"],
                    cwd=self.workspace_root,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
