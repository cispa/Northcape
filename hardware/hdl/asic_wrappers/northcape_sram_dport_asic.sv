/**
  * SRAM memory primitive, built from 32 (width) / 128 (depth) primitives
  * Infers a write-first block RAM on FPGA platforms (e.g., Xilinx 7-series) with two input ports.
  */
module northcape_sram_dport #(
    parameter  int DATA_WIDTH   = -1,
    parameter  int DATA_DEPTH   = -1,
    // not supported on ASIC
    parameter  bit INIT_TO_ZERO = 1'b1,
    parameter  bit WRITE_FIRST  = 1'b0,
    // not alwas awaylable
    parameter  bit USE_LARGE_SRAM = 1'b1,
    localparam int ADDR_WIDTH   = $clog2(DATA_DEPTH)
) (
`ifdef USE_POWER_PINS
    inout wire vccd1,
    inout wire vssd1,
`endif

    input logic clk_i,

    // port A
    input logic [DATA_WIDTH-1:0] a_wdata_i,
    input logic a_wenable_i,
    output logic [DATA_WIDTH-1:0] a_rdata_o,
    input logic [ADDR_WIDTH-1:0] a_addr_i,
    input logic a_enable_i,

    // port B

    input logic [DATA_WIDTH-1:0] b_wdata_i,
    input logic b_wenable_i,
    output logic [DATA_WIDTH-1:0] b_rdata_o,
    input logic [ADDR_WIDTH-1:0] b_addr_i,
    input logic b_enable_i
);
// small block RAM (32*128)
localparam PRIMITIVE_WIDTH_SMALL = 32;
localparam PRIMITIVE_DEPTH_SMALL = 128;

// large block RAM (256*64)
localparam PRIMITIVE_WIDTH_LARGE = 256;
localparam PRIMITIVE_DEPTH_LARGE = 64;

// we select the macro based on width only
localparam PRIMITIVE_WIDTH = (DATA_WIDTH >= PRIMITIVE_WIDTH_LARGE && USE_LARGE_SRAM) ? PRIMITIVE_WIDTH_LARGE : PRIMITIVE_WIDTH_SMALL;
localparam PRIMITIVE_DEPTH = (DATA_WIDTH >= PRIMITIVE_WIDTH_LARGE && USE_LARGE_SRAM) ? PRIMITIVE_DEPTH_LARGE : PRIMITIVE_DEPTH_SMALL;;

localparam NUM_COLS = (DATA_WIDTH + PRIMITIVE_WIDTH - 1) / PRIMITIVE_WIDTH;
localparam NUM_ROWS = (DATA_DEPTH + PRIMITIVE_DEPTH - 1) / PRIMITIVE_DEPTH;

logic [PRIMITIVE_WIDTH * NUM_COLS - 1 : 0] row_in_a, row_in_b;

assign row_in_a = a_wdata_i;
assign row_in_b = b_wdata_i;


logic [NUM_ROWS - 1 : 0] row_select_a, row_select_b;

logic [ADDR_WIDTH - 1 : 0] col_addr_a, col_addr_b;

logic [NUM_ROWS-1:0][PRIMITIVE_WIDTH * NUM_COLS-1:0] rows_out_a, rows_out_b;

assign col_addr_a = a_addr_i % PRIMITIVE_DEPTH;
assign col_addr_b = b_addr_i % PRIMITIVE_DEPTH;

logic [$clog2(NUM_ROWS)-1:0] active_row_a, active_row_b;

assign active_row_a = a_addr_i / PRIMITIVE_DEPTH;
assign active_row_b = b_addr_i / PRIMITIVE_DEPTH;

assign a_rdata_o = rows_out_a[active_row_a];
assign b_rdata_o = rows_out_b[active_row_b];

always_comb begin: activeToOneHot
  row_select_a = '0;
  row_select_b = '0;

  row_select_a[active_row_a] = 1'b1;
  row_select_b[active_row_b] = 1'b1;
end: activeToOneHot

generate
  for(genvar i = 0; i < NUM_ROWS; i++)
  begin: gen_row
    logic row_active_a,row_active_b;

    assign row_active_a = row_select_a[i];
    assign row_active_b = row_select_b[i];
   


    for(genvar j = 0; j < NUM_COLS; j++)
    begin: gen_col
      logic [PRIMITIVE_WIDTH-1:0] col_in_a, col_in_b;

      assign col_in_a = row_in_a[(j+1)*PRIMITIVE_WIDTH -1 : j*PRIMITIVE_WIDTH];
      assign col_in_b = row_in_b[(j+1)*PRIMITIVE_WIDTH -1 : j*PRIMITIVE_WIDTH];


      sram_northcape_wrapper#(
        .DATA_WIDTH(PRIMITIVE_WIDTH),
        .ADDR_WIDTH($clog2(PRIMITIVE_DEPTH))
      ) i_sram_cell(
`ifdef USE_POWER_PINS
        .vccd1(vccd1),
        .vssd1(vssd1),
`endif
        // port A
        .clk0(clk_i),
        .csb0(!(row_active_a & a_enable_i)), // active-low
        .web0(!(row_active_a & a_wenable_i)), // active low
        .addr0(col_addr_a),
        .din0(col_in_a),
        .dout0(rows_out_a[i][(j+1)*PRIMITIVE_WIDTH -1 : j*PRIMITIVE_WIDTH]),

        // port B
        .clk1(clk_i),
        .csb1(!(row_active_b & b_enable_i)), // active-low
        .web1(!(row_active_b & b_wenable_i)), // active low
        .addr1(col_addr_b),
        .din1(col_in_b),
        .dout1(rows_out_b[i][(j+1)*PRIMITIVE_WIDTH -1 : j*PRIMITIVE_WIDTH])
      );
    end: gen_col
  end: gen_row

endgenerate

  
endmodule
