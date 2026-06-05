#!/bin/bash

set -e
set -x

SCRIPT_DIR="$( dirname -- "${BASH_SOURCE[0]}"; )";   # Get the directory name
SCRIPT_DIR="$( realpath -e -- "$SCRIPT_DIR"; )";    # Resolve its full path if need be

echo Installing tzdata
apt update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tzdata

echo Installing required packages
apt-get install -y build-essential clang lld bison flex \
	libreadline-dev gawk tcl-dev libffi-dev git \
	graphviz xdot pkg-config python3 libboost-system-dev \
	libboost-python-dev libboost-filesystem-dev zlib1g-dev ninja-build libgsl-dev gnat magic \
  cmake libx11-dev tcsh tk tk8.6-dev libxt-dev csh wget tcl tcl8.6-dev libcairo-5c-dev libncurses-dev \
  libjpeg-dev libgomp1 libxext-dev libsm-dev libxft-dev libffi-dev cairo-5c gettext xvfb python3 python3-pip \
  python3-dev curl parallel


cd /tmp
echo Installing yosys
git clone --recurse-submodules https://github.com/YosysHQ/yosys.git --depth 1 --branch v0.64

cd yosys
make -j $(nproc)
make install
cd ..

echo Installing yosys-slang plugin for SystemVerilog
git clone --recursive https://github.com/povik/yosys-slang
cp $SCRIPT_DIR/../patches/yosys-slang.patch yosys-slang
cd yosys-slang
git checkout fc6a1efeb785df3c7f1731b081fcf2767cfe7cb9
git submodule update --recursive
# git apply yosys-slang.patch
make -j $(nproc)
make install
cd ..

echo Instlling ghdl
git clone https://github.com/ghdl/ghdl
cd ghdl
./configure
make
make install
cd ..


echo Installing ghdl-yosys plugin for VHDL

git clone https://github.com/ghdl/ghdl-yosys-plugin.git
cd ghdl-yosys-plugin
make
make install
cd ..

echo "Installing nix package manager"
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm --extra-conf "
    extra-substituters = https://openlane.cachix.org
    extra-trusted-public-keys = openlane.cachix.org-1:qqdwh+QMNGmZAuyeQJTH9ErW57OWSvdtuwfBKdS254E=
"
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

echo "Installing openlane2"
git clone https://github.com/efabless/openlane2 --depth 1 -b 2.3.10
cp $SCRIPT_DIR/../patches/openlane2.patch openlane2
cd openlane2
echo "Applying patch"
git apply openlane2.patch
echo "Smoke-testing openlane"
nix-shell --run "openlane --smoke-test"
cd ..

echo "Installing ciel"
pip3 install ciel
echo "Installing sky130A"
ciel enable --pdk-family=sky130 6971617b18b2f322d8f574af7e53f79ddd75dafe

echo "Installing volare pdk builder"
pip3 install volare

echo "Installing OpenRAM"
cd $SCRIPT_DIR
cd ../macros
./generate_openram.sh
