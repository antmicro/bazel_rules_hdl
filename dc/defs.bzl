# Copyright 2025 Antmicro
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

"""Bazel rules for Design Compiler"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("//common:providers.bzl", "LogInfo")
load("//verilog:defs.bzl", "VerilogInfo")

DesignCompilerLibraryInfo = provider(
    doc = "Provides information about the libraries used when creating DDC file",
    fields = {
        "symbol_library": "Symbol library",
        "synthetic_library": "Synthetic library",
        "target_library": "Target library",
    },
)

def _dc_binary(ctx):
    transitive_srcs = depset([], transitive = [ctx.attr.module[VerilogInfo].dag]).to_list()

    all_srcs = [verilog_info_struct.srcs for verilog_info_struct in transitive_srcs]
    all_hdrs = [verilog_info_struct.hdrs for verilog_info_struct in transitive_srcs]
    all_data = [verilog_info_struct.data for verilog_info_struct in transitive_srcs]

    all_files = [src for sub_tuple in (all_srcs + all_data) for src in sub_tuple]
    all_hdrs = [hdr for sub_tuple in all_hdrs for hdr in sub_tuple]

    search_paths = " ".join([f.dirname for f in all_hdrs])
    verilog_files = "\n    ".join([f.path for (f,) in all_srcs])

    dc_ddc = ctx.actions.declare_file("{}.ddc".format(ctx.label.name))
    dc_tcl = ctx.actions.declare_file("{}.tcl".format(ctx.label.name))
    dc_log = ctx.actions.declare_file("{}.log".format(ctx.label.name))

    substitutions = {
        "{{OUTPUT_FILE}}": dc_ddc.path,
        "{{SEARCH_PATHS}}": search_paths,
        "{{SYMBOL_LIBRARY}}": ctx.attr.symbol_library,
        "{{SYNTHETIC_LIBRARY}}": ctx.attr.synthetic_library,
        "{{TARGET_LIBRARY}}": ctx.attr.target_library,
        "{{TOP}}": ctx.attr.top,
        "{{VERILOG_FILES}}": verilog_files,
    }

    ctx.actions.expand_template(
        template = ctx.file.binary_tcl_template,
        output = dc_tcl,
        substitutions = substitutions,
    )

    command = "source " + ctx.file.env_file.path + " && "
    command += "dc_shell -f " + dc_tcl.path + " -output_log_file " + dc_log.path

    ctx.actions.run_shell(
        outputs = [dc_log, dc_ddc],
        inputs = all_files + [dc_tcl, ctx.file.env_file],
        progress_message = "Running on DC: {}".format(ctx.label.name),
        command = command,
    )

    return [
        DefaultInfo(files = depset([dc_ddc])),
        LogInfo(files = depset([dc_log])),
        DesignCompilerLibraryInfo(
            target_library = ctx.attr.target_library,
            symbol_library = ctx.attr.symbol_library,
            synthetic_library = ctx.attr.synthetic_library,
        ),
    ]

dc_binary = rule(
    implementation = _dc_binary,
    attrs = {
        "binary_tcl_template": attr.label(
            doc = "TCL template to run on Device Compiler",
            default = "@rules_hdl//dc:binary.tcl.template",
            allow_single_file = [".template"],
        ),
        "env_file": attr.label(
            doc = "Shell script setting the environment for Design Compiler. Can be used to set environment variables with licenses",
            mandatory = True,
            allow_single_file = [".sh"],
        ),
        "module": attr.label(
            doc = "Verilog library with all the modules",
            providers = [VerilogInfo],
            mandatory = True,
        ),
        "symbol_library": attr.string(
            doc = "Symbol library used by Device Compiler",
            default = "lsi_10k.slib",
        ),
        "synthetic_library": attr.string(
            doc = "Synthetic library used by Device Compiler",
            default = "dw_foundation.sldb",
        ),
        "target_library": attr.string(
            doc = "Target library used by Device Compiler",
            default = "lsi_10k.db",
        ),
        "top": attr.string(
            doc = "The name of the top level verilog module",
            mandatory = True,
        ),
    },
    provides = [DefaultInfo, LogInfo, DesignCompilerLibraryInfo],
)

def _dc_run(ctx):
    dc_log = ctx.actions.declare_file("{}.log".format(ctx.label.name))
    dc_tcl = ctx.actions.declare_file("{}.tcl".format(ctx.label.name))

    tcl_output_dir = paths.join(ctx.genfiles_dir.path, paths.dirname(ctx.build_file_path))
    search_paths = " ".join([f.dirname for f in ctx.files.data])

    dc_lib_provider = ctx.attr.ddc[DesignCompilerLibraryInfo]
    substitutions = {
        "{{INPUT_FILE}}": ctx.file.ddc.path,
        "{{OUTPUT_DIR}}": tcl_output_dir,
        "{{SEARCH_PATHS}}": search_paths,
        "{{SYMBOL_LIBRARY}}": dc_lib_provider.symbol_library,
        "{{SYNTHETIC_LIBRARY}}": dc_lib_provider.synthetic_library,
        "{{TARGET_LIBRARY}}": dc_lib_provider.target_library,
        "{{USER_SCRIPT}}": ctx.file.tcl.path,
    }

    ctx.actions.expand_template(
        template = ctx.file.run_tcl_template,
        output = dc_tcl,
        substitutions = substitutions,
    )

    command = "source " + ctx.file.env_file.path + " && "
    command += "dc_shell -f " + dc_tcl.path + " -output_log_file " + dc_log.path

    ctx.actions.run_shell(
        outputs = ctx.outputs.out + [dc_log],
        inputs = ctx.files.data + [dc_tcl, ctx.file.ddc, ctx.file.env_file, ctx.file.tcl, ctx.file.run_tcl_template],
        progress_message = "Running on DC: {}".format(ctx.label.name),
        command = command,
    )

    return [
        DefaultInfo(files = depset(ctx.outputs.out)),
        LogInfo(files = depset([dc_log])),
    ]

dc_run = rule(
    implementation = _dc_run,
    attrs = {
        "data": attr.label_list(
            doc = "Additional files that can be used by the main TCL script",
            allow_files = True,
        ),
        "ddc": attr.label(
            doc = "DDC file from the dc_binary() rule",
            allow_single_file = [".ddc"],
        ),
        "env_file": attr.label(
            doc = "Shell script setting the environment for Design Compiler. Can be used to set environment variables with licenses",
            mandatory = True,
            allow_single_file = [".sh"],
        ),
        "out": attr.output_list(
            doc = "List of outputs generated by the TCL script",
        ),
        "run_tcl_template": attr.label(
            doc = "Tcl template which sets the environment before running the main TCL",
            default = "@rules_hdl//dc:run.tcl.template",
            allow_single_file = [".template"],
        ),
        "tcl": attr.label(
            doc = "The main TCL script to run using Device Compiler",
            allow_single_file = [".tcl"],
            mandatory = True,
        ),
    },
    provides = [DefaultInfo, LogInfo],
)
