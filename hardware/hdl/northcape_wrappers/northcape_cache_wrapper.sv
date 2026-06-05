`include "ariane_xlnx_mapper.svh"
`include "northcape_xilinx_wrapper.vh"
module northcape_cap_cache_wrapper
#(
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,

    parameter bit SUPPORT_SPECULATIVE_RESOLVER_LOADS = 1'b1,
    parameter bit KEEP_TOP_CMT_ENTRIES_ONLY = 1'b1,
    parameter int STORE_BUFFER_SIZE = 0,
    parameter int ASSOCIATIVITY=-1,
    parameter int CACHE_TYPE = -1,

    parameter CAPABILITY_ID_WIDTH=-1,
    parameter TAG_ID_WIDTH=-1,
    parameter CMT_ENTRY_WIDTH=-1,
    parameter NUM_ENTRIES = -1,
    parameter DEBUG_ILA = 0
)
(
    input logic clk_i,
    input logic rst_ni,

    `AXI_INTERFACE_MODULE_OUTPUT(m_cache_out),

    // resolver interface
    input logic resolver_interface_request_valid,
    input logic [CAPABILITY_ID_WIDTH-1:0] resolver_interface_request_capability_id,
    input logic [TAG_ID_WIDTH-1:0] resolver_interface_request_capability_tag,
    input logic resolver_interface_request_close_speculation_window,
    input logic resolver_interface_response_ready,
    input logic resolver_interface_request_flush,
    input logic resolver_interface_request_is_recursion,
    output logic resolver_interface_response_valid,
    output logic resolver_interface_response_err,
    output logic [CMT_ENTRY_WIDTH-1:0] resolver_interface_response_cmt_entry,
    output logic resolver_interface_response_cache_hit,

    // ops interface
    input logic ops_interface_request_valid,
    input logic [CAPABILITY_ID_WIDTH-1:0] ops_interface_request_capability_id,
    input logic [TAG_ID_WIDTH-1:0] ops_interface_request_capability_tag,
    input logic ops_interface_is_write,
    input logic [CMT_ENTRY_WIDTH-1:0] ops_interface_write_request_capability,
    input logic ops_interface_write_request_flush,
    input logic ops_interface_request_is_uncacheable,
    output logic ops_interface_response_valid,
    output logic ops_interface_response_err,
    output logic [CMT_ENTRY_WIDTH-1:0] ops_interface_response_cmt_entry,


    // to CMT interface
    input int unsigned cmt_table_size_clog2,
    input wire [AXI_ADDR_WIDTH - 1 : 0] cmt_base,
    input wire cmt_reset_done,
    input wire cmt_need_flush_data_caches,
    input wire cmt_wrote_any_capability,
    input wire [CAPABILITY_ID_WIDTH-1:0] cmt_written_capability,

    // performance counters
    output logic resolver_port_miss_o,
    output logic resolver_spec_fail_o,
    output logic ops_port_miss_o,
    output logic missunit_stall_o,
    output logic ops_write_stall_o
);

import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
import northcape_capability_cache_common::*;
import axi5::*;

Axi5#(.AXI_DATA_WIDTH(AXI_DATA_WIDTH), .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_ID_WIDTH(AXI_ID_WIDTH), .AXI_USER_WIDTH(AXI_USER_WIDTH)) northcape_cache_axi_out(.clk_i(clk_i),.rst_ni(rst_ni));

NorthcapeCMTInterface#(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) cmt_interface(.clk_i(clk_i));

assign cmt_interface.table_size_clog2 = cmt_table_size_clog2;
assign cmt_interface.cmt_base = cmt_base;
assign cmt_interface.reset_done = cmt_reset_done;
assign cmt_interface.need_flush_data_caches = cmt_need_flush_data_caches;
assign cmt_interface.wrote_any_capability = cmt_wrote_any_capability;
assign cmt_interface.written_capability = cmt_written_capability;

NorthcapeCapabilityCacheInterfaceResolver resolver_interface (.clk_i(clk_i));

assign resolver_interface.request_valid = resolver_interface_request_valid;
assign resolver_interface.request_capability_id = resolver_interface_request_capability_id;
assign resolver_interface.request_capability_tag = resolver_interface_request_capability_tag;
assign resolver_interface.request_close_speculation_window = resolver_interface_request_close_speculation_window;
assign resolver_interface.response_ready = resolver_interface_response_ready;
assign resolver_interface.request_cache_flush = resolver_interface_request_flush;
assign resolver_interface.request_is_recursion = resolver_interface_request_is_recursion;

assign resolver_interface_response_cmt_entry = resolver_interface.response_cmt_entry;
assign resolver_interface_response_err = resolver_interface.response_err;
assign resolver_interface_response_valid = resolver_interface.response_valid;
assign resolver_interface_response_cache_hit = resolver_interface.response_cache_hit;

NorthcapeCapabilityCacheInterfaceOps ops_interface (.clk_i(clk_i));

assign ops_interface.request_valid = ops_interface_request_valid;
assign ops_interface.request_capability_id = ops_interface_request_capability_id;
assign ops_interface.request_capability_tag = ops_interface_request_capability_tag;
assign ops_interface.is_write = ops_interface_is_write;
assign ops_interface.write_request_capability = ops_interface_write_request_capability;
assign ops_interface.write_request_flush = ops_interface_write_request_flush;
assign ops_interface.request_is_uncacheable = ops_interface_request_is_uncacheable;

assign ops_interface_response_cmt_entry = ops_interface.response_cmt_entry;
assign ops_interface_response_err = ops_interface.response_err;
assign ops_interface_response_valid = ops_interface.response_valid;



function static northcape_capability_cache_common_cache_type_t map_cache_type(input int CACHE_TYPE);
  case(CACHE_TYPE)
    1: return NORTHCAPE_CAPABILITY_TYPE_WT_DIRECT_FF;
    2: return NORTHCAPE_CAPABILITY_TYPE_WT_FULLY_ASSOC_FF;
    3: return NORTHCAPE_CAPABILITY_TYPE_WT_DIRECT_BRAM;
    4: return NORTHCAPE_CAPABILITY_TYPE_WT_N_ASSOC_BRAM;
    default: return NORTHCAPE_CAPABILITY_TYPE_COMMON_NO_CACHE;
  endcase
endfunction

localparam northcape_capability_cache_common_cache_type_t CACHE_TYPE_ENUM = map_cache_type(CACHE_TYPE);


northcape_capability_cache#(
    .HASH_TYPE(HASH_TYPE_IDENTITY),
    .CACHE_TYPE(CACHE_TYPE_ENUM),
    .ASSOCIATIVITY(ASSOCIATIVITY),
    .NUM_ENTRIES(NUM_ENTRIES),
    .SUPPORT_SPECULATIVE_RESOLVER_LOADS(SUPPORT_SPECULATIVE_RESOLVER_LOADS),
    .KEEP_TOP_CMT_ENTRIES_ONLY(KEEP_TOP_CMT_ENTRIES_ONLY),
    .STORE_BUFFER_SIZE(STORE_BUFFER_SIZE),

    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),
    .DEBUG_ILA(DEBUG_ILA)
  )
  i_northcape_capability_cache (
      .clk_i(clk_i),
      .rst_ni(rst_ni),

      
      .axi_master(northcape_cache_axi_out),
      .resolver_port(resolver_interface),
      .ops_port(ops_interface),
      
      .cmt_interface(cmt_interface),

      .resolver_port_miss_o(resolver_port_miss_o),
      .resolver_spec_fail_o(resolver_spec_fail_o),
      .ops_port_miss_o(ops_port_miss_o),
      .missunit_stall_o(missunit_stall_o),
      .ops_write_stall_o(ops_write_stall_o)
  );

`NORTHCAPE_MAP_XILINX_AXI_INTERFACES_OUT(northcape_cache_axi_out,m_cache_out)

generate
  
  if(CAPABILITY_ID_WIDTH < northcape_types::NORTHCAPE_CAPABILITY_ID_WIDTH || TAG_ID_WIDTH < northcape_types::NORTHCAPE_CAPABILITY_TAG_WIDTH || CMT_ENTRY_WIDTH < $bits(northcape_types::northcape_cmt_entry_t))
  begin
    $error("A size is too small!");
    $fatal(1);
  end
  
endgenerate

endmodule
