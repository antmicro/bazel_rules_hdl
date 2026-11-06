"""Module extensions useful alongside Verilator"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def _uvm_verilator_impl(_):
    repo_name = "uvm-verilator"
    git_tag = "uvm-2020-3.2"

    archive_url = "https://github.com/chipsalliance/uvm-verilator/archive/%s.tar.gz" % git_tag
    archive_sha256 = "9647bfe69439340f1f5c8c969b9814aed06cde9fe4c355111bd5e7cd325c0e0f"
    archive_strip_prefix = "uvm-verilator-%s" % git_tag

    http_archive(
        name = repo_name,
        sha256 = archive_sha256,
        url = archive_url,
        strip_prefix = archive_strip_prefix,
        build_file = ":uvm_verilator.BUILD",
    )

uvm_verilator = module_extension(implementation = _uvm_verilator_impl)
