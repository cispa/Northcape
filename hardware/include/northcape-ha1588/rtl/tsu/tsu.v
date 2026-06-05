/*
 * tsu.v
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

module tsu#(
  parameter C_BYPASS_TSU                  = 1'b0,
  parameter C_ENABLE_TIMESTAMP_EVERYTHING = 1'b0,
  parameter C_ENABLE_TSU_ILAS             = 1'b0
) (
    input       rst,
    input       rtc_rst,

    input       gmii_clk,
    input       gmii_ctrl,
    input [7:0] gmii_data,
    input       giga_mode,

    input       tsu_bypass_evt,

    input [7:0] ptp_msgid_mask,
    
    input        rtc_timer_clk,
    input [79:0] rtc_timer_in,  // timeStamp1s_48bit + timeStamp1ns_32bit

    input         q_rst,
    input         q_rd_clk,
    input         q_rd_en,
    output [  7:0] q_rd_stat,
    output [127:0] q_rd_data,  // null_16bit + timeStamp1s_48bit + timeStamp1ns_32bit + msgId_4bit + ckSum_12bit + seqId_16bit 
    output        intr_out,

    input       timestamp_everything_in // skip parser and timestamp all packets?
);

wire        ptp_found;
wire [31:0] ptp_infor;

wire q_wr_en;
wire q_wr_en_dbg_component_1;
wire q_wr_en_dbg_component_2;
wire q_wr_en_dbg_component_3;

// ptp CDC time stamping
wire ts_req;  // TODO: check frame start delimiter
(* ASYNC_REG = "TRUE" *) reg  ts_req_d1, ts_req_d2, ts_req_d3;
always @(posedge rtc_rst or posedge rtc_timer_clk) begin
  if (rtc_rst) begin
    ts_req_d1 <= 1'b0;
    ts_req_d2 <= 1'b0;
    ts_req_d3 <= 1'b0;
  end
  else begin
    ts_req_d1 <= ts_req;
    ts_req_d2 <= ts_req_d1;
    ts_req_d3 <= ts_req_d2;
  end
end
reg [79:0] rtc_time_stamp;
always @(posedge rtc_rst or posedge rtc_timer_clk) begin
  if (rtc_rst)
    rtc_time_stamp <= 80'd0;
  else 
    if (ts_req_d2 & !ts_req_d3)
      rtc_time_stamp <= rtc_timer_in;
end
reg ts_ack, ts_ack_clr;
wire ts_ack_clr_synched;

ha1588_resetsync#(
  .RST_ACTIVE_HIGH(1)
) i_tsu_resetsynch(
  .dst_clk_i(rtc_timer_clk),
  .dst_rst_no(ts_ack_clr_synched),
  .src_rst_ni(ts_ack_clr)
);

always @(posedge ts_ack_clr_synched or posedge rtc_timer_clk) begin
  if (ts_ack_clr_synched)
    ts_ack <= 1'b0;
  else
    if (ts_req_d2 & !ts_req_d3)
      ts_ack <= 1'b1;
end

(* ASYNC_REG = "TRUE" *) reg ts_ack_d1, ts_ack_d2, ts_ack_d3;
always @(posedge rst or posedge gmii_clk) begin
  if (rst) begin
    ts_ack_d1 <= 1'b0;
    ts_ack_d2 <= 1'b0;
    ts_ack_d3 <= 1'b0;
  end
  else begin
    ts_ack_d1 <= ts_ack;
    ts_ack_d2 <= ts_ack_d1;
    ts_ack_d3 <= ts_ack_d2;
  end
end

reg [79:0] tsu_time_stamp;
always @(posedge rst or posedge gmii_clk) begin
  if (rst) begin
    tsu_time_stamp <= 80'd0;
    ts_ack_clr      <= 1'b0;
  end
  else begin
    if (ts_ack_d2 & !ts_ack_d3) begin
      tsu_time_stamp <= rtc_time_stamp;
      ts_ack_clr      <= 1'b1;
    end
    else begin
      tsu_time_stamp <= tsu_time_stamp;
      ts_ack_clr      <= 1'b0;
    end
  end
end

(* ASYNC_REG = "TRUE" *) reg timestamp_everything_in_d1, timestamp_everything_in_d2, timestamp_everything_in_d3;

generate
  if(!C_BYPASS_TSU && C_ENABLE_TIMESTAMP_EVERYTHING)
  begin: generateFFsTimestampEverything
    always @(posedge rst or posedge gmii_clk) begin
      if (rst) begin
        timestamp_everything_in_d1 <= 1'b0;
        timestamp_everything_in_d2 <= 1'b0;
        timestamp_everything_in_d3 <= 1'b0;
      end
      else begin
        timestamp_everything_in_d1 <= timestamp_everything_in;
        timestamp_everything_in_d2 <= timestamp_everything_in_d1;
        timestamp_everything_in_d3 <= timestamp_everything_in_d2;
      end
  end
  end
  else
  begin: setRegsNull
    always @(posedge gmii_clk) begin
      timestamp_everything_in_d1 <= 1'b0;
      timestamp_everything_in_d2 <= 1'b0;
      timestamp_everything_in_d3 <= 1'b0;
    end
  end
endgenerate


generate
  if(!C_BYPASS_TSU)
  begin: tsuParser

    // mii to gmii converter
    reg nibble_h;
    always @(posedge rst or posedge gmii_clk) begin
      if (rst)
        nibble_h <= 1'b0;
      else if (gmii_ctrl)
        nibble_h <= !nibble_h;
    end

    reg       gmii_ctrl_conv;
    reg [7:0] gmii_data_conv;
    always @(posedge rst or posedge gmii_clk) begin
      if (rst) begin
        gmii_ctrl_conv <= 1'b0;
        gmii_data_conv <= 8'd0;
      end
      else begin
        if (giga_mode) begin
          gmii_ctrl_conv      <= gmii_ctrl;
          gmii_data_conv[7:0] <= gmii_data[7:0];
        end
        else begin
          // 4b-8b datapath gearbox
          if (gmii_ctrl) begin
            gmii_ctrl_conv      <= ( nibble_h)? 1'b1:1'b0;
            gmii_data_conv[7:4] <= ( nibble_h)? gmii_data[3:0]:gmii_data_conv[7:4];
            gmii_data_conv[3:0] <= (!nibble_h)? gmii_data[3:0]:gmii_data_conv[3:0];
          end
          else begin
            gmii_ctrl_conv      <= 1'b0;
            gmii_data_conv[7:4] <= gmii_data_conv[7:4];
            gmii_data_conv[3:0] <= gmii_data_conv[3:0];
          end
        end
      end
    end

    // buffer gmii input
    reg       gmii_ctrl_conv_d1, gmii_ctrl_conv_d2, gmii_ctrl_conv_d3, gmii_ctrl_conv_d4,
              gmii_ctrl_conv_d5, gmii_ctrl_conv_d6, gmii_ctrl_conv_d7, gmii_ctrl_conv_d8,
              gmii_ctrl_conv_d9, gmii_ctrl_conv_da;
    reg [7:0] gmii_data_conv_d1, gmii_data_conv_d2, gmii_data_conv_d3, gmii_data_conv_d4,
              gmii_data_conv_d5, gmii_data_conv_d6, gmii_data_conv_d7, gmii_data_conv_d8,
              gmii_data_conv_d9, gmii_data_conv_da;
    always @(posedge rst or posedge gmii_clk) begin
      if (rst) begin
        gmii_ctrl_conv_d1 <= 1'b0;
        gmii_ctrl_conv_d2 <= 1'b0;
        gmii_ctrl_conv_d3 <= 1'b0;
        gmii_ctrl_conv_d4 <= 1'b0;
        gmii_ctrl_conv_d5 <= 1'b0;
        gmii_ctrl_conv_d6 <= 1'b0;
        gmii_ctrl_conv_d7 <= 1'b0;
        gmii_ctrl_conv_d8 <= 1'b0;
        gmii_ctrl_conv_d9 <= 1'b0;
        gmii_ctrl_conv_da <= 1'b0;
        gmii_data_conv_d1 <= 8'd0;
        gmii_data_conv_d2 <= 8'd0;
        gmii_data_conv_d3 <= 8'd0;
        gmii_data_conv_d4 <= 8'd0;
        gmii_data_conv_d5 <= 8'd0;
        gmii_data_conv_d6 <= 8'd0;
        gmii_data_conv_d7 <= 8'd0;
        gmii_data_conv_d8 <= 8'd0;
        gmii_data_conv_d9 <= 8'd0;
        gmii_data_conv_da <= 8'd0;
      end
      else begin
        gmii_ctrl_conv_d1 <= gmii_ctrl_conv;
        gmii_ctrl_conv_d2 <= gmii_ctrl_conv_d1;
        gmii_ctrl_conv_d3 <= gmii_ctrl_conv_d2;
        gmii_ctrl_conv_d4 <= gmii_ctrl_conv_d3;
        gmii_ctrl_conv_d5 <= gmii_ctrl_conv_d4;
        gmii_ctrl_conv_d6 <= gmii_ctrl_conv_d5;
        gmii_ctrl_conv_d7 <= gmii_ctrl_conv_d6;
        gmii_ctrl_conv_d8 <= gmii_ctrl_conv_d7;
        gmii_ctrl_conv_d9 <= gmii_ctrl_conv_d8;
        gmii_ctrl_conv_da <= gmii_ctrl_conv_d9;
        gmii_data_conv_d1 <= gmii_data_conv;
        gmii_data_conv_d2 <= gmii_data_conv_d1;
        gmii_data_conv_d3 <= gmii_data_conv_d2;
        gmii_data_conv_d4 <= gmii_data_conv_d3;
        gmii_data_conv_d5 <= gmii_data_conv_d4;
        gmii_data_conv_d6 <= gmii_data_conv_d5;
        gmii_data_conv_d7 <= gmii_data_conv_d6;
        gmii_data_conv_d8 <= gmii_data_conv_d7;
        gmii_data_conv_d9 <= gmii_data_conv_d8;
        gmii_data_conv_da <= gmii_data_conv_d9;
      end
    end

    // choose buffered gmii input
    reg       int_gmii_ctrl;
    reg       int_gmii_ctrl_d1, int_gmii_ctrl_d2, int_gmii_ctrl_d3, int_gmii_ctrl_d4,
              int_gmii_ctrl_d5;
    reg [7:0] int_gmii_data;
    reg [7:0] int_gmii_data_d1, int_gmii_data_d2, int_gmii_data_d3, int_gmii_data_d4,
              int_gmii_data_d5;
    always @(posedge rst or posedge gmii_clk) begin
      if (rst) begin
        int_gmii_ctrl    <= 1'b0;
        int_gmii_data    <= 8'h00;
        int_gmii_ctrl_d1 <= 1'b0;
        int_gmii_data_d1 <= 8'h00;
        int_gmii_ctrl_d2 <= 1'b0;
        int_gmii_data_d2 <= 8'h00;
        int_gmii_ctrl_d3 <= 1'b0;
        int_gmii_data_d3 <= 8'h00;
        int_gmii_ctrl_d4 <= 1'b0;
        int_gmii_data_d4 <= 8'h00;
        int_gmii_ctrl_d5 <= 1'b0;
        int_gmii_data_d5 <= 8'h00;
      end
      else begin
        if (giga_mode) begin
          int_gmii_ctrl    <= gmii_ctrl_conv;
          int_gmii_data    <= gmii_data_conv;
          int_gmii_ctrl_d1 <= gmii_ctrl_conv_d1;
          int_gmii_data_d1 <= gmii_data_conv_d1;
          int_gmii_ctrl_d2 <= gmii_ctrl_conv_d2;
          int_gmii_data_d2 <= gmii_data_conv_d2;
          int_gmii_ctrl_d3 <= gmii_ctrl_conv_d3;
          int_gmii_data_d3 <= gmii_data_conv_d3;
          int_gmii_ctrl_d4 <= gmii_ctrl_conv_d4;
          int_gmii_data_d4 <= gmii_data_conv_d4;
          int_gmii_ctrl_d5 <= gmii_ctrl_conv_d5;
          int_gmii_data_d5 <= gmii_data_conv_d5;
        end
        else begin
          int_gmii_ctrl    <= gmii_ctrl_conv;
          int_gmii_data    <= gmii_data_conv;
          int_gmii_ctrl_d1 <= gmii_ctrl_conv_d2;
          int_gmii_data_d1 <= gmii_data_conv_d2;
          int_gmii_ctrl_d2 <= gmii_ctrl_conv_d4;
          int_gmii_data_d2 <= gmii_data_conv_d4;
          int_gmii_ctrl_d3 <= gmii_ctrl_conv_d6;
          int_gmii_data_d3 <= gmii_data_conv_d6;
          int_gmii_ctrl_d4 <= gmii_ctrl_conv_d8;
          int_gmii_data_d4 <= gmii_data_conv_d8;
          int_gmii_ctrl_d5 <= gmii_ctrl_conv_da;
          int_gmii_data_d5 <= gmii_data_conv_da;
        end
      end
    end

    // 8b-32b datapath gearbox
    reg        int_valid;
    reg        int_sop, int_eop;
    reg [ 1:0] int_bcnt, int_mod;
    reg [31:0] int_data;
    always @(posedge rst or posedge gmii_clk) begin
      if (rst)
        int_bcnt <= 2'd0;
      else
        if      ( int_gmii_ctrl & !int_gmii_ctrl_d1)
          int_bcnt <= 2'd0;  // clear on sop
        else if ( int_gmii_ctrl)
          int_bcnt <= int_bcnt + 2'd1;  // increment
        else if (!int_gmii_ctrl & int_gmii_ctrl_d3 & (int_bcnt!=2'd0))
          int_bcnt <= int_bcnt + 2'd1;  // end on eop with mod
    end
    always @(posedge rst or posedge gmii_clk) begin
      if (rst) begin
        int_data  <= 32'd0;
        int_valid <=  1'b0;
        int_mod   <=  2'd0;
        int_sop <= 1'b0;
        int_eop <= 1'b0;
      end
      else begin
        if (int_gmii_ctrl) begin
          int_data[ 7: 0] <= (int_bcnt==2'd3)? int_gmii_data_d1:int_data[ 7: 0];
          int_data[15: 8] <= (int_bcnt==2'd2)? int_gmii_data_d1:int_data[15: 8];
          int_data[23:16] <= (int_bcnt==2'd1)? int_gmii_data_d1:int_data[23:16];
          int_data[31:24] <= (int_bcnt==2'd0)? int_gmii_data_d1:int_data[31:24];
        end

        if (int_gmii_ctrl & int_bcnt==2'd3)
          int_valid <= 1'b1;
        else
          int_valid <= 1'b0;

        if (int_gmii_ctrl_d1 & !int_gmii_ctrl_d2)
          int_mod <= 2'd0;
        else if (!int_gmii_ctrl_d1 & int_gmii_ctrl_d2)
          int_mod <= int_bcnt;

        if (int_gmii_ctrl_d4 & !int_gmii_ctrl_d5 & int_bcnt==2'd3)
          int_sop <= 1'b1;
        else
          int_sop <= 1'b0;

        if (!int_gmii_ctrl   &  int_gmii_ctrl_d3 & int_bcnt==2'd3)
          int_eop <= 1'b1;
        else
          int_eop <= 1'b0;

      end
    end

    reg [31:0] int_data_d1;
    reg        int_valid_d1;
    reg        int_sop_d1;
    reg        int_eop_d1;
    reg [ 1:0] int_mod_d1;
    always @(posedge rst or posedge gmii_clk) begin
      if (rst) begin
        int_data_d1  <= 32'h00000000;
        int_valid_d1 <= 1'b0;
        int_sop_d1   <= 1'b0;
        int_eop_d1   <= 1'b0;
        int_mod_d1   <= 2'b00;
      end
      else begin
        if (int_valid) begin
          int_data_d1  <= int_data;
          int_mod_d1   <= int_mod;
        end
          int_valid_d1 <= int_valid;
          int_sop_d1   <= int_sop;
          int_eop_d1   <= int_eop;
      end
    end

    // ptp packet parser here
    // works at 1/4 gmii_clk frequency, needs multicycle timing constraint
    ptp_parser parser(
      .clk(gmii_clk),
      .rst(rst),
      .int_data(int_data_d1),
      .int_valid(int_valid_d1),
      .int_sop(int_sop_d1),
      .int_eop(int_eop_d1),
      .int_mod(int_mod_d1),
      .ptp_msgid_mask(ptp_msgid_mask),
      .ptp_found(ptp_found),
      .ptp_infor(ptp_infor)
    );

    assign q_wr_en = (ptp_found || (C_ENABLE_TIMESTAMP_EVERYTHING == 1 && timestamp_everything_in_d3)) && int_eop_d1;
    assign q_wr_en_dbg_component_1 = ptp_found;
    assign q_wr_en_dbg_component_2 = timestamp_everything_in_d3;
    assign q_wr_en_dbg_component_3 = int_eop_d1;

    assign ts_req = int_gmii_ctrl;
  end
  else
  begin: tsuBypass
    // we JUST got the timestamp - write it into FIFO before it goes away
    assign q_wr_en = ts_ack_clr;
    assign ptp_infor = 0;
    assign ts_req = tsu_bypass_evt;

    assign q_wr_en_dbg_component_1 = 0;
    assign q_wr_en_dbg_component_2 = 0;
    assign q_wr_en_dbg_component_3 = 0;
  end
endgenerate

// ptp time stamp dcfifo
wire q_wr_clk = gmii_clk;
wire [127:0] q_wr_data = {16'd0, tsu_time_stamp, ptp_infor};  // 16+80+32 bit
wire [3:0] q_wrusedw;
wire [3:0] q_rdusedw;
wire q_wr_full;
wire q_rd_empty;
wire rd_rst_busy;
wire wr_rst_busy;

assign intr_out = q_wr_full;

ptp_queue queue(
  .aclr(q_rst),

  .wrclk(q_wr_clk),
  .wrreq(q_wr_en && !q_wr_full && !wr_rst_busy),  // write with overflow protection and make sure not to write during reset
  .data(q_wr_data),
  .wrfull(q_wr_full),
  .wrusedw(q_wrusedw),
  .wr_rst_busy(wr_rst_busy),

  .rdclk(q_rd_clk),
  .rdreq(q_rd_en && !q_rd_empty && !rd_rst_busy),  // read with underflow protection and make sure not to write during reset
  .q(q_rd_data),
  .rdempty(q_rd_empty),
  .rdusedw(q_rdusedw),
  .rd_rst_busy(rd_rst_busy)
  
);

assign q_rd_stat = {4'd0, q_rdusedw};

generate
  if(C_ENABLE_TSU_ILAS)
  begin
    ha1588_tsu_ila i_tsu_ila(
      .clk(q_wr_clk),
      .probe0(q_wr_en), // 1 bit
      .probe1(q_wr_full), // 1 bit
      .probe2(q_wr_en_dbg_component_1), // 1 bit
      .probe3(q_wr_en_dbg_component_2), // 1 bit
      .probe4(q_wr_en_dbg_component_3), // 1 bit
      .probe5(q_wrusedw), // 4 bit
      .probe6(gmii_ctrl), // 1 bit
      .probe7(gmii_data), // 8 bit
      .probe8(giga_mode), // 1 bit
      .probe9(wr_rst_busy)
    );
  end
endgenerate

endmodule
