/**
  * SRAM memory primitive with one input port.
  * Wraps a two-input counter part.
  */
module northcape_sram_sport #(
    parameter  int DATA_WIDTH   = -1,
    parameter  int DATA_DEPTH   = -1,
    // not supported on ASIC
    parameter  bit INIT_TO_ZERO = 1'b1,
    parameter  bit WRITE_FIRST  = 1'b0,
    localparam int ADDR_WIDTH   = $clog2(DATA_DEPTH)
) (
`ifdef USE_POWER_PINS
    inout wire vccd1,
    inout wire vssd1,
`endif

    input logic clk_i,

    input logic [DATA_WIDTH-1:0] wdata_i,
    input logic wenable_i,
    output logic [DATA_WIDTH-1:0] rdata_o,
    input logic [ADDR_WIDTH-1:0] addr_i,
    input logic enable_i
);

northcape_sram_dport #(
  .DATA_WIDTH(DATA_WIDTH),
  .DATA_DEPTH(DATA_DEPTH),
  .INIT_TO_ZERO(INIT_TO_ZERO),
  .WRITE_FIRST(WRITE_FIRST)
) i_cache_sram(
  .clk_i(clk_i),
  
  .a_wdata_i(wdata_i),
  .a_wenable_i(wenable_i),
  .a_rdata_o(rdata_o),
  .a_addr_i(addr_i),
  .a_enable_i(enable_i),

  .b_wdata_i('0),
  .b_wenable_i(1'b0),
  .b_rdata_o(),
  .b_addr_i('0),
  .b_enable_i(1'b0)
);
  
endmodule
