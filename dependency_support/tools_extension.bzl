"""Module extensions for HDL tools."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def _tools_extension_impl(module_ctx):
    # Yosys
    maybe(
        http_archive,
        name = "at_clifford_yosys",
        urls = [
            "https://github.com/YosysHQ/yosys/archive/8f07a0d8404f63349d8d3111217b73c9eafbd667.zip",
        ],
        sha256 = "46a9a4d969770fa20a2fd12c8e83307a597126609645c9655c370c0c365da344",
        strip_prefix = "yosys-8f07a0d8404f63349d8d3111217b73c9eafbd667",
        build_file = "//dependency_support/at_clifford_yosys:bundled.BUILD.bazel",
        patches = [
            "//dependency_support/at_clifford_yosys:yosys.patch",
            "//dependency_support/at_clifford_yosys:autoname.patch",
        ],
    )

    # Icarus Verilog
    maybe(
        http_archive,
        name = "com_icarus_iverilog",
        urls = [
            "https://github.com/steveicarus/iverilog/archive/2e81fcccb36edd2c4dd357034061fc9f2df36548.tar.gz",
        ],
        strip_prefix = "iverilog-2e81fcccb36edd2c4dd357034061fc9f2df36548",
        sha256 = "8881ebf9e04fe2206b8aa88eb18775dc040fc429f7fb5c7e93a309e6c1716949",
        build_file = "//dependency_support/com_icarus_iverilog:bundled.BUILD.bazel",
    )

    return module_ctx.extension_metadata(
        root_module_direct_deps = ["at_clifford_yosys", "com_icarus_iverilog"],
        root_module_direct_dev_deps = [],
    )

tools_extension = module_extension(
    implementation = _tools_extension_impl,
    tag_classes = {
        "use_toolchain": tag_class(
            attrs = {
                "name": attr.string(mandatory = True),
            },
        ),
    },
)
