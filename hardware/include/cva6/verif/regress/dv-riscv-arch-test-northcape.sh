#!/bin/bash

# default target and simulator are fine
unset DV_TARGET
unset DV_SIMULATORS

export ENABLE_NORTHCAPE=y
export TARGET_CFG=cv64a6_imafdc_sv39_northcape

SCRIPT_DIR=$(dirname "$0")
source "$SCRIPT_DIR/dv-riscv-arch-test.sh"

unset ENABLE_NORTHCAPE
unset TARGET_CFG