/**
  * SRAM memory primitive.
  * Infers a write-first block RAM on FPGA platforms (e.g., Xilinx 7-series) with one input port.
  */
module northcape_sram_sport_wenable #(
    parameter int DATA_WIDTH = -1,
    parameter int DATA_DEPTH = -1,
    parameter bit INIT_TO_ZERO = 1'b1,
    parameter bit WRITE_FIRST = 1'b0,
    localparam int ADDR_WIDTH = $clog2(DATA_DEPTH),
    parameter string INIT_FILE = ""
) (
    input logic clk_i,

    // port A
    input logic [DATA_WIDTH-1:0] wdata_i,
    input logic [DATA_WIDTH/8-1:0] wenable_i,
    output logic [DATA_WIDTH-1:0] rdata_o,
    input logic [ADDR_WIDTH-1:0] addr_i,
    input logic enable_i
);

  localparam COL_WIDTH = 8;

  (* ram_style = "block" *) logic [DATA_WIDTH-1:0] bram[DATA_DEPTH-1:0];

  generate
    if (INIT_FILE != "") begin : gen_init_file
      initial $readmemh(INIT_FILE, bram, 0, DATA_DEPTH - 1);
    end : gen_init_file
    else if (INIT_TO_ZERO) begin : gen_init_zero
      initial begin
        for (int init_index = 0; init_index < DATA_DEPTH; init_index++) begin
          bram[init_index] = {DATA_WIDTH{1'b0}};
        end
      end
    end : gen_init_zero
  endgenerate

  generate
    if (WRITE_FIRST) begin : gen_logic_write_first
      genvar i;
      for (i = 0; i < DATA_WIDTH / 8; i++) begin
        always_ff @(posedge (clk_i)) begin : port_access
          if (enable_i) begin
            if (wenable_i[i]) begin
              bram[addr_i][(i+1)*COL_WIDTH-1:i*COL_WIDTH] <= wdata_i[(i+1)*COL_WIDTH-1:i*COL_WIDTH];
              rdata_o[(i+1)*COL_WIDTH-1:i*COL_WIDTH] <= wdata_i[(i+1)*COL_WIDTH-1:i*COL_WIDTH];
            end else begin
              rdata_o[(i+1)*COL_WIDTH-1:i*COL_WIDTH] <= bram[addr_i][(i+1)*COL_WIDTH-1:i*COL_WIDTH];
            end
          end
        end : port_access
      end
    end : gen_logic_write_first
    else begin : gen_logic_read_first
      genvar i;
      for (i = 0; i < DATA_WIDTH / 8; i++) begin
        always_ff @(posedge (clk_i)) begin : write_access
          if (enable_i) begin
            if (wenable_i[i]) begin
              bram[addr_i][(i+1)*COL_WIDTH-1:i*COL_WIDTH] <= wdata_i[(i+1)*COL_WIDTH-1:i*COL_WIDTH];
            end
          end
        end : write_access
      end
      always_ff @(posedge (clk_i)) begin : read_access
        if (enable_i) begin
          rdata_o <= bram[addr_i];
        end
      end : read_access
    end : gen_logic_read_first
  endgenerate

endmodule
