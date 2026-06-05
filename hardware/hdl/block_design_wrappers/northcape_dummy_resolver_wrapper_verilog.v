`include "ariane_xlnx_mapper.svh"
// `include "northcape_xilinx_wrapper.vh"

module northcape_dummy_resolver_wrapper_verilog
#(
    parameter TDATA_WIDTH=128,
    parameter TID_WIDTH=1,
    parameter TDEST_WIDTH=1,
    parameter TUSER_WIDTH = 1
)
(
    input wire aclk,
    input wire aresetn,


    `AXIS_MODULE_INPUT(axis_validate_request),
    `AXIS_MODULE_OUTPUT(axis_validate_response)

);

northcape_dummy_resolver_wrapper
#(
  .TDATA_WIDTH(TDATA_WIDTH),
  .TID_WIDTH(TID_WIDTH),
  .TDEST_WIDTH(TDEST_WIDTH),
  .TUSER_WIDTH(TUSER_WIDTH)
)
i_northcape_dummy_resolver_wrapper
(
  .clk_i(aclk),
  .rst_ni(aresetn),

  `AXIS_INPUT_FORWARD(axis_validate_request),
  `AXIS_INPUT_FORWARD(axis_validate_response)
);

endmodule
