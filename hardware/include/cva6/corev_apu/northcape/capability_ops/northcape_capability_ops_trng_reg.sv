/**
  * Part of the northcape capability operations module.
  * Collects chunks of AXI_DATA_WIDTH random bits from the TRNG and exposes them as user-readable register
  */
module northcape_capability_ops_trng_reg #(
    parameter AXI_DATA_WIDTH = -1
) (
    input clk_i,
    input rst_ni,

    // for random values
    input logic rng_interface_rng_valid,
    input logic [NORTHCAPE_CAPABILITY_OPS_RNG_INTERFACE_BITS-1:0] rng_interface_rng_out,
    output logic rng_interface_rng_consumer_ready,

    input logic clear_i,
    output logic [AXI_DATA_WIDTH-1:0] trng_reg_o
);


  assign rng_interface_rng_consumer_ready = 1'b1;

  /* exposes all-new bits of randomness */
  logic [AXI_DATA_WIDTH-1:0] output_reg_q, output_reg_d;
  logic [$clog2(AXI_DATA_WIDTH)-1:0] counter_d, counter_q;

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : rngRegs
    if (!rst_ni) begin
      output_reg_q <= '0;
    end else begin
      output_reg_q <= output_reg_d;
    end
  end : rngRegs



  always_comb begin : outputRegLogic
    /* hold until new reg available */
    output_reg_d = output_reg_q;
    if (rng_interface_rng_valid) begin
      /* about to start anew - capture the 10 new bits*/
      output_reg_d = rng_interface_rng_out;
    end
    trng_reg_o = output_reg_d;
    if (clear_i) begin
      /* output should never be shown again */
      output_reg_d = '0;
    end
  end : outputRegLogic


endmodule
