"""Module extensions for HDL tools."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def _tools_extension_impl(module_ctx):
    # Yosys
    maybe(
        http_archive,
        name = "at_clifford_yosys",
        # The release tarball (unlike the source archive) includes submodules.
        urls = [
            "https://github.com/YosysHQ/yosys/releases/download/v0.70/yosys.tar.gz",
        ],
        sha256 = "c6bd8b83aad633f6786fc861fe8f5dbc74c37bfae77f7bd0220e6f00f15f1d55",
        build_file = "//dependency_support/at_clifford_yosys:bundled.BUILD.bazel",
        # Submodules ship their own Bazel files, which would split packages
        # and pull in deps we don't have.
        # Need to switch mp calls to support TCL9, yosys using an older version
        patch_cmds = [
            "find libs frontends -mindepth 2 \\( -name BUILD.bazel -o -name MODULE.bazel -o -name WORKSPACE \\) -delete",
            "sed -i 's/mp_unsigned_bin_size(a)/mp_ubin_size(a)/; s/mp_to_unsigned_bin(a, buf.data())/mp_to_ubin(a, buf.data(), buf.size(), nullptr)/' kernel/tclapi.cc",
            "! grep -n 'unsigned_bin' kernel/tclapi.cc",
        ],
    )

    # EQY, built against the Yosys above.
    maybe(
        http_archive,
        name = "eqy",
        urls = ["https://github.com/YosysHQ/eqy/archive/refs/tags/v0.70.tar.gz"],
        sha256 = "8eb3e295c7d1e5708a5879188648371a1a8244be2403221622a953a70f22d412",
        strip_prefix = "eqy-0.70",
        build_file = "//dependency_support/eqy:bundled.BUILD.bazel",
    )

    # SBY
    maybe(
        http_archive,
        name = "sby",
        urls = ["https://github.com/YosysHQ/sby/archive/refs/tags/v0.70.tar.gz"],
        sha256 = "f2a3614f4ca56180d5e650d48a510fc8c1359b4f81a971634a479feb171f363a",
        strip_prefix = "sby-0.70",
        build_file = "//dependency_support/sby:bundled.BUILD.bazel",
    )

    # Yices, the default SMT solver of yosys-smtbmc.
    maybe(
        http_archive,
        name = "yices",
        urls = ["https://github.com/SRI-CSL/yices2/archive/refs/tags/yices-2.7.0.tar.gz"],
        sha256 = "584db72abf6643927b2c3ba98ff793f602216b452b8ff2f34a8851d35904804a",
        strip_prefix = "yices2-yices-2.7.0",
        build_file = "//dependency_support/yices:bundled.BUILD.bazel",
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
        urls = ["https://github.com/verilator/verilator/archive/01770671ed125677ff2c9580fa209e04bdc753d5.tar.gz"],
        sha256 = "78d2d76095def8f5945b7ca3844f80fcca9c4a449acc2e1357395335557655c2",
        strip_prefix = "verilator-01770671ed125677ff2c9580fa209e04bdc753d5",
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
        root_module_direct_deps = ["at_clifford_yosys", "eqy", "sby", "yices", "com_icarus_iverilog", "verilator", "net_lz4"],
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
