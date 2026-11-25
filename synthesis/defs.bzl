"""Rules for synthesizing (System)Verilog code."""

load(
    ":build_defs.bzl",
    _SdcInfo = "SdcInfo",
    _SynthesisInfo = "SynthesisInfo",
    _UhdmInfo = "UhdmInfo",
    _benchmark_synth = "benchmark_synth",
    _reformat_json = "reformat_json",
    _sdc_library = "sdc_library",
    _synth_opt = "synth_opt",
    _synthesize_rtl = "synthesize_rtl",
    _translate = "translate",
)

benchmark_synth = _benchmark_synth
SynthesisInfo = _SynthesisInfo
synthesize_rtl = _synthesize_rtl
UhdmInfo = _UhdmInfo
SdcInfo = _SdcInfo
sdc_library = _sdc_library
translate = _translate
synth_opt = _synth_opt
reformat_json = _reformat_json
