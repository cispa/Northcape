#!/bin/bash
set -e

mkdir $RISCV || true
cd util/gcc-toolchain-builder && bash get-toolchain.sh && bash build-toolchain.sh ../../tools/
cd ../..
bash ./verif/regress/install-verilator.sh
source ./verif/sim/setup-env.sh
cd tools
ln -s $(pwd)/verilator-v5.026/ verilator || true # might exist from cache etc.
cd ..
bash ./verif/regress/install-spike.sh
source ./verif/sim/setup-env.sh
bash ./verif/regress/install-riscv-compliance.sh
source ./verif/sim/setup-env.sh
bash ./verif/regress/install-riscv-tests.sh
source ./verif/sim/setup-env.sh
bash ./verif/regress/install-riscv-arch-test.sh
source ./verif/sim/setup-env.sh
