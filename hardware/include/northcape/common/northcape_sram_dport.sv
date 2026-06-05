/**
  * SRAM memory primitive.
  * Infers a write-first block RAM on FPGA platforms (e.g., Xilinx 7-series) with two input ports.
  */
module northcape_sram_dport #(
    parameter int DATA_WIDTH = -1,
    parameter int DATA_DEPTH = -1,
    parameter bit INIT_TO_ZERO = 1'b1,
    parameter bit WRITE_FIRST = 1'b0,
    localparam int ADDR_WIDTH = $clog2(DATA_DEPTH),
    parameter string INIT_FILE = ""
) (
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
      always_ff @(posedge (clk_i)) begin : a_port_access
        if (a_enable_i) begin
          if (a_wenable_i) begin
            bram[a_addr_i] <= a_wdata_i;
            a_rdata_o <= a_wdata_i;
          end else begin
            a_rdata_o <= bram[a_addr_i];
          end
        end
      end : a_port_access

      always_ff @(posedge (clk_i)) begin : b_port_access
        if (b_enable_i) begin
          if (b_wenable_i) begin
            bram[b_addr_i] <= b_wdata_i;
            b_rdata_o <= b_wdata_i;
          end else begin
            b_rdata_o <= bram[b_addr_i];
          end
        end
      end : b_port_access
    end : gen_logic_write_first
    else begin : gen_logic_read_first
      always_ff @(posedge (clk_i)) begin : a_port_access
        if (a_enable_i) begin
          if (a_wenable_i) begin
            bram[a_addr_i] <= a_wdata_i;
          end
          a_rdata_o <= bram[a_addr_i];
        end
      end : a_port_access

      always_ff @(posedge (clk_i)) begin : b_port_access
        if (b_enable_i) begin
          if (b_wenable_i) begin
            bram[b_addr_i] <= b_wdata_i;
          end
          b_rdata_o <= bram[b_addr_i];
        end
      end : b_port_access
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
