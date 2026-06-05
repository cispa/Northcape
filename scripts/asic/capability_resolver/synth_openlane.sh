#!/bin/sh
set -e

yosys -m slang -m ghdl synth_resolver.ys
nix-shell --run "openlane config.json" ${OPENLANE_ROOT}
