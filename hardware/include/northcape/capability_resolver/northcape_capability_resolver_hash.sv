/**
  * Receives a validation request in AXI stream.
  * Computes a hash (indicating capability metadata entry slot) and forwards the request.
  */

module northcape_capability_resolver_hash #(
    parameter int HASH_TYPE = -1
) (
    input logic clk_i,
    input logic rst_ni,
    // validate request as received by MMU
    Axis5.RECEIVER validate_request,
    // validate request with capability ID and slot
    Axis5.TRANSMITTER validate_request_slot,

    // capability metadata table (CMT) size at the moment
    NorthcapeCMTInterface.CONSUMER cmt_interface
);

  import northcape_types::*;
  import northcape_capability_resolver_common::*;
  `include "northcape_unread.vh"

  typedef NorthcapeCapabilityResolverHash#(.HASH_TYPE(HASH_TYPE)) hash_t;

  axis_validate_request_tdata_t tdata_in;
  capability_resolver_validate_request_with_slot_tdata_t tdata_out;


  always_comb begin : hashForwardLogic
    tdata_in = validate_request.tdata;

    tdata_out.capability_id = tdata_in.address;
    tdata_out.tag = tdata_in.tag;
    tdata_out.access_type = tdata_in.access_type;
    tdata_out.device_id = tdata_in.device_id;
    tdata_out.task_id = tdata_in.task_id;

    tdata_out.flags = tdata_in.flags;
    tdata_out.original_address = tdata_in.original_address;
    tdata_out.original_segment_length = tdata_in.original_segment_length;
    tdata_out.original_permission_tid_match = tdata_in.original_permission_tid_match;
    tdata_out.original_permissions = tdata_in.original_permissions;
    tdata_out.lock_key = tdata_in.lock_key;

    tdata_out.restriction = tdata_in.restriction;
    tdata_out.restriction_type = tdata_in.restriction_type;
    tdata_out.error_code = NORTHCAPE_RESOLVE_NO_ERROR;


    tdata_out.capability_slot =
        hash_t::compute_hash(tdata_in.address, cmt_interface.table_size_clog2);

    validate_request_slot.tdata = tdata_out;

    validate_request_slot.tvalid = validate_request.tvalid;
    validate_request_slot.tid = validate_request.tid;
    validate_request_slot.tdest = validate_request.tdest;
    validate_request_slot.tuser = validate_request.tuser;

    validate_request.tready = validate_request_slot.tready;

    // defaults
    validate_request_slot.tstrb = '1;
    validate_request_slot.tkeep = '1;
    validate_request_slot.tlast = 1;
    validate_request_slot.twakeup = 1;

  end : hashForwardLogic

  // simple format for the AXI-Stream interface
  // TODO currently broken in Xsim
`ifndef XSIM
  assert property (@(posedge clk_i) validate_request.tvalid |-> validate_request.tlast);
  assert property (@(posedge clk_i) validate_request.tvalid |-> validate_request.tstrb == '1);
  assert property (@(posedge clk_i) validate_request.tvalid |-> validate_request.tkeep == '1);
`endif

`ifndef VERILATOR
  property ValidRemainsHigh;
    @(posedge clk_i) disable iff(rst_ni == 0)
        (validate_request.tvalid && !validate_request.tready) |-> ##1 validate_request.tvalid;
  endproperty
  assert property (ValidRemainsHigh);
`endif

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

  `NORTHCAPE_UNREAD(validate_request_slot.clk_i);
  `NORTHCAPE_UNREAD(validate_request_slot.rst_ni);

  `NORTHCAPE_UNREAD(cmt_interface.clk_i);
  `NORTHCAPE_UNREAD(cmt_interface.cmt_base);
  `NORTHCAPE_UNREAD(cmt_interface.reset_done);
  `NORTHCAPE_UNREAD(cmt_interface.need_flush_data_caches);
  `NORTHCAPE_UNREAD(cmt_interface.wrote_any_capability);
  `NORTHCAPE_UNREAD(cmt_interface.written_capability);

  `NORTHCAPE_UNREAD(clk_i);
  `NORTHCAPE_UNREAD(rst_ni);

endmodule
