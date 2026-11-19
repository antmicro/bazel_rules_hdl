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

"""Bazel rules for generating register artifacts from SystemRDL."""

load("@rules_hdl//verilog:defs.bzl", "make_dag_entry", "make_verilog_info")

# ---------------------------------------------------------------------------
# RDL libraries and shared helpers
# ---------------------------------------------------------------------------

RdlInfo = provider(
    doc = "Transitive SystemRDL sources and include directories.",
    fields = {
        "files": "Depset of transitive SystemRDL files.",
        "include_dirs": "Depset of directories searched by SystemRDL include directives.",
    },
)

def _rdl_library_impl(ctx):
    transitive_files = [dep[RdlInfo].files for dep in ctx.attr.deps]
    transitive_dirs = [dep[RdlInfo].include_dirs for dep in ctx.attr.deps]
    files = depset(
        direct = ctx.files.srcs,
        transitive = transitive_files,
    )
    include_dirs = depset(
        direct = [source.dirname for source in ctx.files.srcs],
        transitive = transitive_dirs,
    )
    return [
        DefaultInfo(files = files),
        RdlInfo(
            files = files,
            include_dirs = include_dirs,
        ),
    ]

rdl_library = rule(
    implementation = _rdl_library_impl,
    attrs = {
        "deps": attr.label_list(
            providers = [RdlInfo],
            doc = "Transitive SystemRDL library dependencies.",
        ),
        "srcs": attr.label_list(
            allow_files = [".rdl"],
            doc = "SystemRDL files exported by this library.",
        ),
    },
    doc = "Collect SystemRDL files and propagate their transitive include paths.",
)

def _output_prefix(ctx):
    # Use the target name when no explicit output prefix is set.
    return ctx.attr.prefix if ctx.attr.prefix else ctx.label.name

def _collect_rdl_inputs(ctx):
    infos = [dep[RdlInfo] for dep in ctx.attr.deps]

    return struct(
        files = depset(
            direct = ctx.files.srcs,
            transitive = [info.files for info in infos],
        ),
        include_dirs = sorted(depset(
            transitive = [info.include_dirs for info in infos],
        ).to_list()),
    )

def _common_args(ctx, rdl_inputs):
    # Construct arguments shared by every product tool.
    args = ctx.actions.args()
    args.add("--input-files")
    args.add_all(ctx.files.srcs)

    # RdlInfo dependencies carry all transitive include directories. The
    # compiler searches directories rather than explicit include files.
    if rdl_inputs.include_dirs:
        args.add("--include-paths")
        args.add_all(rdl_inputs.include_dirs)

    # SystemRDL parameter overrides, forwarded as repeatable -P key=value
    # args. Preserve declaration order; the tool rejects duplicate keys.
    if ctx.attr.parameters:
        for p in ctx.attr.parameters:
            args.add("-P")
            args.add(p)
    if ctx.attr.defines:
        for key, value in sorted(ctx.attr.defines.items()):
            args.add("-D")
            args.add("%s=%s" % (key, value))
    if ctx.attr.top:
        args.add("--top")
        args.add(ctx.attr.top)
    if ctx.attr.instance_name:
        args.add("--instance-name")
        args.add(ctx.attr.instance_name)
    args.add("--exporter-options-json")
    args.add(ctx.attr.exporter_options_json)
    args.add("--constructor-options-json")
    args.add(ctx.attr.constructor_options_json)
    return args

def _run(ctx, mnemonic, args, outputs, rdl_inputs, extra_inputs = []):
    # extra_inputs are action inputs but are not exposed as outputs.
    inputs = depset(
        direct = extra_inputs,
        transitive = [rdl_inputs.files],
    )
    ctx.actions.run(
        executable = ctx.executable.tool,
        inputs = inputs,
        outputs = outputs,
        arguments = [args],
        mnemonic = mnemonic,
        use_default_shell_env = False,
    )
    return [DefaultInfo(files = depset(outputs))]

# Common input attrs; each product rule adds only its own options on top.
_COMMON_ATTRS = {
    "constructor_options_json": attr.string(
        default = "{}",
        doc = "JSON object of unverified keyword arguments forwarded to the exporter constructor.",
    ),
    "defines": attr.string_dict(
        doc = "SystemRDL preprocessor definitions, passed to every input compilation.",
    ),
    "deps": attr.label_list(providers = [RdlInfo], doc = "Transitive rdl_library dependencies."),
    "exporter_options_json": attr.string(
        default = "{}",
        doc = "JSON object of unverified keyword arguments forwarded to export().",
    ),
    "instance_name": attr.string(
        doc = "Override the elaborated top-level instance name.",
    ),
    "parameters": attr.string_list(
        default = [],
        doc = "SystemRDL parameter overrides as `key=value` strings, applied at elaboration. " +
              "Example: [\"WIDTH=8\"]. Values are integers (see reg_gen_lib.parse_parameters).",
    ),
    "prefix": attr.string(default = "", doc = "Output name prefix. Defaults to the target name."),
    "srcs": attr.label_list(allow_files = [".rdl"], mandatory = True, doc = "SystemRDL source files."),
    "top": attr.string(
        doc = "Top-level SystemRDL definition to elaborate. Empty selects the compiler default.",
    ),
}

# ---------------------------------------------------------------------------
# reg_gen_rtl
# ---------------------------------------------------------------------------

def _reg_gen_rtl_impl(ctx):
    prefix = _output_prefix(ctx)

    out_sv = ctx.actions.declare_file(prefix + ".sv")
    out_pkg = ctx.actions.declare_file(prefix + "_pkg.sv")
    final_outputs = [out_sv, out_pkg]

    # Preserve the raw file stems: PeakRDL uses them as the generated module
    # and package identifiers. The private directory prevents output clashes.
    raw_dir = ""
    if ctx.executable.postprocessor:
        raw_dir = "_reg_gen_raw/%s" % ctx.label.name
        export_sv = ctx.actions.declare_file(raw_dir + "/" + prefix + ".sv")
        export_pkg = ctx.actions.declare_file(raw_dir + "/" + prefix + "_pkg.sv")
    else:
        export_sv = out_sv
        export_pkg = out_pkg

    exporter_outputs = [export_sv, export_pkg]
    if ctx.attr.generate_hwif_report:
        report_name = prefix + "_hwif.rpt"
        if ctx.executable.postprocessor:
            report_name = raw_dir + "/" + report_name
        hwif_report = ctx.actions.declare_file(report_name)
        exporter_outputs.append(hwif_report)
        final_outputs.append(hwif_report)

    rdl_inputs = _collect_rdl_inputs(ctx)
    args = _common_args(ctx, rdl_inputs)
    args.add("--output")
    args.add(export_sv.path)
    args.add(export_pkg.path)
    _run(ctx, "RegGenRtl", args, exporter_outputs, rdl_inputs)
    if ctx.executable.postprocessor:
        postprocess_args = ctx.actions.args()
        postprocess_args.add("--input-files")
        postprocess_args.add_all([export_sv, export_pkg])
        postprocess_args.add("--output-files")
        postprocess_args.add_all([out_sv, out_pkg])
        ctx.actions.run(
            executable = ctx.executable.postprocessor,
            inputs = [export_sv, export_pkg],
            outputs = [out_sv, out_pkg],
            arguments = [postprocess_args],
            mnemonic = "RegGenRtlPostprocess",
            use_default_shell_env = False,
        )

    providers = [DefaultInfo(files = depset(final_outputs))]
    providers.append(make_verilog_info(
        new_entries = [make_dag_entry(
            srcs = [out_pkg, out_sv],
            hdrs = [],
            data = [],
            plis = [],
            deps = [],
            label = ctx.label,
            tags = [],
        )],
    ))
    return providers

_reg_gen_rtl = rule(
    implementation = _reg_gen_rtl_impl,
    attrs = _COMMON_ATTRS | {
        "generate_hwif_report": attr.bool(doc = "Generate an additional hardware-interface report."),
        "postprocessor": attr.label(
            cfg = "exec",
            executable = True,
            doc = "Optional executable that transforms --input-files into --output-files.",
        ),
        "tool": attr.label(
            default = "//reg_gen:reg_gen_rtl",
            cfg = "exec",
            executable = True,
        ),
    },
    doc = "Generate the SystemVerilog RTL (module + package) of a register block.",
)

# ---------------------------------------------------------------------------
# reg_gen_chdr
# ---------------------------------------------------------------------------

def _reg_gen_chdr_impl(ctx):
    out_header = ctx.actions.declare_file(_output_prefix(ctx) + ".h")
    outputs = [out_header]
    if ctx.attr.testcase:
        outputs.append(ctx.actions.declare_file(_output_prefix(ctx) + ".h.test.c"))

    rdl_inputs = _collect_rdl_inputs(ctx)
    args = _common_args(ctx, rdl_inputs)
    args.add("--output")
    args.add(out_header.path)
    return _run(ctx, "RegGenChdr", args, outputs, rdl_inputs)

_reg_gen_chdr = rule(
    implementation = _reg_gen_chdr_impl,
    attrs = _COMMON_ATTRS | {
        "testcase": attr.bool(doc = "Generate an additional C testcase for the header."),
        "tool": attr.label(
            default = "//reg_gen:reg_gen_chdr",
            cfg = "exec",
            executable = True,
        ),
    },
    doc = "Generate a C header for a register block.",
)

# ---------------------------------------------------------------------------
# reg_gen_html
# ---------------------------------------------------------------------------

def _reg_gen_html_impl(ctx):
    # The directory is named after the prefix so two reg_gen invocations in
    # the same package do not collide on a single output directory.
    out_html = ctx.actions.declare_directory(_output_prefix(ctx) + "_html")

    rdl_inputs = _collect_rdl_inputs(ctx)
    args = _common_args(ctx, rdl_inputs)
    args.add("--output")
    args.add(out_html.path)
    extra_inputs = []

    if ctx.attr.templates and not ctx.files.templates:
        fail("templates must provide at least one template file")
    if ctx.files.templates:
        template_dir = ctx.files.templates[0].dirname
        for template in ctx.files.templates:
            if template.dirname != template_dir:
                fail("HTML templates must all be files in one directory")
        args.add("--template-dir")
        args.add(template_dir)
        extra_inputs.extend(ctx.files.templates)

    if ctx.attr.static_files and not ctx.files.static_files:
        fail("static_files must provide at least one file")
    if ctx.files.static_files:
        static_dir = ctx.files.static_files[0].dirname
        for static_file in ctx.files.static_files:
            if static_file.dirname != static_dir:
                fail("HTML static files must all be files in one directory")
        args.add("--static-dir")
        args.add(static_dir)
        extra_inputs.extend(ctx.files.static_files)

    return _run(ctx, "RegGenHtml", args, [out_html], rdl_inputs, extra_inputs)

_reg_gen_html = rule(
    implementation = _reg_gen_html_impl,
    attrs = _COMMON_ATTRS | {
        "static_files": attr.label(allow_files = True, doc = "Hermetic HTML static files from one directory."),
        "templates": attr.label(allow_files = True, doc = "Hermetic HTML template files from one directory."),
        "tool": attr.label(
            default = "//reg_gen:reg_gen_html",
            cfg = "exec",
            executable = True,
        ),
    },
    doc = "Generate HTML documentation for a register block.",
)

# ---------------------------------------------------------------------------
# reg_gen_md
# ---------------------------------------------------------------------------

def _reg_gen_md_impl(ctx):
    # The file is named after the prefix so two reg_gen targets in the same
    # package do not collide on a single README.md output.
    prefix = _output_prefix(ctx)
    out_readme = ctx.actions.declare_file(prefix + "_README.md")

    rdl_inputs = _collect_rdl_inputs(ctx)
    args = _common_args(ctx, rdl_inputs)
    args.add("--output")
    args.add(out_readme.path)
    args.add("--prefix")
    args.add(prefix)
    args.add("--source-files")
    args.add_all(rdl_inputs.files)
    return _run(ctx, "RegGenMd", args, [out_readme], rdl_inputs)

_reg_gen_md = rule(
    implementation = _reg_gen_md_impl,
    attrs = _COMMON_ATTRS | {
        "tool": attr.label(
            default = "//reg_gen:reg_gen_md",
            cfg = "exec",
            executable = True,
        ),
    },
    doc = "Generate Markdown (README) documentation for a register block.",
)

# ---------------------------------------------------------------------------
# reg_gen_ral
# ---------------------------------------------------------------------------

def _reg_gen_ral_impl(ctx):
    out_uvm = ctx.actions.declare_file(_output_prefix(ctx) + "_uvm.sv")

    rdl_inputs = _collect_rdl_inputs(ctx)
    args = _common_args(ctx, rdl_inputs)
    args.add("--output")
    args.add(out_uvm.path)

    # PeakRDL-uvm accepts one template directory. Templates are label-backed
    # action inputs so custom policy remains hermetic and remotely executable.
    extra_inputs = []
    if ctx.attr.templates and not ctx.files.templates:
        fail("templates must provide at least one template file")

    templates = ctx.files.templates
    if templates:
        template_dir = templates[0].dirname
        for template in templates:
            if template.dirname != template_dir:
                fail("RAL templates must all be files in one directory, but got %s and %s" % (
                    template_dir,
                    template.dirname,
                ))

        extra_inputs = templates
        args.add("--template-dir")
        args.add(template_dir)

    providers = _run(ctx, "RegGenRal", args, [out_uvm], rdl_inputs, extra_inputs)
    providers.append(make_verilog_info(
        new_entries = [make_dag_entry(
            srcs = [out_uvm],
            hdrs = [],
            data = [],
            plis = [],
            deps = [],
            label = ctx.label,
            tags = [],
        )],
    ))
    return providers

_reg_gen_ral = rule(
    implementation = _reg_gen_ral_impl,
    attrs = _COMMON_ATTRS | {
        "templates": attr.label(
            allow_files = True,
            doc = "Custom UVM template files. All files must be in one directory.",
        ),
        "tool": attr.label(
            default = "//reg_gen:reg_gen_ral",
            cfg = "exec",
            executable = True,
        ),
    },
    doc = "Generate a UVM RAL model for a register block.",
)

# ---------------------------------------------------------------------------
# Thin public macros
# ---------------------------------------------------------------------------

_PRODUCTS = ["rtl", "chdr", "html", "md", "ral"]

def _config_values(config, kwargs, graph_options = [], forwarded_graph_options = []):
    config = dict(config or {})
    constructor = config.pop("constructor_kwargs", {})
    rule_values = {}

    for key in graph_options + forwarded_graph_options:
        if key in kwargs:
            fail("%s must be set inside config" % key)
    for key in graph_options:
        if key in config:
            rule_values[key] = config.pop(key)
    for key in forwarded_graph_options:
        if key in config:
            rule_values[key] = config[key]

    rule_values["exporter_options_json"] = json.encode(config)
    rule_values["constructor_options_json"] = json.encode(constructor)
    return rule_values

def _common_values(parameters, defines, top, instance_name, kwargs):
    values = dict(kwargs)
    values.update({
        "defines": defines,
        "instance_name": instance_name,
        "parameters": parameters,
        "top": top,
    })
    return values

def reg_gen_rtl(
        name,
        srcs,
        deps = [],
        prefix = "",
        config = {},
        parameters = [],
        defines = {},
        top = "",
        instance_name = "",
        **kwargs):
    values = _common_values(parameters, defines, top, instance_name, kwargs)
    values.update(_config_values(
        config,
        kwargs,
        graph_options = ["postprocessor"],
        forwarded_graph_options = ["generate_hwif_report"],
    ))
    _reg_gen_rtl(name = name, srcs = srcs, deps = deps, prefix = prefix, **values)

def reg_gen_chdr(
        name,
        srcs,
        deps = [],
        prefix = "",
        config = {},
        parameters = [],
        defines = {},
        top = "",
        instance_name = "",
        **kwargs):
    values = _common_values(parameters, defines, top, instance_name, kwargs)
    values.update(_config_values(config, kwargs, forwarded_graph_options = ["testcase"]))
    _reg_gen_chdr(name = name, srcs = srcs, deps = deps, prefix = prefix, **values)

def reg_gen_html(
        name,
        srcs,
        deps = [],
        prefix = "",
        config = {},
        parameters = [],
        defines = {},
        top = "",
        instance_name = "",
        **kwargs):
    values = _common_values(parameters, defines, top, instance_name, kwargs)
    values.update(_config_values(config, kwargs, graph_options = ["templates", "static_files"]))
    _reg_gen_html(name = name, srcs = srcs, deps = deps, prefix = prefix, **values)

def reg_gen_md(
        name,
        srcs,
        deps = [],
        prefix = "",
        config = {},
        parameters = [],
        defines = {},
        top = "",
        instance_name = "",
        **kwargs):
    values = _common_values(parameters, defines, top, instance_name, kwargs)
    values.update(_config_values(config, kwargs))
    _reg_gen_md(name = name, srcs = srcs, deps = deps, prefix = prefix, **values)

def reg_gen_ral(
        name,
        srcs,
        deps = [],
        prefix = "",
        config = {},
        parameters = [],
        defines = {},
        top = "",
        instance_name = "",
        **kwargs):
    values = _common_values(parameters, defines, top, instance_name, kwargs)
    values.update(_config_values(config, kwargs, graph_options = ["templates"]))
    _reg_gen_ral(name = name, srcs = srcs, deps = deps, prefix = prefix, **values)

def reg_gen(
        name,
        srcs,
        deps = [],
        prefix = "",
        config = {},
        parameters = [],
        defines = {},
        top = "",
        instance_name = "",
        **kwargs):
    """Creates all five products from one dictionary of product configs.

    Args:
        name: name of the target
        srcs: RDL inputs/sources
        deps: RDL library dependencies (other RDL files)
        prefix: Prefix given to outputs, e.g. <myip>_csr_pkg
        config: Product selection
        parameters: Additional parameters passed to peakrdl
        defines: Additional defines passed to peakrdl
        top: Top level
        instance_name: Top level instance name
        **kwargs: Additional options
    """
    prefix = prefix if prefix else name
    common = _common_values(parameters, defines, top, instance_name, kwargs)
    for product in config:
        if product not in _PRODUCTS:
            fail("unknown reg_gen product %r; expected one of %s" % (product, _PRODUCTS))

    products = [
        ("rtl", reg_gen_rtl),
        ("chdr", reg_gen_chdr),
        ("html", reg_gen_html),
        ("md", reg_gen_md),
        ("ral", reg_gen_ral),
    ]
    for product, generator in products:
        generator(
            name = name + "_" + product,
            srcs = srcs,
            deps = deps,
            prefix = prefix,
            config = config.get(product, {}),
            **common
        )
