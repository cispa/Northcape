`include "ariane_xlnx_mapper.svh"
`include "northcape_xilinx_wrapper.vh"
module northcape_cap_resolver_wrapper
#(
    parameter TDATA_WIDTH=-1,
    parameter TID_WIDTH=-1,
    parameter TDEST_WIDTH=-1,
    parameter TUSER_WIDTH = -1,

    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,

    parameter CAPABILITY_ID_WIDTH=-1,
    parameter TAG_ID_WIDTH=-1,
    parameter CMT_ENTRY_WIDTH=-1,

    parameter bit CACHE_RECURSION_SKIP = 1'b0,

    // pipeline stage between validate request and first processing stage
    parameter bit INPUT_PIPELINE_STAGE_ENABLED  = 1'b1,
    // pipeline stage between lookup/cache output and parser
    parameter bit PARSER_PIPELINE_STAGE_ENABLED = 1'b1,
    // pipeline stage between parser and output response
    parameter bit OUTPUT_PIPELINE_STAGE_ENABLED = 1'b1,
    
    parameter bit DEBUG_ILA = 1'b0
)
(
    input logic clk_i,
    input logic rst_ni,

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

    
    // cache interface
    output logic resolver_interface_request_valid,
    output logic [CAPABILITY_ID_WIDTH-1:0] resolver_interface_request_capability_id,
    output logic [TAG_ID_WIDTH-1:0] resolver_interface_request_capability_tag,
    output logic resolver_interface_request_close_speculation_window,
    output logic resolver_interface_response_ready,
    output logic resolver_interface_request_flush,
    output logic resolver_interface_request_is_recursion,
    input logic resolver_interface_response_valid,
    input logic resolver_interface_response_err,
    input logic [CMT_ENTRY_WIDTH-1:0] resolver_interface_response_cmt_entry,
    input logic resolver_interface_response_cache_hit,

    // to CMT interface
    input int unsigned cmt_table_size_clog2,
    input wire [AXI_ADDR_WIDTH - 1 : 0] cmt_base,
    input wire cmt_reset_done,
    input wire cmt_need_flush_data_caches,
    input wire cmt_wrote_any_capability,
    input wire [CAPABILITY_ID_WIDTH-1:0] cmt_written_capability
);

import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
import axi5::*;
import northcape_types::*;
`include "northcape_unread.vh"

localparam NUMBER_PORTS = 6;

Axis5#(.AXIS_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH), .AXIS_TID_WIDTH(AXIS_VALIDATE_REQUEST_TID_WIDTH), .AXIS_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH), .AXIS_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH)) northcape_axis_validate_request_in[NUMBER_PORTS](.clk_i(clk_i),.rst_ni(rst_ni)), northcape_axis_validate_request(.clk_i(clk_i),.rst_ni(rst_ni)), northcape_axis_validate_request_recursion(.clk_i(clk_i),.rst_ni(rst_ni));
Axis5#(.AXIS_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH), .AXIS_TID_WIDTH(AXIS_VALIDATE_RESPONSE_TID_WIDTH), .AXIS_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH), .AXIS_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH)) northcape_axis_validate_response_out[NUMBER_PORTS](.clk_i(clk_i),.rst_ni(rst_ni)), northcape_axis_validate_response(.clk_i(clk_i),.rst_ni(rst_ni));

Axi5#(.AXI_DATA_WIDTH(AXI_DATA_WIDTH), .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_ID_WIDTH(AXI_ID_WIDTH), .AXI_USER_WIDTH(AXI_USER_WIDTH)) northcape_resolver_axi_out(.clk_i(clk_i),.rst_ni(rst_ni));

NorthcapeCMTInterface#(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) cmt_interface(.clk_i(clk_i));

assign cmt_interface.table_size_clog2 = cmt_table_size_clog2;
assign cmt_interface.cmt_base = cmt_base;
assign cmt_interface.reset_done = cmt_reset_done;
assign cmt_interface.need_flush_data_caches = cmt_need_flush_data_caches;
assign cmt_interface.wrote_any_capability = cmt_wrote_any_capability;
assign cmt_interface.written_capability = cmt_written_capability;

NorthcapeCapabilityCacheInterfaceResolver resolver_interface (.clk_i(clk_i));
// not used here
assign resolver_interface_request_valid = resolver_interface.request_valid;
assign resolver_interface_request_capability_id = resolver_interface.request_capability_id;
assign resolver_interface_request_capability_tag = resolver_interface.request_capability_tag;
assign resolver_interface_request_close_speculation_window = resolver_interface.request_close_speculation_window;
assign resolver_interface_response_ready = resolver_interface.response_ready;
assign resolver_interface_request_flush = resolver_interface.request_cache_flush;
assign resolver_interface_request_is_recursion = resolver_interface.request_is_recursion;

assign resolver_interface.response_valid = resolver_interface_response_valid;
assign resolver_interface.response_err = resolver_interface_response_err;
assign resolver_interface.response_cmt_entry = resolver_interface_response_cmt_entry;
assign resolver_interface.response_cache_hit = resolver_interface_response_cache_hit;

// input ports + 1 for recursion
Axis5Mux#(
    .NUMBER_IN_PORTS(NUMBER_PORTS),
    .ARBITRATION_TYPE(axis5_mux::ARBITRATION_RR)
  ) i_mux(
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .in_ports(northcape_axis_validate_request_in),
    .out_port(northcape_axis_validate_request.TRANSMITTER)
  );

northcape_capability_resolver#(
    .HASH_TYPE(HASH_TYPE_IDENTITY),
    .HAS_CACHE_INTERFACE(1'b1),

    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),

    .CACHE_RECURSION_SKIP(CACHE_RECURSION_SKIP),

    .INPUT_PIPELINE_STAGE_ENABLED(INPUT_PIPELINE_STAGE_ENABLED),
    .PARSER_PIPELINE_STAGE_ENABLED(PARSER_PIPELINE_STAGE_ENABLED),
    .OUTPUT_PIPELINE_STAGE_ENABLED(OUTPUT_PIPELINE_STAGE_ENABLED),
    .DEBUG_ILA(DEBUG_ILA)
  )
  i_northcape_capability_resolver (
      .clk_i(clk_i),
      .rst_ni(rst_ni),

      .cache_interface(resolver_interface),

      .validate_request(northcape_axis_validate_request.RECEIVER),
      .axi_master(northcape_resolver_axi_out),
      .validate_response(northcape_axis_validate_response.TRANSMITTER),
      .validate_request_recursion(northcape_axis_validate_request_recursion),
      
      .cmt_interface(cmt_interface)
  );

  Axis5Demux#(
    .NUMBER_OUT_PORTS(NUMBER_PORTS)
  ) i_demux(
    .in_port(northcape_axis_validate_response.RECEIVER),
    .out_ports(northcape_axis_validate_response_out)
  );

  `NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(northcape_axis_validate_response_out[0], axis_validate_response_0)
  `NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(northcape_axis_validate_request_in[0], axis_validate_request_0)
  `NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(northcape_axis_validate_response_out[1], axis_validate_response_1)
  `NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(northcape_axis_validate_request_in[1], axis_validate_request_1)
  `NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(northcape_axis_validate_response_out[2], axis_validate_response_2)
  `NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(northcape_axis_validate_request_in[2], axis_validate_request_2)
  `NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(northcape_axis_validate_response_out[3], axis_validate_response_3)
  `NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(northcape_axis_validate_request_in[3], axis_validate_request_3)
  `NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(northcape_axis_validate_response_out[4], axis_validate_response_4)
  `NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(northcape_axis_validate_request_in[4], axis_validate_request_4)
  `NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(northcape_axis_validate_response_out[5], axis_validate_response_5)
  `NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(northcape_axis_validate_request_in[5], axis_validate_request_5)

  // this interface is completely unused in favor of cache interface
  assign northcape_resolver_axi_out.arready = 1'b0;
  assign northcape_resolver_axi_out.awready = 1'b0;
  assign northcape_resolver_axi_out.rid = '0;
  assign northcape_resolver_axi_out.rvalid = 1'b0;
  assign northcape_resolver_axi_out.rdata = '0;
  assign northcape_resolver_axi_out.ruser = '0;
  assign northcape_resolver_axi_out.rresp = OKAY;
  assign northcape_resolver_axi_out.rlast = 1'b0;
  assign northcape_resolver_axi_out.wready = 1'b0;
  assign northcape_resolver_axi_out.bvalid = 1'b0;
  assign northcape_resolver_axi_out.bresp = OKAY;
  assign northcape_resolver_axi_out.bid = '0;
  assign northcape_resolver_axi_out.buser = '0;

  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.arid);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.araddr);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.arlen);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.arsize);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.arburst);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.arlock);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.arcache);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.arprot);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.arqos);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.arregion);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.aruser);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.arvalid);

  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.awid);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.awaddr);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.awlen);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.awsize);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.awburst);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.awlock);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.awcache);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.awprot);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.awqos);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.awregion);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.awuser);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.awvalid);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.atop_type);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.atop_subtype);

  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.wid);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.wdata);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.wstrb);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.wlast);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.wuser);
  `NORTHCAPE_UNREAD(northcape_resolver_axi_out.wvalid);

  // tdest not used here
  `NORTHCAPE_UNREAD(axis_validate_request_0_tdest);
  `NORTHCAPE_UNREAD(axis_validate_request_1_tdest);
  `NORTHCAPE_UNREAD(axis_validate_request_2_tdest);
  `NORTHCAPE_UNREAD(axis_validate_request_3_tdest);
  `NORTHCAPE_UNREAD(axis_validate_request_4_tdest);
  `NORTHCAPE_UNREAD(axis_validate_request_5_tdest);

  // some bytes of "padding"
  `NORTHCAPE_UNREAD(axis_validate_request_0_tdata);
  `NORTHCAPE_UNREAD(axis_validate_request_1_tdata);
  `NORTHCAPE_UNREAD(axis_validate_request_2_tdata);
  `NORTHCAPE_UNREAD(axis_validate_request_3_tdata);
  `NORTHCAPE_UNREAD(axis_validate_request_4_tdata);
  `NORTHCAPE_UNREAD(axis_validate_request_5_tdata);

  `NORTHCAPE_UNREAD(axis_validate_request_0_tstrb);
  `NORTHCAPE_UNREAD(axis_validate_request_1_tstrb);
  `NORTHCAPE_UNREAD(axis_validate_request_2_tstrb);
  `NORTHCAPE_UNREAD(axis_validate_request_3_tstrb);
  `NORTHCAPE_UNREAD(axis_validate_request_4_tstrb);
  `NORTHCAPE_UNREAD(axis_validate_request_5_tstrb);

  `NORTHCAPE_UNREAD(axis_validate_request_0_tkeep);
  `NORTHCAPE_UNREAD(axis_validate_request_1_tkeep);
  `NORTHCAPE_UNREAD(axis_validate_request_2_tkeep);
  `NORTHCAPE_UNREAD(axis_validate_request_3_tkeep);
  `NORTHCAPE_UNREAD(axis_validate_request_4_tkeep);
  `NORTHCAPE_UNREAD(axis_validate_request_5_tkeep);

  // recursion is internal with cache interface
  `NORTHCAPE_UNREAD(northcape_axis_validate_request_recursion.tvalid);
  `NORTHCAPE_UNREAD(northcape_axis_validate_request_recursion.tdata);
  `NORTHCAPE_UNREAD(northcape_axis_validate_request_recursion.tid);
  `NORTHCAPE_UNREAD(northcape_axis_validate_request_recursion.tdest);
  `NORTHCAPE_UNREAD(northcape_axis_validate_request_recursion.tuser);
  `NORTHCAPE_UNREAD(northcape_axis_validate_request_recursion.tstrb);
  `NORTHCAPE_UNREAD(northcape_axis_validate_request_recursion.tkeep);
  `NORTHCAPE_UNREAD(northcape_axis_validate_request_recursion.tlast);
  `NORTHCAPE_UNREAD(northcape_axis_validate_request_recursion.twakeup);

  assign northcape_axis_validate_request_recursion.tready = 1'b0;

generate
  
  if(TDATA_WIDTH < AXIS_VALIDATE_REQUEST_TDATA_WIDTH || TDATA_WIDTH < AXIS_VALIDATE_RESPONSE_TDATA_WIDTH || TDEST_WIDTH < AXIS_VALIDATE_RESPONSE_TDEST_WIDTH)
  begin
    $error("TDATA or TDEST is too small!");
    $fatal(1);
  end

  if(CAPABILITY_ID_WIDTH < northcape_types::NORTHCAPE_CAPABILITY_ID_WIDTH || TAG_ID_WIDTH < NORTHCAPE_CAPABILITY_TAG_WIDTH || CMT_ENTRY_WIDTH < $bits(northcape_cmt_entry_t))
  begin
    $error("A size is too small!");
    $fatal(1);
  end
  
endgenerate

endmodule
