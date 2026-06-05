set ha1588 [get_cells -hierarchical ha1588_axi_0]

puts "Constraining $ha1588"

# ASYNC_REG properties
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_00_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/rtc_rst_s1_reg]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/time_ld_s1_reg]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/perd_ld_s1_reg]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/adjt_ld_s1_reg]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/time_rd_s1_reg]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/queue/dcfifo/U0/inst_fifo_gen/gconvfifo.rf/grf.rf/gntv_or_sync_fifo.mem/gbm.gbmg.gbmga.ngecc.bmg/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop*.ram.r/prim_noinit.ram/DEVICE_7SERIES.NO_BMM_INFO.SDP.WIDE_PRIM36_NO_ECC.ram]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/rx_q_data_int_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/time_reg_sec_int_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/data_out_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/time_reg_ns_int_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_1c_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rtc/time_acc_30n_08f_pre_neg_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rtc/time_acc_30n_08f_pre_pos_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_18_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rtc/adj_ld_done_reg]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/data_out_reg_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_14_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rtc/time_acc_48s_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_44_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/tsuParser.parser/ptp_event_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rtc/time_acc_30n_08f_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_10_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_*_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rtc/period_fix_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rtc/adj_cnt_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rtc/time_adj_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_40_reg[2]]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_60_reg[2]]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/generateFFsTimestampEverything.timestamp_everything_in_d1_reg]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/syncGigaMode.rx_giga_mode_latch_reg]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/syncGigaMode.rx_giga_mode_d1_reg]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/syncGigaMode.tx_giga_mode_latch_reg]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/syncGigaMode.tx_giga_mode_d1_reg]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/tsuParser.int_gmii_ctrl_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/ts_req_d1_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/tsuParser.gmii_ctrl_conv_d1_reg]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/rtc_time_stamp_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/tsu_time_stamp_reg*]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/ts_ack_reg]
set_property ASYNC_REG true [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/ts_ack_d1_reg]

# RTC, TSU -> REG
set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_00_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rgs/rtc_rst_s1_reg] 8.000
set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_00_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rgs/time_ld_s1_reg] 8.000
set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_00_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rgs/perd_ld_s1_reg] 8.000
set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_00_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rgs/adjt_ld_s1_reg] 8.000
set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_00_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rgs/time_rd_s1_reg] 8.000

set ram_cells [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/queue/dcfifo/U0/inst_fifo_gen/gconvfifo.rf/grf.rf/gntv_or_sync_fifo.mem/gbm.gbmg.gbmga.ngecc.bmg/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop*.ram.r/prim_noinit.ram/DEVICE_7SERIES.NO_BMM_INFO.SDP.WIDE_PRIM36_NO_ECC.ram]
set_bus_skew -from $ram_cells -to [get_cells $ha1588/inst/ha1588_inst/u_rgs/rx_q_data_int_reg*] 8.000
set_max_delay -datapath_only -from $ram_cells -to [get_cells $ha1588/inst/ha1588_inst/u_rgs/rx_q_data_int_reg*] 8.000

set_bus_skew -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/time_reg_sec_int_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rgs/data_out_reg*] 8.000
set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/time_reg_sec_int_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rgs/data_out_reg*] 8.000

set_bus_skew -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/time_reg_ns_int_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rgs/data_out_reg*] 8.000
set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/time_reg_ns_int_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rgs/data_out_reg*] 8.000

set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_1c_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rtc/time_acc_30n_08f_pre_neg_reg*] 8.000
set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_1c_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rtc/time_acc_30n_08f_pre_pos_reg*] 8.000

set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_18_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rtc/time_acc_30n_08f_pre_neg_reg*] 8.000
set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_18_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rtc/time_acc_30n_08f_pre_pos_reg*] 8.000

set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rtc/adj_ld_done_reg] -to [get_cells $ha1588/inst/ha1588_inst/u_rgs/data_out_reg_reg*] 8.000

set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_14_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rtc/time_acc_48s_reg*] 8.000

set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_44_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/tsuParser.parser/ptp_event_reg*] 8.000


set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_18_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rtc/time_acc_30n_08f_reg*] 8.000
set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_1c_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rtc/time_acc_30n_08f_reg*] 8.000

set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_10_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rtc/time_acc_48s_reg*] 8.000

# REG -> TSU
set rtc_regs [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_*_reg*]
set_bus_skew -from $rtc_regs -to [get_cells $ha1588/inst/ha1588_inst/u_rtc/period_fix_reg*] 8.000
set_max_delay -datapath_only -from $rtc_regs -to [get_cells $ha1588/inst/ha1588_inst/u_rtc/period_fix_reg*] 8.000

set_bus_skew -from $rtc_regs -to [get_cells $ha1588/inst/ha1588_inst/u_rtc/adj_cnt_reg*] 8.000
set_max_delay -datapath_only -from $rtc_regs -to [get_cells $ha1588/inst/ha1588_inst/u_rtc/adj_cnt_reg*] 8.000

set_bus_skew -from $rtc_regs -to [get_cells $ha1588/inst/ha1588_inst/u_rtc/time_adj_reg*] 8.000
set_max_delay -datapath_only -from $rtc_regs -to [get_cells $ha1588/inst/ha1588_inst/u_rtc/time_adj_reg*] 8.000

set_bus_skew -from $rtc_regs -to [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/tsuParser.parser/ptp_event_reg*] 8.000
set_max_delay -datapath_only -from $rtc_regs -to [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/tsuParser.parser/ptp_event_reg*] 8.000

set_bus_skew -from $rtc_regs -to [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/tsuParser.parser/ptp_event_reg*] 8.000
set_max_delay -datapath_only -from $rtc_regs -to [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/tsuParser.parser/ptp_event_reg*] 8.000

set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_40_reg[2]] -to [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/generateFFsTimestampEverything.timestamp_everything_in_d1_reg] 8.000
set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rgs/reg_60_reg[2]] -to [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/generateFFsTimestampEverything.timestamp_everything_in_d1_reg] 8.000

set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/syncGigaMode.rx_giga_mode_latch_reg] -to [get_cells $ha1588/inst/ha1588_inst/syncGigaMode.rx_giga_mode_d1_reg] 8.000
set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/syncGigaMode.tx_giga_mode_latch_reg] -to [get_cells $ha1588/inst/ha1588_inst/syncGigaMode.tx_giga_mode_d1_reg] 8.000

set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/tsuParser.int_gmii_ctrl_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/ts_req_d1_reg*] 8.000

set_max_delay -datapath_only -from [get_cells $ha1588/inst/syncGigaMode.rx_giga_mode_latch_reg*] -to [get_cells $ha1588/inst/syncGigaMode.rx_giga_mode_d1_reg*] 8.000

# TSU trigger -> RTC
# parser might not be enabled...
catch {
    set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/tsuParser.gmii_ctrl_conv_d1_reg] -to [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/ts_req_d1_reg] 8.000
    set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/tsuParser.gmii_ctrl_conv_d1_reg] -to [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/ts_req_d1_reg] 8.000
}

set_bus_skew -from [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/rtc_time_stamp_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/tsu_time_stamp_reg*] 8.000
set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/rtc_time_stamp_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/tsu_time_stamp_reg*] 8.000

set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/ts_ack_reg] -to [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/ts_ack_d1_reg] 8.000

set_bus_skew -from [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/rtc_time_stamp_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/tsu_time_stamp_reg*] 8.000
set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/rtc_time_stamp_reg*] -to [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/tsu_time_stamp_reg*] 8.000

set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/ts_ack_reg] -to [get_cells $ha1588/inst/ha1588_inst/u_rx_tsu/ts_ack_d1_reg] 8.000

set_max_delay -datapath_only -from [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/tsuParser.gmii_ctrl_conv_d1_reg] -to [get_cells $ha1588/inst/ha1588_inst/u_tx_tsu/ts_req_d1_reg] 8.000
