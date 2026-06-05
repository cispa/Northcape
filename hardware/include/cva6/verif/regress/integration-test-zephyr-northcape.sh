#!/bin/bash
export ENABLE_NORTHCAPE=y
export TARGET_CFG=cv64a6_imafdc_sv39_northcape

set -e

echo Launching Sim TPM

make -C corev_apu/northcape/tests/dpi/ swtpm

./verif/regress/integration-test-zephyr.sh $@

unset ENABLE_NORTHCAPE
unset TARGET_CFG

echo Killing TPM
