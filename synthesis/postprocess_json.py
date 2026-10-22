"""Post-processing Yosys synthesis JSON to the standardized format used in PnR"""
import json
import sys
import argparse


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--yosys_stats", type=str, help="Yosys generated JSON statistics file.", required=True)
    parser.add_argument("--report_json", type=str, help="Output JSON file path", required=True)
    args = parser.parse_args()

    with open(args.yosys_stats, 'r') as filehandler:
        data = json.load(filehandler)

    result = {
            "synthesis": {
                "modules": data["modules"],
                "design": data["design"],
                "metadata": {
                    "creator": data["creator"],
                    "invocation": data["invocation"]
                    }
                }
            }
    with open(args.report_json, 'w') as filehandler:
        json.dump(result, filehandler, indent=4)
