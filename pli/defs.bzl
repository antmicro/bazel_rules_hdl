"""PLI, VPI and DPI related rules"""

load(
    ":providers.bzl",
    _PliInfo = "PliInfo",
    _pli_library = "pli_library",
)

PliInfo = _PliInfo
pli_library = _pli_library
