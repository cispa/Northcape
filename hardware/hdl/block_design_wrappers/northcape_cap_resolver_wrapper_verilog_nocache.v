`include "ariane_xlnx_mapper.svh"
`include "northcape_xilinx_wrapper.vh"

module northcape_cap_resolver_wrapper_verilog_nocache
#(
    parameter TDATA_WIDTH=512,
    parameter TID_WIDTH=1,
    parameter TDEST_WIDTH=16,
    parameter TUSER_WIDTH = 1,

    parameter AXI_ADDR_WIDTH = 64,
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ID_WIDTH = 10,
    parameter AXI_USER_WIDTH = 1,
    parameter CAPABILITY_ID_WIDTH = 38,

    // size of the FIFO that buffers requests
    // indicates number of max parallel requests
    parameter FIFO_DEPTH_CLOG_2=4,
    parameter MAX_AXI_TRANSACTIONS = 4
)
(
    input wire aclk,
    input wire aresetn,

    `AXI_INTERFACE_MODULE_OUTPUT(m_resolver_out),

    // TODO currently forced to define these manually...
    `AXIS_MODULE_INPUT(axis_validate_request_0),
    `AXIS_MODULE_OUTPUT(axis_validate_response_0),
    `AXIS_MODULE_INPUT(axis_validate_request_1),
    `AXIS_MODULE_OUTPUT(axis_validate_response_1),
    `AXIS_MODULE_INPUT(axis_validate_request_2),
    `AXIS_MODULE_OUTPUT(axis_validate_response_2),
    `AXIS_MODULE_INPUT(axis_validate_request_3),
    `AXIS_MODULE_OUTPUT(axis_validate_response_3),
    `AXIS_MODULE_INPUT(axis_validate_request_4),
    `AXIS_MODULE_OUTPUT(axis_validate_response_4),
    `AXIS_MODULE_INPUT(axis_validate_request_5),
    `AXIS_MODULE_OUTPUT(axis_validate_response_5),

    // to CMT interface
    input wire[31:0] cmt_table_size_clog2,
    input wire [AXI_ADDR_WIDTH - 1 : 0] cmt_base,
    input wire cmt_reset_done,
    input wire cmt_need_flush_data_caches,
    input wire cmt_wrote_any_capability,
    input wire [CAPABILITY_ID_WIDTH-1:0] cmt_written_capability

);

northcape_cap_resolver_wrapper_nocache
#(
  .TDATA_WIDTH(TDATA_WIDTH),
  .TID_WIDTH(TID_WIDTH),
  .TDEST_WIDTH(TDEST_WIDTH),
  .TUSER_WIDTH(TUSER_WIDTH),

  .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
  .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
  .AXI_ID_WIDTH(AXI_ID_WIDTH),
  .AXI_USER_WIDTH(AXI_USER_WIDTH),

  .FIFO_DEPTH_CLOG_2(FIFO_DEPTH_CLOG_2),
  .MAX_AXI_TRANSACTIONS(MAX_AXI_TRANSACTIONS)
)
i_northcape_cap_resolver_wrapper
(
  .clk_i(aclk),
  .rst_ni(aresetn),

  `AXIS_INPUT_FORWARD(axis_validate_request_0),
  `AXIS_INPUT_FORWARD(axis_validate_response_0),
  `AXIS_INPUT_FORWARD(axis_validate_request_1),
  `AXIS_INPUT_FORWARD(axis_validate_response_1),
  `AXIS_INPUT_FORWARD(axis_validate_request_2),
  `AXIS_INPUT_FORWARD(axis_validate_response_2),
  `AXIS_INPUT_FORWARD(axis_validate_request_3),
  `AXIS_INPUT_FORWARD(axis_validate_response_3),
  `AXIS_INPUT_FORWARD(axis_validate_request_4),
  `AXIS_INPUT_FORWARD(axis_validate_response_4),
  `AXIS_INPUT_FORWARD(axis_validate_request_5),
  `AXIS_INPUT_FORWARD(axis_validate_response_5),

  `AXI_INTERFACE_FORWARD(m_resolver_out),

  .cmt_table_size_clog2(cmt_table_size_clog2),
  .cmt_base(cmt_base),
  .cmt_reset_done(cmt_reset_done),
  .cmt_need_flush_data_caches(cmt_need_flush_data_caches),
  .cmt_wrote_any_capability(cmt_wrote_any_capability),
  .cmt_written_capability(cmt_written_capability)
);

endmodule
