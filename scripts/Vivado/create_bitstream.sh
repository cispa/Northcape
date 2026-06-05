#!/bin/sh
set -e

echo "Updating Device tree and zero-stage boot loader before generating device tree"

export IS_GENESYS=1
cd ../Vitis
./create_device_tree.sh

echo "Running synthesis/implementation/bitstream generation in Vivado"
cd ../Vivado
/opt/Xilinx/Vivado/2024.2/bin/vivado -mode batch -source create_bitstream.tcl || exit 1
