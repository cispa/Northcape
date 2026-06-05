/**
  * Implements the write channel of the Northcape MMU.
  */

import northcape_types::*;
import axi5::*;
import northcape_mmu_common::NorthcapeMMUCommon;

module northcape_mmu_write_chan #(
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,
    parameter bit ACCEPT_AXI_WRAP_BURSTS = 1,
    parameter device_id_t WRITE_CHAN_DEVICE_ID = -1,
    parameter bit DEVICE_INDICATES_EXECUTE = 0,

    parameter bit SELF_PRESERVATION_MODE_ACTIVE = 1,
    // cover edge case in which alignment of capability token does not match alignment of base address?
    parameter bit SHIFTING_ACTIVE = 1,
    // cover edge case where bursts partially leave the capability and we need to censor information?
    parameter bit MASKING_ACTIVE = 1,
    parameter bit ENABLE_ILA = 0
) (
    input logic clk_i,
    input logic rst_ni,

    Axi5WriteOnly.TO   axi_slave,
    Axi5WriteOnly.FROM axi_master,

    Axis5.TRANSMITTER axis_validate_request_write,
    Axis5.RECEIVER axis_validate_response_write,
    output atomic_transaction_request_t atomic_transaction_request_o,

    input task_id_t current_task_id_irq_i,
    input task_id_t current_task_id_non_irq_i,

    // current CMT metadata from operations module
    NorthcapeCMTInterface.CONSUMER cmt_interface,

    // is the read channel currently waiting for the R data from an atomic transaction?
    input logic rd_channel_is_waiting_for_atomic_i
);

  `include "northcape_mmu_definitions.svh"
  `include "northcape_unread.vh"

  typedef NorthcapeMMUCommon#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .ACCEPT_AXI_WRAP_BURSTS(ACCEPT_AXI_WRAP_BURSTS),
      .IS_WRITE_CHAN(1'b1)
  ) northcape_mmu_common_t;

  generate
    if (AXI_ADDR_WIDTH < 1 || AXI_DATA_WIDTH < 1 || AXI_ID_WIDTH < 1 || AXI_USER_WIDTH < 1) begin
      $error("Invalid parameters!");
    end
  endgenerate

  //===================================
  // Default assignments
  //===================================

  assign axis_validate_request_write.tstrb   = '1;
  assign axis_validate_request_write.tkeep   = '1;
  assign axis_validate_request_write.tid     = 0;
  assign axis_validate_request_write.tdest   = 0;
  assign axis_validate_request_write.tuser   = 0;
  assign axis_validate_request_write.twakeup = 1;
  assign axis_validate_request_write.tlast   = 1;

  //===================================
  // WRITE state + wires
  //===================================
  mmu_state_t state_q, state_d;

  axi_bus_addr_t initial_addr_write_q, initial_addr_write_d;
  // invariant: addr_write_q is the "currently" transferred address after burst started, addr_write_d is "next" transferred address (except in FORWARD_ADDR/WAIT_VALIDATION, where it is current)
  // addr_write_d1 is the value that goes into the register
  axi_bus_addr_t addr_write_q, addr_write_d, addr_write_d1;

  axi_len_t burst_len_write_q, burst_len_write_d, current_burst_len_write;
  axi_size_t burst_size_write_q, burst_size_write_d, current_burst_size_write;
  axi_burst_t burst_type_write_q, burst_type_write_d, current_burst_type_write;

  logic dec_burst_len_write_q;

  axis_validate_request_tdata_t request_tdata_write_d, request_tdata_write_q;
  axis_validate_response_tdata_t response_tdata_write;

  // guaranteed to be less than 128 by sizes
  logic [7:0] decoded_burst_size_write;

  bit [AXI_DATA_WIDTH/8-1:0] burst_mask_write;

  axi_bus_addr_t
      segment_start_write_q, segment_start_write_d, segment_end_write_q, segment_end_write_d;

  capability_id_t current_capability_id_write;
  capability_tag_t current_capability_tag_write;
  capability_off_t current_capability_offset_write;

  logic axi_master_valid_out_write;

  int unsigned bytes_in_burst_write;

  logic bounds_check_ok_write;

  logic axi_slave_data_burst_complete_write;
  logic axi_slave_data_transfer_complete_write;

  logic hold_wresp_valid, hold_wresp_valid_out;

  northcape_device_interpreted_restriction_t
      device_interpreted_restriction_write_q, device_interpreted_restriction_write_d;

  northcape_axi_user_t current_axi_user_write;

  task_id_t current_task_id;
  logic transaction_is_irq_q, transaction_is_irq_d;

  atomic_transaction_request_t atomic_transaction_request_d;

  // assignments for master registers
  logic [AXI_ID_WIDTH-1:0] axi_master_awid_d, axi_master_awid_q;
  axi_len_t axi_master_awlen_d, axi_master_awlen_q;
  axi_size_t axi_master_awsize_d, axi_master_awsize_q;
  axi_burst_t axi_master_awburst_d, axi_master_awburst_q;
  logic axi_master_awlock_d, axi_master_awlock_q;
  axi_cache_t axi_master_awcache_d, axi_master_awcache_q;
  axi_prot_t axi_master_awprot_d, axi_master_awprot_q;
  axi_qos_t axi_master_awqos_d, axi_master_awqos_q;
  axi_region_t axi_master_awregion_d, axi_master_awregion_q;
  logic [AXI_ADDR_WIDTH-1:0] axi_master_awaddr_d, axi_master_awaddr_q;
  axi5_atop_t axi_master_awatop_d, axi_master_awatop_q;

  logic first_beat_complete_read_d, first_beat_complete_read_q;


  bit [$clog2(AXI_DATA_WIDTH)-1:0] shift_out_write_q, shift_out_write_d;

  // when the resolver is ready, so are we - do not stall it
  assign axis_validate_response_write.tready = 1'b1;

`ifdef NORTHCAPE_TEST_COVERAGE
  covergroup mmu_write_chan_coverage_group @(posedge clk_i);
    coverpoint state_q;

    burst_len: coverpoint burst_len_write_q;
    burst_size: coverpoint burst_size_write_q;
    burst_type: coverpoint burst_type_write_q {ignore_bins reserved = {BURST_RESERVED};}

    burst_mask: coverpoint burst_mask_write {
      bins no_byte_masks = {8'b00000000};
      bins one_byte_mask = {8'b00000001};
      bins two_byte_mask = {8'b00000011};
      bins three_byte_mask = {8'b00000111};
      bins four_byte_mask = {8'b00001111};
      bins five_byte_mask = {8'b00011111};
      bins six_byte_mask = {8'b00111111};
      bins seven_byte_mask = {8'b01111111};
      bins eight_byte_mask = {8'b11111111};
      // should always cover one byte in monotonic order
      bins wrong_masks[] = default;
    }

    bounds_check_ok_write: coverpoint bounds_check_ok_write;

    cross burst_len, burst_size, burst_type, bounds_check_ok_write;
  endgroup

  mmu_write_chan_coverage_group cov_group;
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

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : wrapAddrFFLogic
    if (rst_ni == 0) begin
      addr_write_q <= '0;
    end else begin
      addr_write_q <= addr_write_d1;
    end
  end : wrapAddrFFLogic

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : axiMasterAttributeFFs
    if (rst_ni == 0) begin
      axi_master_awid_q <= '0;
      axi_master_awlen_q <= '0;
      axi_master_awsize_q <= '0;
      axi_master_awburst_q <= BURST_RESERVED;
      axi_master_awlock_q <= '0;
      axi_master_awcache_q <= '0;
      axi_master_awprot_q <= '0;
      axi_master_awqos_q <= '0;
      axi_master_awregion_q <= '0;
      axi_master_awaddr_q <= '0;
      axi_master_awatop_q <= '0;
      request_tdata_write_q <= '0;
    end else begin
      axi_master_awid_q <= axi_master_awid_d;
      axi_master_awlen_q <= axi_master_awlen_d;
      axi_master_awsize_q <= axi_master_awsize_d;
      axi_master_awburst_q <= axi_master_awburst_d;
      axi_master_awlock_q <= axi_master_awlock_d;
      axi_master_awcache_q <= axi_master_awcache_d;
      axi_master_awprot_q <= axi_master_awprot_d;
      axi_master_awqos_q <= axi_master_awqos_d;
      axi_master_awregion_q <= axi_master_awregion_d;
      axi_master_awaddr_q <= axi_master_awaddr_d;
      axi_master_awatop_q <= axi_master_awatop_d;
      request_tdata_write_q <= request_tdata_write_d;
    end
  end : axiMasterAttributeFFs

  logic request_atomic_transaction_q, request_atomic_transaction_d;

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : axiSlaveFFLogic
    if (rst_ni == 0) begin
      burst_len_write_q <= '0;
      burst_size_write_q <= '0;
      burst_type_write_q <= BURST_RESERVED;
      initial_addr_write_q <= '0;

      atomic_transaction_request_o.atomic_transaction_requested <= 0;

      atomic_transaction_request_o.burst_type <= BURST_RESERVED;
      atomic_transaction_request_o.slave_token <= '0;
      atomic_transaction_request_o.segment_start <= '0;
      atomic_transaction_request_o.segment_end <= '0;
      atomic_transaction_request_o.transaction_size <= '0;

      atomic_transaction_request_o.atomic_error <= 0;
      atomic_transaction_request_o.atomic_request_len <= '0;
      atomic_transaction_request_o.atomic_request_id <= '0;

      request_atomic_transaction_q <= 0;

      if (SHIFTING_ACTIVE) begin
        shift_out_write_q <= '0;
      end

      transaction_is_irq_q <= 1'b0;
    end else begin
      burst_len_write_q <= burst_len_write_d;
      burst_size_write_q <= burst_size_write_d;
      burst_type_write_q <= burst_type_write_d;
      initial_addr_write_q <= initial_addr_write_d;

      atomic_transaction_request_o <= atomic_transaction_request_d;
      request_atomic_transaction_q <= request_atomic_transaction_d;

      if (SHIFTING_ACTIVE) begin
        shift_out_write_q <= shift_out_write_d;
      end

      transaction_is_irq_q <= transaction_is_irq_d;
    end
  end : axiSlaveFFLogic

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : axisResponseFFLogic
    if (rst_ni == 0) begin
      segment_start_write_q <= '0;
      segment_end_write_q <= '0;
      device_interpreted_restriction_write_q <= '0;
    end else begin
      segment_start_write_q <= segment_start_write_d;
      segment_end_write_q <= segment_end_write_d;
      device_interpreted_restriction_write_q <= device_interpreted_restriction_write_d;

    end
  end : axisResponseFFLogic


  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : holdWrespReadyFF
    if (rst_ni == 0) begin
      hold_wresp_valid <= 0;
    end else begin
      hold_wresp_valid <= hold_wresp_valid_out;
    end
  end : holdWrespReadyFF

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

  always_comb begin : axiRequestParsingLogic
    burst_len_write_d = burst_len_write_q;
    burst_size_write_d = burst_size_write_q;
    burst_type_write_d = burst_type_write_q;
    initial_addr_write_d = initial_addr_write_q;

    unique case (state_q)
      IDLE: begin
        // the master cannot change the values later to trick us
        burst_len_write_d = current_burst_len_write;
        burst_size_write_d = current_burst_size_write;
        burst_type_write_d = current_burst_type_write;
        initial_addr_write_d = axi_slave.awaddr;
      end
      REPORT_ERROR: begin
        burst_len_write_d = burst_len_write_q - {7'h0, dec_burst_len_write_q};
      end
      FORWARD_DATA_FIRST_TRANSACTION, FORWARD_DATA: begin
        if (burst_type_write_q != WRAP || !ACCEPT_AXI_WRAP_BURSTS) begin
          burst_len_write_d = burst_len_write_q - {7'h0, dec_burst_len_write_q};
        end
      end
      default: begin
      end
    endcase
  end : axiRequestParsingLogic

  always_comb begin : restrictionParserLogic
    segment_start_write_d = segment_start_write_q;
    segment_end_write_d = segment_end_write_q;
    device_interpreted_restriction_write_d = device_interpreted_restriction_write_q;

    if (axis_validate_response_write.tvalid == 1'b1) begin
      segment_start_write_d = {32'h0, response_tdata_write.address};
      segment_end_write_d = {32'h0, response_tdata_write.address} + {32'h0, response_tdata_write.segment_length};

      if (response_tdata_write.restriction_type == NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED) begin
        device_interpreted_restriction_write_d = response_tdata_write.restriction.device_interpreted_bits;
      end else begin
        device_interpreted_restriction_write_d = '0;
      end
    end
  end : restrictionParserLogic

  always_comb begin : axiMasterAWForwardingLogic
    axi_master_awid_d = axi_master_awid_q;
    axi_master_awlen_d = axi_master_awlen_q;
    axi_master_awsize_d = axi_master_awsize_q;
    axi_master_awburst_d = axi_master_awburst_q;
    axi_master_awlock_d = axi_master_awlock_q;
    axi_master_awcache_d = axi_master_awcache_q;
    axi_master_awprot_d = axi_master_awprot_q;
    axi_master_awqos_d = axi_master_awqos_q;
    axi_master_awregion_d = axi_master_awregion_q;


    axi_master_awaddr_d = axi_master_awaddr_q;

    axi_master_awatop_d = axi_master_awatop_q;

    if (axi_slave.awvalid == 1'b1 && state_q == IDLE) begin
      // new transaction received - can already register in all forwarded fields except valid (depends on bounds check later)
      axi_master_awid_d = axi_slave.awid;
      axi_master_awlen_d = axi_slave.awlen;
      axi_master_awsize_d = axi_slave.awsize;
      axi_master_awburst_d = axi_slave.awburst;
      axi_master_awlock_d = axi_slave.awlock;
      axi_master_awcache_d = axi_slave.awcache;
      axi_master_awprot_d = axi_slave.awprot;
      axi_master_awqos_d = axi_slave.awqos;
      axi_master_awregion_d = axi_slave.awregion;
      // offset is (only) valid RIGHT now
      axi_master_awaddr_d = {32'h0, current_capability_offset_write};

      axi_master_awatop_d.atop_type = axi_slave.atop_type;
      axi_master_awatop_d.atop_subtype = axi_slave.atop_subtype;
    end else if (axis_validate_response_write.tvalid == 1'b1 && axis_validate_response_write.tready == 1'b1) begin
      // Control unit returns the beginning of the segment
      // bounds are checked at the same time by the state logic - if the device changes the offset later, we ignore the value
      // offset was set in idle
      axi_master_awaddr_d = current_capability_offset_write + {32'h0, response_tdata_write.address};
    end

    axi_master.awid = axi_master_awid_d;
    axi_master.awlen = axi_master_awlen_d;
    axi_master.awsize = axi_master_awsize_d;
    axi_master.awburst = axi_master_awburst_d;
    axi_master.awlock = axi_master_awlock_d;
    axi_master.awcache = axi_master_awcache_d;
    axi_master.awprot = axi_master_awprot_d;
    axi_master.awqos = axi_master_awqos_d;
    axi_master.awregion = axi_master_awregion_d;


    axi_master.awaddr = axi_master_awaddr_d;

    axi_master.atop_type = axi_master_awatop_d.atop_type;
    axi_master.atop_subtype = axi_master_awatop_d.atop_subtype;

    axi_slave.bid = axi_master_awid_d;

    // not valid after reset
    axi_master.awvalid = axi_master_valid_out_write;
  end : axiMasterAWForwardingLogic

  // global for debugging
  logic [AXI_DATA_WIDTH/8-1:0] strobe_mask, shifted_strobes;
  logic [AXI_DATA_WIDTH-1:0] shifted_data;
  bit direction_out;
  logic strobes_changed;

  assign strobes_changed = (strobe_mask != axi_slave.wstrb);

  generate
    if (ENABLE_ILA == 1'b1) begin
      mmu_mask_shift_debug_ila i_dbg_ila (
          .clk_i  (clk_i),
          .probe0 (state_q),
          .probe1 (addr_write_q),
          .probe2 (segment_start_write_d),
          .probe3 (segment_end_write_q),
          .probe4 (burst_size_write_q),
          .probe5 (  /* was beat number */),
          .probe6 (axi_master.awaddr),
          .probe7 (burst_mask_write),
          .probe8 (shifted_data),
          .probe9 (strobe_mask),
          .probe10(shift_out_write_q),
          .probe11(strobes_changed),
          .probe12(shifted_strobes),
          .probe13(axi_slave.wstrb),
          .probe14(axi_slave.wvalid)
      );
    end else begin
`ifndef ASIC
      $info("Not generating debug ILA!");
`endif
    end
  endgenerate

  always_comb begin : axiMasterWdataLogic
    // default assignments
    axi_master.wstrb = '0;
    axi_master.wlast = '0;
    axi_master.wvalid = '0;
    axi_slave.wready = 0;

    // unused; copying suffices
    axi_master.wid = axi_slave.wid;

    // e.g., cva6 uses the user bits for communicating with the atomics wrapper
    axi_master.wuser = axi_slave.wuser;


    if (MASKING_ACTIVE) begin
      // for first beat in WAIT_VALIDATION or FORWARD_ADDR, must use "next" address, as register has not been set
      burst_mask_write = northcape_mmu_common_t::get_per_byte_mask_for_addr(
        !first_beat_complete_read_q ? addr_write_d : addr_write_q,
        segment_start_write_d,
        segment_end_write_d
      );

      strobe_mask = burst_mask_write;
    end else begin
      strobe_mask = '1;
    end

    if (SHIFTING_ACTIVE) begin
      // data and strobes are expected in the same respective lanes, we must shift both
      // we do not need to mask the data, however, as the strobes control what part is ignored
      shifted_strobes = northcape_mmu_common_t::shift_strobes(axi_slave.wstrb, shift_out_write_d);
      shifted_data = northcape_mmu_common_t::shift_data(axi_slave.wdata, shift_out_write_d);
    end else begin
      shifted_strobes = axi_slave.wstrb;
      shifted_data = axi_slave.wdata;
    end

    axi_master.wdata = shifted_data;

    unique case (state_q)
      WAIT_COMPLETE, FORWARD_DATA: begin
        axi_slave.wready  = axi_master.wready;
        axi_master.wvalid = axi_slave.wvalid;
        axi_master.wlast  = axi_slave.wlast;
        // have missed the last transaction transition, but need to apply the mask
        axi_master.wstrb  = shifted_strobes & strobe_mask;
      end
      REQUEST_VALIDATION, WAIT_VALIDATION: begin
        // cannot check bounds before response from responder
        axi_slave.wready  = bounds_check_ok_write & axi_master.wready;
        axi_master.wvalid = bounds_check_ok_write & axi_slave.wvalid;
        axi_master.wlast  = bounds_check_ok_write & axi_slave.wlast;

        axi_master.wstrb  = shifted_strobes & strobe_mask;
      end
      FORWARD_ADDR, FORWARD_DATA_FIRST_TRANSACTION: begin
        axi_slave.wready  = axi_master.wready;
        axi_master.wvalid = axi_slave.wvalid;
        axi_master.wlast  = axi_slave.wlast;

        axi_master.wstrb  = shifted_strobes & strobe_mask;
      end
      FORWARD_DATA_LAST_TRANSACTION: begin
        axi_slave.wready  = axi_master.wready;
        axi_master.wvalid = axi_slave.wvalid;
        axi_master.wlast  = axi_slave.wlast;

        axi_master.wstrb  = shifted_strobes & strobe_mask;
      end
      FORWARD_DATA_ZERO_OUT: begin
        // we are forwarding all-zeros data, control signals can be copied
        axi_master.wstrb  = '0;
        axi_master.wvalid = axi_slave.wvalid;
        axi_master.wlast  = axi_slave.wlast;

        axi_slave.wready  = axi_master.wready;
      end
      REPORT_ERROR: begin
        axi_master.wstrb  = '0;
        axi_master.wvalid = 0;
        axi_master.wlast  = 0;
        // burst must be completed - throw the data away
        axi_slave.wready  = 1;
      end
      LAST_REPORT_ERROR: begin
        axi_master.wstrb  = '0;
        // this is already 1 from previous cycles, and so might be ready
        axi_master.wvalid = 0;
        axi_master.wlast  = 0;
        // burst must be completed - throw the data away
        axi_slave.wready  = 1;
      end
      SINGLE_REPORT_ERROR: begin
        axi_master.wstrb  = '0;
        // might otherwise hold this for 1 too many cycles
        axi_master.wvalid = 0;
        axi_master.wlast  = 0;
        // burst must be completed - throw the data away
        axi_slave.wready  = 1;
      end
      default: begin
        // we're not actively forwarding data - other lanes can keep their value, but valid MUST stay low
        // this also includes transfers where we mask out entire words, e.g., burst
        axi_master.wvalid = 0;
        axi_slave.wready  = 0;
      end
    endcase
  end

  always_comb begin : axiSlaveRespLogic
    // default assignments
    axi_slave.bvalid = 0;
    axi_slave.bresp = DECERR;
    axi_master.bready = 0;

    // write user never used
    axi_slave.buser = '0;


    hold_wresp_valid_out = hold_wresp_valid;

    unique case (state_q)
      REPORT_ERROR, LAST_REPORT_ERROR, SINGLE_REPORT_ERROR: begin
        // bvalid should only be helt for one cycle, such that we do not accidentally terminate a second / following transaction
        axi_slave.bvalid = 0;
        axi_slave.bresp = DECERR;
        hold_wresp_valid_out = 1;
      end
      FORWARD_DATA, FORWARD_DATA_FIRST_TRANSACTION, FORWARD_DATA_LAST_TRANSACTION: begin
        // either transaction was forwarded or no transaction started - our wresp channel is in the same state as the upstream one
        // need to make sure valid gets 0ed when either upstream is not yet ready or slave has already confirmed the valid
        axi_slave.bvalid  = axi_master.bvalid && (!axi_slave.bready || !axi_slave.bvalid);
        axi_slave.bresp   = axi_master.bresp;
        axi_master.bready = axi_slave.bready;

      end
      WAIT_COMPLETE: begin
        // after a successful transfer, we can simply forward the channels
        axi_slave.bvalid  = axi_master.bvalid;
        axi_slave.bresp   = axi_master.bresp;
        axi_master.bready = axi_slave.bready;
      end
      REPORT_ERROR_BCHAN: begin
        // can only raise bvalid AFTER last write beat was accepted
        // but must only raise it for one cycle
        axi_slave.bvalid = 0;
        axi_slave.bresp  = DECERR;
        if (hold_wresp_valid) begin
          axi_slave.bvalid = 1;
          if (axi_slave.bready == 1'b1) begin
            // keep the valid for one more cycle
            hold_wresp_valid_out = 0;
          end
        end
      end
      default: begin
        // slave might query for the transaction status at any time - hold everything until slave is ready
        if (hold_wresp_valid) begin
          axi_slave.bvalid = 1;
          if (axi_slave.bready == 1'b1) begin
            // keep the valid for one more cycle
            hold_wresp_valid_out = 0;
          end
        end else begin
          // might be from last completed transaction
          axi_slave.bvalid  = axi_master.bvalid;
          axi_slave.bresp   = axi_master.bresp;
          axi_master.bready = axi_slave.bready;
        end
      end

    endcase
  end

  always_comb begin : validateResponseParsingLogic
    response_tdata_write = axis_validate_response_write.tdata;
  end : validateResponseParsingLogic

  always_comb begin : taskIdLogic
    // maintained in a FF in case the AW handshake does not complete immediately
    // we leave IDLE as soon as the transaction is requested - lock the bit in at the right time
    unique case (state_q)
      IDLE: transaction_is_irq_d = axi_slave.awuser[1];
      default: transaction_is_irq_d = transaction_is_irq_q;
    endcase
    current_task_id = transaction_is_irq_d ? current_task_id_irq_i : current_task_id_non_irq_i;
  end : taskIdLogic

  always_comb begin : requestTdataLogic
    automatic
    bit
    is_not_atomic = (axi_slave.atop_type == ATOMIC_NONE || axi_slave.atop_type == ATOMIC_STORE);

    request_tdata_write_d = request_tdata_write_q;

    // master can change address at any time
    if (state_q == IDLE) begin
      request_tdata_write_d.address = current_capability_id_write;
      request_tdata_write_d.tag = current_capability_tag_write;
      // need to indicate both read and write for atomics that return
      request_tdata_write_d.device_id = WRITE_CHAN_DEVICE_ID;
      if (DEVICE_INDICATES_EXECUTE) begin
        request_tdata_write_d.task_id = current_task_id;
        unique case ({
          is_not_atomic, transaction_is_irq_d
        })
          2'b00: request_tdata_write_d.access_type = READ_WRITE;
          2'b01: request_tdata_write_d.access_type = READ_WRITE_IRQ;
          2'b10: request_tdata_write_d.access_type = WRITE;
          default request_tdata_write_d.access_type = WRITE_IRQ;
        endcase
      end else begin
        request_tdata_write_d.task_id = '0;
        request_tdata_write_d.access_type = is_not_atomic ? WRITE : READ_WRITE;
      end

      request_tdata_write_d.flags.is_recursion = 1'b0;
      request_tdata_write_d.flags.have_base_length = 1'b0;
      request_tdata_write_d.flags.have_lock_key = 1'b0;
      request_tdata_write_d.flags.reserved = '0;
      request_tdata_write_d.original_address = '0;
      request_tdata_write_d.original_segment_length = '0;
      request_tdata_write_d.original_permission_tid_match = 1'b0;
      request_tdata_write_d.original_permissions = '0;
      request_tdata_write_d.lock_key = '0;

      request_tdata_write_d.restriction = '0;
      request_tdata_write_d.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
      request_tdata_write_d.error_code = NORTHCAPE_RESOLVE_NO_ERROR;
    end

    axis_validate_request_write.tdata = request_tdata_write_d;
  end : requestTdataLogic

  always_comb begin : axiUserOutputConstructor
    current_axi_user_write.reserved = '0;
    current_axi_user_write.device_interpreted_restriction = device_interpreted_restriction_write_d;
    // both MMU chans are the same device
    current_axi_user_write.current_device_id = (WRITE_CHAN_DEVICE_ID) >> 1;
    current_axi_user_write.current_task_id = current_task_id;

    axi_master.awuser = current_axi_user_write;
  end : axiUserOutputConstructor



  always_comb begin : capabilityTokenParsing
    current_capability_id_write =
        capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(initial_addr_write_d);
    current_capability_tag_write =
        capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(initial_addr_write_d);
    current_capability_offset_write =
        capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(initial_addr_write_d);
  end : capabilityTokenParsing

  always_comb begin : boundsCheckLogic
    automatic logic [AXI_ADDR_WIDTH - 1 : 0] start_addr;
    start_addr = current_capability_offset_write + (ACCEPT_AXI_WRAP_BURSTS && burst_type_write_q == WRAP ? axi5_address_calculations#(AXI_ADDR_WIDTH)::axi5_wrapped_burst_get_start_address(
        burst_len_write_q, burst_size_write_q, {32'h0, response_tdata_write.address}) :
        response_tdata_write.address);

    shift_out_write_d = shift_out_write_q;

    if (axis_validate_response_write.tvalid) begin
      // our capability token always imply offset 0
      // our capability segments need not be bus-width aligned, though
      // we need to shift accordingly to correct this
      shift_out_write_d = AXI_DATA_WIDTH / 8 - response_tdata_write.address % (AXI_DATA_WIDTH / 8);
    end

    decoded_burst_size_write = 1 << burst_size_write_q;
    bytes_in_burst_write = northcape_mmu_common_t::getBytesInBurst(
      burst_size_write_q,
      burst_type_write_q,
      burst_len_write_q,
      start_addr,
      decoded_burst_size_write
    );
    if (axis_validate_response_write.tvalid == 1'b1) begin
      bounds_check_ok_write = northcape_mmu_common_t::checkBounds(
        bytes_in_burst_write,
        current_capability_offset_write,
        response_tdata_write.segment_length,
        burst_type_write_q,
        start_addr,
        cmt_interface.cmt_base,
        cmt_interface.table_size_clog2,
        burst_len_write_q,
        decoded_burst_size_write,
        response_tdata_write.address % (AXI_DATA_WIDTH / 8) != 0,
        .self_preservation_mode_active(SELF_PRESERVATION_MODE_ACTIVE),
        .shifting_active(SHIFTING_ACTIVE)
      );
    end else begin
      // HAVE to ignore invalid data
      bounds_check_ok_write = 1'b0;
    end
  end : boundsCheckLogic


  always_comb begin : nextStateLogicWrite
    if(state_q == REPORT_ERROR || state_q == LAST_REPORT_ERROR || state_q == SINGLE_REPORT_ERROR)
        begin
      // we always generate ready=1
      axi_slave_data_burst_complete_write = axi_slave.wvalid;
      axi_slave_data_transfer_complete_write = axi_slave.wvalid && axi_slave.wlast;
    end else begin
      // master generates handshaking symbols
      axi_slave_data_burst_complete_write = axi_slave.wvalid && axi_slave.wready;
      axi_slave_data_transfer_complete_write = axi_slave.wvalid && axi_slave.wready && axi_slave.wlast;
    end
    // default output values
    // also, write side does not forward atomic transactions (but the read side does)
    state_d = northcape_mmu_common_t::computeNextState(
      .current_state(state_q),
      .slave_address_channel_valid_ready(axi_slave.awvalid && axi_slave.awready),
      .axis_validate_request_ready(axis_validate_request_write.tvalid && axis_validate_request_write.tready),
      .axis_validate_response_valid(axis_validate_response_write.tvalid),
      .bounds_check_ok(bounds_check_ok_write),
      .last_burst_len(burst_len_write_q),
      .last_burst_size(burst_size_write_q),
      .last_burst_type(burst_type_write_q),
      .master_addr_chan_ready(axi_master.awvalid & axi_master.awready), // might stall the valid signal waiting for read chan
      .last_segment_start(segment_start_write_d),
      .last_segment_end(segment_end_write_d),
      .axi_slave_data_burst_complete(axi_slave_data_burst_complete_write),
      .axi_slave_data_transfer_complete(axi_slave_data_transfer_complete_write),
      .axi_slave_data_channel_ready(axi_slave.wready),
      .master_addr_chan_addr(axi_master.awaddr),
      .input_data_chan_valid(axi_slave.wvalid),
      .input_data_chan_last(axi_slave.wlast),
      .last_wrap_addr(state_q inside {REQUEST_VALIDATION, WAIT_VALIDATION, FORWARD_ADDR} ? addr_write_d : addr_write_q),
      .expect_atomic_transaction(0),
      .atomic_transaction_complete(0),
      .error_beat_complete(axi_slave.wvalid),
      .atomic_request_error_in(0),
      .axi_slave_bready(axi_slave.bready)
    );
  end : nextStateLogicWrite

  always_comb begin : writeFSMOutputLogicWrite
    axi_slave.awready = 0;
    axis_validate_request_write.tvalid = 0;
    current_burst_len_write = burst_len_write_q;
    current_burst_size_write = burst_size_write_q;
    current_burst_type_write = burst_type_write_q;
    axi_master_valid_out_write = 0;
    first_beat_complete_read_d = first_beat_complete_read_q;

    if (state_q == IDLE || !first_beat_complete_read_q) begin
      // reset + set again if already valid
      first_beat_complete_read_d = axi_slave.wvalid && axi_slave.wready;
    end

    // othwerwise, the address might be incremented when no transaction was actually completed (yet)
    if (first_beat_complete_read_q && axi_master.wvalid && axi_master.wready) begin
      addr_write_d = northcape_mmu_common_t::get_next_addr(burst_type_write_q, addr_write_q,
                                                           burst_len_write_q, burst_size_write_q);
      addr_write_d1 = addr_write_d;
    end else if (!first_beat_complete_read_q) begin
      // have starting address
      // use registered value here to ensure the value does not change
      addr_write_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(
          initial_addr_write_q) + segment_start_write_d;
      addr_write_d1 = addr_write_d;
      if (axi_master.wvalid && axi_master.wready) begin
        // need to jump ahead to maintain addr_write_q invariant
        addr_write_d1 = northcape_mmu_common_t::get_next_addr(
            burst_type_write_q, addr_write_d, burst_len_write_q, burst_size_write_q);
      end
    end else begin
      addr_write_d  = addr_write_q;
      addr_write_d1 = addr_write_q;
    end

    dec_burst_len_write_q = 0;

    atomic_transaction_request_d = atomic_transaction_request_o;
    request_atomic_transaction_d = request_atomic_transaction_q;


    // output logic based on next state
    unique case (state_q)
      IDLE: begin
        // this has to be helt for only one cycle to let the master know we have processed the request
        axi_slave.awready = 1;
        if (axi_slave.awvalid == 1'b1) begin
          // do not request until transaction confirmed
          axis_validate_request_write.tvalid = axi_slave.awvalid && axi_slave.awready;

          // need to remember burst size and len for permission check
          current_burst_len_write = axi_slave.awlen;
          current_burst_size_write = axi_slave.awsize;
          current_burst_type_write = axi_slave.awburst;
        end

        atomic_transaction_request_d.atomic_error = 0;
        atomic_transaction_request_d.atomic_request_len = axi_slave.awlen;
        atomic_transaction_request_d.atomic_request_id = axi_slave.awid;

        atomic_transaction_request_d.burst_type = current_burst_type_write;
        atomic_transaction_request_d.slave_token = axi_slave.awaddr;
        atomic_transaction_request_d.transaction_size = current_burst_size_write;

        // atomic stores have no data response
        if (axi_slave.atop_type != ATOMIC_NONE && axi_slave.atop_type != ATOMIC_STORE) begin
          request_atomic_transaction_d = axi_slave.awvalid;
        end
        // either 0 or helt at least one cycle
        atomic_transaction_request_d.atomic_transaction_requested = 1'b0;
      end
      REQUEST_VALIDATION, WAIT_VALIDATION: begin
        // high unconditionally in REQUEST_VALIDATION - need to make sure that the slave has seen it for one cycle
        axis_validate_request_write.tvalid = (state_q == REQUEST_VALIDATION);
        if (axis_validate_response_write.tvalid == 1'b1) begin
          if (bounds_check_ok_write) begin
            // see FORWARD_ADDR - we do not want to risk deadlocking the read side here
            axi_master_valid_out_write = request_atomic_transaction_q ? 1'b0 : 1'b1;
          end
        end
      end
      WAIT_ADDRESS_HANDSHAKE, FORWARD_ADDR: begin
        // in case of an atomic transaction, we must also wait for the read side of the MMU to stall waiting for the read response
        // otherwise, we might deadlock the AXI crossbar - the MMU might wait for resolver response, while the resolver might wait for rvalid
        // the crossbar might wait for the MMU to accept the R response from the atomic and stall the resolver...

        // in case of non-atomic, we will leave this state as soon as ready is high - can set to 1 unconditionally
        // in case of atomic, we cannot assume that awvalid has been set high yet - might have had to wait for the read side
        axi_master_valid_out_write = request_atomic_transaction_q ? rd_channel_is_waiting_for_atomic_i : 1'b1;
        if (request_atomic_transaction_q) begin
          request_atomic_transaction_d = 1'b0; // must wait for the MMU to be able to accept R response before we set this down
          atomic_transaction_request_d.atomic_transaction_requested = 1'b1;
          atomic_transaction_request_d.segment_start = segment_start_write_q;
          atomic_transaction_request_d.segment_end = segment_end_write_q;
        end
      end
      FORWARD_DATA_FIRST_TRANSACTION, FORWARD_DATA, REPORT_ERROR: begin
        if (axi_slave_data_burst_complete_write) begin
          // one transaction burst was completed - one less to go
          dec_burst_len_write_q = 1;
        end
        if (state_q == REPORT_ERROR) begin
          // either 0 or helt at least one cycle
          atomic_transaction_request_d.atomic_transaction_requested = 1'b0;
          atomic_transaction_request_d.atomic_error = 1;
          request_atomic_transaction_d = 0;
          if (request_atomic_transaction_q) begin
            atomic_transaction_request_d.atomic_transaction_requested = 1'b1;
          end
        end else begin
          // either 0 or helt at least one cycle
          atomic_transaction_request_d.atomic_transaction_requested = 1'b0;
          // the MMU has understood that we are doing an atomic transaction
          request_atomic_transaction_d = 1'b0;
        end
      end
      SINGLE_REPORT_ERROR: begin
        atomic_transaction_request_d.atomic_error = 1;
        request_atomic_transaction_d = 0;
        if (request_atomic_transaction_q) begin
          atomic_transaction_request_d.atomic_transaction_requested = 1'b1;
        end
      end
      default: begin
        // either 0 or helt at least one cycle
        atomic_transaction_request_d.atomic_transaction_requested = 1'b0;
      end
    endcase
  end : writeFSMOutputLogicWrite

  `NORTHCAPE_UNREAD(axi_slave.clk_i);
  `NORTHCAPE_UNREAD(axi_slave.rst_ni);
  `NORTHCAPE_UNREAD(axi_slave.bid);
  `NORTHCAPE_UNREAD(axi_slave.buser);
  `NORTHCAPE_UNREAD(axi_slave.awuser);
  `NORTHCAPE_UNREAD(axi_master.clk_i);
  `NORTHCAPE_UNREAD(axi_master.rst_ni);
  `NORTHCAPE_UNREAD(axi_master.bid);
  `NORTHCAPE_UNREAD(axi_master.buser);
  `NORTHCAPE_UNREAD(axis_validate_request_write.clk_i);
  `NORTHCAPE_UNREAD(axis_validate_request_write.rst_ni);
  `NORTHCAPE_UNREAD(axis_validate_response_write.clk_i);
  `NORTHCAPE_UNREAD(axis_validate_response_write.rst_ni);
  `NORTHCAPE_UNREAD(axis_validate_response_write.tdata);
  `NORTHCAPE_UNREAD(axis_validate_response_write.tstrb);
  `NORTHCAPE_UNREAD(axis_validate_response_write.tkeep);
  `NORTHCAPE_UNREAD(axis_validate_response_write.tlast);
  `NORTHCAPE_UNREAD(axis_validate_response_write.tid);
  `NORTHCAPE_UNREAD(axis_validate_response_write.tdest);
  `NORTHCAPE_UNREAD(axis_validate_response_write.tuser);
  `NORTHCAPE_UNREAD(axis_validate_response_write.twakeup);

  `NORTHCAPE_UNREAD(cmt_interface.clk_i);
  `NORTHCAPE_UNREAD(cmt_interface.cmt_base);
  `NORTHCAPE_UNREAD(cmt_interface.table_size_clog2);
  `NORTHCAPE_UNREAD(cmt_interface.reset_done);
  `NORTHCAPE_UNREAD(cmt_interface.need_flush_data_caches);
  `NORTHCAPE_UNREAD(cmt_interface.wrote_any_capability);
  `NORTHCAPE_UNREAD(cmt_interface.written_capability);

  `NORTHCAPE_UNREAD(response_tdata_write.permissions);
  `NORTHCAPE_UNREAD(response_tdata_write.error_code);

  `NORTHCAPE_UNREAD(axi_slave.awuser);
  `NORTHCAPE_UNREAD(axi_slave.wuser);
endmodule
