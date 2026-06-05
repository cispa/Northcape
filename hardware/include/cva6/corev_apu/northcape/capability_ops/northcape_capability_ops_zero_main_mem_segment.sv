/**
  * Part of the northcape capability operations module.
  * Contains an FSM that can be used for zeroing a segment in main memory.
  */
module northcape_capability_ops_zero_main_mem_segment #(
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_ID_WIDTH   = -1,
    parameter AXI_USER_WIDTH = -1
) (
    Axi5WriteOnly.FROM axi_master,

    input northcape_types::northcape_physical_address_t segment_phys_addr_i,
    input northcape_types::segment_length_t segment_length_i,

    input  logic start_i,
    output logic done_o,

    output logic [2:0] debug_state_o,
    output logic [8:0] debug_zero_len_o
);
  import northcape_types::*;
  import axi5::*;
  import northcape_mmu_common::NorthcapeMMUCommon;

  `include "northcape_unread.vh"

  typedef enum {
    ZERO_SEGMENT_IDLE,
    ZERO_SEGMENT_SETUP_WRITE,
    ZERO_SEGMENT_WAIT_WRITE_COMPLETE,
    ZERO_SEGMENT_WAIT_RESPONSE,
    ZERO_SEGMENT_CHECK_MORE,
    ZERO_SEGMENT_DONE
  } northcape_capability_ops_cmt_zero_state_t;

  // hierarchical state machine for zeroing the CMT
  northcape_capability_ops_cmt_zero_state_t zero_segment_state_q, zero_segment_state_d;

  // FSM for zeroing CMT private state
  logic [AXI_ADDR_WIDTH-1:0] zero_addr_q, zero_addr_d;
  // invariant: in SETUP_WRITE, WAIT_WRITE_COMPLETE states, this is the number of UNFINISHED bursts AFTER the current cycle
  // maximum value is 256
  logic [8:0] zero_len_q, zero_len_d;
  logic zero_is_last_q, zero_is_last_d;
  int unsigned zero_bursts_left_q, zero_bursts_left_d, zero_bursts_initial_d;
  // B (response) channel handshake can happen at any point...
  logic b_handshake_complete_d, b_handshake_complete_q;

  // AXI handshake signals
  logic awvalid_d, wvalid_d, bready_d, wlast_d;
  logic [AXI_ADDR_WIDTH-1:0] awaddr_d;
  logic [AXI_DATA_WIDTH-1:0] wdata_d;
  logic [AXI_DATA_WIDTH/8-1:0] wstrb_d;
  axi_len_t awlen_d;

  logic clk_i;
  logic rst_ni;

  localparam int unsigned MAX_BYTES_PER_BURST = (AXI_DATA_WIDTH / 8) * AXI5_MAX_BURST_LEN;

  logic [AXI_DATA_WIDTH/8-1:0] beat_strobes_d;

  // we need to keep track of the bounds of the segment here...
  int unsigned transfer_num_q, transfer_num_d;
  int unsigned beat_num_q, beat_num_d;

  logic done_d;

  logic first_beat_completed;

  assign clk_i  = axi_master.clk_i;
  assign rst_ni = axi_master.rst_ni;

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : stateQFF
    if (rst_ni == 0) begin
      zero_segment_state_q <= ZERO_SEGMENT_IDLE;
    end else begin
      zero_segment_state_q <= zero_segment_state_d;
    end
  end : stateQFF

  // static/default values
  assign axi_master.awsize = $clog2(AXI_DATA_WIDTH / 8);
  assign axi_master.awburst = INCR;
  assign axi_master.awlock = 0;
  assign axi_master.awcache = '0;
  assign axi_master.awprot = '0;
  assign axi_master.awqos = '0;
  assign axi_master.awregion = '0;
  assign axi_master.awuser = '0;
  assign axi_master.awid = '0;
  assign axi_master.atop_type = ATOMIC_NONE;
  assign axi_master.atop_subtype = '0;

  assign axi_master.wid = '0;
  assign axi_master.wuser = '0;

  assign zero_bursts_initial_d = segment_length_i / MAX_BYTES_PER_BURST + (segment_length_i % MAX_BYTES_PER_BURST ? 1 : 0);

  // flip-flops for zero FSM private data
  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : zeroFSMFF
    if (rst_ni == 0) begin
      zero_addr_q <= '0;
      zero_len_q <= 0;
      zero_is_last_q <= 0;
      zero_bursts_left_q <= '0;
      done_o <= 0;

      transfer_num_q <= '0;
      beat_num_q <= '0;

      b_handshake_complete_q <= 1'b0;
    end else begin
      zero_addr_q <= zero_addr_d;
      zero_len_q <= zero_len_d;
      zero_is_last_q <= zero_is_last_d;
      zero_bursts_left_q <= zero_bursts_left_d;
      done_o <= done_d;

      transfer_num_q <= transfer_num_d;
      beat_num_q <= beat_num_d;

      b_handshake_complete_q <= b_handshake_complete_d;
    end
  end : zeroFSMFF

  // axi signalling logic
  always_comb begin : axiHandshakeLogic
    awvalid_d = 1'b0;
    wvalid_d = 1'b0;
    bready_d = 1'b0;

    // valid or ignored
    awaddr_d = zero_addr_q;

    wdata_d = 1'b0;
    wlast_d = 1'b0;
    wstrb_d = '0;

    b_handshake_complete_d = b_handshake_complete_q;

    unique case (zero_segment_state_q)
      ZERO_SEGMENT_SETUP_WRITE: begin
        awvalid_d = 1'b1;

        wvalid_d  = 1'b1;
        wdata_d   = '0;
        wlast_d   = zero_is_last_d;

        wstrb_d   = beat_strobes_d;

        bready_d  = 1'b1;
        b_handshake_complete_d |= axi_master.bvalid;
      end
      ZERO_SEGMENT_WAIT_WRITE_COMPLETE: begin
        // leave state immediately once write is done
        wvalid_d = 1'b1;
        wdata_d  = '0;
        // zero_is_last_q might lag behind on last transaction in longer burst
        wlast_d  = zero_is_last_d;

        bready_d = 1'b1;

        wstrb_d  = beat_strobes_d;

        b_handshake_complete_d |= axi_master.bvalid;
      end
      ZERO_SEGMENT_WAIT_RESPONSE: begin
        wvalid_d = 0;
        wlast_d  = 0;
        bready_d = 1'b1;

        b_handshake_complete_d |= axi_master.bvalid;
      end
      default: begin
        awvalid_d = 0;
        wvalid_d = 0;
        bready_d = 0;
        b_handshake_complete_d = 1'b0;
      end
    endcase

    axi_master.awvalid = awvalid_d;
    axi_master.wvalid  = wvalid_d;
    axi_master.bready  = bready_d;
    axi_master.awaddr  = awaddr_d;
    axi_master.awlen   = awlen_d;
    axi_master.wdata   = wdata_d;
    axi_master.wlast   = wlast_d;
    axi_master.wstrb   = wstrb_d;
  end : axiHandshakeLogic
`ifndef ASIC
  property writeWithinSegmentBounds;
    @(posedge clk_i) disable iff (!awvalid_d)
   awaddr_d >= segment_phys_addr_i && awaddr_d + (awlen_d + 1) * AXI_DATA_WIDTH/8 <= segment_phys_addr_i + segment_length_i;
  endproperty
  withinBounds :
  assert property (writeWithinSegmentBounds);

  property segmentLengthPositive;
    @(posedge clk_i) disable iff (!start_i) segment_length_i != 0;
  endproperty
  segmentLengthPermissible :
  assert property (segmentLengthPositive);
`endif

  // zeroing logic
  always_comb begin : segmentZeroLogic
    zero_addr_d = zero_addr_q;
    zero_len_d = zero_len_q;
    zero_is_last_d = zero_is_last_q;
    zero_bursts_left_d = zero_bursts_left_q;
    done_d = done_o;

    transfer_num_d = transfer_num_q;
    beat_num_d = beat_num_q;

    awlen_d = '0;

    // in CHECK_MORE state, wvalid is low - cannot count the wready yet
    first_beat_completed = zero_segment_state_q == ZERO_SEGMENT_SETUP_WRITE && axi_master.wready;

    unique case (zero_segment_state_q)
      ZERO_SEGMENT_IDLE: begin
        zero_bursts_left_d = zero_bursts_initial_d;
        done_d = 0;
        zero_addr_d = segment_phys_addr_i;
        transfer_num_d = '0;
        beat_num_d = '0;
      end
      // in ZERO_SEGMENT_CHECK_MORE, need to set length etc. for next request
      ZERO_SEGMENT_CHECK_MORE, ZERO_SEGMENT_SETUP_WRITE: begin
        // when this burst is completed, we can go on to the next one
        // we might be into the burst for two cycles, depending on whether wready goes high immediately
        if (zero_bursts_left_q == 1) begin
          zero_len_d = (segment_length_i % MAX_BYTES_PER_BURST) / (AXI_DATA_WIDTH / 8);
          // segment could be smaller than bus width
          zero_len_d += (segment_length_i % MAX_BYTES_PER_BURST) % (AXI_DATA_WIDTH / 8) ? 1 : 0;
          if (!zero_len_d) begin
            // must have been an exact multiple of the max length
            zero_len_d = AXI5_MAX_BURST_LEN;
          end
          // the indicated value - how many beats we want to transfer minus 1 acc. to AXI spec
          // as long as zero_len_d is not 0, this does not overflow - zero_len_d cannot be null after two edge cases above are caught
          awlen_d = zero_len_d - 1;

          // last burst - len might be shorter
          // first beat might already be accepted right now
          zero_is_last_d = zero_len_d == 1;
          // now, this is the number of beats to wait for
          // did the first transfer happen already?
          zero_len_d -= first_beat_completed;
        end else begin
          // more bursts to follow - write as many as possible
          // first beat might already be accepted right now
          zero_len_d = AXI5_MAX_BURST_LEN - first_beat_completed;
          awlen_d = AXI5_MAX_BURST_LEN - 1;
          zero_is_last_d = 0;
        end
        if (zero_segment_state_q == ZERO_SEGMENT_CHECK_MORE) begin
          zero_bursts_left_d = zero_bursts_left_q - 1;
          zero_addr_d = zero_addr_q + AXI5_MAX_BURST_LEN * (AXI_DATA_WIDTH / 8);
          transfer_num_d = transfer_num_q + 1;
        end
        // might already have accepted one beat
        beat_num_d = first_beat_completed;
      end
      ZERO_SEGMENT_WAIT_WRITE_COMPLETE: begin
        zero_is_last_d = zero_len_q == 1;
        if (axi_master.wready && zero_len_q != 0) begin
          // beat accepted
          zero_len_d = zero_len_q - 1;
          beat_num_d = beat_num_q + 1;
        end
      end
      ZERO_SEGMENT_DONE: begin
        done_d = 1;
      end
      default: begin
        // nothing to do currently
      end

    endcase

  end : segmentZeroLogic

  // FSM next state logic for zeroing CMT
  always_comb begin : segmentZeroStateMachine
    zero_segment_state_d = zero_segment_state_q;

    unique case (zero_segment_state_q)
      ZERO_SEGMENT_IDLE: begin
        if (start_i) begin
          zero_segment_state_d = ZERO_SEGMENT_SETUP_WRITE;
        end
      end
      ZERO_SEGMENT_SETUP_WRITE: begin
        if (axi_master.awready) begin
          // write accepted
          if (axi_master.wready && zero_is_last_d) begin
            // single transfer
            if (b_handshake_complete_d) begin
              // completed beat in one go
              zero_segment_state_d = ZERO_SEGMENT_CHECK_MORE;
            end else begin
              // need to wait for write confirmation
              zero_segment_state_d = ZERO_SEGMENT_WAIT_RESPONSE;
            end
          end else begin
            // more beats
            zero_segment_state_d = ZERO_SEGMENT_WAIT_WRITE_COMPLETE;
          end
        end
      end
      ZERO_SEGMENT_WAIT_WRITE_COMPLETE: begin
        if (axi_master.wready && axi_master.wlast) begin
          if (b_handshake_complete_d) begin
            zero_segment_state_d = ZERO_SEGMENT_CHECK_MORE;
          end else begin
            zero_segment_state_d = ZERO_SEGMENT_WAIT_RESPONSE;
          end
        end
      end
      ZERO_SEGMENT_WAIT_RESPONSE: begin
        if (b_handshake_complete_d) begin
          zero_segment_state_d = ZERO_SEGMENT_CHECK_MORE;
        end
      end
      ZERO_SEGMENT_CHECK_MORE: begin
        // transaction complete, will dec to 0 in one cycle
        if (zero_bursts_left_q == 1) begin
          // no bursts left
          zero_segment_state_d = ZERO_SEGMENT_DONE;
        end else begin
          // start next write
          zero_segment_state_d = ZERO_SEGMENT_SETUP_WRITE;
        end
      end
      ZERO_SEGMENT_DONE: begin
        zero_segment_state_d = ZERO_SEGMENT_IDLE;
      end
    endcase
  end : segmentZeroStateMachine

  // as it happens, the MMU has to compute the same thing
  typedef NorthcapeMMUCommon#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .IS_WRITE_CHAN (1)
  ) northcape_mmu_common_t;
  // global for debugging
  logic [AXI_ADDR_WIDTH-1:0] current_addr, initial_addr;
  int unsigned used_beat_num;
  always_comb begin : lastBeatStrobesLogic
    current_addr = 64'(segment_phys_addr_i) + 64'(transfer_num_q) * MAX_BYTES_PER_BURST + 64'(beat_num_q) * (AXI_DATA_WIDTH/8);
    initial_addr = 64'(segment_phys_addr_i) + 64'(transfer_num_q) * MAX_BYTES_PER_BURST;

    beat_strobes_d = northcape_mmu_common_t::get_per_byte_mask_for_addr(
      .current_addr(current_addr),
      .segment_start(segment_phys_addr_i),
      .segment_end(segment_phys_addr_i + segment_length_i)
    );
  end : lastBeatStrobesLogic

  always_comb begin : debugStateLogic
    debug_state_o = '0;
    debug_zero_len_o = zero_len_d;
    unique case (zero_segment_state_q)
      ZERO_SEGMENT_IDLE: begin
        debug_state_o = 3'h0;
      end
      ZERO_SEGMENT_SETUP_WRITE: begin
        debug_state_o = 3'h1;
      end
      ZERO_SEGMENT_WAIT_WRITE_COMPLETE: begin
        debug_state_o = 3'h2;
      end
      ZERO_SEGMENT_WAIT_RESPONSE: begin
        debug_state_o = 3'h3;
      end
      ZERO_SEGMENT_CHECK_MORE: begin
        debug_state_o = 3'h4;
      end
      ZERO_SEGMENT_DONE: begin
        debug_state_o = 3'h5;
      end
      default: begin
        debug_state_o = '1;
      end
    endcase
  end : debugStateLogic

  `NORTHCAPE_UNREAD(axi_master.bid);
  `NORTHCAPE_UNREAD(axi_master.bresp);
  `NORTHCAPE_UNREAD(axi_master.buser);

`ifdef NORTHCAPE_TEST_COVERAGE
  covergroup capability_ops_zero_cmt_coverage_group @(posedge clk_i);
    coverpoint zero_segment_state_q;
    coverpoint zero_len_q;
    coverpoint zero_bursts_left_q;
    coverpoint zero_bursts_initial_d;
    coverpoint beat_num_q;
    coverpoint transfer_num_q;
    coverpoint beat_strobes_d;
  endgroup

  capability_ops_zero_cmt_coverage_group cov_group;
  initial begin
    cov_group = new;
  end

`endif
endmodule
