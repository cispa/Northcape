#!/bin/sh
. ./testsetup_questa.sh || exit $?
cd ../../tests/unit || exit 1
envsubst < tests_vlog.f > .tests_vlog.f || exit 1
sed -i 's/--include /+incdir+/g' .tests_vlog.f || exit 1
echo "Running tests in questa!"

set -e

vlib work
vlog northcape_mmu_unit_test.sv -F .tests_vlog.f 
vsim northcape_mmu_top

exit $?
