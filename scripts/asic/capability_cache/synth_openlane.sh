#!/bin/bash
set -e

yosys -m slang -m ghdl synth_cache.ys
python3 gen_config_json.py
nix-shell --run "openlane config.json" ${OPENLANE_ROOT}
