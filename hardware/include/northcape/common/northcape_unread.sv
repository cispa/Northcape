/**
  * Dummy module, used to ignore a signal
  */

module northcape_unread #(
    parameter NUMBER_BITS = 1
) (
    input  logic [NUMBER_BITS-1:0] unread,
    output logic [NUMBER_BITS-1:0] dummy_output
);

  assign dummy_output = unread;

endmodule
