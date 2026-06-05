/**
  * SRAM memory primitive, built from 32 (width) / 128 (depth) primitives
  * Infers a write-first block RAM on FPGA platforms (e.g., Xilinx 7-series) with two input ports.
  */
module hpdcache_sram_sport #(
    parameter  int DATA_WIDTH   = -1,
    parameter  int DATA_DEPTH   = -1,
    localparam int ADDR_WIDTH   = $clog2(DATA_DEPTH),
    localparam int WMASK_WIDTH  = DATA_WIDTH / 8
) (
`ifdef USE_POWER_PINS
    inout wire vccd1,
    inout wire vssd1,
`endif

    input logic clk_i,

    // port A
    input logic [DATA_WIDTH-1:0] wdata_i,
    input logic wenable_i,
    input logic [WMASK_WIDTH-1:0] wmask_i,
    output logic [DATA_WIDTH-1:0] rdata_o,
    input logic [ADDR_WIDTH-1:0] addr_i,
    input logic enable_i
);

// we select the macro based on width only
localparam PRIMITIVE_WIDTH = 64;
localparam PRIMITIVE_DEPTH = 128;

localparam NUM_COLS = (DATA_WIDTH + PRIMITIVE_WIDTH - 1) / PRIMITIVE_WIDTH;
localparam NUM_ROWS = (DATA_DEPTH + PRIMITIVE_DEPTH - 1) / PRIMITIVE_DEPTH;

logic [PRIMITIVE_WIDTH * NUM_COLS - 1 : 0] row_in;

assign row_in = wdata_i;

logic [NUM_ROWS - 1 : 0] row_select;

logic [ADDR_WIDTH - 1 : 0] col_addr;

logic [NUM_ROWS-1:0][PRIMITIVE_WIDTH * NUM_COLS-1:0] rows_out;

assign col_addr = addr_i % PRIMITIVE_DEPTH;

logic [$clog2(NUM_ROWS)-1:0] active_row_d, active_row_q;

assign active_row_d = addr_i / PRIMITIVE_DEPTH;
// break a problematic combinatorical path - latency of 1 cycle is expected anyways
assign rdata_o = rows_out[active_row_q];

always_comb begin: activeToOneHot
  row_select = '0;

  row_select[active_row_d] = 1'b1;
end: activeToOneHot

generate
  for(genvar i = 0; i < NUM_ROWS; i++)
  begin: gen_row
    logic row_active;

    assign row_active = row_select[i];
   


    for(genvar j = 0; j < NUM_COLS; j++)
    begin: gen_col
      logic [PRIMITIVE_WIDTH-1:0] col_in_a, col_in_b;

      assign col_in = row_in[(j+1)*PRIMITIVE_WIDTH -1 : j*PRIMITIVE_WIDTH];


      sram_hpdcache_wrapper#(
        .DATA_WIDTH(PRIMITIVE_WIDTH),
        .ADDR_WIDTH($clog2(PRIMITIVE_DEPTH))
      ) i_sram_cell(
`ifdef USE_POWER_PINS
        .vccd1(vccd1),
        .vssd1(vssd1),
`endif
        // port A
        .clk0(clk_i),
        .csb0(!(row_active & enable_i)), // active-low
        .web0(!(row_active & wenable_i)), // active low
        .wmask0(~wmask_i), // active low
        .addr0(col_addr),
        .din0(col_in),
        .dout0(rows_out[i][(j+1)*PRIMITIVE_WIDTH -1 : j*PRIMITIVE_WIDTH])
      );
    end: gen_col
  end: gen_row

endgenerate

always_ff @(posedge(clk_i))
begin
  active_row_q <= active_row_d;
end

  
endmodule
