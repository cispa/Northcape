`include "ariane_xlnx_mapper.svh"
`include "northcape_xilinx_wrapper.vh"
module northcape_dummy_resolver_wrapper
#(
    parameter TDATA_WIDTH=-1,
    parameter TID_WIDTH=-1,
    parameter TDEST_WIDTH=-1,
    parameter TUSER_WIDTH = -1
)
(
    input logic clk_i,
    input logic rst_ni,


    `AXIS_MODULE_INPUT(axis_validate_request),
    `AXIS_MODULE_OUTPUT(axis_validate_response)

);

Axis5#(.AXIS_TDATA_WIDTH(TDATA_WIDTH), .AXIS_TID_WIDTH(TID_WIDTH), .AXIS_TDEST_WIDTH(TDEST_WIDTH), .AXIS_TUSER_WIDTH(TUSER_WIDTH)) northcape_axis_validate_request(.aclk(aclk),.rst_ni(rst_ni));
Axis5#(.AXIS_TDATA_WIDTH(TDATA_WIDTH), .AXIS_TID_WIDTH(TID_WIDTH), .AXIS_TDEST_WIDTH(TDEST_WIDTH), .AXIS_TUSER_WIDTH(TUSER_WIDTH)) northcape_axis_validate_response(.aclk(aclk),.rst_ni(rst_ni));


northcape_capability_resolver_dummy i_northcape_capability_resolver_read
(
  .axis_validate_request(northcape_axis_validate_request),
  .axis_validate_response(northcape_axis_validate_response)
);

`NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(northcape_axis_validate_response, axis_validate_response)

`NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(northcape_axis_validate_request, axis_validate_request)


endmodule
