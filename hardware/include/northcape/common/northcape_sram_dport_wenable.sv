/**
  * SRAM memory primitive.
  * Infers a write-first block RAM on FPGA platforms (e.g., Xilinx 7-series) with two input ports and byte-wise write enables.
  */
module northcape_sram_dport_wenable #(
    // could be 9 bits, with a parity / metadata bit
    parameter int BYTE_WIDTH = 8,
    parameter int DATA_BYTES = -1,
    parameter int DATA_DEPTH = -1,
    parameter bit INIT_TO_ZERO = 1'b1,
    parameter bit WRITE_FIRST = 1'b0,
    localparam int ADDR_WIDTH = $clog2(DATA_DEPTH),
    localparam int DATA_WIDTH = DATA_BYTES * BYTE_WIDTH,
    parameter string INIT_FILE = ""
) (
    input logic clk_i,

    // port A
    input logic [DATA_WIDTH-1:0] a_wdata_i,
    input logic [DATA_BYTES-1:0] a_wenable_i,
    output logic [DATA_WIDTH-1:0] a_rdata_o,
    input logic [ADDR_WIDTH-1:0] a_addr_i,
    input logic a_enable_i,

    // port B

    input logic [DATA_WIDTH-1:0] b_wdata_i,
    input logic [DATA_BYTES-1:0] b_wenable_i,
    output logic [DATA_WIDTH-1:0] b_rdata_o,
    input logic [ADDR_WIDTH-1:0] b_addr_i,
    input logic b_enable_i
);

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
      for (genvar i = 0; i < DATA_BYTES; i++) begin : gen_byte_access
        localparam BIT_START = (i + 1) * BYTE_WIDTH;
        localparam BIT_END = i * BYTE_WIDTH;

        always_ff @(posedge (clk_i)) begin : a_port_access
          if (a_enable_i) begin
            if (a_wenable_i[i]) begin
              bram[a_addr_i][BIT_START-1:BIT_END] <= a_wdata_i[BIT_START-1:BIT_END];
              a_rdata_o[BIT_START-1:BIT_END] <= a_wdata_i[BIT_START-1:BIT_END];
            end else begin
              a_rdata_o[BIT_START-1:BIT_END] <= bram[a_addr_i][BIT_START-1:BIT_END];
            end
          end
        end : a_port_access

        always_ff @(posedge (clk_i)) begin : b_port_access
          if (b_enable_i) begin
            if (b_wenable_i[i]) begin
              bram[b_addr_i][BIT_START-1:BIT_END] <= b_wdata_i[BIT_START-1:BIT_END];
              b_rdata_o[BIT_START-1:BIT_END] <= b_wdata_i[BIT_START-1:BIT_END];
            end else begin
              b_rdata_o[BIT_START-1:BIT_END] <= bram[b_addr_i][BIT_START-1:BIT_END];
            end
          end
        end : b_port_access
      end : gen_byte_access
    end : gen_logic_write_first
    else begin : gen_logic_read_first

      always_ff @(posedge (clk_i)) begin : a_port_read
        if (a_enable_i) begin
          a_rdata_o <= bram[a_addr_i];
        end
      end : a_port_read

      always_ff @(posedge (clk_i)) begin : b_port_read
        if (b_enable_i) begin
          b_rdata_o <= bram[b_addr_i];
        end
      end : b_port_read

      for (genvar i = 0; i < DATA_BYTES; i++) begin : gen_byte_access
        localparam BIT_START = (i + 1) * BYTE_WIDTH;
        localparam BIT_END = i * BYTE_WIDTH;

        always_ff @(posedge (clk_i)) begin : a_port_write
          if (a_enable_i) begin
            if (a_wenable_i[i]) begin
              bram[a_addr_i][BIT_START-1:BIT_END] <= a_wdata_i[BIT_START-1:BIT_END];
            end
          end
        end : a_port_write

        always_ff @(posedge (clk_i)) begin : b_port_write
          if (b_enable_i) begin
            if (b_wenable_i[i]) begin
              bram[b_addr_i][BIT_START-1:BIT_END] <= b_wdata_i[BIT_START-1:BIT_END];
            end
          end
        end : b_port_write
      end : gen_byte_access
    end : gen_logic_read_first
  endgenerate


`ifndef VERILATOR
  property p_mutual_exclusion;
    @(posedge clk_i)
        (a_enable_i || b_enable_i) |-> ((!a_wenable_i || !b_wenable_i) || (a_addr_i != b_addr_i));
  endproperty

  assert property (p_mutual_exclusion)
  else $error("Write address collision!");
`endif

endmodule
