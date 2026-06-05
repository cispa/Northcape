#!/bin/sh
set -e

echo "Updating Device tree and zero-stage boot loader before generating device tree"

cd ../Vitis
unset IS_GENESYS
./create_device_tree.sh

echo "Running synthesis/implementation/bitstream generation in Vivado"
cd ../Vivado
/opt/Xilinx/Vivado/2024.2/bin/vivado -mode batch -source create_bitstream_arty.tcl || exit 1
