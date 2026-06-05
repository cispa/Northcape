/**
  * Simulated RNG, uses $urandom to generate pseudo-random output
  */
module trng (
    input  logic clk,
    input  logic rst,
    output logic \rand
);

  always_ff @(posedge (clk)) begin : rng
    if (rst == 1) begin
      \rand <= 0;
    end else begin
      \rand <= $urandom();
    end

  end : rng

endmodule
