#!/bin/sh
set -e
set -x

cd ..
cd $1
pwd
# TODO errors out due to setup/hold violations sometimes
./synth_openlane.sh || echo Error code $?
