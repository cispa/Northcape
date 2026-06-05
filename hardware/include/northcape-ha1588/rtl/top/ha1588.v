/*
 * ha1588.v
 * 
 * Copyright (c) 2012, BABY&HW. All rights reserved.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301  USA
 */

`timescale 1ns/1ns

// TODO: add define to generate rtc only or tsu only.

module ha1588 (
  input         rst,clk,
  input         wr_in,rd_in,
  input  [ 7:0] addr_in_read,
  input  [ 7:0] addr_in_write,
  input  [31:0] data_in,
  output [31:0] data_out,

  input         rtc_clk,
  output [31:0] rtc_time_ptp_ns,
  output [47:0] rtc_time_ptp_sec,
  output        rtc_time_one_pps,

  input       rx_gmii_clk,
  input       rx_gmii_ctrl,
  input [7:0] rx_gmii_data,
  input       rx_giga_mode,

  input       tx_gmii_clk,
  input       tx_gmii_ctrl,
  input [7:0] tx_gmii_data,
  input       tx_giga_mode,

  // timestamping triggers for when C_BYPASS_TSU is active
  input       rx_tsu_bypass_evt,
  input       tx_tsu_bypass_evt,
  
  output      rx_intr_out,
  output      tx_intr_out
);

parameter addr_is_in_word = 0;
parameter C_BYPASS_TSU = 0;
parameter C_ENABLE_TIMESTAMP_EVERYTHING = 0;
parameter C_ENABLE_REG_ILAS = 1'b0;
parameter C_ENABLE_TSU_ILAS = 1'b0;

wire [ 5: 0] word_addr_in_read, word_addr_in_write;
wire [ 7: 0] byte_addr_in_read, byte_addr_in_write;
generate
  if (addr_is_in_word)
  begin
    assign word_addr_in_read = addr_in_read[ 5: 0];
    assign word_addr_in_write = addr_in_write[ 5: 0];
  end
  else
  begin
    assign word_addr_in_read = addr_in_read[ 7: 2];
    assign word_addr_in_write = addr_in_write[ 7: 2];
  end
endgenerate
assign byte_addr_in_read = {word_addr_in_read, 2'b00};
assign byte_addr_in_write = {word_addr_in_write, 2'b00};

wire rtc_rst, rtc_rst_synched;
wire rx_tsu_rst_synched, tx_tsu_rst_synched;
wire rtc_time_ld, rtc_period_ld, rtc_adj_ld, adj_ld_done;
wire [37:0] rtc_time_reg_ns;
wire [47:0] rtc_time_reg_sec;
wire [39:0] rtc_period;
wire [31:0] rtc_adj_ld_data;
wire [39:0] rtc_period_adj;
wire [37:0] rtc_time_reg_ns_val;
wire [47:0] rtc_time_reg_sec_val;
wire [79:0] rtc_time_ptp_val = {rtc_time_ptp_sec[47:0], rtc_time_ptp_ns[31:0]};

wire rx_q_rst, rx_q_clk;
wire rx_q_rd_en;
wire [  7:0] rx_q_ptp_msgid_mask;
wire [  7:0] rx_q_stat;
wire [127:0] rx_q_data;
wire tx_q_rst, tx_q_clk;
wire tx_q_rd_en;
wire [  7:0] tx_q_ptp_msgid_mask;
wire [  7:0] tx_q_stat;
wire [127:0] tx_q_data;

wire rx_q_timestamp_everything;
wire tx_q_timestamp_everything;

rgs#(
  .C_ENABLE_REG_ILAS(C_ENABLE_REG_ILAS)
) u_rgs
(
  .rst(rst),
  .clk(clk),
  .wr_in(wr_in),
  .rd_in(rd_in),
  .addr_in_read(byte_addr_in_read),
  .addr_in_write(byte_addr_in_write),
  .data_in(data_in),
  .data_out(data_out),
  .rtc_clk_in(rtc_clk),
  .rtc_sync_rst_in(rtc_rst_synched),
  .rtc_rst_out(rtc_rst),
  .time_ld_out(rtc_time_ld),
  .time_reg_ns_out(rtc_time_reg_ns),
  .time_reg_sec_out(rtc_time_reg_sec),
  .period_ld_out(rtc_period_ld),
  .period_out(rtc_period),
  .adj_ld_out(rtc_adj_ld),
  .adj_ld_data_out(rtc_adj_ld_data),
  .period_adj_out(rtc_period_adj),
  .adj_ld_done_in(adj_ld_done),
  .time_reg_ns_in(rtc_time_reg_ns_val),
  .time_reg_sec_in(rtc_time_reg_sec_val),
  .rx_q_rst_out(rx_q_rst),
  .rx_q_rd_clk_out(rx_q_clk),
  .rx_q_rd_en_out(rx_q_rd_en),
  .rx_q_ptp_msgid_mask_out(rx_q_ptp_msgid_mask),
  .rx_q_stat_in(rx_q_stat),
  .rx_q_data_in(rx_q_data),
  .rx_q_timestamp_everything(rx_q_timestamp_everything),
  .tx_q_rst_out(tx_q_rst),
  .tx_q_rd_clk_out(tx_q_clk),
  .tx_q_rd_en_out(tx_q_rd_en),
  .tx_q_ptp_msgid_mask_out(tx_q_ptp_msgid_mask),
  .tx_q_stat_in(tx_q_stat),
  .tx_q_data_in(tx_q_data),
  .tx_q_timestamp_everything(tx_q_timestamp_everything)
);

ha1588_resetsync#(
  .RST_ACTIVE_HIGH(1)
) i_rtc_rst_sync(
  .dst_clk_i(rtc_clk),
  .dst_rst_no(rtc_rst_synched),
  .src_rst_ni(rtc_rst)
);

rtc u_rtc
(
  .rst(rtc_rst_synched),
  .clk(rtc_clk),
  .time_ld(rtc_time_ld),
  .time_reg_ns_in(rtc_time_reg_ns),
  .time_reg_sec_in(rtc_time_reg_sec),
  .period_ld(rtc_period_ld),
  .period_in(rtc_period),
  .adj_ld(rtc_adj_ld),
  .adj_ld_data(rtc_adj_ld_data),
  .adj_ld_done(adj_ld_done),
  .period_adj(rtc_period_adj),
  .time_reg_ns(rtc_time_reg_ns_val),
  .time_reg_sec(rtc_time_reg_sec_val),
  .time_one_pps(rtc_time_one_pps),
  .time_ptp_ns(rtc_time_ptp_ns),
  .time_ptp_sec(rtc_time_ptp_sec)
);

ha1588_resetsync#(
  .RST_ACTIVE_HIGH(1)
) i_rx_tsu_rst_sync(
  .dst_clk_i(rx_gmii_clk),
  .dst_rst_no(rx_tsu_rst_synched),
  .src_rst_ni(rst)
);

tsu#(
  .C_BYPASS_TSU                   (C_BYPASS_TSU),
  .C_ENABLE_TIMESTAMP_EVERYTHING  (C_ENABLE_TIMESTAMP_EVERYTHING),
  .C_ENABLE_TSU_ILAS              (C_ENABLE_TSU_ILAS)
) u_rx_tsu
(
  .rst(rx_tsu_rst_synched),
  .rtc_rst(rtc_rst_synched),
  .gmii_clk(rx_gmii_clk),
  .gmii_ctrl(rx_gmii_ctrl),
  .gmii_data(rx_gmii_data),
  .giga_mode(rx_giga_mode),
  .ptp_msgid_mask(rx_q_ptp_msgid_mask),
  .rtc_timer_clk(rtc_clk),
  .rtc_timer_in(rtc_time_ptp_val),
  .q_rst(rx_q_rst),
  .q_rd_clk(rx_q_clk),
  .q_rd_en(rx_q_rd_en),
  .q_rd_stat(rx_q_stat),
  .q_rd_data(rx_q_data),
  .tsu_bypass_evt(rx_tsu_bypass_evt),
  .intr_out(rx_intr_out),
  .timestamp_everything_in(rx_q_timestamp_everything)
);

ha1588_resetsync#(
  .RST_ACTIVE_HIGH(1)
) i_tx_tsu_rst_sync(
  .dst_clk_i(tx_gmii_clk),
  .dst_rst_no(tx_tsu_rst_synched),
  .src_rst_ni(rst)
);


tsu#(
  .C_BYPASS_TSU                   (C_BYPASS_TSU),
  .C_ENABLE_TIMESTAMP_EVERYTHING  (C_ENABLE_TIMESTAMP_EVERYTHING)
) u_tx_tsu
(
  .rst(tx_tsu_rst_synched),
  .rtc_rst(rtc_rst_synched),
  .gmii_clk(tx_gmii_clk),
  .gmii_ctrl(tx_gmii_ctrl),
  .gmii_data(tx_gmii_data),
  .giga_mode(tx_giga_mode),
  .ptp_msgid_mask(tx_q_ptp_msgid_mask),
  .rtc_timer_clk(rtc_clk),
  .rtc_timer_in(rtc_time_ptp_val),
  .q_rst(tx_q_rst),
  .q_rd_clk(tx_q_clk),
  .q_rd_en(tx_q_rd_en),
  .q_rd_stat(tx_q_stat),
  .q_rd_data(tx_q_data),
  .tsu_bypass_evt(tx_tsu_bypass_evt),
  .intr_out(tx_intr_out),
  .timestamp_everything_in(tx_q_timestamp_everything)
);

endmodule
