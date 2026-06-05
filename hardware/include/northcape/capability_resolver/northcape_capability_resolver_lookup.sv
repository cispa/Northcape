/**
  * Receives a capability_resolver_validate_request_with_slot_tdata_t and performs
  * the memory lookup to retrieve the corresponding CMT entry.
  * Forwards a capability_resolver_validate_request_with_entry_tdata_t.
  */
module northcape_capability_resolver_lookup #(
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,
    parameter FIFO_DEPTH_CLOG_2 = -1,
    parameter MAX_AXI_TRANSACTIONS = -1
) (
    input logic clk_i,
    input logic rst_ni,

    Axis5.RECEIVER validate_request_slot,
    Axis5.TRANSMITTER validate_request_entry,

    Axi5.FROM axi_master,

    // CMT metadata from operations module
    NorthcapeCMTInterface.CONSUMER cmt_interface
);

  import northcape_capability_resolver_common::*;
  import northcape_types::*;
  import axi5::*;
  `include "northcape_unread.vh"

  bit [AXI_ADDR_WIDTH - 1 : 0] resolved_cmt_addr;

  capability_resolver_validate_request_with_slot_tdata_t
      lookup_tdata_in, tdata_fifo_out_arready, tdata_fifo_out_rvalid;
  capability_resolver_validate_request_with_entry_tdata_t tdata_out;

  localparam FIFO_DATA_WIDTH = $bits(lookup_tdata_in);

  NorthcapeFifoInterface #(.FIFO_DATA_WIDTH(FIFO_DATA_WIDTH))
      fifo_interface_arready (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      fifo_interface_rvalid (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );

  // this FIFO buffers incoming requests from MMUs
  // it waits for the master to accept the read (arready)
  northcape_fifo #(
      .FIFO_DATA_WIDTH  (FIFO_DATA_WIDTH),
      .FIFO_DEPTH_CLOG_2(FIFO_DEPTH_CLOG_2)
  ) i_tdata_fifo (
      .fifo_interface(fifo_interface_arready)
  );

  // this FIFO buffers outstanding (i.e., accepted) reads
  // it waits for the read transaction to be completed (rvalid + rready)
  northcape_fifo #(
      .FIFO_DATA_WIDTH  (FIFO_DATA_WIDTH),
      .FIFO_DEPTH_CLOG_2($clog2(MAX_AXI_TRANSACTIONS))
  ) i_read_fifo (
      .fifo_interface(fifo_interface_rvalid)
  );



  always_comb begin : axiReadChanLogic
    if (rst_ni == 0) begin
      axi_master.araddr = '0;
      axi_master.arvalid = 0;
      validate_request_slot.tready = 0;
    end else begin
      axi_master.araddr = resolved_cmt_addr;
      // can forward request when: request valid OR at least one request in the arready FIFO
      // this saves one cycle latency in case the FIFO is empty
      // also need room to wait for rvalid for the next started transaction, so we check that the rvalid FIFO is not full as well
      // need to also wait for CMT reset to be done
      axi_master.arvalid = (validate_request_slot.tvalid || !fifo_interface_arready.is_empty) && !fifo_interface_rvalid.is_full && cmt_interface.reset_done;
      // request is accepted as soon as there is space in the arready FIFO
      validate_request_slot.tready = !fifo_interface_arready.is_full && cmt_interface.reset_done;
    end
  end : axiReadChanLogic

  // assume 1-cycle transfers
  assert property (@(posedge clk_i) axi_master.rvalid |-> axi_master.rlast);

  assign lookup_tdata_in = validate_request_slot.tdata;
  assign validate_request_entry.tdata = tdata_out;

  always_comb begin : fifoLogic
    // only save once
    // in case the FIFO is empty and we complete a handshake on the AXI bus, we can skip this FIFO entirely
    if (fifo_interface_arready.is_empty && axi_master.arvalid && axi_master.arready) begin
      fifo_interface_arready.enable_wr = 1'b0;
    end else begin
      fifo_interface_arready.enable_wr = !fifo_interface_arready.is_full && validate_request_slot.tvalid && cmt_interface.reset_done;
    end
    fifo_interface_arready.wr_data = lookup_tdata_in;

    // request accepted - can go into next fifo
    fifo_interface_arready.enable_rd = axi_master.arvalid && axi_master.arready && !fifo_interface_arready.is_empty;

    if (fifo_interface_arready.is_empty && axi_master.arvalid && axi_master.arready) begin
      // first FIFO was skipped completely
      tdata_fifo_out_arready = lookup_tdata_in;
    end else begin
      // fallthrough - read oldest FIFO data available immediately
      tdata_fifo_out_arready = fifo_interface_arready.rd_data;
    end

    // pipeline data into rvalid FIFO
    fifo_interface_rvalid.enable_wr = !fifo_interface_rvalid.is_full && axi_master.arvalid && axi_master.arready;
    fifo_interface_rvalid.wr_data = tdata_fifo_out_arready;

    // next pipeline stage has consumed the data - delete them
    fifo_interface_rvalid.enable_rd = axi_master.rvalid && axi_master.rready;

    // fallthrough - read data available immediately
    tdata_fifo_out_rvalid = fifo_interface_rvalid.rd_data;

  end : fifoLogic

  always_comb begin : axiDefaultValAssign
    // AR chan
    axi_master.arid = '0;
    // REQUIRED to fit into one data cycle
    axi_master.arlen = 0;
    axi_master.arsize = $clog2($bits(northcape_cmt_entry_t) / 8);
    axi_master.arburst = axi5::INCR;
    axi_master.arlock = 0;
    axi_master.arcache = '0;
    axi_master.arprot = '0;
    axi_master.arqos = '0;
    axi_master.arregion = '0;
    axi_master.aruser = '0;


    // we NEVER write, can leave values undefined

    // AW chan
    axi_master.awvalid = 0;

    // W chan
    axi_master.wvalid = 0;

    // B chan
    axi_master.bready = 0;

  end : axiDefaultValAssign

  always_comb begin : addrResolutionLogic
    if (fifo_interface_arready.is_empty) begin
      // lookup_tdata_in not yet written into the FIFO
      // use lookup_tdata_in to start signalling immediately 
      // value only used when tvalid is high
      resolved_cmt_addr = cmt_interface.cmt_base +
          lookup_tdata_in.capability_slot * $bits(northcape_cmt_entry_t) / 8;
    end else begin
      // use the first entry from the arready FIFO
      resolved_cmt_addr = cmt_interface.cmt_base +
          tdata_fifo_out_arready.capability_slot * $bits(northcape_cmt_entry_t) / 8;
    end
  end

  always_comb begin : rForwardLogic
    tdata_out.capability_id = tdata_fifo_out_rvalid.capability_id;
    tdata_out.tag = tdata_fifo_out_rvalid.tag;
    tdata_out.access_type = tdata_fifo_out_rvalid.access_type;
    tdata_out.device_id = tdata_fifo_out_rvalid.device_id;
    tdata_out.task_id = tdata_fifo_out_rvalid.task_id;

    tdata_out.flags = tdata_fifo_out_rvalid.flags;
    tdata_out.original_address = tdata_fifo_out_rvalid.original_address;
    tdata_out.original_segment_length = tdata_fifo_out_rvalid.original_segment_length;
    tdata_out.original_permission_tid_match = tdata_fifo_out_rvalid.original_permission_tid_match;
    tdata_out.original_permissions = tdata_fifo_out_rvalid.original_permissions;
    tdata_out.lock_key = tdata_fifo_out_rvalid.lock_key;

    tdata_out.restriction = tdata_fifo_out_rvalid.restriction;
    tdata_out.restriction_type = tdata_fifo_out_rvalid.restriction_type;
    tdata_out.response_cache_hit = 1'b0;
    tdata_out.error_code = NORTHCAPE_RESOLVE_NO_ERROR;

    // only interpreted when rvalid is set
    // all-zeros has invalid type --> on read error, always guaranteed parser fail
    tdata_out.cmt_entry = axi_master.rresp == OKAY ? axi_master.rdata : '0;

    // we accept the read data if and only if our consumer can accept it
    // no buffering on our end needed
    validate_request_entry.tvalid = axi_master.rvalid;
    axi_master.rready = validate_request_entry.tready;

    // other AXIS metadata
    validate_request_entry.tid = validate_request_slot.tid;
    validate_request_entry.tdest = validate_request_slot.tdest;
    validate_request_entry.tuser = validate_request_slot.tuser;

    // default values
    validate_request_entry.tstrb = '1;
    validate_request_entry.tkeep = '1;
    validate_request_entry.tlast = 1;
    validate_request_entry.twakeup = 1;
  end : rForwardLogic

  // unused
  assign axi_master.awid = '0;
  assign axi_master.awaddr = '0;
  assign axi_master.awlen = '0;
  assign axi_master.awsize = '0;
  assign axi_master.awburst = BURST_RESERVED;
  assign axi_master.awlock = '0;
  assign axi_master.awcache = '0;
  assign axi_master.awprot = '0;
  assign axi_master.awqos = '0;
  assign axi_master.awregion = '0;
  assign axi_master.awuser = '0;
  assign axi_master.atop_type = ATOMIC_NONE;
  assign axi_master.atop_subtype = '0;
  assign axi_master.wid = '0;
  assign axi_master.wdata = '0;
  assign axi_master.wstrb = '0;
  assign axi_master.wlast = '0;
  assign axi_master.wuser = '0;


  `NORTHCAPE_UNREAD(validate_request_slot.clk_i);
  `NORTHCAPE_UNREAD(validate_request_slot.rst_ni);
  `NORTHCAPE_UNREAD(validate_request_slot.tdata);
  `NORTHCAPE_UNREAD(validate_request_slot.tstrb);
  `NORTHCAPE_UNREAD(validate_request_slot.tkeep);
  `NORTHCAPE_UNREAD(validate_request_slot.tdest);
  `NORTHCAPE_UNREAD(validate_request_slot.tid);
  `NORTHCAPE_UNREAD(validate_request_slot.tlast);
  `NORTHCAPE_UNREAD(validate_request_slot.tuser);
  `NORTHCAPE_UNREAD(validate_request_slot.twakeup);
  `NORTHCAPE_UNREAD(validate_request_entry.clk_i);
  `NORTHCAPE_UNREAD(validate_request_entry.rst_ni);


  `NORTHCAPE_UNREAD(axi_master.clk_i);
  `NORTHCAPE_UNREAD(axi_master.rst_ni);
  `NORTHCAPE_UNREAD(axi_master.awready);
  `NORTHCAPE_UNREAD(axi_master.rid);
  `NORTHCAPE_UNREAD(axi_master.rlast);
  `NORTHCAPE_UNREAD(axi_master.ruser);
  `NORTHCAPE_UNREAD(axi_master.wready);
  `NORTHCAPE_UNREAD(axi_master.bid);
  `NORTHCAPE_UNREAD(axi_master.bresp);
  `NORTHCAPE_UNREAD(axi_master.buser);
  `NORTHCAPE_UNREAD(axi_master.bvalid);

  `NORTHCAPE_UNREAD(cmt_interface.clk_i);
  `NORTHCAPE_UNREAD(cmt_interface.table_size_clog2);
  `NORTHCAPE_UNREAD(cmt_interface.need_flush_data_caches);
  `NORTHCAPE_UNREAD(cmt_interface.wrote_any_capability);
  `NORTHCAPE_UNREAD(cmt_interface.written_capability);


endmodule
