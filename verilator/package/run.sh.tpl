#!/usr/bin/env bash

set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

verilator {VERILATOR_ARGS}
{SIMULATION_BINARY} "$@"
