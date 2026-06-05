/**
  * Leading zero count (LZC) implementation.
  * Recursive with parametrizable size.
  * Based on https://electronics.stackexchange.com/a/649761
  */
module northcape_leading_zero_count #(
    parameter SIZE = -1,
    localparam SIZE_OUT = $clog2(SIZE) + 1,
    localparam SIZE_OUT_HALF_WIDTH = SIZE_OUT - 1
) (
    input logic [SIZE-1:0] one_hot_i,
    output logic [SIZE_OUT-1:0] leading_zero_count_o
);

  generate
    if (SIZE < 2) begin : gen_error
      $error("Size is invalid!");
    end : gen_error
    else if (SIZE == 2) begin : gen_recursion_stop
      always_comb begin : recursion_stop
        unique case (one_hot_i)
          2'b00:   leading_zero_count_o = 2'd2;
          2'b01:   leading_zero_count_o = 2'd1;
          default: leading_zero_count_o = '0;
        endcase
      end : recursion_stop
    end : gen_recursion_stop
    else begin : gen_recursion
      logic [SIZE_OUT_HALF_WIDTH-1:0] right_half_out;
      logic [SIZE_OUT_HALF_WIDTH-1:0] left_half_out;

      logic [SIZE/2-1:0] one_hot_right;
      logic [SIZE/2-1:0] one_hot_left;

      assign one_hot_left  = one_hot_i[SIZE-1:SIZE/2];
      assign one_hot_right = one_hot_i[SIZE/2-1:0];

      northcape_leading_zero_count #(
          .SIZE(SIZE / 2)
      ) i_left_rec (
          .one_hot_i(one_hot_left),
          .leading_zero_count_o(left_half_out)
      );

      northcape_leading_zero_count #(
          .SIZE(SIZE / 2)
      ) i_right_rec (
          .one_hot_i(one_hot_right),
          .leading_zero_count_o(right_half_out)
      );


      assign leading_zero_count_o = (~left_half_out[SIZE_OUT_HALF_WIDTH-1]) ? {left_half_out [SIZE_OUT_HALF_WIDTH-1] & right_half_out [SIZE_OUT_HALF_WIDTH-1], 1'b0                    , left_half_out[SIZE_OUT_HALF_WIDTH-2:0]} :
                                                       {left_half_out [SIZE_OUT_HALF_WIDTH-1] & right_half_out [SIZE_OUT_HALF_WIDTH-1], ~right_half_out[SIZE_OUT_HALF_WIDTH-1], right_half_out[SIZE_OUT_HALF_WIDTH-2:0]};
    end : gen_recursion
  endgenerate



endmodule
