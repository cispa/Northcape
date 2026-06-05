/**
  * Shift register suitable for SPI: bitwise shift/in, shift/out
  * Can also be loaded in parallel.
  * On 7-series, should infer an SRL primitive.
  */
module shift_reg_lowarea #(
    /* shift register has 2**DEPTH_SELECT_BITS entries */
    parameter int DEPTH_SELECT_BITS   = -1,
    parameter bit HAS_OUTPUT_REGISTER = 1'b0
) (
    input logic clk_i,
    input logic rst_ni,

    input logic data_serial_i,

    input logic shift_i,
    // from which position to output
    input logic [DEPTH_SELECT_BITS-1:0] select_i,

    output logic data_serial_o
);
  `include "northcape_unread.vh"

  logic [2**DEPTH_SELECT_BITS-1:0] shift_reg_q;

  always_ff @(posedge (clk_i)) begin : shiftReg
    if (shift_i) begin
      shift_reg_q <= {shift_reg_q[2**DEPTH_SELECT_BITS-2:0], data_serial_i};
    end
  end : shiftReg

  generate
    if (HAS_OUTPUT_REGISTER) begin : gen_output_reg
      logic output_reg_q;

      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : outputReg
        if (rst_ni == 1'b0) begin
          output_reg_q <= 1'b0;
        end else begin
          output_reg_q <= shift_reg_q[select_i];
        end
      end : outputReg

      assign data_serial_o = output_reg_q;
    end : gen_output_reg
    else begin : gen_no_output_reg
      assign data_serial_o = shift_reg_q[select_i];
      `NORTHCAPE_UNREAD(rst_ni);
    end : gen_no_output_reg
  endgenerate

endmodule
