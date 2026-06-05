set script_file [info script]
set ha1588_dir [file dirname [file normalize "$script_file/../../"]]

create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.2 -module_name dcfifo_128b_16
set_property -dict [list \
  CONFIG.Fifo_Implementation {Independent_Clocks_Block_RAM} \
  CONFIG.INTERFACE_TYPE {Native} \
  CONFIG.Input_Data_Width {128} \
  CONFIG.Input_Depth {16} \
  CONFIG.Read_Data_Count {true} \
  CONFIG.Valid_Flag {false} \
  CONFIG.Write_Acknowledge_Flag {false} \
  CONFIG.Write_Data_Count {true} \
  CONFIG.Full_Flags_Reset_Value {0} \
  CONFIG.Use_Embedded_Registers {true} \
] [get_ips dcfifo_128b_16]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_ha1588_reg_dbg
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {9} \
  CONFIG.C_PROBE4_WIDTH {38} \
  CONFIG.C_PROBE5_WIDTH {48} \
  CONFIG.C_PROBE6_WIDTH {38} \
  CONFIG.C_PROBE7_WIDTH {48} \
] [get_ips ila_ha1588_reg_dbg]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_ha1588_reg2_dbg
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {12} \
  CONFIG.C_PROBE2_WIDTH {8} \
  CONFIG.C_PROBE3_WIDTH {8} \
  CONFIG.C_PROBE4_WIDTH {32} \
  CONFIG.C_PROBE5_WIDTH {32} \
  CONFIG.C_PROBE6_WIDTH {8} \
  CONFIG.C_PROBE10_WIDTH {48} \
] [get_ips ila_ha1588_reg2_dbg]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ha1588_tsu_ila
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {10} \
  CONFIG.C_PROBE5_WIDTH {4} \
  CONFIG.C_PROBE7_WIDTH {8} \
] [get_ips ha1588_tsu_ila]

add_files -norecurse $ha1588_dir/par/xilinx/ip/define.h
set_property is_global_include true [get_files  $ha1588_dir/par/xilinx/ip/define.h]
add_files -norecurse  $ha1588_dir/par/xilinx/ip/ha1588_resetsync.v
add_files -norecurse $ha1588_dir/rtl/top/ha1588.v
add_files -norecurse $ha1588_dir/rtl/reg/reg.v
add_files -norecurse $ha1588_dir/rtl/rtc/rtc.v
add_files -norecurse $ha1588_dir/rtl/tsu/tsu.v
add_files -norecurse $ha1588_dir/rtl/tsu/ptp_parser.v
add_files -norecurse $ha1588_dir/rtl/tsu/ptp_queue.v
add_files -norecurse $ha1588_dir/rtl/bus/xps/pcores/ha1588_axi_v1_00_a/hdl/verilog/ha1588_axi.v
add_files -fileset constrs_1 -norecurse $ha1588_dir/par/xilinx/ha1588.xdc

