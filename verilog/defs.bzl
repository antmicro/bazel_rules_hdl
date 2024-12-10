"""verilog rules"""

load(
    ":filelist.bzl",
    _verilog_filelist = "verilog_filelist",
)
load(
    ":providers.bzl",
    _VerilogInfo = "VerilogInfo",
    _verilog_library = "verilog_library",
)

VerilogInfo = _VerilogInfo
verilog_library = _verilog_library
verilog_filelist = _verilog_filelist
