# 2FF synchronizer
set_max_delay -datapath_only -from [get_cells SoC_i/interrupt_sync_0/inst/irq_q_reg] -to [get_cells SoC_i/interrupt_sync_0/inst/irq_q1_reg] 4.000
set_max_delay -datapath_only -from [get_cells SoC_i/init_complete_sync/inst/irq_q_reg] -to [get_cells SoC_i/init_complete_sync/inst/irq_q1_reg] 4.000

# debug module - 50 MHz vs. slower JTAG clock
set_max_delay -from [get_cells SoC_i/cpu_debug/inst/i_debug_module_wrapper/i_dmi_jtag/i_dmi_cdc/i_cdc_resp/i_src/data_src_q_reg*] -to [get_cells SoC_i/cpu_debug/inst/i_debug_module_wrapper/i_dmi_jtag/i_dmi_cdc/i_cdc_resp/i_dst/data_dst_q_reg*] 20.000
set_bus_skew -from [get_cells SoC_i/cpu_debug/inst/i_debug_module_wrapper/i_dmi_jtag/i_dmi_cdc/i_cdc_resp/i_src/data_src_q_reg*] -to [get_cells SoC_i/cpu_debug/inst/i_debug_module_wrapper/i_dmi_jtag/i_dmi_cdc/i_cdc_resp/i_dst/data_dst_q_reg*] 20.000

set_max_delay -from [get_cells SoC_i/cpu_debug/inst/i_debug_module_wrapper/i_dmi_jtag/i_dmi_cdc/i_cdc_req/i_src/data_src_q_reg*] -to [get_cells SoC_i/cpu_debug/inst/i_debug_module_wrapper/i_dmi_jtag/i_dmi_cdc/i_cdc_req/i_dst/data_dst_q_reg*] 20.000
set_bus_skew -from [get_cells SoC_i/cpu_debug/inst/i_debug_module_wrapper/i_dmi_jtag/i_dmi_cdc/i_cdc_req/i_src/data_src_q_reg*] -to [get_cells SoC_i/cpu_debug/inst/i_debug_module_wrapper/i_dmi_jtag/i_dmi_cdc/i_cdc_req/i_dst/data_dst_q_reg*] 20.000

set_max_delay -from [get_cells SoC_i/cpu_debug/inst/i_debug_module_wrapper/i_dmi_jtag/i_dmi_cdc/i_cdc_resp/i_src/req_src_q_reg] -to [get_cells SoC_i/cpu_debug/inst/i_debug_module_wrapper/i_dmi_jtag/i_dmi_cdc/i_cdc_resp/i_dst/req_dst_q_reg] 20.000
set_max_delay -from [get_cells SoC_i/cpu_debug/inst/i_debug_module_wrapper/i_dmi_jtag/i_dmi_cdc/i_cdc_req/i_dst/ack_dst_q_reg] -to [get_cells SoC_i/cpu_debug/inst/i_debug_module_wrapper/i_dmi_jtag/i_dmi_cdc/i_cdc_req/i_src/ack_src_q_reg] 20.000

set_property INTERNAL_VREF 0.75 [get_iobanks 33]
set_property INTERNAL_VREF 0.75 [get_iobanks 34]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]
