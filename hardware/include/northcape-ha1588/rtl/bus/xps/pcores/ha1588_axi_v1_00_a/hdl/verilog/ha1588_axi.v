`timescale 1ns/1ns

module ha1588_axi
  #(
    /* assigned to 8-bit interface below */
    parameter integer C_S_AXI_REG_ADDR_WIDTH             = 8,
    parameter integer C_S_AXI_REG_DATA_WIDTH             = 32,

    parameter integer C_EXTERNAL_INTR_OUT_WIDTH          = 1,
    parameter         C_BYPASS_TSU                       = 0,
    parameter         C_ENABLE_TIMESTAMP_EVERYTHING      = 0,
    parameter         C_GIGA_MODE_IS_IN_AXI_CLK_DOMAIN   = 0,
    /* set to 1 to buffer write address in a register - useful if you CANNOT ENSURE that awvalid, wvalid arrive at same clock */
    parameter         C_AXI_WRITE_SKIDBUFFER             = 1,
    /* set to 1 to buffer read response in a register - useful if you CANNOT ENSURE that rready is always high */
    parameter         C_AXI_READ_SKIDBUFFER              = 1,
    parameter         C_ENABLE_REG_ILAS                  = 1'b0,
    parameter         C_ENABLE_TSU_ILAS                  = 1'b0
   )
  (
    // Register Slave System Signals
    input wire                                 S_AXI_REG_ACLK,
    input wire                                 S_AXI_REG_ARESETN,
 
    // Register Slave Interface Write Address Ports
    input  wire [C_S_AXI_REG_ADDR_WIDTH-1:0]   S_AXI_REG_AWADDR,
    input  wire [3-1:0]                        S_AXI_REG_AWPROT,
    input  wire                                S_AXI_REG_AWVALID,
    output wire                                S_AXI_REG_AWREADY,

    // Register Slave Interface Write Data Ports
    input  wire [C_S_AXI_REG_DATA_WIDTH-1:0]   S_AXI_REG_WDATA,
    input  wire [C_S_AXI_REG_DATA_WIDTH/8-1:0] S_AXI_REG_WSTRB,
    input  wire                                S_AXI_REG_WVALID,
    output wire                                S_AXI_REG_WREADY,

    // Register Slave Interface Write Response Ports
    output wire [2-1:0]                        S_AXI_REG_BRESP,
    output reg                                 S_AXI_REG_BVALID,
    input  wire                                S_AXI_REG_BREADY,

    // Register Slave Interface Read Address Ports
    input  wire [C_S_AXI_REG_ADDR_WIDTH-1:0]   S_AXI_REG_ARADDR,
    input  wire [3-1:0]                        S_AXI_REG_ARPROT,
    input  wire                                S_AXI_REG_ARVALID,
    output wire                                S_AXI_REG_ARREADY,

    // Register Slave Interface Read Data Ports
    output wire [C_S_AXI_REG_DATA_WIDTH-1:0]   S_AXI_REG_RDATA,
    output wire [2-1:0]                        S_AXI_REG_RRESP,
    output reg                                 S_AXI_REG_RVALID,
    input  wire                                S_AXI_REG_RREADY,

    output wire                                RX_INTR_OUT,
    output wire                                TX_INTR_OUT,


    // RTC and TSU Ports
    input  wire        rtc_clk,
    output wire [31:0] rtc_time_ptp_ns,
    output wire [47:0] rtc_time_ptp_sec,
    output wire        rtc_time_one_pps,

    input  wire        rx_gmii_clk,
    input  wire        rx_gmii_ctrl,
    input  wire [ 7:0] rx_gmii_data,
    input  wire        rx_giga_mode,
    input  wire        tx_gmii_clk,
    input  wire        tx_gmii_ctrl,
    input  wire [ 7:0] tx_gmii_data,
    input  wire        tx_giga_mode,

    // timestamping triggers for when C_BYPASS_TSU is active
    input  wire        rx_tsu_bypass_evt,
    input  wire        tx_tsu_bypass_evt
  );

  wire        up_wr;
  wire        up_rd;
  wire        write_active;
  wire [ 7:0] up_addr;
  wire [31:0] up_data_wr;
  wire [31:0] up_data_rd;

  // 1: outstanding read (i.e., need to keep rvalid high and rdata)
  // 0: no outstanding read (i.e., rvalid low, rdata undefined, arready high)
  reg         rd_skidbuffer_q;
  wire        rd_skidbuffer_d;


  generate
    if(C_AXI_READ_SKIDBUFFER)
    begin: gen_skidbuffer
      assign rd_skidbuffer_d = (S_AXI_REG_ARVALID) ? 1'b1 : ((S_AXI_REG_RREADY) ? 1'b0 : rd_skidbuffer_q);
      always @(negedge S_AXI_REG_ARESETN or posedge S_AXI_REG_ACLK) begin
        if(!S_AXI_REG_ARESETN) rd_skidbuffer_q <= 1'b0;
        else                   rd_skidbuffer_q <= rd_skidbuffer_d;
      end
    end
    else
    begin: gen_no_skidbuffer
      assign rd_skidbuffer_d = S_AXI_REG_ARVALID;
      // assignment is not possible due to this being a register
      always @(negedge S_AXI_REG_ARESETN or posedge S_AXI_REG_ACLK) begin
        if(!S_AXI_REG_ARESETN) rd_skidbuffer_q <= 1'b0;
        else                   rd_skidbuffer_q <= 1'b0;
      end
    end

  endgenerate

  //////////////////////////////////////////////////////////////////////////////
  // AXI interface
  //
  // TODO: to support interleaved write address channel and write data channel,
  //       with FIFO for each channel.
  // TODO: to support write data byte select
  // TODO: to support write response channel holding
  // TODO: to support read response channel holding
  //////////////////////////////////////////////////////////////////////////////
  assign S_AXI_REG_AWREADY = 1'b1;
  assign S_AXI_REG_WREADY  = 1'b1;
  assign S_AXI_REG_BRESP   = 2'b00;
  always @(negedge S_AXI_REG_ARESETN or posedge S_AXI_REG_ACLK) begin
    if (!S_AXI_REG_ARESETN) S_AXI_REG_BVALID <= 1'b0;
    else                    S_AXI_REG_BVALID <= S_AXI_REG_WVALID;
  end
  // do not accept a new request before the response for the old one has been processed
  assign S_AXI_REG_ARREADY = !rd_skidbuffer_q;
  assign S_AXI_REG_RDATA   = up_data_rd;
  assign S_AXI_REG_RRESP   = 2'b00;
  // we need at least 1 clock cycle to provide data
  always @(negedge S_AXI_REG_ARESETN or posedge S_AXI_REG_ACLK) begin
    if (!S_AXI_REG_ARESETN) S_AXI_REG_RVALID <= 1'b0;
    else                    S_AXI_REG_RVALID <= rd_skidbuffer_d;
  end

  /////////////////////////////////////////////////////////////////////////////
  // Local Bus interface
  //
  /////////////////////////////////////////////////////////////////////////////

generate
  if(C_AXI_WRITE_SKIDBUFFER)
  begin: genSkidbuffer
    reg  [ 7:0] write_addr_skidbuffer;
    always @(posedge(S_AXI_REG_ACLK), negedge(S_AXI_REG_ARESETN) ) begin
      if(!S_AXI_REG_ARESETN)
      begin
        write_addr_skidbuffer <= 0;
      end
      else
      begin
        if(S_AXI_REG_AWVALID)
        begin
          write_addr_skidbuffer <= S_AXI_REG_AWADDR;
        end
      end
  end
    
    assign up_addr    = S_AXI_REG_AWVALID? S_AXI_REG_AWADDR : write_addr_skidbuffer;
  end
  else
  begin: genNoSkidbuffer
    wire [ 7:0] write_addr_skidbuffer;
    assign write_addr_skidbuffer = S_AXI_REG_AWADDR;
    assign up_addr    = S_AXI_REG_AWVALID? S_AXI_REG_AWADDR : write_addr_skidbuffer;
  end
endgenerate

  assign up_wr      = S_AXI_REG_WVALID;
  // need to maintain data unchanged before current read is complete, even if master asks for new data
  assign up_rd      = S_AXI_REG_ARVALID && !rd_skidbuffer_q;
  assign up_data_wr = S_AXI_REG_WDATA;


  wire rx_giga_mode_int;
  wire tx_giga_mode_int;

generate
  if(C_GIGA_MODE_IS_IN_AXI_CLK_DOMAIN)
  begin: syncGigaMode

    reg rx_giga_mode_latch;
    reg tx_giga_mode_latch;

    (* ASYNC_REG = "TRUE" *) reg rx_giga_mode_d1, rx_giga_mode_d2;
    (* ASYNC_REG = "TRUE" *) reg tx_giga_mode_d1, tx_giga_mode_d2;

    wire gmii_tx_rst, gmii_rx_rst;

    ha1588_resetsync#(
      .RST_ACTIVE_HIGH(0)
    ) i_gmii_rx_rstsync(
      .src_rst_ni(S_AXI_REG_ARESETN),
      .dst_clk_i (rx_gmii_clk),
      .dst_rst_no(gmii_rx_rst)
    );

    ha1588_resetsync#(
      .RST_ACTIVE_HIGH(0)
    ) i_gmii_tx_rstsync(
      .src_rst_ni(S_AXI_REG_ARESETN),
      .dst_clk_i (tx_gmii_clk),
      .dst_rst_no(gmii_tx_rst)
    );

    always@(posedge(S_AXI_REG_ACLK), negedge(S_AXI_REG_ARESETN))
    begin: inputLatch
      if(!S_AXI_REG_ARESETN)
      begin
        rx_giga_mode_latch <= 1'b0;
        tx_giga_mode_latch <= 1'b0;
      end
      else
      begin
        rx_giga_mode_latch <= rx_giga_mode;
        tx_giga_mode_latch <= tx_giga_mode;
      end
    end

    always@(posedge(rx_gmii_clk), negedge(gmii_rx_rst))
    begin: gigaModeSyncRx
      if(!gmii_rx_rst)
      begin
        rx_giga_mode_d1 <= 1'b0;
        rx_giga_mode_d2 <= 1'b0;
      end
      else
      begin
        rx_giga_mode_d1 <= rx_giga_mode_latch;
        rx_giga_mode_d2 <= rx_giga_mode_d1;
      end
    end

    always@(posedge(tx_gmii_clk), negedge(gmii_tx_rst))
    begin: gigaModeSyncTx
      if(!gmii_tx_rst)
      begin
        tx_giga_mode_d1 <= 1'b0;
        tx_giga_mode_d2 <= 1'b0;
      end
      else
      begin
        tx_giga_mode_d1 <= tx_giga_mode_latch;
        tx_giga_mode_d2 <= tx_giga_mode_d1;
      end
    end

    assign rx_giga_mode_int = rx_giga_mode_d2;
    assign tx_giga_mode_int = tx_giga_mode_d2;
  end
  else
  begin: passGigaMode
    assign rx_giga_mode_int = rx_giga_mode;
    assign tx_giga_mode_int = tx_giga_mode;
  end

endgenerate

ha1588#(
  .C_BYPASS_TSU                     (C_BYPASS_TSU),
  .C_ENABLE_TIMESTAMP_EVERYTHING    (C_ENABLE_TIMESTAMP_EVERYTHING),
  .C_ENABLE_REG_ILAS                (C_ENABLE_REG_ILAS),
  .C_ENABLE_TSU_ILAS                (C_ENABLE_TSU_ILAS)
) ha1588_inst (
  .rst(!S_AXI_REG_ARESETN),
  .clk(S_AXI_REG_ACLK),
  .wr_in(up_wr),
  .rd_in(up_rd),
  .addr_in_read(S_AXI_REG_ARADDR),
  .addr_in_write(up_addr),
  .data_in(up_data_wr),
  .data_out(up_data_rd),

  .rtc_clk(rtc_clk),
  .rtc_time_ptp_ns(rtc_time_ptp_ns),
  .rtc_time_ptp_sec(rtc_time_ptp_sec),
  .rtc_time_one_pps(rtc_time_one_pps),

  .rx_gmii_clk(rx_gmii_clk),
  .rx_gmii_ctrl(rx_gmii_ctrl),
  .rx_gmii_data(rx_gmii_data),
  .rx_giga_mode(rx_giga_mode_int),
  .tx_gmii_clk(tx_gmii_clk),
  .tx_gmii_ctrl(tx_gmii_ctrl),
  .tx_gmii_data(tx_gmii_data),
  .tx_giga_mode(tx_giga_mode_int),

  .rx_tsu_bypass_evt(rx_tsu_bypass_evt),
  .tx_tsu_bypass_evt(tx_tsu_bypass_evt),

  .rx_intr_out(RX_INTR_OUT),
  .tx_intr_out(TX_INTR_OUT)
);

endmodule

