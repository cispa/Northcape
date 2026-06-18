#!/bin/bash
export ENABLE_NORTHCAPE=y
export TARGET_CFG=cv64a6_imafdc_sv39_northcape

set -e

echo Launching Sim TPM

[ -f corev_apu/northcape ] || ln -s $(pwd)/../northcape corev_apu/northcape || true


./verif/regress/integration-test-zephyr.sh $@

unset ENABLE_NORTHCAPE
unset TARGET_CFG

echo Killing TPM
