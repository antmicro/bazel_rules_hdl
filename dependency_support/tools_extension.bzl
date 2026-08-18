"""Module extensions for HDL tools."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def _at_clifford_yosys_aliases_impl(repository_ctx):
    repository_ctx.file("BUILD.bazel", repository_ctx.attr.build_file_content)

_at_clifford_yosys_aliases = repository_rule(
    implementation = _at_clifford_yosys_aliases_impl,
    attrs = {
        "build_file_content": attr.string(mandatory = True),
    },
    doc = "Aliases for rules_hdl's dependency_support/at_clifford_yosys package.",
)

def _tools_extension_impl(module_ctx):
    # Yosys / OSS CAD Suite
    maybe(
        http_archive,
        name = "at_clifford_yosys_data",
        urls = [
            "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-08-10/oss-cad-suite-linux-x64-20260810.tgz",
        ],
        type = "tar.gz",
        sha256 = "4d1137c56eaa7f2fadce7dd7f79b614cc5f7862684bcbe79765bb9a1f9037db0",
        strip_prefix = "oss-cad-suite",
        build_file = "//dependency_support/at_clifford_yosys:bundled.BUILD.bazel",
    )

    # Alias Yosys tools for compatibility with existing rules relying on @at_clifford_yosys/... targets.
    alias_targets = [
        "yosys",
        "yosys_abc",
        "yosys_config",
        "yosys_filterlib",
        "yosys_smtbmc",
        "yosys_witness",
        "eqy",
    ]
    alias_build_content = 'package(default_visibility = ["//visibility:public"])\n\n'
    for target in alias_targets:
        real_label = str(Label("//dependency_support/at_clifford_yosys:" + target))
        alias_build_content += 'alias(\n    name = "{}",\n    actual = "{}",\n)\n\n'.format(target, real_label)

    _at_clifford_yosys_aliases(
        name = "at_clifford_yosys",
        build_file_content = alias_build_content,
    )

    # Icarus Verilog
    maybe(
        http_archive,
        name = "com_icarus_iverilog",
        urls = [
            "https://github.com/steveicarus/iverilog/archive/v12_0.tar.gz",
        ],
        strip_prefix = "iverilog-12_0",
        sha256 = "a68cb1ef7c017ef090ebedb2bc3e39ef90ecc70a3400afb4aa94303bc3beaa7d",
        build_file = "//dependency_support/com_icarus_iverilog:bundled.BUILD.bazel",
    )

    # Verilator
    maybe(
        http_archive,
        name = "verilator",
        urls = ["https://github.com/verilator/verilator/archive/v5.052.tar.gz"],
        sha256 = "8c8d2e11e6ad32f641dd250742a94195ddecb912e2e2dabe2f42ddbbb99c1092",
        strip_prefix = "verilator-5.052",
        build_file = "//dependency_support/verilator:verilator.BUILD.bazel",
    )

    # lz4
    maybe(
        http_archive,
        name = "net_lz4",
        urls = ["https://github.com/lz4/lz4/releases/download/v1.10.0/lz4-1.10.0.tar.gz"],
        strip_prefix = "lz4-1.10.0",
        sha256 = "537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b",
        build_file = "//dependency_support/net_lz4:net_lz4.BUILD.bazel",
    )

    return module_ctx.extension_metadata(
        root_module_direct_deps = ["at_clifford_yosys", "at_clifford_yosys_data", "com_icarus_iverilog", "verilator", "net_lz4"],
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
