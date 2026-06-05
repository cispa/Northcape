/**
  * 2-FlipFlop Synchronizer
  */
module twoff_sync #(
    parameter int WIDTH = -1,
    parameter logic [WIDTH-1:0] RESET_VAL = '0
) (
    input logic clk_i,
    input logic rst_ni,

    input  logic [WIDTH-1:0] data_i,
    output logic [WIDTH-1:0] data_o
);

  logic [WIDTH-1:0] q1, q2;

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin
    if (rst_ni == 1'b0) begin
      q1 <= RESET_VAL;
      q2 <= RESET_VAL;
    end else begin
      q1 <= data_i;
      q2 <= q1;
    end
  end

  assign data_o = q2;

endmodule
