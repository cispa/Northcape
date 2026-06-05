`include "ariane_xlnx_mapper.svh"
`include "northcape_xilinx_wrapper.vh"

module northcape_cap_resolver_wrapper_verilog
#(
    parameter TDATA_WIDTH=512,
    parameter TID_WIDTH=1,
    parameter TDEST_WIDTH=16,
    parameter TUSER_WIDTH = 1,

    parameter AXI_ADDR_WIDTH = 64,
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ID_WIDTH = 10,
    parameter AXI_USER_WIDTH = 1,

    parameter CAPABILITY_ID_WIDTH=38,
    parameter TAG_ID_WIDTH=16,
    parameter CMT_ENTRY_WIDTH=256,

    parameter CACHE_RECURSION_SKIP = 1,

    // pipeline stage between validate request and first processing stage
    parameter INPUT_PIPELINE_STAGE_ENABLED  = 1'b1,
    // pipeline stage between lookup/cache output and parser
    parameter PARSER_PIPELINE_STAGE_ENABLED = 1'b0,
    // pipeline stage between parser and output response
    parameter OUTPUT_PIPELINE_STAGE_ENABLED = 1'b1,

    parameter DEBUG_ILA = 0
)
(
    input wire aclk,
    input wire aresetn,

    // cache interface
    output wire resolver_interface_request_valid,
    output wire [CAPABILITY_ID_WIDTH-1:0] resolver_interface_request_capability_id,
    output wire [TAG_ID_WIDTH-1:0] resolver_interface_request_capability_tag,
    output wire resolver_interface_request_close_speculation_window,
    output wire resolver_interface_response_ready,
    output wire resolver_interface_request_flush,
    output wire resolver_interface_request_is_recursion,
    input wire resolver_interface_response_valid,
    input wire resolver_interface_response_err,
    input wire [CMT_ENTRY_WIDTH-1:0] resolver_interface_response_cmt_entry,
    input wire resolver_interface_response_cache_hit,

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

northcape_cap_resolver_wrapper
#(
  .TDATA_WIDTH(TDATA_WIDTH),
  .TID_WIDTH(TID_WIDTH),
  .TDEST_WIDTH(TDEST_WIDTH),
  .TUSER_WIDTH(TUSER_WIDTH),

  .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
  .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
  .AXI_ID_WIDTH(AXI_ID_WIDTH),
  .AXI_USER_WIDTH(AXI_USER_WIDTH),

  .CAPABILITY_ID_WIDTH(CAPABILITY_ID_WIDTH),
  .TAG_ID_WIDTH(TAG_ID_WIDTH),
  .CMT_ENTRY_WIDTH(CMT_ENTRY_WIDTH),

  .CACHE_RECURSION_SKIP(CACHE_RECURSION_SKIP),

  .INPUT_PIPELINE_STAGE_ENABLED(INPUT_PIPELINE_STAGE_ENABLED),
  .PARSER_PIPELINE_STAGE_ENABLED(PARSER_PIPELINE_STAGE_ENABLED),
  .OUTPUT_PIPELINE_STAGE_ENABLED(OUTPUT_PIPELINE_STAGE_ENABLED),
  .DEBUG_ILA(DEBUG_ILA)
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

  .resolver_interface_request_valid(resolver_interface_request_valid),
  .resolver_interface_request_capability_id(resolver_interface_request_capability_id),
  .resolver_interface_request_capability_tag(resolver_interface_request_capability_tag),
  .resolver_interface_request_close_speculation_window(resolver_interface_request_close_speculation_window),
  .resolver_interface_request_is_recursion(resolver_interface_request_is_recursion),
  .resolver_interface_response_ready(resolver_interface_response_ready),
  .resolver_interface_request_flush(resolver_interface_request_flush),
  .resolver_interface_response_valid(resolver_interface_response_valid),
  .resolver_interface_response_err(resolver_interface_response_err),
  .resolver_interface_response_cmt_entry(resolver_interface_response_cmt_entry),
  .resolver_interface_response_cache_hit(resolver_interface_response_cache_hit),

  .cmt_table_size_clog2(cmt_table_size_clog2),
  .cmt_base(cmt_base),
  .cmt_reset_done(cmt_reset_done),
  .cmt_need_flush_data_caches(cmt_need_flush_data_caches),
  .cmt_written_capability(cmt_written_capability),
  .cmt_wrote_any_capability(cmt_wrote_any_capability)
);

endmodule
