#!/bin/sh
. ./testsetup.sh || exit $?
cd ../../tests || exit 1
echo "Running MMU tests in Vivado xsim!"
envsubst < tests.f > .tests.f && runSVUnit -f .tests.f -s xsim -e '-debug typical' -r '--tclbatch ../scripts/tests/vivado_waveconfig_debug.tcl -g' $@
exit $?