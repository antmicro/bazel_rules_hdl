# Copyright 2023 Google LLC
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

"""These build rules run automated GDS write on an implemented design"""

load("//place_and_route:open_road.bzl", "OpenRoadInfo")
load("//synthesis:build_defs.bzl", "SynthesisInfo")

def _gds_write_impl(ctx):
    final_gds = ctx.actions.declare_file("{}.gds".format(ctx.attr.name))
    klayout_final_lyt = ctx.actions.declare_file("{}_klayout.lyt".format(ctx.attr.name))
    klayout_final_lef = ctx.actions.declare_file("{}_klayout.lef".format(ctx.attr.name))
    # Declare a list of additional LEF files to be copied into bazel build directory
    final_lefs = []
    for lef in ctx.files.additional_lef:
        final_lefs.append(ctx.actions.declare_file("{}_{}.lef".format(ctx.attr.name, lef.basename.split('.', 1)[0])))

    # Copy additional LEF files to bazel build directory
    gen_lef_files_cmd = ""
    for i in range(len(ctx.files.additional_lef)):
        gen_lef_files_cmd += "cp {} {}; ".format(ctx.files.additional_lef[i].path, final_lefs[i].path)

    ctx.actions.run_shell(
        outputs = final_lefs,
        inputs = ctx.files.additional_lef,
        command = gen_lef_files_cmd,
        mnemonic = "CopyAdditionalLefFiles"
    )

    # Copy KLayout LEF file to bazel build directory
    ctx.actions.run_shell(
        outputs = [klayout_final_lef],
        inputs = [ctx.file.klayout_lef],
        command = "cp {} {}; ".format(ctx.file.klayout_lef.path, klayout_final_lef.path),
        mnemonic = "CopyKLayoutLefFile"
    )

    # Fix path to KLayout LEF file in KLayout technology file
    additional_lef_paths = "{}".format(final_lefs[i].basename)
    ctx.actions.run_shell(
        outputs = [
            klayout_final_lyt
        ],
        inputs = depset(
            [ctx.file.klayout_lyt, klayout_final_lef] +
            final_lefs
        ),
        # Replace existing entry with reference to correct KLayout LEF file
        # Save the results in klayout_final.lyt in bazel build directory
        command =
            "sed " +
            "\"s/<lef-files>.*<\\/lef-files>/<lef-files>{}<\\/lef-files>/g\" ".format(klayout_final_lef.basename) +
            "{} ".format(ctx.file.klayout_lyt.path) +
            "> {}".format(klayout_final_lyt.path),
        mnemonic = "FixPathInKlayoutTechFile"
    )

    # PYTHONPATH environment variable with python script imports
    pythonpath = ""
    for imp in ctx.attr._gds_write[PyInfo].imports.to_list():
        pythonpath += ":{}".format(imp)

    # Write GDS generation shell script
    additional_gds_paths = " ".join([file.path for file in ctx.files.additional_gds])
    write_gds_script = ctx.actions.declare_file("write_gds.sh")
    write_gds_cmd = "PYTHONPATH=$PYTHONPATH:{} python {}".format(pythonpath, ctx.executable._gds_write.path) + \
			" --design-name {}".format(ctx.attr.implemented_rtl[SynthesisInfo].top_module) + \
			" --input-def {}".format(ctx.attr.implemented_rtl[OpenRoadInfo].routed_def.path) + \
			" --tech-file {}".format(klayout_final_lyt.path) + \
			" --out {}".format(final_gds.path) + \
			" --additional-gds {}".format(additional_gds_paths) + \
			" --fill-config {}".format(ctx.file.fill_config.path)

    ctx.actions.write(
        output = write_gds_script,
        content = write_gds_cmd,
        is_executable = True,
    )

    # Generate GDS file
    ctx.actions.run(
        outputs = [
            final_gds
        ],
        inputs = depset(
            ctx.files.additional_lef +
            ctx.files.additional_gds +
            [
                ctx.attr.implemented_rtl[OpenRoadInfo].routed_def,
                klayout_final_lyt,
                ctx.file.fill_config
            ]
        ),
        executable = write_gds_script,
        tools = depset([ctx.executable._gds_write]),
    )

    return [DefaultInfo(files = depset([final_gds]))]

gds_write = rule(
    implementation = _gds_write_impl,
    attrs = {
        "implemented_rtl": attr.label(mandatory = True, providers = [OpenRoadInfo, SynthesisInfo]),
        "klayout_lyt": attr.label(mandatory = True, allow_single_file = True),
        "klayout_lef": attr.label(mandatory = True, allow_single_file = True),
        "additional_lef": attr.label_list(allow_files = True),
        "additional_gds": attr.label_list(allow_files = True),
        "fill_config": attr.label(allow_single_file = True),
        "_gds_write": attr.label(
            cfg = "exec",
            executable = True,
            allow_files = True,
            default = Label("//gds_write:def2stream"),
        ),
    }
)

