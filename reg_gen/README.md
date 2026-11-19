# SystemRDL register generation

Use these Bazel macros to generate register artifacts from SystemRDL sources.
The available products are RTL, a C header, HTML documentation, Markdown
documentation, and a UVM RAL model.

## Generate all products

```starlark
load("//reg_gen:defs.bzl", "reg_gen")

reg_gen(
    name = "control_regs",
    srcs = ["control.rdl"],
    config = {
        "rtl": {
            "cpuif": "apb3_flattened",
            "default_reset_async": True,
        },
        "ral": {
            "use_uvm_factory": True,
        },
    },
)
```

This creates five targets:

| Target | Output |
| --- | --- |
| `control_regs_rtl` | `control_regs.sv`, `control_regs_pkg.sv` |
| `control_regs_chdr` | `control_regs.h` |
| `control_regs_html` | `control_regs_html/` |
| `control_regs_md` | `control_regs_README.md` |
| `control_regs_ral` | `control_regs_uvm.sv` |

Each product's `config` dictionary contains keyword arguments for its PeakRDL
exporter. Arguments for an exporter constructor go under `constructor_kwargs`:

```starlark
config = {
    "html": {
        "constructor_kwargs": {
            "show_signals": True,
        },
        "title": "Control registers",
    },
}
```

Use the option names documented by the corresponding PeakRDL exporter. Values
must be JSON-compatible.

## Generate one product

Use a product-specific macro when only one artifact is needed:

```starlark
load("//reg_gen:defs.bzl", "reg_gen_rtl")

reg_gen_rtl(
    name = "control_regs_rtl",
    srcs = ["control.rdl"],
    config = {
        "cpuif": "apb3_flattened",
    },
)
```

The product-specific macros are `reg_gen_rtl`, `reg_gen_chdr`,
`reg_gen_html`, `reg_gen_md`, and `reg_gen_ral`. RTL and RAL targets also
provide `VerilogInfo` for use by downstream HDL targets.

## File and output options

Options that refer to Bazel files or add outputs also belong in `config`:

- RTL: `postprocessor`, `generate_hwif_report`
- C header: `testcase`
- HTML: `templates`, `static_files`
- RAL: `templates`

For example:

```starlark
reg_gen_ral(
    name = "control_regs_ral",
    srcs = ["control.rdl"],
    config = {
        "templates": "//path/to/templates",
        "use_uvm_factory": True,
    },
)
```

## Shared RDL sources

Use `rdl_library` to share SystemRDL files and their include paths:

```starlark
load("//reg_gen:defs.bzl", "rdl_library", "reg_gen_html")

rdl_library(
    name = "common_rdl",
    srcs = ["common.rdl"],
)

reg_gen_html(
    name = "control_regs_html",
    srcs = ["control.rdl"],
    deps = [":common_rdl"],
)
```

All generator macros also accept `prefix`, `parameters`, `defines`, `top`,
and `instance_name` for controlling compilation and output names.
