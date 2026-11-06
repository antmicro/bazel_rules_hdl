load("@rules_hdl//verilog:defs.bzl", "verilog_library")
load("@rules_hdl//pli:defs.bzl", "pli_library")

package(default_visibility = ["//visibility:public"])

pli_library(
    name = "uvm_dpi",
    srcs = [
        "src/dpi/uvm_dpi.cc",
    ],
    hdrs = glob([
		"src/dpi/*.h",
		"src/dpi/*.c",
		"src/dpi/*.cc"
	]),
)

verilog_library(
    name = "uvm",
    hdrs = glob([
		"src/*/*.svh",
		"src/uvm_macros.svh",
		"src/reg/sequences/*.svh",
		"src/deprecated/macros/*.svh",
	]),
    srcs = [
        "src/uvm_pkg.sv",
    ],
    plis = [
        ":uvm_dpi",  
    ],
)
