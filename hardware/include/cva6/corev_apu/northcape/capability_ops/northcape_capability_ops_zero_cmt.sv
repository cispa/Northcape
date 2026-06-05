/**
  * Part of the northcape capability resolver operations module.
  * Contains an FSM that can be used for zeroing the CMT.
  */
module northcape_capability_ops_zero_cmt #(
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_ID_WIDTH   = -1,
    parameter AXI_USER_WIDTH = -1,

    parameter logic [AXI_ADDR_WIDTH-1:0] INITIAL_CMT_BASE = -1,
    parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1
) (
    Axi5WriteOnly.FROM axi_master,

    NorthcapeCMTInterface.CONSUMER cmt_interface,

    input  logic start_i,
    output logic done_o
);
  import northcape_types::*;
  import axi5::*;

  `include "northcape_unread.vh"

  typedef enum {
    ZERO_IDLE,
    ZERO_SETUP_WRITE,
    ZERO_WAIT_WRITE_COMPLETE,
    ZERO_WAIT_RESPONSE,
    ZERO_CHECK_MORE,
    ZERO_DONE
  } northcape_capability_ops_cmt_zero_state_t;

  // hierarchical state machine for zeroing the CMT
  northcape_capability_ops_cmt_zero_state_t zero_state_q, zero_state_d;

  // FSM for zeroing CMT private state
  logic [AXI_ADDR_WIDTH-1:0] zero_addr_q, zero_addr_d;
  axi_len_t zero_len_q, zero_len_d;
  logic zero_is_last_q, zero_is_last_d;
  int unsigned zero_bursts_left_q, zero_bursts_left_d, zero_bursts_initial_d;

  logic clk_i;
  logic rst_ni;

  logic done_d;

  // AXI handshaking signals
  logic awvalid_d, wvalid_d, wlast_d, bready_d;

  localparam int unsigned INITIAL_CMT_SIZE_BYTES = (1 << INITIAL_CMT_SIZE_CLOG2) * $bits(
      northcape_cmt_entry_t
  ) / 8;
  localparam int unsigned MAX_BYTES_PER_BURST = (AXI_DATA_WIDTH / 8) * AXI5_MAX_BURST_LEN;

  assign clk_i  = axi_master.clk_i;
  assign rst_ni = axi_master.rst_ni;

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : stateQFF
    if (rst_ni == 0) begin
      zero_state_q <= ZERO_IDLE;
    end else begin
      zero_state_q <= zero_state_d;
    end
  end : stateQFF

  // static/default values
  assign axi_master.awsize       = $clog2(AXI_DATA_WIDTH / 8);
  assign axi_master.awburst      = INCR;
  assign axi_master.awlock       = 0;
  assign axi_master.awcache      = '0;
  assign axi_master.awprot       = '0;
  assign axi_master.awqos        = '0;
  assign axi_master.awregion     = '0;
  assign axi_master.awuser       = '0;
  assign axi_master.awid         = '0;
  assign axi_master.atop_type    = ATOMIC_NONE;
  assign axi_master.atop_subtype = '0;

  assign axi_master.wid          = '0;
  assign axi_master.wdata        = '0;
  assign axi_master.wstrb        = '1;
  assign axi_master.wuser        = '0;


  // FFs for AXI master interface
  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : axiWriteFF
    if (rst_ni == 0) begin
      axi_master.awvalid <= 0;
      axi_master.wvalid  <= 0;
      axi_master.bready  <= 0;

      axi_master.awaddr  <= '0;
      axi_master.awlen   <= '0;

      axi_master.wlast   <= 0;
    end else begin
      // valid or not used
      axi_master.awaddr  <= zero_addr_q;
      axi_master.awlen   <= zero_len_d;

      axi_master.awvalid <= awvalid_d;
      axi_master.wvalid  <= wvalid_d;
      axi_master.wlast   <= wlast_d;
      axi_master.bready  <= bready_d;
    end
  end : axiWriteFF

  assign zero_bursts_initial_d = INITIAL_CMT_SIZE_BYTES / MAX_BYTES_PER_BURST + (INITIAL_CMT_SIZE_BYTES % MAX_BYTES_PER_BURST ? 1 : 0);

  // if this is zero, we overflow
  assert property (@(posedge (clk_i)) zero_bursts_initial_d != 0);

  // flip-flops for zero FSM private data
  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : zeroFSMFF
    if (rst_ni == 0) begin
      zero_addr_q <= INITIAL_CMT_BASE;
      zero_len_q <= '0;
      zero_is_last_q <= 0;
      zero_bursts_left_q <= '0;
      done_o <= 0;
    end else begin
      zero_addr_q <= zero_addr_d;
      zero_len_q <= zero_len_d;
      zero_is_last_q <= zero_is_last_d;
      zero_bursts_left_q <= zero_bursts_left_d;
      done_o <= done_d;
    end
  end : zeroFSMFF

  // AXI handshaking logic
  always_comb begin : axiHandshakeLogic
    awvalid_d = 1'b0;
    wvalid_d  = 1'b0;
    wlast_d   = 1'b0;
    bready_d  = 1'b0;

    unique case (zero_state_q)
      ZERO_SETUP_WRITE: begin

        awvalid_d = !(axi_master.awvalid && axi_master.awready);

        wvalid_d  = 1'b0;
        wlast_d   = zero_is_last_q;

        // if bvalid was early, we might accept it here and then deadlock
        bready_d  = 1'b0;
      end
      ZERO_WAIT_WRITE_COMPLETE: begin
        wvalid_d = !(axi_master.wvalid && axi_master.wready && axi_master.wlast);
        // zero_is_last_q might lag behind on last transaction in longer burst
        wlast_d  = zero_is_last_q || (zero_len_q == 1 && axi_master.wvalid && axi_master.wready);

        bready_d = !(axi_master.bready && axi_master.bvalid);
      end
      ZERO_WAIT_RESPONSE: begin
        bready_d = !(axi_master.bready && axi_master.bvalid);
      end
      default: begin
        // default assignment above
      end
    endcase
  end : axiHandshakeLogic

  // counting logic
  always_comb begin : countingLogic
    zero_bursts_left_d = zero_bursts_left_q;
    done_d = done_o;
    zero_len_d = zero_len_q;
    zero_is_last_d = zero_is_last_q;
    zero_addr_d = zero_addr_q;

    unique case (zero_state_q)
      ZERO_IDLE: begin
        zero_bursts_left_d = zero_bursts_initial_d;
        done_d = 0;
        if (zero_bursts_initial_d == 1) begin
          automatic axi_len_t computed_len;

          computed_len = INITIAL_CMT_SIZE_BYTES / (AXI_DATA_WIDTH / 8) - 1;
          zero_len_d = computed_len;
          zero_is_last_d = (computed_len == 0);
        end else begin

          zero_len_d = AXI5_MAX_BURST_LEN - 1;
          zero_is_last_d = 0;
        end
      end
      // in ZERO_CHECK_MORE, need to set length etc. for next request
      ZERO_CHECK_MORE, ZERO_SETUP_WRITE: begin
        // when this burst is completed, we can go on to the next one
        // we might be into the burst for two cycles, depending on whether wready goes high immediately
        if(zero_bursts_left_q == 1 || (zero_state_q == ZERO_CHECK_MORE && zero_bursts_left_q == 1))
                  begin
          automatic axi_len_t computed_len;

          computed_len = (INITIAL_CMT_SIZE_BYTES % MAX_BYTES_PER_BURST) / (AXI_DATA_WIDTH / 8) - 1;
          // last burst - len might be shorter
          // first beat might already be accepted right now
          zero_len_d = computed_len;
          zero_is_last_d = (computed_len == 0);
        end else begin
          // more bursts to follow - write as many as possible
          // first beat might already be accepted right now
          zero_len_d = AXI5_MAX_BURST_LEN - 1 - (axi_master.wvalid && axi_master.wready);
          zero_is_last_d = 0;
        end
        if (zero_state_q == ZERO_CHECK_MORE) begin
          zero_bursts_left_d = zero_bursts_left_q - 1;
          zero_addr_d = zero_addr_q + AXI5_MAX_BURST_LEN * (AXI_DATA_WIDTH / 8);
        end
        // TODO when resizing is implemented, need to set zero_addr and zero_len differently
      end
      ZERO_WAIT_WRITE_COMPLETE: begin
        if (axi_master.wvalid && axi_master.wready && zero_len_q != 0) begin
          // beat accepted
          zero_len_d = zero_len_q - 1;
          zero_is_last_d = zero_len_q - 1 == 0;
        end
      end
      ZERO_DONE: begin
        done_d = 1;
      end
      default: begin
        // default assignment above
      end

    endcase
  end : countingLogic

  // FSM next state logic for zeroing CMT
  always_comb begin : cmtZeroStateMachine
    zero_state_d = zero_state_q;

    unique case (zero_state_q)
      ZERO_IDLE: begin
        if (start_i) begin
          zero_state_d = ZERO_SETUP_WRITE;
        end
      end
      ZERO_SETUP_WRITE: begin
        if (axi_master.awvalid && axi_master.awready) begin
          // write accepted
          zero_state_d = ZERO_WAIT_WRITE_COMPLETE;
        end
      end
      ZERO_WAIT_WRITE_COMPLETE: begin
        if (axi_master.wvalid && axi_master.wready && axi_master.wlast) begin
          if (axi_master.bvalid && axi_master.bready) begin
            zero_state_d = ZERO_CHECK_MORE;
          end else begin
            zero_state_d = ZERO_WAIT_RESPONSE;
          end
        end
      end
      ZERO_WAIT_RESPONSE: begin
        if (axi_master.bvalid && axi_master.bready) begin
          zero_state_d = ZERO_CHECK_MORE;
        end
      end
      ZERO_CHECK_MORE: begin
        // transaction complete, will dec to 0 in one cycle
        if (zero_bursts_left_q == 1) begin
          // no bursts left
          zero_state_d = ZERO_DONE;
        end else begin
          // start next write
          zero_state_d = ZERO_SETUP_WRITE;
        end
      end
      ZERO_DONE: begin
        zero_state_d = ZERO_IDLE;
      end
    endcase
  end : cmtZeroStateMachine

  `NORTHCAPE_UNREAD(axi_master.bresp);
  `NORTHCAPE_UNREAD(axi_master.buser);
  `NORTHCAPE_UNREAD(axi_master.bid);
  `NORTHCAPE_UNREAD(cmt_interface.cmt_base);
  `NORTHCAPE_UNREAD(cmt_interface.table_size_clog2);
  `NORTHCAPE_UNREAD(cmt_interface.reset_done);
  `NORTHCAPE_UNREAD(cmt_interface.clk_i);


`ifdef NORTHCAPE_TEST_COVERAGE
  covergroup capability_ops_zero_cmt_coverage_group @(posedge clk_i);
    coverpoint zero_state_q;
    coverpoint zero_len_q;
    coverpoint zero_bursts_left_q;
    coverpoint zero_bursts_initial_d;
  endgroup

  capability_ops_zero_cmt_coverage_group cov_group;
  initial begin
    cov_group = new;
  end

`endif
endmodule
