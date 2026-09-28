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

"""Rules for packaging a Verilog library as a standalone `--binary` reproducer.

The generated command is intentionally independent of the Verilator actions
created by other rules in this repository. It provides a small, editable local
reproducer; it does not reproduce another Bazel target's invocation exactly.
"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load("@rules_pkg//:pkg.bzl", "pkg_tar")
load("@rules_pkg//pkg:providers.bzl", "PackageFilesInfo")
load("//verilog:defs.bzl", "VerilogInfo")

_RUNFILE_EXTENSIONS = ["dat", "mem"]

def _package_path(file):
    """Returns a portable archive path for a Verilog library file."""
    path = file.short_path
    if path.startswith("../"):
        return "external/" + path[3:]
    return path.removeprefix("./")

def _unique_files(entries, field):
    files = []
    seen = {}
    for entry in entries:
        for file in getattr(entry, field):
            if file not in seen:
                seen[file] = True
                files.append(file)
    return files

def _include_directories(files):
    directories = []
    for file in files:
        path = _package_path(file)
        if "/" not in path:
            continue
        parts = path.rsplit("/", 1)[0].split("/")
        for i in range(len(parts)):
            directories.append("/".join(parts[:i + 1]))
    return depset(directories).to_list()

def _verilator_package_contents_impl(ctx):
    entries = ctx.attr.verilog_library[VerilogInfo].dag.to_list()
    srcs = _unique_files(entries, "srcs")
    hdrs = _unique_files(entries, "hdrs")
    data = _unique_files(entries, "data")
    files = depset(srcs + hdrs + data).to_list()

    destinations = {}
    for file in files:
        destination = _package_path(file)
        if destination in destinations and destinations[destination] != file:
            fail("Verilog files {} and {} have the same package path '{}'".format(
                destinations[destination].path,
                file.path,
                destination,
            ))
        destinations[destination] = file

    design_files = [
        _package_path(file)
        for file in srcs
        if file.extension not in _RUNFILE_EXTENSIONS
    ]
    include_dirs = [
        "-I" + directory
        for directory in _include_directories(srcs + hdrs)
    ]
    verilator_args = [
        "--binary",
        "--top-module",
        ctx.attr.module_top,
    ] + ctx.attr.vopts
    if ctx.attr.copts:
        verilator_args.extend(["-CFLAGS", " ".join(ctx.attr.copts)])
    verilator_args.extend(include_dirs)
    verilator_args.extend(design_files)

    run_script = ctx.actions.declare_file(ctx.label.name + "/run.sh")
    ctx.actions.expand_template(
        output = run_script,
        substitutions = {
            "{SIMULATION_BINARY}": shell.quote("./obj_dir/V" + ctx.attr.module_top),
            "{VERILATOR_ARGS}": " ".join([
                shell.quote(arg)
                for arg in verilator_args
            ]),
        },
        template = ctx.file._run_template,
        is_executable = True,
    )
    destinations["run.sh"] = run_script

    return [
        DefaultInfo(files = depset(files + [run_script])),
        PackageFilesInfo(
            attributes = {},
            dest_src_map = destinations,
        ),
    ]

_verilator_package_contents = rule(
    implementation = _verilator_package_contents_impl,
    attrs = {
        "copts": attr.string_list(
            doc = "C++ compiler options passed through Verilator's -CFLAGS option.",
        ),
        "module_top": attr.string(
            doc = "The name of the top-level Verilog module.",
            mandatory = True,
        ),
        "verilog_library": attr.label(
            doc = "The verilog_library whose transitive files are packaged.",
            mandatory = True,
            providers = [VerilogInfo],
        ),
        "vopts": attr.string_list(
            doc = "Command-line options passed directly to Verilator after --binary.",
        ),
        "_run_template": attr.label(
            allow_single_file = True,
            default = Label("//verilator/package:run.sh.tpl"),
        ),
    },
)

def verilator_package(name, verilog_library, module_top, copts = [], vopts = [], **kwargs):
    """Packages a Verilog library as a standalone `verilator --binary` reproducer.

    The resulting tar contains every transitive source, header, and data file
    referenced by `verilog_library`, plus an executable `run.sh` at its root.
    `run.sh` builds and runs the design using `verilator --binary`; `verilator`
    must be available on PATH when the archive is used. This is an independent,
    editable reproducer and does not exactly reproduce the invocation of another
    Verilator Bazel rule.

    Args:
        name: Name of the generated pkg_tar target.
        verilog_library: A target providing VerilogInfo.
        module_top: The name of the top-level Verilog module.
        copts: C++ compiler options passed through Verilator's -CFLAGS option.
        vopts: Command-line options passed directly to Verilator after --binary.
        **kwargs: Additional arguments forwarded to pkg_tar.
    """
    contents_name = name + "_contents"
    _verilator_package_contents(
        name = contents_name,
        copts = copts,
        module_top = module_top,
        tags = ["manual"],
        verilog_library = verilog_library,
        visibility = ["//visibility:private"],
        vopts = vopts,
    )

    if "srcs" in kwargs:
        fail("verilator_package controls pkg_tar's srcs attribute")
    mode = kwargs.pop("mode", "0644")
    modes = dict(kwargs.pop("modes", {}))
    modes["run.sh"] = "0755"
    pkg_tar(
        name = name,
        srcs = [":" + contents_name],
        mode = mode,
        modes = modes,
        **kwargs
    )
