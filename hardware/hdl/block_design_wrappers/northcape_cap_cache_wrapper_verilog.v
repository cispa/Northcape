`include "ariane_xlnx_mapper.svh"
`include "northcape_xilinx_wrapper.vh"

module northcape_cap_cache_wrapper_verilog
#(
    parameter AXI_ADDR_WIDTH = 64,
    parameter AXI_DATA_WIDTH = 256,
    parameter AXI_ID_WIDTH = 10,
    parameter AXI_USER_WIDTH = 1,
`ifdef NUM_ENTRIES
    parameter NUM_ENTRIES = `NUM_ENTRIES,
`else
    parameter NUM_ENTRIES = 1024,
`endif
    parameter SUPPORT_SPECULATIVE_RESOLVER_LOADS = 1,
    parameter KEEP_TOP_CMT_ENTRIES_ONLY = 0,
`ifdef STORE_BUFFER_SIZE
    parameter STORE_BUFFER_SIZE = `STORE_BUFFER_SIZE,
`else
    parameter STORE_BUFFER_SIZE = 0,
`endif
`ifdef ASSOCIATIVITY
    parameter ASSOCIATIVITY = `ASSOCIATIVITY,
`else
    parameter ASSOCIATIVITY=4,
`endif
    /*
     * NORTHCAPE_CAPABILITY_TYPE_COMMON_NO_CACHE = 0
     * NORTHCAPE_CAPABILITY_TYPE_WT_DIRECT_FF = 1
     * NORTHCAPE_CAPABILITY_TYPE_WT_FULLY_ASSOC_FF = 2
     * NORTHCAPE_CAPABILITY_TYPE_WT_DIRECT_BRAM = 3
     * NORTHCAPE_CAPABILITY_TYPE_WT_N_ASSOC_BRAM = 4
     */
`ifdef CACHE_TYPE
    parameter CACHE_TYPE = `CACHE_TYPE,
`else
    parameter CACHE_TYPE = 4,
`endif

    parameter CAPABILITY_ID_WIDTH=38,
    parameter TAG_ID_WIDTH=16,
    parameter CMT_ENTRY_WIDTH=256,
    parameter DEBUG_ILA = 0
)
(
    input wire aclk,
    input wire aresetn,

    `AXI_INTERFACE_MODULE_OUTPUT(m_cache_out),

    // resolver interface
    input wire resolver_interface_request_valid,
    input wire [CAPABILITY_ID_WIDTH-1:0] resolver_interface_request_capability_id,
    input wire [TAG_ID_WIDTH-1:0] resolver_interface_request_capability_tag,
    input wire resolver_interface_response_ready,
    input wire resolver_interface_request_flush,
    input wire resolver_interface_request_close_speculation_window,
    input wire resolver_interface_request_is_recursion,
    output wire resolver_interface_response_valid,
    output wire resolver_interface_response_err,
    output wire [CMT_ENTRY_WIDTH-1:0] resolver_interface_response_cmt_entry,
    output wire resolver_interface_response_cache_hit,

    // ops interface
    input wire ops_interface_request_valid,
    input wire [CAPABILITY_ID_WIDTH-1:0] ops_interface_request_capability_id,
    input wire [TAG_ID_WIDTH-1:0] ops_interface_request_capability_tag,
    input wire ops_interface_is_write,
    input wire [CMT_ENTRY_WIDTH-1:0] ops_interface_write_request_capability,
    input wire ops_interface_write_request_flush,
    input wire ops_interface_request_is_uncacheable,
    output wire ops_interface_response_valid,
    output wire ops_interface_response_err,
    output wire [CMT_ENTRY_WIDTH-1:0] ops_interface_response_cmt_entry,
    
    // to CMT interface
    input wire[31:0] cmt_table_size_clog2,
    input wire [AXI_ADDR_WIDTH - 1 : 0] cmt_base,
    input wire cmt_reset_done,
    input wire cmt_need_flush_data_caches,
    input wire cmt_wrote_any_capability,
    input wire [CAPABILITY_ID_WIDTH-1:0] cmt_written_capability,

    // performance counters
    output wire resolver_port_miss_o,
  `ifndef ASIC
    output wire resolver_spec_fail_o,
  `endif
    output wire ops_port_miss_o,
    output wire missunit_stall_o,
    output wire ops_write_stall_o
);

// TODO somehow, this single signal causes routing congestion problems...
`ifdef ASIC
wire resolver_spec_fail_o;
`endif

northcape_cap_cache_wrapper
#(

  .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
  .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
  .AXI_ID_WIDTH(AXI_ID_WIDTH),
  .AXI_USER_WIDTH(AXI_USER_WIDTH),

  .STORE_BUFFER_SIZE(STORE_BUFFER_SIZE),

  .ASSOCIATIVITY(ASSOCIATIVITY),
  .CACHE_TYPE(CACHE_TYPE),

  .NUM_ENTRIES(NUM_ENTRIES),
  .SUPPORT_SPECULATIVE_RESOLVER_LOADS(SUPPORT_SPECULATIVE_RESOLVER_LOADS),
  .KEEP_TOP_CMT_ENTRIES_ONLY(KEEP_TOP_CMT_ENTRIES_ONLY),

  .CAPABILITY_ID_WIDTH(CAPABILITY_ID_WIDTH),
  .TAG_ID_WIDTH(TAG_ID_WIDTH),
  .CMT_ENTRY_WIDTH(CMT_ENTRY_WIDTH),
  .DEBUG_ILA(DEBUG_ILA)
)
i_northcape_cap_cache_wrapper
(
  .clk_i(aclk),
  .rst_ni(aresetn),

  `AXI_INTERFACE_FORWARD(m_cache_out),

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

  .ops_interface_request_valid(ops_interface_request_valid),
  .ops_interface_request_capability_id(ops_interface_request_capability_id),
  .ops_interface_request_capability_tag(ops_interface_request_capability_tag),
  .ops_interface_is_write(ops_interface_is_write),
  .ops_interface_write_request_capability(ops_interface_write_request_capability),
  .ops_interface_write_request_flush(ops_interface_write_request_flush),
  .ops_interface_request_is_uncacheable(ops_interface_request_is_uncacheable),
  .ops_interface_response_valid(ops_interface_response_valid),
  .ops_interface_response_err(ops_interface_response_err),
  .ops_interface_response_cmt_entry(ops_interface_response_cmt_entry),

  .cmt_table_size_clog2(cmt_table_size_clog2),
  .cmt_base(cmt_base),
  .cmt_reset_done(cmt_reset_done),
  .cmt_need_flush_data_caches(cmt_need_flush_data_caches),
  .cmt_wrote_any_capability(cmt_wrote_any_capability),
  .cmt_written_capability(cmt_written_capability),
  .resolver_port_miss_o(resolver_port_miss_o),
  .resolver_spec_fail_o(resolver_spec_fail_o),
  .ops_port_miss_o(ops_port_miss_o),
  .missunit_stall_o(missunit_stall_o),
  .ops_write_stall_o(ops_write_stall_o)
);

endmodule
