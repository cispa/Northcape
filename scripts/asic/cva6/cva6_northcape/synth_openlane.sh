#!/bin/sh
set -e

cat cva6.flist ../cva6.flist > .cva6.flist
yosys -m slang -m ghdl synth_cva6.ys
python3 ./gen_config_json.py
nix-shell --run "openlane config.json" ${OPENLANE_ROOT}
