#!/bin/sh
set -e

NORTHCAPE_MMU=y yosys -m slang -m ghdl synth_mmu.ys
nix-shell --run "openlane config.json" ${OPENLANE_ROOT}
