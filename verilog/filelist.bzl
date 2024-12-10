"""Verilog filelist generation rules"""

load(":providers.bzl", "VerilogInfo")

def _verilog_filelist_impl(ctx):
    """Collects all direct and transitive sources/headers of a verilog library"""

    # Sources
    srcs = depset([], transitive = [ctx.attr.lib[VerilogInfo].dag]).to_list()

    # Flatten
    all_srcs = [info.srcs for info in srcs]
    all_hdrs = [info.hdrs for info in srcs]

    all_srcs = [f for sub_tuple in all_srcs for f in sub_tuple]
    all_hdrs = [f for sub_tuple in all_hdrs for f in sub_tuple]

    # Include directories
    include_dirs = depset([f.dirname for f in all_hdrs]).to_list()

    # Write the .f file
    content = []

    for name in include_dirs:
        content.append(ctx.attr.include_prefix + name)

    for name in all_srcs:
        content.append(name.path)

    file = ctx.actions.declare_file(ctx.label.name + ".f")
    ctx.actions.write(file, "\n".join(content) + "\n")

    return DefaultInfo(
        files = depset([file]),
    )

verilog_filelist = rule(
    doc = "Generate a .f file from a Verilog library.",
    implementation = _verilog_filelist_impl,
    attrs = {
        "include_prefix": attr.string(
            doc = "Prefix for include directories",
            default = "+incdir+",
        ),
        "lib": attr.label(
            doc = "The Verilog library to use",
            providers = [VerilogInfo],
            mandatory = True,
        ),
    },
    provides = [
        DefaultInfo,
    ],
)
