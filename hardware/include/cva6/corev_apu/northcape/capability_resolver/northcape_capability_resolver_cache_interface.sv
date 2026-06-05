/**
  * Receives a validation request in AXI stream.
  * Performs a lookup on the request in the capability cache.
  * Forwards a capability_resolver_validate_request_with_entry_tdata_t.
  */
module northcape_capability_resolver_cache_interface #(
    parameter bit PIPELINE_STAGE_ENABLED = 1'b0
) (
    // requests from the previous pipeline stage, originate in MMU
    Axis5.RECEIVER validate_request,
    // requests from the parser - always take priority
    Axis5.RECEIVER validate_request_recursion,
    Axis5.TRANSMITTER validate_request_entry,
    // need to flush capability cache on failure, reported by resolver
    input logic request_cache_flush_i,
    // need to close the speculation window on successful end of recursion
    input logic request_close_speculation_window_i,

    input logic clk_i,
    input logic rst_ni,

    NorthcapeCapabilityCacheInterfaceResolver.RESOLVER_INTERFACE cache_interface,
    NorthcapeCMTInterface.CONSUMER cmt_interface
);
  import northcape_types::*;
  import northcape_capability_resolver_common::capability_resolver_validate_request_with_entry_tdata_t;
  `include "northcape_unread.vh"

axis_validate_request_tdata_t tdata_in;
  capability_resolver_validate_request_with_entry_tdata_t tdata_out;

  assign tdata_in = validate_request_recursion.tvalid ? validate_request_recursion.tdata : validate_request.tdata;

  // if the parser is not ready (should happen only on occasion), we need to stall accepting the transmission
  assign validate_request.tready = cache_interface.response_valid && validate_request_entry.tready && !validate_request_recursion.tvalid &&  (~PIPELINE_STAGE_ENABLED || validate_request_entry.tvalid);
  // no need to check tready for the next stage: assume MMUs are always ready, accepting the recursion request will ready the next pipeline stage
  assign validate_request_recursion.tready = cache_interface.response_valid &&  (~PIPELINE_STAGE_ENABLED || validate_request_entry.tvalid);

  assign validate_request_entry.tdata = tdata_out;

  // defaults
  assign validate_request_entry.tstrb = '1;
  assign validate_request_entry.tkeep = '1;
  assign validate_request_entry.tlast = 1;
  assign validate_request_entry.twakeup = 1;


  always_comb begin : cacheRequestLogic
    cache_interface.request_capability_id = tdata_in.address;
    cache_interface.request_capability_tag = tdata_in.tag;

    cache_interface.response_ready = validate_request_entry.tready &&  (~PIPELINE_STAGE_ENABLED || validate_request_entry.tvalid);
    cache_interface.request_valid = (validate_request.tvalid || validate_request_recursion.tvalid) && cmt_interface.reset_done;
    cache_interface.request_is_recursion = validate_request_recursion.tvalid;
    cache_interface.request_cache_flush = request_cache_flush_i;
    cache_interface.request_close_speculation_window = request_close_speculation_window_i;
  end : cacheRequestLogic



  generate
    if (PIPELINE_STAGE_ENABLED) begin : gen_pipeline_stage

      $error("TODO not supported!");

      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : outputPipe
        if (~rst_ni) begin
          tdata_out.capability_id <= '0;
          tdata_out.tag <= '0;
          tdata_out.access_type <= READ;
          tdata_out.device_id <= '0;
          tdata_out.task_id <= '0;
          // all-zeros CMT entry is guaranteed to be invalid
          tdata_out.cmt_entry <= '0;
          tdata_out.flags <= '0;
          tdata_out.original_address <= '0;
          tdata_out.original_segment_length <= '0;
          tdata_out.original_permission_tid_match <= '0;
          tdata_out.original_permissions <= '0;
          tdata_out.lock_key <= '0;
          tdata_out.restriction <= '0;
          tdata_out.restriction_type <= NORTHCAPE_RESTRICTIONS_NONE;
          tdata_out.response_cache_hit <= '0;
          tdata_out.error_code <= NORTHCAPE_RESOLVE_NO_ERROR;

          validate_request_entry.tvalid <= 1'b0;
          validate_request_entry.tid <= '0;
          validate_request_entry.tdest <= '0;
          validate_request_entry.tuser <= '0;
        end else begin
          // make sure we only hold this for 1 cycle
          if(cache_interface.response_valid && !(validate_request_entry.tready && validate_request_entry.tvalid))
          begin
            tdata_out.capability_id <= tdata_in.address;
            tdata_out.tag <= tdata_in.tag;
            tdata_out.access_type <= tdata_in.access_type;
            tdata_out.device_id <= tdata_in.device_id;
            tdata_out.task_id <= tdata_in.task_id;
            // all-zeros CMT entry is guaranteed to be invalid
            tdata_out.cmt_entry <= cache_interface.response_err ? '0 : cache_interface.response_cmt_entry;
            tdata_out.flags <= tdata_in.flags;
            tdata_out.original_address <= tdata_in.original_address;
            tdata_out.original_segment_length <= tdata_in.original_segment_length;
            tdata_out.original_permission_tid_match <= tdata_in.original_permission_tid_match;
            tdata_out.original_permissions <= tdata_in.original_permissions;
            tdata_out.lock_key <= tdata_in.lock_key;
            tdata_out.restriction <= tdata_in.restriction;
            tdata_out.restriction_type <= tdata_in.restriction_type;
            tdata_out.response_cache_hit <= cache_interface.response_cache_hit;
            tdata_out.error_code <= cache_interface.response_err ? NORTHCAPE_RESOLVE_ERROR_BUS : NORTHCAPE_RESOLVE_NO_ERROR;


            validate_request_entry.tvalid <= cache_interface.response_valid;
            validate_request_entry.tid <= validate_request_recursion.tvalid ?  validate_request_recursion.tid : validate_request.tid;
            validate_request_entry.tdest <= validate_request_recursion.tvalid ? validate_request_recursion.tdest : validate_request.tdest;
            validate_request_entry.tuser <= validate_request_recursion.tvalid ? validate_request_recursion.tuser : validate_request.tuser;
          end else begin
            validate_request_entry.tvalid <= 1'b0;
          end
        end
      end : outputPipe
    end : gen_pipeline_stage
    else begin : gen_no_pipeline

      // need tvalid + tready for transfer, but cannot take tvalid down once it was raised
      // cache will hold data and tvalid
      assign validate_request_entry.tvalid = cache_interface.response_valid;

      assign validate_request_entry.tid = validate_request_recursion.tvalid ?  validate_request_recursion.tid : validate_request.tid;
      assign validate_request_entry.tdest = validate_request_recursion.tvalid ? validate_request_recursion.tdest : validate_request.tdest;
      assign validate_request_entry.tuser = validate_request_recursion.tvalid ? validate_request_recursion.tuser : validate_request.tuser;
      always_comb begin : outputLogic
        tdata_out.capability_id = tdata_in.address;
        tdata_out.tag = tdata_in.tag;
        tdata_out.access_type = tdata_in.access_type;
        tdata_out.device_id = tdata_in.device_id;
        tdata_out.task_id = tdata_in.task_id;
        // all-zeros CMT entry is guaranteed to be invalid
        tdata_out.cmt_entry = cache_interface.response_err ? '0 : cache_interface.response_cmt_entry;
        tdata_out.flags = tdata_in.flags;
        tdata_out.original_address = tdata_in.original_address;
        tdata_out.original_segment_length = tdata_in.original_segment_length;
        tdata_out.original_permission_tid_match = tdata_in.original_permission_tid_match;
        tdata_out.original_permissions = tdata_in.original_permissions;
        tdata_out.lock_key = tdata_in.lock_key;
        tdata_out.restriction = tdata_in.restriction;
        tdata_out.restriction_type = tdata_in.restriction_type;
        tdata_out.response_cache_hit = cache_interface.response_cache_hit;
        tdata_out.error_code = cache_interface.response_err ? NORTHCAPE_RESOLVE_ERROR_BUS : NORTHCAPE_RESOLVE_NO_ERROR;
      end : outputLogic

      `NORTHCAPE_UNREAD(clk_i);
      `NORTHCAPE_UNREAD(rst_ni);
    end : gen_no_pipeline
  endgenerate



  `NORTHCAPE_UNREAD(validate_request.clk_i);
  `NORTHCAPE_UNREAD(validate_request.rst_ni);
  `NORTHCAPE_UNREAD(validate_request.tdata);
  `NORTHCAPE_UNREAD(validate_request.tstrb);
  `NORTHCAPE_UNREAD(validate_request.tkeep);
  `NORTHCAPE_UNREAD(validate_request.tdest);
  `NORTHCAPE_UNREAD(validate_request.tid);
  `NORTHCAPE_UNREAD(validate_request.tlast);
  `NORTHCAPE_UNREAD(validate_request.tuser);
  `NORTHCAPE_UNREAD(validate_request.twakeup);

  `NORTHCAPE_UNREAD(validate_request_recursion.clk_i);
  `NORTHCAPE_UNREAD(validate_request_recursion.rst_ni);
  `NORTHCAPE_UNREAD(validate_request_recursion.tdata);
  `NORTHCAPE_UNREAD(validate_request_recursion.tstrb);
  `NORTHCAPE_UNREAD(validate_request_recursion.tkeep);
  `NORTHCAPE_UNREAD(validate_request_recursion.tdest);
  `NORTHCAPE_UNREAD(validate_request_recursion.tid);
  `NORTHCAPE_UNREAD(validate_request_recursion.tlast);
  `NORTHCAPE_UNREAD(validate_request_recursion.tuser);
  `NORTHCAPE_UNREAD(validate_request_recursion.twakeup);

  `NORTHCAPE_UNREAD(validate_request_entry.clk_i);
  `NORTHCAPE_UNREAD(validate_request_entry.rst_ni);

  `NORTHCAPE_UNREAD(cache_interface.clk_i);

  `NORTHCAPE_UNREAD(cmt_interface.table_size_clog2);
  `NORTHCAPE_UNREAD(cmt_interface.cmt_base);
  `NORTHCAPE_UNREAD(cmt_interface.need_flush_data_caches);
  `NORTHCAPE_UNREAD(cmt_interface.wrote_any_capability);
  `NORTHCAPE_UNREAD(cmt_interface.written_capability);
  `NORTHCAPE_UNREAD(cmt_interface.clk_i);

endmodule
