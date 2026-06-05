#!/bin/sh
# all jtag targets
XILINX_OUTPUT=$(/opt/Xilinx/Vitis/2024.2/bin/xsct -interactive find_arty.tcl)
JTAG_SERIAL=$(echo $XILINX_OUTPUT | python3 -c "import re; print(re.search(r'Digilent\W*Arty\W*A7-100T\W*([0-9A-F]+)', input()).group(1))")
echo "Assuming JTAG SERIAL $JTAG_SERIAL"
killall hw_server
/opt/Xilinx/Vivado/2024.2/bin/hw_server -e "set jtag-port-filter $JTAG_SERIAL"
