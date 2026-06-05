#!/bin/sh
set -e

apt-get update && apt-get install --yes autoconf automake autotools-dev curl git libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool bc zlib1g-dev device-tree-compiler python3 python3-pip help2man libboost-all-dev libwolfssl-dev
pip install -r verif/sim/dv/requirements.txt
export RISCV=$(pwd)/tools
