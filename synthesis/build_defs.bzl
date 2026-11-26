# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Rules for synthesizing (System)Verilog code."""

load("//pdk:build_defs.bzl", "StandardCellInfo")
load("//verilog:defs.bzl", "VerilogInfo", "make_dag_entry", "make_verilog_info")

# There are no rules to generate this provider, but it does provide the mechanism to build
# rules based on surelog in the open source world.
UhdmInfo = provider(
    "Surelog/UHDM based RTL representation",
    fields = {
        "uhdm": "UHDM file representing the rtl circuit",
    },
)

SynthesisInfo = provider(
    "Information about the synthesis target",
    fields = {
        "log_file": "Log output file from the synthesis step.",
        "standard_cell_info": "The StandardCellInfo provider this target was synthesized against.",
        "synthesized_netlist": "The structural verilog synthesized with standard_cell_info",
        "top_module": "The name of the top level module of the synthesized netlist",
    },
)

def _transitive_srcs(deps):
    return depset(
        [],
        transitive = [dep[VerilogInfo].dag for dep in deps],
    )

def _create_inc_dir_list(files, hdr_files):
    """Create an include directory list from files and header files"""

    ## Do it for both RTL files and headers, just in case the synthesis tool
    ## does not set the RTL verilog directories as part of include paths

    # Base include directories
    base_include_dirs = depset([f.dirname for f in (files + hdr_files)]).to_list()

    # For each include directory traverse it back to root and add all intermediate
    # directories as potential locations of include files. Deduplicate the final
    # list via depset()
    include_dirs = []
    for dirname in base_include_dirs:
        parts = dirname.split("/")
        for i in range(len(parts)):
            include_dirs.append("/".join([parts[j] for j in range(0, i + 1)]))
    include_dirs = depset(include_dirs).to_list()

    return include_dirs

def _yosys_script_header(ctx, yosys_stats = None):
    """Generate a default header for all the Yosys scripts with common variables set"""
    cmd = []
    cmd.append("yosys -import")
    cmd.append("set top %s" % ctx.attr.top_module)
    if yosys_stats != None:
        cmd.append("set yosys_stats %s" % yosys_stats.path)

    ## Only 1 library expected for standard_cells
    cmd.append("set stdcell_lib %s" % ctx.attr.standard_cells[StandardCellInfo].default_corner.liberty.path)

    ## liberty will contain standard cells and all other potential liberty files
    liberty = [ctx.attr.standard_cells]
    if ctx.attr.extra_libs != []:
        liberty.extend(ctx.attr.extra_libs)
    lib_files = [lib[StandardCellInfo].default_corner.liberty for lib in liberty]
    cmd.append("set liberty [list]")
    for lib in lib_files:
        cmd.append("lappend liberty %s" % lib.path)
    cmd.append("foreach lib $liberty { read_liberty -lib $lib }")

    return cmd, lib_files

def _translate_logic(ctx, rtlil_netlist, log_file, standard_cell_black_box, parser_extra_commands, tool_extra_args):
    """Yosys compilation logic, abstracted away from rule implementation"""

    inputs = []

    translate_common_tcl = ctx.actions.declare_file("{}_synthesis_translate_common.tcl".format(ctx.label.name))
    rtlil_compile_script = ctx.actions.declare_file("{}_synthesis_translate.tcl".format(ctx.label.name))

    ## Retrieve all RTL files and headers
    transitive_srcs = _transitive_srcs([dep for dep in ctx.attr.deps if VerilogInfo in dep])
    verilog_srcs = [verilog_info_struct.srcs for verilog_info_struct in transitive_srcs.to_list()]
    verilog_data = [verilog_info_struct.data for verilog_info_struct in transitive_srcs.to_list()]
    verilog_files = [src for sub_tuple in (verilog_srcs + verilog_data) for src in sub_tuple]
    verilog_hdrs = [verilog_info_struct.hdrs for verilog_info_struct in transitive_srcs.to_list()]
    verilog_hdr_files = [hdr for sub_tuple in verilog_hdrs for hdr in sub_tuple]

    include_dirs = _create_inc_dir_list(verilog_files, verilog_hdr_files)

    inputs.extend(verilog_files)
    inputs.extend(verilog_hdr_files)

    # Use a dictionnary to fill the TCL script
    substitutions = {
        "{{INCDIR}}": " ".join(include_dirs),
        "{{PARSER_EXTRA_COMMANDS}}": " ".join(parser_extra_commands),
        "{{RTLIL_NETLIST}}": rtlil_netlist.path,
        "{{RTL_FILES}}": " ".join([f.path for f in verilog_files]),
        "{{STDCELL_BLACKBOX}}": standard_cell_black_box.path,
        "{{STDCELL_LIB}}": ctx.attr.standard_cells[StandardCellInfo].default_corner.liberty.path,
        "{{TOP}}": ctx.attr.top_module,
    }

    inputs.append(ctx.attr.standard_cells[StandardCellInfo].default_corner.liberty)

    # Exttra liberty files
    extra_libs = ""
    if ctx.attr.extra_libs != []:
        lib_files = [lib[StandardCellInfo].default_corner.liberty for lib in ctx.attr.extra_libs]
        for lib in lib_files:
            extra_libs += "lappend liberty %s\n" % lib.path
            inputs.append(lib)
    substitutions["{{EXTRA_LIBS}}"] = extra_libs

    # Define need custom pre-processing
    macro_names = []
    macro_values = []
    for d in ctx.attr.verilog_defines:
        macro_name, _, macro_value = d.partition("=")
        macro_value = macro_value or str(1)
        macro_names.append(macro_name)
        macro_values.append(macro_value)
    substitutions["{{MACRO_NAMES}}"] = " ".join(macro_names)
    substitutions["{{MACRO_VALUES}}"] = " ".join(macro_values)

    if ctx.attr.frontend == "custom":
        inputs.append(ctx.file.translate_tcl)
        substitutions["{{TRANSLATE_TCL}}"] = ctx.file.translate_tcl.path

    # Generate a common TCL script containing all the variables
    template_common = None
    template_translate = None
    for script in ctx.files._synth_tcl_templates:
        if script.basename == "translate_%s.tcl" % ctx.attr.frontend:
            template_translate = script
        elif script.basename == "translate_common.tcl":
            template_common = script
    if template_common == None or template_translate == None:
        fail("ERROR: failed to retrieve TCL templates")

    # Common translate, same for all
    ctx.actions.expand_template(
        template = template_common,
        output = translate_common_tcl,
        substitutions = substitutions,
    )

    inputs.append(translate_common_tcl)

    substitutions["{{TRANSLATE_COMMON_TCL}}"] = translate_common_tcl.path

    # Compile, frontend specific
    ctx.actions.expand_template(
        template = template_translate,
        output = rtlil_compile_script,
        substitutions = substitutions,
    )

    ## Yosys arguments
    args = []
    args.append("-q")  # quiet mode only errors printed to stderr
    args.append("-Q")  # Don't print header
    args.extend(["-l", log_file.path])  # put output in log file
    args.extend(tool_extra_args)

    # Main TCL script
    args.extend(["-c", rtlil_compile_script.path])
    inputs.append(rtlil_compile_script)

    ## Yosys runfiles
    tcl_library_dir = ""
    yosys_runfiles = ctx.attr.yosys_tool[DefaultInfo].default_runfiles.files.to_list()
    for f in yosys_runfiles:
        if not tcl_library_dir and f.path.endswith("library/init.tcl"):
            tcl_library_dir = f.dirname
    inputs.extend(yosys_runfiles)
    env = {
        "TCL_LIBRARY": tcl_library_dir,
    }

    ctx.actions.run(
        outputs = [log_file, rtlil_netlist, standard_cell_black_box],
        inputs = inputs,
        arguments = args,
        env = env,
        executable = ctx.executable.yosys_tool,
        mnemonic = "TranslateRTL",
    )

def _translate_impl(ctx):
    """RTL compilation and translation into RTLIL"""
    rtlil_filename = "{}_netlist.rtlil".format(ctx.label.name)
    if ctx.attr.output_file_name:
        rtlil_filename = ctx.attr.output_file_name
    rtlil_netlist = ctx.actions.declare_file(rtlil_filename)
    log_file = ctx.actions.declare_file("{}_synthesis_translate.log".format(ctx.label.name))
    standard_cell_black_box = ctx.actions.declare_file("{}_stdcells_blackbox.v".format(ctx.label.name))
    parser_commands = ctx.attr.parser_extra_commands
    tool_extra_args = ctx.attr.tool_extra_args

    _translate_logic(ctx, rtlil_netlist, log_file, standard_cell_black_box, parser_commands, tool_extra_args)

    return [
        DefaultInfo(
            runfiles = ctx.runfiles(files = [rtlil_netlist]),
            files = depset([rtlil_netlist]),
        ),
        OutputGroupInfo(
            logs = depset([log_file]),
            blackbox = depset([standard_cell_black_box]),
        ),
    ]

def _synth_opt_main_script(ctx):
    synth_opt_tcl = None
    if ctx.attr.strategy == "custom":
        synth_opt_tcl = ctx.file.custom_synth_opt_tcl
    else:
        for script in ctx.files._synth_opt_scripts:
            if script.basename == "opt_%s.tcl" % ctx.attr.strategy:
                synth_opt_tcl = script
    if synth_opt_tcl == None:
        fail("Could not find the main synthesis optimization script")
    return synth_opt_tcl

def _synth_opt_impl(ctx):
    """Optimization on RTLIL representation and generation of the verilog netlist"""
    netlist_filename = "{}_netlist.v".format(ctx.label.name)
    if ctx.attr.verilog_netlist_name:
        netlist_filename = ctx.attr.verilog_netlist_name
    verilog_netlist = ctx.actions.declare_file(netlist_filename)
    log_file = ctx.actions.declare_file("{}_synthesis_opt.log".format(ctx.label.name))
    yosys_stats = ctx.actions.declare_file("{}_yosys_stats.json".format(ctx.label.name))
    rtlil_netlist = ctx.file.rtlil_netlist
    extra_inputs = list(ctx.files._synth_opt_scripts)
    if ctx.attr.strategy == "custom":
        extra_inputs.extend(ctx.files.custom_srcs)

    # Select the main optimization script
    synth_opt_tcl = _synth_opt_main_script(ctx)

    _synth_opt_logic(ctx, rtlil_netlist, ctx.attr.strategy, synth_opt_tcl, extra_inputs, verilog_netlist, log_file, yosys_stats, ctx.attr.tool_extra_args)

    return [
        DefaultInfo(
            runfiles = ctx.runfiles(files = [verilog_netlist]),
            files = depset([verilog_netlist]),
        ),
        OutputGroupInfo(
            logs = depset([log_file]),
            auxiliary = depset([yosys_stats]),
        ),
        SynthesisInfo(
            standard_cell_info = ctx.attr.standard_cells[StandardCellInfo],
            synthesized_netlist = verilog_netlist,
            top_module = ctx.attr.top_module,
            log_file = log_file,
        ),
        make_verilog_info(
            new_entries = [make_dag_entry(
                label = ctx.label,
                srcs = [verilog_netlist],
                hdrs = [],
                data = [],
                deps = [],
                tags = [],
                plis = [],
            )],
        ),
    ]

def _synth_opt_logic(ctx, rtlil_netlist, strategy, synth_opt_tcl, extra_inputs, verilog_netlist, log_file, yosys_stats, tool_extra_args):
    syn_opt_script = ctx.actions.declare_file("{}_synthesis_opt.tcl".format(ctx.label.name))

    inputs = [rtlil_netlist]
    inputs.extend(extra_inputs)

    ## Generate the translation commands
    cmd, liberty = _yosys_script_header(ctx, yosys_stats)
    inputs.extend(liberty)
    cmd.append("read_rtlil %s" % rtlil_netlist.path)
    cmd.append("hierarchy -check -top $top")

    ## Pass the reference clock period
    cmd.append("set period_ps %s" % ctx.attr.target_clock_period_pico_seconds)

    # Openroad configuration for PDK information
    or_config = ctx.attr.standard_cells[StandardCellInfo].open_road_configuration

    env = {}

    cmd.append("set dont_use_args [list]")
    if or_config:
        for dont_use_pattern in or_config.do_not_use_cell_list:
            cmd.append("lappend dont_use_args -dont_use %s" % dont_use_pattern)

    if strategy != "custom":
        # Constr for ABC, always generated
        std_cell = ctx.attr.standard_cells
        constr = ctx.actions.declare_file("{}_abc_constraints.constr".format(ctx.label.name))
        constr_contents = ""
        default_driver_cell = getattr(std_cell[StandardCellInfo], "default_input_driver_cell", "")
        if default_driver_cell:
            constr_contents = "set_driving_cell {}\n".format(default_driver_cell)
        default_load = getattr(std_cell[StandardCellInfo], "default_output_load", "")
        if default_load:
            constr_contents += "set_load {}\n".format(default_load)
        ctx.actions.write(constr, constr_contents)
        inputs.append(constr)
        cmd.append("set abc_constr %s" % constr.path)

        # Adder mapping
        if or_config:
            ha_fa_mapping = or_config.ha_fa_mapping
            if ha_fa_mapping:
                ha_fa_mapping_path = ha_fa_mapping[DefaultInfo].files.to_list()[0].path
                env["ADDER_MAPPING"] = "1"
                inputs.append(ha_fa_mapping[DefaultInfo].files.to_list()[0])
                cmd.append("set adder_mapping %s" % ha_fa_mapping_path)

        # ABC script
        abc_script_file = None
        lms_aig = None
        for f in ctx.files._synth_opt_scripts:
            if f.basename == "abc_%s.script" % strategy:
                abc_script_file = f
            if f.basename == "lazy_man_synth_library.aig":
                lms_aig = f
        if abc_script_file == None:
            fail("ERROR: abc script not found under name abc_%s.script" % strategy)
        if strategy == "lms" and lms_aig == None:
            fail("ERROR: failed to retrieve lms aig file.")

        ## Rewrite abc file with proper timing
        substitutions = {
            "lazy_man_synth_library.aig": "unused" if lms_aig == None else lms_aig.path,
            "{D}": str(ctx.attr.target_clock_period_pico_seconds),
        }
        abc_script_with_timing = ctx.actions.declare_file("{}_abc_with_timing.script".format(ctx.label.name))
        ctx.actions.expand_template(
            template = abc_script_file,
            output = abc_script_with_timing,
            substitutions = substitutions,
        )
        cmd.append("set abc_script %s" % abc_script_with_timing.path)
        inputs.append(abc_script_with_timing)

    # ABC always added to sources, used or not
    inputs.append(ctx.executable.abc_tool)

    cmd.append("source %s" % synth_opt_tcl.path)

    # Tie port, valid for all strategies
    if or_config:
        if or_config.tie_low_port or or_config.tie_high_port:
            cmd_string = "hilomap -singleton "
            if or_config.tie_low_port:
                cmd_string += "-locell "
                tielow_cells = str(or_config.tie_low_port).split("/")
                for cell in tielow_cells:
                    cmd_string += "%s " % cell
            if or_config.tie_high_port:
                cmd_string += "-hicell "
                tiehi_cells = str(or_config.tie_high_port).split("/")
                for cell in tiehi_cells:
                    cmd_string += "%s " % cell
            cmd.append(cmd_string)

    # Output and reporting
    cmd.append("write_verilog %s" % verilog_netlist.path)
    cmd.append("""
stat -liberty $stdcell_lib
tee -q -o $yosys_stats stat -liberty $stdcell_lib -json
yosys log Structured stats: $yosys_stats
read_liberty -lib -ignore_miss_func $stdcell_lib
ltp -noff $top
yosys log -n "Flop count: "
yosys select -count t:*__df* t:DF* t:*_DFF* t:*_SDFF* t:*_ADFF* t:*dff
yosys log Liberty: $stdcell_lib
""")

    # Yosys script
    ctx.actions.write(syn_opt_script, "\n".join(cmd))

    ## Yosys runfiles
    tcl_library_dir = ""
    yosys_runfiles = ctx.attr.yosys_tool[DefaultInfo].default_runfiles.files.to_list()
    for f in yosys_runfiles:
        if not tcl_library_dir and f.path.endswith("library/init.tcl"):
            tcl_library_dir = f.dirname
    inputs.extend(yosys_runfiles)
    env["ABC"] = ctx.executable.abc_tool.path
    env["TCL_LIBRARY"] = tcl_library_dir

    ## Yosys arguments
    args = []
    args.append("-q")  # quiet mode only errors printed to stderr
    args.append("-Q")  # Don't print header
    args.extend(["-l", log_file.path])  # put output in log file
    args.extend(tool_extra_args)
    args.extend(["-c", syn_opt_script.path])
    inputs.append(syn_opt_script)

    ctx.actions.run(
        outputs = [log_file, verilog_netlist, yosys_stats],
        inputs = inputs,
        arguments = args,
        env = env,
        executable = ctx.executable.yosys_tool,
        mnemonic = "OptimizeRTL",
    )

def _synthesize_design_impl(ctx):
    rtlil_filename = "{}_netlist.rtlil".format(ctx.label.name)
    rtlil_netlist = ctx.actions.declare_file(rtlil_filename)
    standard_cell_black_box = ctx.actions.declare_file("{}_stdcells_blackbox.v".format(ctx.label.name))

    translate_log_file = ctx.actions.declare_file("{}_synthesis_translate.log".format(ctx.label.name))
    parser_commands = ctx.attr.parser_extra_commands
    tool_extra_args = ctx.attr.tool_extra_args

    _translate_logic(ctx, rtlil_netlist, translate_log_file, standard_cell_black_box, parser_commands, tool_extra_args)

    netlist_filename = "{}_netlist.v".format(ctx.label.name)
    if ctx.attr.verilog_netlist_name:
        netlist_filename = ctx.attr.verilog_netlist_name
    verilog_netlist = ctx.actions.declare_file(netlist_filename)

    syn_opt_log_file = ctx.actions.declare_file("{}_synthesis_opt.log".format(ctx.label.name))
    yosys_stats = ctx.actions.declare_file("{}_yosys_stats.json".format(ctx.label.name))

    # Select the main optimization script
    extra_inputs = list(ctx.files._synth_opt_scripts)
    synth_opt_tcl = _synth_opt_main_script(ctx)
    if ctx.attr.strategy == "custom":
        extra_inputs.extend(ctx.files.custom_srcs)

    _synth_opt_logic(ctx, rtlil_netlist, ctx.attr.strategy, synth_opt_tcl, extra_inputs, verilog_netlist, syn_opt_log_file, yosys_stats, tool_extra_args)

    report_json = ctx.actions.declare_file("{}_synthesis_report.json".format(ctx.label.name))

    ctx.actions.run(
        executable = ctx.executable._postprocess_json,
        inputs = [yosys_stats],
        outputs = [report_json],
        arguments = [
            "--yosys_stats",
            yosys_stats.path,
            "--report_json",
            report_json.path,
        ],
        mnemonic = "PostProcessJSON",
    )

    benchmark_file = _benchmark_synth(ctx, syn_opt_log_file)

    return [
        DefaultInfo(
            runfiles = ctx.runfiles(files = [verilog_netlist]),
            files = depset([verilog_netlist]),
        ),
        OutputGroupInfo(
            logs = depset([translate_log_file, syn_opt_log_file]),
            reports = depset([report_json, benchmark_file]),
            auxiliary = depset([yosys_stats]),
            blackbox = depset([standard_cell_black_box]),
        ),
        SynthesisInfo(
            standard_cell_info = ctx.attr.standard_cells[StandardCellInfo],
            synthesized_netlist = verilog_netlist,
            top_module = ctx.attr.top_module,
            log_file = syn_opt_log_file,
        ),
        make_verilog_info(
            new_entries = [make_dag_entry(
                label = ctx.label,
                srcs = [verilog_netlist],
                hdrs = [],
                data = [],
                deps = [],
                tags = [],
                plis = [],
            )],
        ),
    ]

def _reformat_json_impl(ctx):
    """Convert Yosys-generated JSON report into expected report_json format"""

    report_json = ctx.actions.declare_file("{}_synthesis_report.json".format(ctx.label.name))

    ctx.actions.run(
        executable = ctx.executable._postprocess_json,
        inputs = [ctx.file.yosys_stats],
        outputs = [report_json],
        arguments = [
            "--yosys_stats",
            ctx.file.yosys_stats.path,
            "--report_json",
            report_json.path,
        ],
        mnemonic = "PostProcessJSON",
    )
    return [
        DefaultInfo(
            files = depset([report_json]),
        ),
    ]

def _benchmark_synth(ctx, synth_log_file):
    """Computes and prints various metrics from the synthesis log.

    Args:
      ctx: The current rule's context object.
      synth_log_file: Output log file from Yosys for parsing.
    Returns:
      Benchmark file with metrics.
    """
    benchmark_file = ctx.actions.declare_file(ctx.label.name + "_report.textproto")
    benchmark_path = benchmark_file.path

    cat = "zcat" if ("log.gz" in synth_log_file.path) else "cat"

    cmds = [
        "echo \"# proto-file: synthesis/power_performance_area.proto\" >> {out};".format(out = benchmark_path),
        "echo \"# proto-message: hdl.ppa.PowerPerformanceAreaProto\n\" >> {out};".format(out = benchmark_path),
    ]
    awk_cmds = [
        "area=$({cat} {log} | awk '/Chip area for/ {{ print $6; }}');",
        "cells=$({cat} {log} | tac | awk '/Number of cells/ {{ print $4; exit }} $NF == \"cells\" && $1 ~ /^[0-9]+$/ {{ print $1; exit }}');",
        "flops=$({cat} {log} | awk '/Flop count:/ {{ print $3 }}');",
        "ltp=$({cat} {log} | awk -F '[=)]' '/Longest topological path/ {{ print $2}}');",
    ]
    cmds.extend([cmd.format(cat = cat, log = synth_log_file.path) for cmd in awk_cmds])
    textproto = proto.encode_text(
        struct(
            area = struct(
                cell_area_um2 = "$area",
                num_total_cells = "$cells",
                num_sequential = "$flops",
            ),
            performance = struct(longest_topological_path = "$ltp"),
        ),
    )
    cmds.append("echo \"{textproto}\" >> {out}".format(textproto = textproto, out = benchmark_path))

    ctx.actions.run_shell(
        outputs = [benchmark_file],
        command = "".join(cmds),
        mnemonic = "BenchmarkingSynthesis",
        inputs = [synth_log_file],
    )
    return benchmark_file

translate = rule(
    implementation = _translate_impl,
    attrs = {
        "deps": attr.label_list(
            providers = [[VerilogInfo], [UhdmInfo]],
        ),
        "extra_libs": attr.label_list(
            providers = [StandardCellInfo],
            doc = "Extra Liberty file required",
            default = [],
        ),
        "frontend": attr.string(
            values = ["yosys", "surelog", "slang", "custom"],
            default = "yosys",
            doc = "Frontend tool used to parse the design. Possible values are: yosys, surelog, slang, custom (user provided script)",
        ),
        "output_file_name": attr.string(
            doc = "The output file name.",
        ),
        "parser_extra_commands": attr.string_list(
            default = [],
            doc = "Extra commands for the frontend parser",
        ),
        "standard_cells": attr.label(
            providers = [StandardCellInfo],
            default = "@com_google_skywater_pdk_sky130_fd_sc_hd//:sky130_fd_sc_hd",
        ),
        "tool_extra_args": attr.string_list(
            default = [],
            doc = "Extra command-line arguments for yosys",
        ),
        "top_module": attr.string(
            default = "top",
            doc = "Name of RTL top module",
        ),
        "translate_tcl": attr.label(
            default = None,
            allow_single_file = True,
            doc = "Tcl script replacing the generated one for translation",
        ),
        "verilog_defines": attr.string_list(
            doc = "Verilog defines to pass to the synthesis tool. Expect a list of strings like \"NAME[=VALUE]\"",
        ),
        "yosys_tool": attr.label(
            default = Label("@at_clifford_yosys//:yosys"),
            executable = True,
            cfg = "exec",
        ),
        "_synth_tcl_templates": attr.label_list(
            allow_files = True,
            default = [Label("//synthesis/translate:synth_tcl_scripts")],
            doc = "Default scripts used for templating",
        ),
    },
)

synth_opt = rule(
    implementation = _synth_opt_impl,
    attrs = {
        "abc_tool": attr.label(
            default = Label("@abc//:abc_bin"),
            executable = True,
            cfg = "exec",
        ),
        "custom_srcs": attr.label_list(
            allow_files = True,
            default = [],
            doc = "User-provided extra input files for optimization",
        ),
        "custom_synth_opt_tcl": attr.label(
            default = None,
            allow_single_file = True,
            doc = "User-provided custom optimization TCL script",
        ),
        "extra_libs": attr.label_list(
            providers = [StandardCellInfo],
            doc = "Extra Liberty file required",
            default = [],
        ),
        "rtlil_netlist": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "RTLIL netlist",
        ),
        "standard_cells": attr.label(
            providers = [StandardCellInfo],
            default = "@com_google_skywater_pdk_sky130_fd_sc_hd//:sky130_fd_sc_hd",
        ),
        "strategy": attr.string(
            values = ["basic", "lms", "lite", "speed", "area", "custom"],
            default = "basic",
            doc = "Optimization strategy. basic by default, set to custom if you provide your own TCL script",
        ),
        "target_clock_period_pico_seconds": attr.int(
            default = 100000,
            doc = "target clock period in picoseconds",
        ),
        "tool_extra_args": attr.string_list(
            default = [],
            doc = "Extra command-line arguments for yosys",
        ),
        "top_module": attr.string(
            default = "top",
            doc = "Name of the RTL top module",
        ),
        "verilog_netlist_name": attr.string(
            doc = "The verilog netlist file name.",
        ),
        "yosys_tool": attr.label(
            default = Label("@at_clifford_yosys//:yosys"),
            executable = True,
            cfg = "exec",
        ),
        "_synth_opt_scripts": attr.label_list(
            allow_files = True,
            default = [Label("//synthesis/synth_opt:synth_opt_scripts")],
            doc = "Default scripts used for optimization",
        ),
        "_synth_tcl_templates": attr.label_list(
            allow_files = True,
            default = [Label("//synthesis/translate:synth_tcl_templates")],
            doc = "Default scripts used for templating",
        ),
    },
)

synthesize_rtl = rule(
    implementation = _synthesize_design_impl,
    attrs = {
        "abc_tool": attr.label(
            default = Label("@abc//:abc_bin"),
            executable = True,
            cfg = "exec",
        ),
        "custom_srcs": attr.label_list(
            allow_files = True,
            default = [],
            doc = "User-provided extra input files for optimization",
        ),
        "custom_synth_opt_tcl": attr.label(
            default = None,
            allow_single_file = True,
            doc = "User-provided custom optimization TCL script",
        ),
        "deps": attr.label_list(
            providers = [[VerilogInfo], [UhdmInfo]],
        ),
        "extra_libs": attr.label_list(
            providers = [StandardCellInfo],
            doc = "Extra Liberty file required",
            default = [],
        ),
        "frontend": attr.string(
            values = ["yosys", "surelog", "slang", "custom"],
            default = "yosys",
            doc = "Frontend tool used to parse the design. Possible values are: yosys, surelog, slang, custom (user-provided script)",
        ),
        "parser_extra_commands": attr.string_list(
            default = [],
            doc = "Extra commands for the frontend parser",
        ),
        "standard_cells": attr.label(
            providers = [StandardCellInfo],
            default = "@com_google_skywater_pdk_sky130_fd_sc_hd//:sky130_fd_sc_hd",
        ),
        "strategy": attr.string(
            values = ["basic", "lms", "lite", "speed", "area", "custom"],
            default = "basic",
            doc = "Optimization strategy. basic by default, set to custom if you provide your own TCL script",
        ),
        "target_clock_period_pico_seconds": attr.int(
            default = 100000,
            doc = "target clock period in picoseconds",
        ),
        "tool_extra_args": attr.string_list(
            default = [],
            doc = "Extra command-line arguments for yosys",
        ),
        "top_module": attr.string(
            default = "top",
            doc = "Name of RTL top module",
        ),
        "translate_tcl": attr.label(
            default = None,
            allow_single_file = True,
            doc = "Tcl script replacing the generated one for translation",
        ),
        "verilog_defines": attr.string_list(
            doc = "Verilog defines to pass to the synthesis tool. Expect a list of strings like \"NAME[=VALUE]\"",
        ),
        "verilog_netlist_name": attr.string(
            doc = "Name of the generated verilog netlist.",
        ),
        "yosys_tool": attr.label(
            default = Label("@at_clifford_yosys//:yosys"),
            executable = True,
            cfg = "exec",
        ),
        "_postprocess_json": attr.label(
            default = Label("//synthesis:postprocess_json"),
            executable = True,
            cfg = "exec",
        ),
        "_synth_opt_scripts": attr.label_list(
            allow_files = True,
            default = [Label("//synthesis/synth_opt:synth_opt_scripts")],
            doc = "Default scripts used for optimization",
        ),
        "_synth_tcl_templates": attr.label_list(
            allow_files = True,
            default = [Label("//synthesis/translate:synth_tcl_templates")],
            doc = "Default scripts used for templating",
        ),
    },
)

reformat_json = rule(
    implementation = _reformat_json_impl,
    attrs = {
        "yosys_stats": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "JSON generated by Yosys",
        ),
        "_postprocess_json": attr.label(
            default = Label("//synthesis:postprocess_json"),
            executable = True,
            cfg = "exec",
        ),
    },
)

def _benchmark_synth_impl(ctx):
    """Implementation of the 'benchmark_synth' rule.

    Computes and prints various metrics about a synth target.

    Args:
      ctx: The current rule's context object.
    Returns:
      DefaultInfo provider
    """
    synth_info = ctx.attr.synth_target[SynthesisInfo]

    synth_log = synth_info.log_file.short_path
    grep = "zgrep" if ("log.gz" in synth_log) else "grep"
    cmd1 = "{grep} Chip.area {log}".format(grep = grep, log = synth_log)
    cmd2 = "{grep} Longest.topological.path {log}".format(grep = grep, log = synth_log)
    cmd3 = "{grep} Flop.count {log}".format(grep = grep, log = synth_log)
    cmd4 = "{grep} ^Liberty: {log}".format(grep = grep, log = synth_log)
    cmd5 = "{grep} 'End of script.*CPU:.user' {log}".format(grep = grep, log = synth_log)

    executable_file = ctx.actions.declare_file(ctx.label.name + ".sh")

    runfiles = ctx.runfiles(files = [
        synth_info.log_file,
    ])

    ctx.actions.write(
        output = executable_file,
        content = "\n".join([
            "#!/usr/bin/env bash",
            "set -e",
            cmd1,
            cmd2,
            cmd3,
            cmd4,
            cmd5,
            "exit 0",
        ]),
        is_executable = True,
    )

    return [
        DefaultInfo(
            runfiles = runfiles,
            files = depset(
                direct = [executable_file],
                transitive = [],
            ),
            executable = executable_file,
        ),
    ]

benchmark_synth_attrs = {
    "synth_target": attr.label(
        doc = "The synth target to benchmark.",
        providers = [SynthesisInfo, DefaultInfo],
    ),
}

benchmark_synth = rule(
    doc = """Computes and prints various metrics about a synth target.

Example:
    ```
    benchmark_synth(
        name = "picorv32_benchmark_synth",
        synth_target = ":picorv32_synth",
    )
    ```
    """,
    implementation = _benchmark_synth_impl,
    attrs = benchmark_synth_attrs,
    executable = True,
)

SdcInfo = provider(
    doc = "sdc",
    fields = {
        "sdc": "Path to the SDC file",
    },
)

def _sdc_library_impl(ctx):
    return [
        DefaultInfo(
            files = depset(transitive = [t.files for t in ctx.attr.srcs]),
        ),
        SdcInfo(
            sdc = ctx.attr.srcs[0],
        ),
    ]

sdc_library = rule(
    doc = "Define an SDC library.",
    implementation = _sdc_library_impl,
    attrs = {
        "srcs": attr.label_list(
            doc = "SDC sources.",
            allow_files = [".sdc"],
        ),
    },
)
