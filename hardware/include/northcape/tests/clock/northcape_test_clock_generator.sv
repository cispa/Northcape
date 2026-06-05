/**
  * Generates a configurable clock for a testbench.
  */
module northcape_test_clock_generator #(
    parameter CLOCK_PERIOD_NS = -1
) (
    output logic clk_i
);

  localparam half_clock_period_ns = CLOCK_PERIOD_NS / 2;

  initial begin
    clk_i = 0;
    forever begin
      #half_clock_period_ns clk_i = ~clk_i;
    end
  end

endmodule
