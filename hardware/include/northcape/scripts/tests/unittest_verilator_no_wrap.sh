#!/bin/sh
. ./testsetup.sh || exit $?
cd ../../tests/unit || exit 1
envsubst < tests.f > .tests.f || exit 1
sed -i 's/--include /+incdir+/g' .tests.f || exit 1
echo "Running tests in verilator!"
runSVUnit -f .tests.f -s verilator -d NORTHCAPE_MMU_NO_AXI_WRAP $@
exit $?
