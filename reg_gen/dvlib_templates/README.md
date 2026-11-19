# dvlib-compatible PeakRDL-uvm templates

Use these templates to generate a UVM RAL model for a DV environment that
provides the OpenTitan-style `dvlib` register base classes. Generated register
blocks derive from `dv_base_reg_block` and follow the corresponding DV-library
conventions.

They are not general-purpose UVM templates and are not suitable for an
environment that only provides standard `uvm_reg_block` support.

Use them explicitly:

```starlark
load("//reg_gen:defs.bzl", "reg_gen_ral")

reg_gen_ral(
    name = "control_ral",
    srcs = ["control.rdl"],
    config = {
        "templates": "//reg_gen/dvlib_templates:dvlib_templates",
    },
)
```
