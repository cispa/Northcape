/**
  * Implements the read channel of the Northcape MMU.
  */

import northcape_types::*;
import axi5::*;
import northcape_mmu_common::NorthcapeMMUCommon;

module northcape_mmu_read_chan #(
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,
    parameter bit ACCEPT_AXI_WRAP_BURSTS = 1,
    parameter device_id_t READ_CHAN_DEVICE_ID = -1,

    parameter bit SELF_PRESERVATION_MODE_ACTIVE = 1,
    // cover edge case in which alignment of capability token does not match alignment of base address?
    parameter bit SHIFTING_ACTIVE = 1,
    // cover edge case where bursts partially leave the capability and we need to censor information?
    parameter bit MASKING_ACTIVE = 1,
    parameter bit ENABLE_ILA = 0,
    // some devices (e.g., DMAs) are not trusted with X-only capabilities
    parameter bit DEVICE_INDICATES_EXECUTE = 1'b0
) (
    input logic clk_i,
    input logic rst_ni,
    Axi5ReadOnly.TO axi_slave,
    Axi5ReadOnly.FROM axi_master,

    Axis5.TRANSMITTER axis_validate_request_read,
    Axis5.RECEIVER axis_validate_response_read,
    input atomic_transaction_request_t atomic_transaction_request_i,

    /* MMU needs to discriminate based on AWUSER */
    output task_id_t task_id_irq_q_o,
    output task_id_t task_id_non_irq_q_o,

    // current CMT metadata from operations module
    NorthcapeCMTInterface.CONSUMER cmt_interface,

    output logic rd_channel_is_waiting_for_atomic_o
);
  `include "northcape_mmu_definitions.svh"
  `include "northcape_unread.vh"

  typedef NorthcapeMMUCommon#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .ACCEPT_AXI_WRAP_BURSTS(ACCEPT_AXI_WRAP_BURSTS),
      .IS_WRITE_CHAN(1'b0)
  ) northcape_mmu_common_t;

  typedef enum logic {
    NORTHCAPE_MMU_NON_IRQ,
    NORTHCAPE_MMU_IRQ
  } northcape_transaction_is_irq_t;

  generate
    if (AXI_ADDR_WIDTH < 1 || AXI_DATA_WIDTH < 1 || AXI_ID_WIDTH < 1 || AXI_USER_WIDTH < 1) begin
      $error("Invalid parameters!");
    end
  endgenerate

  //===================================
  // Default assignments
  //===================================
  assign axis_validate_request_read.tstrb   = '1;
  assign axis_validate_request_read.tkeep   = '1;
  assign axis_validate_request_read.tid     = 0;
  assign axis_validate_request_read.tdest   = 0;
  assign axis_validate_request_read.tuser   = 0;
  assign axis_validate_request_read.twakeup = 1;
  assign axis_validate_request_read.tlast   = 1;

  //===================================
  // READ state + wires
  //===================================

  mmu_state_t state_q, state_d;
  logic axi_master_arvalid_d;

  axis_validate_request_tdata_t request_tdata_read_d, request_tdata_read_q;
  axis_validate_response_tdata_t response_tdata_read;

  // start and end of current segment
  // used for atomic transaction
  segment_base_addr_t atomic_segment_start;
  segment_length_t atomic_segment_length;


  axi_bus_addr_t segment_start_read_q, segment_start_read_d, segment_end_read_q, segment_end_read_d;

  // invariant: addr_read_q is the "currently" transferred address after burst started, addr_read_d is "next" transferred address (except in FORWARD_ADDR/WAIT_VALIDATION, where it is current)
  // addr_read_d1 is the value that goes into the register
  axi_bus_addr_t addr_read_q, addr_read_d, addr_read_d1;
  axi_bus_addr_t burst_cap_token_read_q, burst_cap_token_read_d;

  localparam BITS_IN_AXI_BUS_WIDTH = $clog2(AXI_DATA_WIDTH / 8);

  bit [BITS_IN_AXI_BUS_WIDTH-1:0] last_burst_initial_bus_offset_read;


  axi_len_t burst_len_read_q, burst_len_read_d, current_burst_len_read;

  logic dec_burst_len_read_d;

  axi_size_t burst_size_read_q, burst_size_read_d, current_burst_size_read;
  axi_burst_t burst_type_read_q, burst_type_read_d, current_burst_type_read;

  capability_id_t current_capability_id_read;
  capability_tag_t current_capability_tag_read;
  capability_off_t current_capability_offset_read;

  logic [AXI_DATA_WIDTH-1:0] burst_mask_read;

  // used to reflect ID and user back on error
  logic [AXI_ID_WIDTH-1:0] burst_id_read_q, burst_id_read_d;

  // used to determine whether we should do an execute or normal read
  logic current_read_is_instruction_fetch, read_is_instruction_fetch_q, read_is_instruction_fetch_d;

  // whether we are doing an execute with IRQ context
  logic read_is_irq_d;

  // indicates that this is the first read into a set-task-id segment
  // to prevent a subsystem caller from skipping parts of the subsystem's code, we must ignore the token offset and always start at the beginning of the segment
  logic last_read_changes_task_id;

  // registers for task IDs within and outside of IRQ context, respectively
  task_id_t task_id_irq_q, task_id_non_irq_q;
  // value assigned to current task ids
  task_id_t task_id_irq_d, task_id_irq_d1, task_id_non_irq_d, task_id_non_irq_d1;
  // value read from current task ID
  task_id_t last_task_id;
  northcape_transaction_is_irq_t transaction_is_irq_q, transaction_is_irq_d;

  // we can only persist the task ID on successfull accesses
  task_id_t next_task_id;

  // guaranteed to be less than 128 by sizes
  logic [7:0] decoded_burst_size_read;

  // this is only valid when the last_burst_len and last_burst_size are valid
  int unsigned bytes_in_burst_read;

  logic bounds_check_ok_read;

  logic axi_slave_data_burst_complete_read, axi_slave_data_transfer_complete_read;

  atomic_transaction_request_t atomic_request_q, atomic_request_d;

  logic atomic_transaction_completed;

  northcape_device_interpreted_restriction_t
      device_interpreted_restriction_read_q, device_interpreted_restriction_read_d;

  northcape_axi_user_t current_axi_user_read;

  // assignments for master registers
  logic [AXI_ID_WIDTH-1:0] axi_master_arid_d, axi_master_arid_q;
  axi_len_t axi_master_arlen_d, axi_master_arlen_q;
  axi_size_t axi_master_arsize_d, axi_master_arsize_q;
  axi_burst_t axi_master_arburst_d, axi_master_arburst_q;
  logic axi_master_arlock_d, axi_master_arlock_q;
  axi_cache_t axi_master_arcache_d, axi_master_arcache_q;
  axi_prot_t axi_master_arprot_d, axi_master_arprot_q;
  axi_qos_t axi_master_arqos_d, axi_master_arqos_q;
  axi_region_t axi_master_arregion_d, axi_master_arregion_q;
  logic [AXI_ADDR_WIDTH-1:0] axi_master_araddr_d, axi_master_araddr_q;

  logic first_beat_complete_read_d, first_beat_complete_read_q;

  // when the resolver is ready, so are we - do not stall it
  assign axis_validate_response_read.tready = 1'b1;

`ifdef NORTHCAPE_TEST_COVERAGE
  covergroup mmu_read_chan_coverage_group @(posedge clk_i);
    coverpoint state_q;

    burst_len: coverpoint burst_len_read_q;
    burst_size: coverpoint burst_size_read_q;
    burst_type: coverpoint burst_type_read_q {ignore_bins reserved = {BURST_RESERVED};}

    burst_mask: coverpoint burst_mask_read {
      bins no_byte_masks = {64'h0000000000000000};
      bins one_byte_mask = {64'h00000000000000FF};
      bins two_byte_mask = {64'h000000000000FFFF};
      bins three_byte_mask = {64'h0000000000FFFFFF};
      bins four_byte_mask = {64'h00000000FFFFFFFF};
      bins five_byte_mask = {64'h000000FFFFFFFFFF};
      bins six_byte_mask = {64'h0000FFFFFFFFFFFF};
      bins seven_byte_mask = {64'h00FFFFFFFFFFFFFF};
      bins eight_byte_mask = {64'hFFFFFFFFFFFFFFFF};
      // should always cover one byte in monotonic order
      bins wrong_masks[] = default;
    }

    bounds_check_ok_read: coverpoint bounds_check_ok_read;

    cross burst_len, burst_size, burst_type, bounds_check_ok_read;
  endgroup

  mmu_read_chan_coverage_group cov_group;
  initial begin
    cov_group = new;
  end

`endif

  //===================================
  // Sequential Logic
  //===================================

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : stateFFLogic
    if (rst_ni == 0) begin
      state_q <= IDLE;
    end else begin
      state_q <= state_d;
    end
  end : stateFFLogic

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : addrFFLogic
    if (rst_ni == 0) begin
      addr_read_q <= '0;
    end else begin
      addr_read_q <= addr_read_d1;
    end
  end : addrFFLogic

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : masterAttributeFFs
    if (rst_ni == 0) begin
      axi_master_arid_q <= '0;
      axi_master_arlen_q <= '0;
      axi_master_arsize_q <= '0;
      axi_master_arburst_q <= BURST_RESERVED;
      axi_master_arlock_q <= '0;
      axi_master_arcache_q <= '0;
      axi_master_arprot_q <= '0;
      axi_master_arqos_q <= '0;
      axi_master_arregion_q <= '0;
      axi_master_araddr_q <= '0;
      request_tdata_read_q <= '0;
    end else begin
      axi_master_arid_q <= axi_master_arid_d;
      axi_master_arlen_q <= axi_master_arlen_d;
      axi_master_arsize_q <= axi_master_arsize_d;
      axi_master_arburst_q <= axi_master_arburst_d;
      axi_master_arlock_q <= axi_master_arlock_d;
      axi_master_arcache_q <= axi_master_arcache_d;
      axi_master_arprot_q <= axi_master_arprot_d;
      axi_master_arqos_q <= axi_master_arqos_d;
      axi_master_arregion_q <= axi_master_arregion_d;
      axi_master_araddr_q <= axi_master_araddr_d;
      request_tdata_read_q <= request_tdata_read_d;
    end
  end : masterAttributeFFs

  assign current_read_is_instruction_fetch = DEVICE_INDICATES_EXECUTE && axi_slave.aruser[0];
  assign read_is_irq_d = DEVICE_INDICATES_EXECUTE && axi_slave.aruser[1];

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : axiSlaveFFLogic
    if (rst_ni == 0) begin
      burst_len_read_q <= '0;
      burst_size_read_q <= '0;
      burst_type_read_q <= BURST_RESERVED;
      burst_cap_token_read_q <= '0;
      burst_id_read_q <= '0;
      if (DEVICE_INDICATES_EXECUTE) begin
        read_is_instruction_fetch_q <= 0;
      end
    end else begin
      burst_len_read_q <= burst_len_read_d;
      burst_size_read_q <= burst_size_read_d;
      burst_type_read_q <= burst_type_read_d;
      burst_cap_token_read_q <= burst_cap_token_read_d;
      burst_id_read_q <= burst_id_read_d;
      if (DEVICE_INDICATES_EXECUTE) begin
        read_is_instruction_fetch_q <= read_is_instruction_fetch_d;
      end
    end
  end : axiSlaveFFLogic


  // only read when both are valid
  assign last_read_changes_task_id = response_tdata_read.restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID && DEVICE_INDICATES_EXECUTE == 1'b1 && last_task_id != next_task_id;

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : axisResponseFFLogic
    if (rst_ni == 0) begin
      segment_start_read_q <= '0;
      segment_end_read_q <= '0;
      device_interpreted_restriction_read_q <= '0;
    end else begin
      segment_start_read_q <= segment_start_read_d;
      segment_end_read_q <= segment_end_read_d;
      device_interpreted_restriction_read_q <= device_interpreted_restriction_read_d;
    end
  end : axisResponseFFLogic

  // this is only valid for one cycle, during which we might be in another state
  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : lastAtomicRequestFF
    if (rst_ni == 0) begin
      atomic_request_q.atomic_transaction_requested <= 0;

      atomic_request_q.burst_type <= BURST_RESERVED;
      atomic_request_q.slave_token <= '0;
      atomic_request_q.segment_start <= '0;
      atomic_request_q.segment_end <= '0;
      atomic_request_q.transaction_size <= '0;

      atomic_request_q.atomic_error <= 0;
      atomic_request_q.atomic_request_len <= '0;
      atomic_request_q.atomic_request_id <= '0;

    end else begin
      atomic_request_q <= atomic_request_d;
    end
  end : lastAtomicRequestFF

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : currentTaskIdRegs
    if (rst_ni == 1'b0) begin
      transaction_is_irq_q <= NORTHCAPE_MMU_NON_IRQ;
      task_id_irq_q <= '0;
      task_id_non_irq_q <= '0;
    end else begin
      // transaction_is_irq_d is valid during idle state, no dependency on bounds check
      transaction_is_irq_q <= transaction_is_irq_d;
      task_id_irq_q <= task_id_irq_d1;
      task_id_non_irq_q <= task_id_non_irq_d1;
    end
  end : currentTaskIdRegs

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : firstBurstCompleteReadFF
    if (rst_ni == 1'b0) begin
      first_beat_complete_read_q <= '0;
    end else begin
      first_beat_complete_read_q <= first_beat_complete_read_d;
    end
  end : firstBurstCompleteReadFF

  //===================================
  // Combinational Logic
  //===================================

  always_comb begin : axiParamsLogic

    burst_len_read_d = burst_len_read_q;
    burst_size_read_d = burst_size_read_q;
    burst_type_read_d = burst_type_read_q;
    burst_cap_token_read_d = burst_cap_token_read_q;
    burst_id_read_d = burst_id_read_q;
    read_is_instruction_fetch_d = read_is_instruction_fetch_q;

    if (state_q == IDLE) begin
      // in case of atomic transaction, need to store the medatadata ASAP
      // when we are in the forward state, it might be too late, as we might have already set an incorrect number of expected data response beats
      if (atomic_request_q.atomic_transaction_requested) begin
        // need to behave as if during read error
        // to this end, sample metadata
        burst_len_read_d = atomic_request_q.atomic_request_len;
        burst_id_read_d = atomic_request_q.atomic_request_id;
        burst_size_read_d = atomic_request_q.transaction_size;
        burst_type_read_d = atomic_request_q.burst_type;
        burst_cap_token_read_d = atomic_request_q.slave_token;
        // instruction fetching never uses write
        read_is_instruction_fetch_d = 0;
      end else begin
        // the master cannot change the values later to trick us
        burst_len_read_d = current_burst_len_read;
        burst_size_read_d = current_burst_size_read;
        burst_type_read_d = current_burst_type_read;
        burst_cap_token_read_d = axi_slave.araddr;
        burst_id_read_d = axi_slave.arid;
        read_is_instruction_fetch_d = current_read_is_instruction_fetch;
      end
    end
            else if(state_q == REPORT_ERROR || ((state_q == FORWARD_DATA || state_q == FORWARD_DATA_FIRST_TRANSACTION) && (burst_type_read_q != WRAP || !ACCEPT_AXI_WRAP_BURSTS)))
            begin
      burst_len_read_d = burst_len_read_q - {7'h0, dec_burst_len_read_d};
    end
  end : axiParamsLogic

  always_comb begin : validateResponseParsingLogic
    segment_start_read_d = segment_start_read_q;
    segment_end_read_d = segment_end_read_q;
    device_interpreted_restriction_read_d = device_interpreted_restriction_read_q;

    response_tdata_read = axis_validate_response_read.tdata;

    if (axis_validate_response_read.tvalid == 1'b1) begin
      segment_start_read_d = {32'h0, response_tdata_read.address};
      segment_end_read_d = {32'h0, response_tdata_read.address} + {32'h0, response_tdata_read.segment_length};

      if (response_tdata_read.restriction_type == NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED) begin
        device_interpreted_restriction_read_d = response_tdata_read.restriction.device_interpreted_bits;
      end else begin
        device_interpreted_restriction_read_d = '0;
      end
    end
  end : validateResponseParsingLogic

  always_comb begin : axiMasterARForwardingLogic

    axi_master_arid_d = axi_master_arid_q;
    axi_master_arlen_d = axi_master_arlen_q;
    axi_master_arsize_d = axi_master_arsize_q;
    axi_master_arburst_d = axi_master_arburst_q;
    axi_master_arlock_d = axi_master_arlock_q;
    axi_master_arcache_d = axi_master_arcache_q;
    axi_master_arprot_d = axi_master_arprot_q;
    axi_master_arqos_d = axi_master_arqos_q;
    axi_master_arregion_d = axi_master_arregion_q;

    // not valid after reset
    axi_master_araddr_d = axi_master_araddr_q;

    if (axi_slave.arvalid == 1'b1 && state_q == IDLE) begin
      // new transaction received - can already register in all forwarded fields except valid (depends on bounds check later)
      axi_master_arid_d = axi_slave.arid;
      axi_master_arlen_d = axi_slave.arlen;
      axi_master_arsize_d = axi_slave.arsize;
      axi_master_arburst_d = axi_slave.arburst;
      axi_master_arlock_d = axi_slave.arlock;
      axi_master_arcache_d = axi_slave.arcache;
      axi_master_arprot_d = axi_slave.arprot;
      axi_master_arqos_d = axi_slave.arqos;
      axi_master_arregion_d = axi_slave.arregion;
      axi_master_araddr_d = {32'h0, current_capability_offset_read};
    end
            else if(state_q inside {REQUEST_VALIDATION, WAIT_VALIDATION} && axis_validate_response_read.tvalid == 1'b1 && axis_validate_response_read.tready == 1'b1)
            begin
      // Control unit returns the beginning of the segment
      // bounds are checked at the same time by the state logic - if the device changes the offset later, we ignore the value
      // offset was added to the address at the idle state
      axi_master_araddr_d = current_capability_offset_read + {32'h0, response_tdata_read.address};
    end

    axi_master.arid = axi_master_arid_d;
    axi_master.arlen = axi_master_arlen_d;
    axi_master.arsize = axi_master_arsize_d;
    axi_master.arburst = axi_master_arburst_d;
    axi_master.arlock = axi_master_arlock_d;
    axi_master.arcache = axi_master_arcache_d;
    axi_master.arprot = axi_master_arprot_d;
    axi_master.arqos = axi_master_arqos_d;
    axi_master.arregion = axi_master_arregion_d;

    // not valid after reset
    axi_master.araddr = axi_master_araddr_d;
    axi_master.arvalid = axi_master_arvalid_d;
  end : axiMasterARForwardingLogic

  // global for debugging
  logic [AXI_DATA_WIDTH-1:0] masked_data, shifted_data;
  bit [$clog2(AXI_DATA_WIDTH/8)-1:0] shift_out_read;
  bit direction_out;
  logic data_changed;

  assign data_changed = (axi_master.rdata != axi_slave.rdata);
  generate
    if (ENABLE_ILA == 1'b1) begin
      mmu_mask_shift_debug_ila i_dbg_ila (
          .clk_i  (clk_i),
          .probe0 (state_q),
          .probe1 (addr_read_d),
          .probe2 (segment_start_read_d),
          .probe3 (segment_end_read_q),
          .probe4 (burst_size_read_q),
          .probe5 (  /* TODO needed? */ '0),
          .probe6 (last_burst_initial_bus_offset_read),
          .probe7 (burst_mask_read),
          .probe8 (burst_cap_token_read_q),
          .probe9 (masked_data),
          .probe10(shift_out_read),
          .probe11(data_changed),
          .probe12(shifted_data),
          .probe13(axi_master.rdata),
          .probe14(axi_master.rvalid)
      );
    end else begin
`ifndef ASIC
      $info("Not generating debug ILA!");
`endif
    end
  endgenerate

  always_comb begin : readDataForwardLogic


    // default assignments
    axi_slave.rresp = SLVERR;  // undefined state
    axi_slave.rlast = '0;
    axi_slave.rvalid = '0;
    axi_slave.rdata = '0;
    axi_master.rready = 0;

    // otherwise, a register is inferred
    last_burst_initial_bus_offset_read = '0;

    // unused; copying suffices
    axi_slave.rid = axi_master.rid;
    axi_slave.ruser = axi_master.ruser;

    if (MASKING_ACTIVE) begin
      if (state_q != FORWARD_ATOMIC_TRANSACTION) begin
        last_burst_initial_bus_offset_read = current_capability_offset_read % (AXI_DATA_WIDTH / 8);
        // in WAIT_VALIDATION, FORWARD_ADDR, we need to use the "next" address in order to not miss a transfer
        burst_mask_read = northcape_mmu_common_t::get_per_byte_mask_for_addr(
          !first_beat_complete_read_q ? addr_read_d : addr_read_q,
          segment_start_read_d,
          segment_end_read_q
        );
      end else begin
        last_burst_initial_bus_offset_read = (atomic_request_q.segment_start + capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(
            atomic_request_q.slave_token)) % (AXI_DATA_WIDTH / 8);
        // need addr_read_q here, otherwise, always "one ahead"
        burst_mask_read = northcape_mmu_common_t::get_per_byte_mask_for_addr(
            addr_read_q, atomic_request_q.segment_start, atomic_request_q.segment_end);
      end

      burst_mask_read = northcape_axi_masks#(
          .MASK_TARGET_WIDTH_BITS(AXI_DATA_WIDTH),
          .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
      )::stretchMask(
        burst_mask_read
      );

      masked_data = axi_master.rdata & burst_mask_read;
    end else begin
      masked_data = axi_master.rdata;
      // otherwise, a register is inferred
      last_burst_initial_bus_offset_read = '0;
    end

    if (SHIFTING_ACTIVE) begin
      if (state_q != FORWARD_ATOMIC_TRANSACTION) begin
        // our capability token always imply offset 0
        // our capability segments need not be bus-width aligned, though
        // we need to shift accordingly to correct this
        // as data is generated by slave here, we need to shift in the opposite direction WRT write channel
        shift_out_read = segment_start_read_d % (AXI_DATA_WIDTH / 8);
      end else begin
        shift_out_read = atomic_request_q.segment_start % (AXI_DATA_WIDTH / 8);
      end
      shifted_data = northcape_mmu_common_t::shift_data(masked_data, shift_out_read);
    end else begin
      shifted_data = masked_data;
    end

    unique case (state_q)
      FORWARD_DATA: begin
        //do not "eat" data before slave can accept it
        axi_master.rready = axi_slave.rready;
        axi_slave.rvalid  = axi_master.rvalid;
        axi_slave.rresp   = axi_master.rresp;
        axi_slave.rlast   = axi_master.rlast;
        axi_slave.rdata   = shifted_data;
      end
      REQUEST_VALIDATION, WAIT_VALIDATION: begin
        // cannot forward anything before I have bounds
        axi_master.rready = bounds_check_ok_read & axi_slave.rready;
        axi_slave.rvalid  = bounds_check_ok_read & axi_master.rvalid;
        axi_slave.rresp   = axi_master.rresp;
        axi_slave.rlast   = bounds_check_ok_read & axi_master.rlast;

        axi_slave.rdata   = shifted_data;
      end
      FORWARD_ADDR, FORWARD_DATA_FIRST_TRANSACTION: begin
        axi_master.rready = axi_slave.rready;
        axi_slave.rvalid  = axi_master.rvalid;
        axi_slave.rresp   = axi_master.rresp;
        axi_slave.rlast   = axi_master.rlast;

        axi_slave.rdata   = shifted_data;

      end
      FORWARD_DATA_LAST_TRANSACTION, WAIT_COMPLETE: begin
        // WRAP bursts do not necessarily set last on last transaction, as we might have to zero out
        if(axi_master.rvalid && (axi_master.rlast || (ACCEPT_AXI_WRAP_BURSTS && burst_type_read_q == WRAP)))
            begin
          axi_master.rready = axi_slave.rready;
          axi_slave.rvalid = 1;
          axi_slave.rresp = axi_master.rresp;
          axi_slave.rlast = ACCEPT_AXI_WRAP_BURSTS && burst_type_read_q == WRAP ? axi_master.rlast : 1;

          axi_slave.rdata = shifted_data;
        end else if (axi_slave.rready) begin
          axi_master.rready = 0;
          axi_slave.rvalid  = 0;
          axi_slave.rdata   = '0;
        end
      end
      FORWARD_DATA_ZERO_OUT: begin
        // we are forwarding all-zeros data, control signals can be forwarded
        // cannot set valid and ready to 1 as to not to desync the transmissions (we do not buffer)
        axi_slave.rdata   = '0;
        axi_slave.rvalid  = axi_master.rvalid;
        axi_slave.rlast   = axi_master.rlast;
        axi_slave.rresp   = axi_master.rresp;

        axi_master.rready = axi_slave.rready;
      end
      REPORT_ERROR: begin

        if (DEVICE_INDICATES_EXECUTE && read_is_instruction_fetch_q) begin
          axi_slave.rdata = northcape_mmu_common_t::INSTRUCTION_FETCH_ERROR_RESP;
          axi_slave.rresp = OKAY;
        end else begin
          axi_slave.rdata = '0;
          axi_slave.rresp = DECERR;
        end

        axi_slave.rvalid = 1;
        axi_slave.rlast = 0;
        axi_slave.rid = burst_id_read_q;
        axi_slave.ruser = '0;
      end
      LAST_REPORT_ERROR: begin
        if (DEVICE_INDICATES_EXECUTE && read_is_instruction_fetch_q) begin
          axi_slave.rdata = northcape_mmu_common_t::INSTRUCTION_FETCH_ERROR_RESP;
          axi_slave.rresp = OKAY;
        end else begin
          axi_slave.rdata = '0;
          axi_slave.rresp = DECERR;
        end

        // this is already 1 from previous cycles, and so might be ready
        axi_slave.rvalid = 1;
        axi_slave.rlast = 1;

        axi_slave.rid = burst_id_read_q;
        axi_slave.ruser = '0;
      end
      SINGLE_REPORT_ERROR: begin
        if (DEVICE_INDICATES_EXECUTE && read_is_instruction_fetch_q) begin
          axi_slave.rdata = northcape_mmu_common_t::INSTRUCTION_FETCH_ERROR_RESP;
          axi_slave.rresp = OKAY;
        end else begin
          axi_slave.rdata = '0;
          axi_slave.rresp = DECERR;
        end

        // might otherwise hold this for 1 too many cycles
        axi_slave.rvalid = 1;
        axi_slave.rlast = 1;
        axi_slave.rid = burst_id_read_q;
        axi_slave.ruser = '0;
      end
      FORWARD_ATOMIC_TRANSACTION: begin
        axi_master.rready = axi_slave.rready;
        axi_slave.rvalid  = axi_master.rvalid;
        axi_slave.rresp   = axi_master.rresp;
        axi_slave.rlast   = axi_master.rlast;

        axi_slave.rdata   = shifted_data;
      end
      default: begin
        // default assignment above
      end
    endcase
  end : readDataForwardLogic

  always_comb begin : atomicTransactionCompletedLogic
    atomic_transaction_completed = (state_q == FORWARD_ATOMIC_TRANSACTION && axi_master.rvalid && axi_master.rlast && axi_slave.rready);
  end : atomicTransactionCompletedLogic



  always_comb begin : requestTdataLogic
    request_tdata_read_d = request_tdata_read_q;
    // slave can change address after we left IDLE - need to keep the tdata
    if (state_q == IDLE) begin

      request_tdata_read_d.address = current_capability_id_read;
      request_tdata_read_d.tag = current_capability_tag_read;

      if (DEVICE_INDICATES_EXECUTE) begin
        unique case ({
          current_read_is_instruction_fetch, read_is_irq_d
        })
          2'b00:   request_tdata_read_d.access_type = READ;
          2'b01:   request_tdata_read_d.access_type = READ_IRQ;
          2'b10:   request_tdata_read_d.access_type = EXECUTE;
          default: request_tdata_read_d.access_type = EXECUTE_IRQ;
        endcase
      end else begin
        request_tdata_read_d.access_type = READ;
      end

      request_tdata_read_d.device_id = READ_CHAN_DEVICE_ID;

      if (DEVICE_INDICATES_EXECUTE) begin
        // needs to be kept stable, otherwise, race condition when all parsing happens in comb. logic
        request_tdata_read_d.task_id = read_is_irq_d ? task_id_irq_q : task_id_non_irq_q;
      end else begin
        request_tdata_read_d.task_id = '0;
      end

      request_tdata_read_d.flags.is_recursion = 1'b0;
      request_tdata_read_d.flags.have_base_length = 1'b0;
      request_tdata_read_d.flags.have_lock_key = 1'b0;
      request_tdata_read_d.flags.reserved = '0;
      request_tdata_read_d.original_address = '0;
      request_tdata_read_d.original_segment_length = '0;
      request_tdata_read_d.original_permission_tid_match = 1'b0;
      request_tdata_read_d.original_permissions = '0;
      request_tdata_read_d.lock_key = '0;

      request_tdata_read_d.restriction = '0;
      request_tdata_read_d.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
      request_tdata_read_d.error_code = NORTHCAPE_RESOLVE_NO_ERROR;
    end

    axis_validate_request_read.tdata = request_tdata_read_d;
  end : requestTdataLogic

  always_comb begin : atomicRequestStorageLogic
    atomic_request_d = atomic_request_q;

    if (atomic_transaction_request_i.atomic_transaction_requested) begin
      atomic_request_d = atomic_transaction_request_i;
    end
            else if(state_q == IDLE || (state_q == FORWARD_ATOMIC_TRANSACTION && axi_master.rvalid && axi_slave.rready && axi_master.rlast))
            begin
      // state machine will transition into the transaction forwarding state immediately
      // we need to clear the flag such that we do not erroneously jump back into the forwarding state once we are done
      // in case we are just about to go back into idle from forwarding an atomic transaction, we need to clear the flag immediately - otherwise, we might erroneously cycle into the state again
      atomic_request_d.atomic_transaction_requested = 0;
    end
  end : atomicRequestStorageLogic

  always_comb begin : capabilityTokenParsing
    current_capability_id_read =
        capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(burst_cap_token_read_d);
    current_capability_tag_read =
        capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(burst_cap_token_read_d);
    current_capability_offset_read =
        capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(burst_cap_token_read_d);

  end : capabilityTokenParsing

  always_comb begin : axiUserOutputConstructor
    current_axi_user_read.reserved = '0;
    current_axi_user_read.device_interpreted_restriction = device_interpreted_restriction_read_d;
    // both MMU chans are the same device
    current_axi_user_read.current_device_id = (READ_CHAN_DEVICE_ID) >> 1;
    current_axi_user_read.current_task_id = transaction_is_irq_d ? task_id_irq_d : task_id_non_irq_d;

    axi_master.aruser = current_axi_user_read;
  end : axiUserOutputConstructor

  // global for debugging  
  northcape_physical_address_t start_addr;

  always_comb begin : boundsCheckLogic
    start_addr = current_capability_offset_read + (ACCEPT_AXI_WRAP_BURSTS && burst_type_read_q == WRAP ? axi5_address_calculations#(AXI_ADDR_WIDTH)::axi5_wrapped_burst_get_start_address(
        burst_len_read_q, burst_size_read_q, {32'h0, response_tdata_read.address}) :
        response_tdata_read.address);

    decoded_burst_size_read = 1 << burst_size_read_q;
    bytes_in_burst_read = northcape_mmu_common_t::getBytesInBurst(
        burst_size_read_q, burst_type_read_q, burst_len_read_q, start_addr,
            decoded_burst_size_read);

    if (last_read_changes_task_id && current_capability_offset_read != '0) begin
      // the caller attempts to skip over parts of the code segment
      bounds_check_ok_read = 1'b0;
    end else begin
      if (axis_validate_response_read.tvalid == 1'b1) begin
        bounds_check_ok_read = northcape_mmu_common_t::checkBounds(
          bytes_in_burst_read,
          current_capability_offset_read,
          response_tdata_read.segment_length,
          burst_type_read_q,
          start_addr,
          cmt_interface.cmt_base,
          cmt_interface.table_size_clog2,
          burst_len_read_q,
          decoded_burst_size_read,
          response_tdata_read.address % (AXI_DATA_WIDTH / 8) != 0,
          .self_preservation_mode_active(SELF_PRESERVATION_MODE_ACTIVE),
          .shifting_active(SHIFTING_ACTIVE)
        );
      end else begin
        // HAVE to ignore invalid data
        bounds_check_ok_read = 1'b0;
      end
    end
  end : boundsCheckLogic

  always_comb begin : nextTaskIdLogic
    task_id_irq_d = task_id_irq_q;
    task_id_non_irq_d = task_id_non_irq_q;
    next_task_id = transaction_is_irq_q ? task_id_irq_q : task_id_non_irq_q;

    task_id_non_irq_d1 = task_id_non_irq_q;
    task_id_irq_d1 = task_id_irq_q;

    if (state_q inside {REQUEST_VALIDATION, WAIT_VALIDATION} && axis_validate_response_read.tvalid == 1'b1 && response_tdata_read.restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID && DEVICE_INDICATES_EXECUTE == 1'b1 && read_is_instruction_fetch_q == 1'b1) begin

      // all conditions fulfilled for determining the next task ID:
      // response data are valid
      // we accept execute requests
      // the response has a set-task-ID restriction
      // the request is successfull
      next_task_id = response_tdata_read.restriction.task_restriction.task_id;

    end


    unique case (transaction_is_irq_d)
      NORTHCAPE_MMU_IRQ: begin
        task_id_irq_d = next_task_id;
      end
      default: begin
        task_id_non_irq_d = next_task_id;
      end
    endcase


    if (bounds_check_ok_read == 1'b1) begin
      task_id_non_irq_d1 = task_id_non_irq_d;
      task_id_irq_d1 = task_id_irq_d;
    end

  end : nextTaskIdLogic


  always_comb begin : nextStateLogicRead
    if(state_q == REPORT_ERROR || state_q == LAST_REPORT_ERROR || state_q == SINGLE_REPORT_ERROR)
        begin
      // we always generate valid=1
      axi_slave_data_burst_complete_read = axi_slave.rready;
      axi_slave_data_transfer_complete_read = axi_slave.rready && (state_q == LAST_REPORT_ERROR || state_q == SINGLE_REPORT_ERROR);
    end else begin
      // master generates handshaking symbols
      axi_slave_data_burst_complete_read = axi_master.rvalid && axi_slave.rready;
      axi_slave_data_transfer_complete_read = axi_master.rvalid && axi_slave.rready && axi_slave.rlast;
    end

    // default output values
    state_d = northcape_mmu_common_t::computeNextState(
      .current_state(state_q),
      .slave_address_channel_valid_ready(axi_slave.arvalid && axi_slave.arready),
      .axis_validate_request_ready(axis_validate_request_read.tvalid && axis_validate_request_read.tready),
      .axis_validate_response_valid(axis_validate_response_read.tvalid),
      .bounds_check_ok(bounds_check_ok_read),
      .last_burst_len(burst_len_read_q),
      .last_burst_size(burst_size_read_q),
      .last_burst_type(burst_type_read_q),
      .master_addr_chan_ready(axi_master.arready),
      .last_segment_start(segment_start_read_d),
      .last_segment_end(segment_end_read_d),
      .axi_slave_data_burst_complete(axi_slave_data_burst_complete_read),
      .axi_slave_data_transfer_complete(axi_slave_data_transfer_complete_read),
      .axi_slave_data_channel_ready(axi_slave.rready),
      .master_addr_chan_addr(axi_master_araddr_d),
      .input_data_chan_valid(axi_master.rvalid),
      .input_data_chan_last(axi_master.rlast),
      .last_wrap_addr(state_q inside {REQUEST_VALIDATION, WAIT_VALIDATION, FORWARD_ADDR} ? addr_read_d : addr_read_q),
      .expect_atomic_transaction(atomic_request_q.atomic_transaction_requested),
      .atomic_transaction_complete(atomic_transaction_completed),
      .error_beat_complete(axi_slave.rready),
      .atomic_request_error_in(atomic_request_q.atomic_error),
      .axi_slave_bready(1'b0)
    );
  end : nextStateLogicRead


  always_comb begin : currentTaskIdDemux
    // to write side
    task_id_irq_q_o = task_id_irq_d;
    task_id_non_irq_q_o = task_id_non_irq_d;

    // need the value from combinational logic here
    // this might change in the same cycle it is read again, i.e., when requesting validation
    unique case (transaction_is_irq_q)
      NORTHCAPE_MMU_IRQ: begin
        last_task_id = task_id_irq_q;
      end
      default: begin
        last_task_id = task_id_non_irq_q;
      end
    endcase
  end : currentTaskIdDemux

  always_comb begin : nextMMUIrqStateLogic
    transaction_is_irq_d = transaction_is_irq_q;

    unique case (state_q)
      IDLE: begin
        if (axi_slave.arvalid == 1'b1 && read_is_irq_d) begin
          // this transaction is in IRQ context
          transaction_is_irq_d = NORTHCAPE_MMU_IRQ;
        end else if (axi_slave.arvalid == 1'b1) begin
          // this transaction is NOT in IRQ context
          transaction_is_irq_d = NORTHCAPE_MMU_NON_IRQ;
        end
        // otherwise: maintain flag 
      end
      default: begin
        transaction_is_irq_d = transaction_is_irq_q;
      end
    endcase
  end : nextMMUIrqStateLogic

  always_comb begin : readFSMOutputLogicRead
    axi_slave.arready = 1'b0;
    axis_validate_request_read.tvalid = 1'b0;
    current_burst_len_read = burst_len_read_q;
    current_burst_size_read = burst_size_read_q;
    current_burst_type_read = burst_type_read_q;
    axi_master_arvalid_d = 1'b0;
    dec_burst_len_read_d = '0;

    rd_channel_is_waiting_for_atomic_o = 1'b0;

    addr_read_d = addr_read_q;
    addr_read_d1 = addr_read_q;


    first_beat_complete_read_d = first_beat_complete_read_q;

    if (state_q == IDLE || !first_beat_complete_read_q) begin
      // reset + set again if already valid
      first_beat_complete_read_d = axi_master.rvalid && axi_slave.rready;
    end

    if (state_q == IDLE && atomic_request_q.atomic_transaction_requested) begin
      // bootstrap last address from atomic transaction
      addr_read_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(
          atomic_request_q.slave_token) + atomic_request_q.segment_start;
      addr_read_d1 = addr_read_d;
      rd_channel_is_waiting_for_atomic_o = 1'b1;
    end else if (first_beat_complete_read_q && axi_master.rvalid && axi_slave.rready) begin
      // in transaction - compute next address in burst
      addr_read_d = northcape_mmu_common_t::get_next_addr(burst_type_read_q, addr_read_q,
                                                          burst_len_read_q, burst_size_read_q);
      addr_read_d1 = addr_read_d;
      // TODO tooling bug: updating the read address if we are already transferring leads to infinite loop in Vivado
      // we do not set rvalid here, so should be fine
      // for atomic, we derive the initial address as above
    end else if (state_q != FORWARD_ATOMIC_TRANSACTION && !first_beat_complete_read_q) begin
      // bootstrap last address from burst metadata
      // use registered value here to ensure the value does not change
      addr_read_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(
          burst_cap_token_read_q) + segment_start_read_d;
      addr_read_d1 = addr_read_d;
      if (axi_master.rvalid && axi_slave.rready) begin
        // currently transferring the first address - need to jump forward to keep addr_read_q invariant
        addr_read_d1 = northcape_mmu_common_t::get_next_addr(burst_type_read_q, addr_read_d,
                                                             burst_len_read_q, burst_size_read_q);
      end
    end else if (state_q == FORWARD_ATOMIC_TRANSACTION && !first_beat_complete_read_q) begin
      if (axi_master.rvalid && axi_slave.rready) begin
        // currently transferring the first address - need to jump forward to keep addr_read_q invariant
        addr_read_d1 = northcape_mmu_common_t::get_next_addr(burst_type_read_q, addr_read_q,
                                                             burst_len_read_q, burst_size_read_q);
      end
    end else begin
      // maintain
      addr_read_d  = addr_read_q;
      addr_read_d1 = addr_read_q;
    end

    // output logic based on next state
    unique case (state_q)
      IDLE: begin
        // prioritize atomics - by not setting arready we make sure not to "swallow" a transaction
        axi_slave.arready = !atomic_request_q.atomic_transaction_requested;

        if (axi_slave.arvalid == 1'b1 && !atomic_request_q.atomic_transaction_requested) begin

          // need to remember burst size and len for permission check
          current_burst_len_read = axi_slave.arlen;
          current_burst_size_read = axi_slave.arsize;
          current_burst_type_read = axi_slave.arburst;
          // do not request read until transaction is confirmed
          axis_validate_request_read.tvalid = axi_slave.arvalid && axi_slave.arready;
        end
      end
      REQUEST_VALIDATION, WAIT_VALIDATION: begin
        // high unconditionally during REQUEST_VALIDATION - need to make sure that the slave has seen it for one cycle
        axis_validate_request_read.tvalid = (state_q == REQUEST_VALIDATION);
        if (axis_validate_response_read.tvalid == 1'b1) begin
          if (bounds_check_ok_read) begin
            axi_master_arvalid_d = 1;
          end
        end
      end
      WAIT_ADDRESS_HANDSHAKE, FORWARD_ADDR: begin
        // keep waiting for ready
        axi_master_arvalid_d = 1'b1;
      end
      FORWARD_DATA_FIRST_TRANSACTION, FORWARD_DATA, REPORT_ERROR: begin
        if (axi_slave_data_burst_complete_read) begin
          // one transaction burst was completed - one less to go
          dec_burst_len_read_d = 1;
        end
      end
      FORWARD_ATOMIC_TRANSACTION: begin
        rd_channel_is_waiting_for_atomic_o = 1'b1;
      end
      default: begin
        // already defined above
      end
    endcase
  end : readFSMOutputLogicRead

  `NORTHCAPE_UNREAD(axi_slave.clk_i);
  `NORTHCAPE_UNREAD(axi_slave.rst_ni);
  `NORTHCAPE_UNREAD(axi_master.clk_i);
  `NORTHCAPE_UNREAD(axi_master.rst_ni);
  `NORTHCAPE_UNREAD(axis_validate_request_read.clk_i);
  `NORTHCAPE_UNREAD(axis_validate_request_read.rst_ni);
  `NORTHCAPE_UNREAD(axis_validate_response_read.clk_i);
  `NORTHCAPE_UNREAD(axis_validate_response_read.rst_ni);
  `NORTHCAPE_UNREAD(axis_validate_response_read.tdata);
  `NORTHCAPE_UNREAD(axis_validate_response_read.tstrb);
  `NORTHCAPE_UNREAD(axis_validate_response_read.tkeep);
  `NORTHCAPE_UNREAD(axis_validate_response_read.tlast);
  `NORTHCAPE_UNREAD(axis_validate_response_read.tid);
  `NORTHCAPE_UNREAD(axis_validate_response_read.tdest);
  `NORTHCAPE_UNREAD(axis_validate_response_read.tuser);
  `NORTHCAPE_UNREAD(axis_validate_response_read.twakeup);

  `NORTHCAPE_UNREAD(cmt_interface.clk_i);
  `NORTHCAPE_UNREAD(cmt_interface.cmt_base);
  `NORTHCAPE_UNREAD(cmt_interface.table_size_clog2);
  `NORTHCAPE_UNREAD(cmt_interface.reset_done);
  `NORTHCAPE_UNREAD(cmt_interface.need_flush_data_caches);
  `NORTHCAPE_UNREAD(cmt_interface.wrote_any_capability);
  `NORTHCAPE_UNREAD(cmt_interface.written_capability);


  `NORTHCAPE_UNREAD(response_tdata_read.permissions);
  `NORTHCAPE_UNREAD(response_tdata_read.error_code);

  `NORTHCAPE_UNREAD(axi_slave.aruser);
endmodule
