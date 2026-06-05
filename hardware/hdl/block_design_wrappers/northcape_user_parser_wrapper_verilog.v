
`include "ariane_xlnx_mapper.svh"
module northcape_user_parser_wrapper_verilog#(
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter PASSTHROUGH_MODE = -1
)(
    input wire aclk,
    input wire aresetn,

    `AXI_INTERFACE_MODULE_MONITOR(s_axi),

    output wire [15:0] active_device,
    output wire [31:0] active_task,
    output wire [63:0] active_device_specific_restriction,
    output wire parsing_error
);

  northcape_user_parser_wrapper#(
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),
    .PASSTHROUGH_MODE(PASSTHROUGH_MODE)
  ) i_user_parser(
    .clk_i(aclk),
    .rst_ni(aresetn),

    `AXI_INTERFACE_FORWARD(s_axi),

    .active_device(active_device),
    .active_task(active_task),
    .active_device_specific_restriction(active_device_specific_restriction),
    .parsing_error(parsing_error)
  );

endmodule
