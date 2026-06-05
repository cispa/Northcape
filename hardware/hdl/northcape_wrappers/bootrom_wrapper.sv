`include "northcape_xilinx_wrapper.vh"
`include "ariane_xlnx_mapper.svh"
`include "northcape_ariane_wrapper.svh"
// wraps a RAM or ROM with the boot image. AXI 64-bit interface.
module bootrom_wrapper #(
    // AXI parameters
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,
    parameter BOOTROM_SIZE_BYTES = 1048576,  // 1 Mib
    localparam BRAM_DEPTH=BOOTROM_SIZE_BYTES / (AXI_DATA_WIDTH / 8),
    localparam AXI_ADDR_WIDTH = $clog2(BOOTROM_SIZE_BYTES),
    parameter WRITABLE = 1'b1  // 1: is boot RAM (writable), 0: is boot ROM (not writable)
) (
    (*X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_i CLK" *)
   (*X_INTERFACE_PARAMETER = "FREQ_HZ 50000000, ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET rst_ni"*)
    input logic clk_i,
    input logic rst_ni,
    `AXI_INTERFACE_MODULE_INPUT(S_AXI)
);
  import axi5::*;
  import axi_pkg::BURST_FIXED;
  import axi_pkg::BURST_INCR;
  import axi_pkg::BURST_WRAP;

  import axi_pkg::RESP_OKAY;
  import axi_pkg::RESP_EXOKAY;
  import axi_pkg::RESP_DECERR;
  import axi_pkg::RESP_SLVERR;

  Axi5 #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) axi_in (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );
  AXI_BUS #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) axi_ariane ();

  `NORTHCAPE_MAP_XILINX_AXI_INTERFACES_IN(axi_in, S_AXI);
  `MAP_NORTHCAPE_INTERFACE_TO_ARIANE_INTERFACE(axi_in, axi_ariane);

  logic bram_en;
  logic bram_we;
  logic [AXI_ADDR_WIDTH-1:0] bram_addr;
  logic [AXI_DATA_WIDTH/8-1:0] bram_be;
  logic [AXI_DATA_WIDTH-1:0] bram_data_in;
  logic [AXI_DATA_WIDTH-1:0] bram_data_out;

  logic [$clog2(BRAM_DEPTH)-1:0] bram_addr_real;

  axi2mem #(
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) i_axi2mem (
      .clk_i (clk_i),
      .rst_ni(rst_ni),
      .slave (axi_ariane),

      .req_o (bram_en),
      .we_o  (bram_we),
      .addr_o(bram_addr),
      .be_o  (bram_be),
      .user_o(),
      .data_o(bram_data_in),
      .user_i('0),
      .data_i(bram_data_out)
  );
  /* byte -> word address */
  assign bram_addr_real = bram_addr / (AXI_DATA_WIDTH / 8);

  northcape_sram_sport_wenable #(
      .DATA_WIDTH(AXI_DATA_WIDTH),
      .DATA_DEPTH(BRAM_DEPTH),
      .INIT_TO_ZERO(1'b0),
      .WRITE_FIRST(1'b0),
      .INIT_FILE("bootrom_64.mem")
  ) i_northcape_sram (
      .clk_i(clk_i),

      .wdata_i(bram_data_in),
      .wenable_i(WRITABLE && bram_we ? bram_be : '0),
      .rdata_o(bram_data_out),
      .addr_i(bram_addr_real),
      .enable_i(bram_en)
  );

endmodule
