/**
  * Top-level module for the capability resolver.
  * The capability resolver receives a validation request from an MMU,
  * performs a lookup of the entry in the CMT and returns a validation
  * response to the same MMU (or recurses to itself).
  * Implementation: pipeline hash - lookup - parser modules.
  */

module northcape_capability_resolver #(
    parameter int HASH_TYPE = -1,

    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH   = -1,
    parameter AXI_USER_WIDTH = -1,

    parameter bit HAS_CACHE_INTERFACE = 1'b0,

    // size of the FIFO that buffers requests
    // indicates number of max parallel requests
    // MUST BE big enough such that all MMUs' max number of inflight requests
    // (currently 1) as well as one recursion request can be buffered
    // otherwise deadlock possible when waiting for itself in recursion!
    parameter FIFO_DEPTH_CLOG_2 = -1,


    parameter MAX_AXI_TRANSACTIONS = -1,

    // device ID to be used for requesting recursion
    parameter northcape_types::device_id_t CAPABILITY_RESOLVER_RECURSION_DEVICE_ID = -1,

    // in conjunction with the capability cache, allows the resolver to skip recursive capability resolution on cache hit
    parameter bit CACHE_RECURSION_SKIP = 1'b0,

    // pipeline stage between validate request and first processing stage
    parameter bit INPUT_PIPELINE_STAGE_ENABLED  = 1'b1,
    // pipeline stage between lookup/cache output and parser
    parameter bit PARSER_PIPELINE_STAGE_ENABLED = 1'b0,
    // pipeline stage between parser and output response
    parameter bit OUTPUT_PIPELINE_STAGE_ENABLED = 1'b1,

    parameter bit DEBUG_ILA = 1'b0
) (
    input logic clk_i,
    input logic rst_ni,

    // validate request as received by MMU
    Axis5.RECEIVER validate_request,

    // for memory lookups
    Axi5.FROM axi_master,

    NorthcapeCapabilityCacheInterfaceResolver.RESOLVER_INTERFACE cache_interface,

    // validate response to MMU
    Axis5.TRANSMITTER validate_response,

    // validate request for recursion
    Axis5.TRANSMITTER validate_request_recursion,

    // current capability metadata (from operations module)
    NorthcapeCMTInterface.CONSUMER cmt_interface
);
  import northcape_capability_resolver_common::*;
  import northcape_types::*;
  import axi5::*;

  `include "northcape_unread.vh"

  logic request_cache_flush;
  logic request_close_speculation_window;

  Axis5 #(
      .AXIS_TDATA_WIDTH($bits(capability_resolver_validate_request_with_slot_tdata_t)),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_REQUEST_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH)
  ) request_with_slot (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  Axis5 #(
      .AXIS_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_REQUEST_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH)
  ) validate_request_pipelined (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  Axis5 #(
      .AXIS_TDATA_WIDTH($bits(capability_resolver_validate_request_with_entry_tdata_t)),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_REQUEST_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH)
  )
      request_with_entry (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      request_with_entry_pipelined (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );

  Axis5 #(
      .AXIS_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_RESPONSE_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH)
  ) validate_response_pipelined (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );


  axis5_pipeline_stage #(
      .AXIS_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_REQUEST_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH),

      .PIPELINE_STAGE_ENABLED(INPUT_PIPELINE_STAGE_ENABLED)
  ) i_input_pipeline (
      .port_in (validate_request),
      .port_out(validate_request_pipelined)
  );

  Axis5 #(
      .AXIS_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_REQUEST_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH)
  ) validate_request_recursion_internal (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );


  generate
    if (HAS_CACHE_INTERFACE == 1'b1) begin : gen_cache_pipeline
      /* TODO pipeline stage breaks because close/flush from parser will be one cycle too late */
      northcape_capability_resolver_cache_interface #(
          .PIPELINE_STAGE_ENABLED(1'b0)
      ) i_cache_interface (
          .validate_request(validate_request_pipelined),
          .validate_request_entry(request_with_entry),
          .validate_request_recursion(validate_request_recursion_internal),
          .cache_interface(cache_interface),
          .cmt_interface(cmt_interface),
          .request_cache_flush_i(request_cache_flush),
          .request_close_speculation_window_i(request_close_speculation_window),

          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );

      northcape_capability_resolver_parser #(
          .CAPABILITY_RESOLVER_RECURSION_DEVICE_ID(CAPABILITY_RESOLVER_RECURSION_DEVICE_ID),
          .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
          .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
          .CACHE_RECURSION_SKIP(CACHE_RECURSION_SKIP)
      ) i_parser (
          .clk_i (clk_i),
          .rst_ni(rst_ni),

          .validate_request_entry(request_with_entry_pipelined),
          .validate_request_recursion(validate_request_recursion_internal),
          .validate_response(validate_response_pipelined),
          .request_cache_flush_o(request_cache_flush),
          .request_close_speculation_window_o(request_close_speculation_window)
      );

      // interface not used
      assign axi_master.arid = '0;
      assign axi_master.araddr = '0;
      assign axi_master.arlen = '0;
      assign axi_master.arsize = '0;
      assign axi_master.arburst = INCR;
      assign axi_master.arlock = 1'b0;
      assign axi_master.arcache = '0;
      assign axi_master.arprot = '0;
      assign axi_master.arqos = '0;
      assign axi_master.arregion = '0;
      assign axi_master.aruser = '0;
      assign axi_master.arvalid = '0;

      assign axi_master.awid = '0;
      assign axi_master.awaddr = '0;
      assign axi_master.awlen = '0;
      assign axi_master.awsize = '0;
      assign axi_master.awburst = INCR;
      assign axi_master.awlock = 1'b0;
      assign axi_master.awcache = '0;
      assign axi_master.awprot = '0;
      assign axi_master.awqos = '0;
      assign axi_master.awregion = '0;
      assign axi_master.awuser = '0;
      assign axi_master.awvalid = '0;
      assign axi_master.atop_type = ATOMIC_NONE;
      assign axi_master.atop_subtype = '0;

      assign axi_master.rready = '0;

      assign axi_master.wid = '0;
      assign axi_master.wdata = '0;
      assign axi_master.wstrb = '0;
      assign axi_master.wlast = 1'b0;
      assign axi_master.wuser = '0;
      assign axi_master.wvalid = 1'b0;

      assign axi_master.bready = '0;

      `NORTHCAPE_UNREAD(axi_master.arready);

      `NORTHCAPE_UNREAD(axi_master.awready);

      `NORTHCAPE_UNREAD(axi_master.wready);

      `NORTHCAPE_UNREAD(axi_master.rvalid);
      `NORTHCAPE_UNREAD(axi_master.rdata);
      `NORTHCAPE_UNREAD(axi_master.rresp);
      `NORTHCAPE_UNREAD(axi_master.rlast);
      `NORTHCAPE_UNREAD(axi_master.ruser);
      `NORTHCAPE_UNREAD(axi_master.rid);

      `NORTHCAPE_UNREAD(axi_master.bvalid);
      `NORTHCAPE_UNREAD(axi_master.bresp);
      `NORTHCAPE_UNREAD(axi_master.bid);
      `NORTHCAPE_UNREAD(axi_master.buser);

      `NORTHCAPE_UNREAD(axi_master.clk_i);
      `NORTHCAPE_UNREAD(axi_master.rst_ni);

      // recursion handled internally - interface not used
      assign validate_request_recursion.tvalid = 1'b0;
      assign validate_request_recursion.tdata = '0;
      assign validate_request_recursion.tid = '0;
      assign validate_request_recursion.tdest = '0;
      assign validate_request_recursion.tuser = '0;
      assign validate_request_recursion.tstrb = '0;
      assign validate_request_recursion.tkeep = '0;
      assign validate_request_recursion.tlast = '0;
      assign validate_request_recursion.twakeup = '0;

      `NORTHCAPE_UNREAD(validate_request_recursion.tready);
      `NORTHCAPE_UNREAD(validate_request_recursion.clk_i);
      `NORTHCAPE_UNREAD(validate_request_recursion.rst_ni);
    end : gen_cache_pipeline
    else begin : gen_lookup_pipeline

      // pipeline stage one: compute slot in hash table
      northcape_capability_resolver_hash #(
          .HASH_TYPE(HASH_TYPE)
      ) i_resolver_hash (
          .clk_i(clk_i),
          .rst_ni(rst_ni),
          .validate_request(validate_request_pipelined),
          .validate_request_slot(request_with_slot),
          .cmt_interface(cmt_interface)
      );

      northcape_capability_resolver_lookup #(
          .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
          .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
          .AXI_ID_WIDTH(AXI_ID_WIDTH),
          .AXI_USER_WIDTH(AXI_USER_WIDTH),
          .FIFO_DEPTH_CLOG_2(FIFO_DEPTH_CLOG_2),
          .MAX_AXI_TRANSACTIONS(MAX_AXI_TRANSACTIONS)
      ) i_lookup (
          .clk_i (clk_i),
          .rst_ni(rst_ni),

          .validate_request_slot(request_with_slot),
          .axi_master(axi_master),
          .validate_request_entry(request_with_entry),

          .cmt_interface(cmt_interface)
      );
      `NORTHCAPE_UNREAD(request_cache_flush);

      northcape_capability_resolver_parser #(
          .CAPABILITY_RESOLVER_RECURSION_DEVICE_ID(CAPABILITY_RESOLVER_RECURSION_DEVICE_ID),
          .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
          .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
          .CACHE_RECURSION_SKIP(CACHE_RECURSION_SKIP)
      ) i_parser (
          .clk_i (clk_i),
          .rst_ni(rst_ni),

          .validate_request_entry(request_with_entry_pipelined),
          .validate_request_recursion(validate_request_recursion),
          .validate_response(validate_response_pipelined),
          .request_cache_flush_o(request_cache_flush),
          .request_close_speculation_window_o(request_close_speculation_window)
      );
    end : gen_lookup_pipeline
  endgenerate
  // cache interface caches internally
  axis5_pipeline_stage #(
      .AXIS_TDATA_WIDTH($bits(capability_resolver_validate_request_with_entry_tdata_t)),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_REQUEST_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH),

      .PIPELINE_STAGE_ENABLED(PARSER_PIPELINE_STAGE_ENABLED && !HAS_CACHE_INTERFACE)
  ) i_parser_pipeline (
      .port_in (request_with_entry),
      .port_out(request_with_entry_pipelined)
  );

  axis5_pipeline_stage #(
      .AXIS_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_RESPONSE_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH),

      .PIPELINE_STAGE_ENABLED(OUTPUT_PIPELINE_STAGE_ENABLED)
  ) i_output_pipeline (
      .port_in (validate_response_pipelined),
      .port_out(validate_response)
  );


  `NORTHCAPE_UNREAD(cmt_interface.need_flush_data_caches);
  `NORTHCAPE_UNREAD(cmt_interface.wrote_any_capability);
  `NORTHCAPE_UNREAD(cmt_interface.written_capability);

  generate
    if (PARSER_PIPELINE_STAGE_ENABLED && HAS_CACHE_INTERFACE) begin
      $error("Parser pipeline stage and cache interface are NOT supported!");
    end
    if (DEBUG_ILA) begin : gen_debug_ila
      capability_resolver_validate_request_with_entry_tdata_t request_tdata;
      axis_validate_response_tdata_t response_tdata;

      assign request_tdata  = request_with_entry_pipelined.tdata;
      assign response_tdata = validate_response_pipelined.tdata;

      northcape_capability_resolver_ila i_ila (
          .clk(clk_i),
          .probe0(validate_request.tvalid),  // 1 bit
          .probe1(validate_request.tready),  // 1 bit
          .probe2(validate_request_pipelined.tvalid),  // 1 bit
          .probe3(validate_request_pipelined.tready),  // 1 bit
          .probe4(request_cache_flush),  // 1 bit
          .probe5(cache_interface.response_cache_hit),  // 1 bit
          .probe6(request_with_entry.tvalid),  // 1 bit
          .probe7(request_with_entry.tready),  // 1 bit
          .probe8(request_with_entry_pipelined.tvalid),  // 1 bit
          .probe9(request_with_entry_pipelined.tready),  // 1 bit
          .probe10(validate_response_pipelined.tvalid),  // 1 bit
          .probe11(validate_response_pipelined.tready),  // 1 bit
          .probe12(validate_response.tvalid),  // 1 bit
          .probe13(validate_response.tready),  // 1 bit
          .probe14(cache_interface.request_valid),  // 1 bit
          .probe15(cache_interface.response_valid),  // 1 bit
          .probe16(validate_request_recursion_internal.tvalid),  // 1 bit
          .probe17(validate_request_recursion_internal.tready),  // 1 bit
          .probe18(request_tdata.capability_id),  // 38 bits
          .probe19(request_tdata.cmt_entry),  // 256 bits
          .probe20(response_tdata),  // 144 bits
          .probe21(cache_interface.response_err)  // 1 bit
      );
    end : gen_debug_ila

  endgenerate

endmodule
