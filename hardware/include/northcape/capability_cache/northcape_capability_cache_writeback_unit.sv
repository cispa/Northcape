/**
  * Writeback unit: commits CMT entries to memory.
  */
module northcape_capability_cache_writeback_unit #(
    parameter int HASH_TYPE = -1,
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,
    // size of the optional store buffer - set to 0 to disable
    parameter int STORE_BUFFER_SIZE = 0,
    parameter bit DEBUG_ILA = 1'b0
) (
    input logic rst_ni,

    Axi5WriteOnly.FROM axi_master,
    NorthcapeCMTInterface.CONSUMER cmt_interface,

    input northcape_types::capability_id_t request_capability_id_i,
    // capability ID that is about to go to the missunit
    input northcape_types::capability_id_t missunit_capability_id_i,
    input northcape_types::northcape_cmt_entry_t request_capability_i,
    input logic request_capability_id_valid_i,

    output logic response_valid_o,
    output logic response_err_o,
    output logic store_buffer_hazard_o
);
  import northcape_types::*;
  import axi5::*;
  import northcape_capability_ops_common::NorthcapeCapabilityOpsGenerator;


  `include "northcape_unread.vh"

  typedef NorthcapeCapabilityOpsGenerator#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .HASH_TYPE(HASH_TYPE)
  ) gen_t;

  //===================================
  // declarations and static assignments
  //===================================
  logic clk_i;

  // either from FIFO or served directly
  capability_id_t write_capability_id;
  northcape_cmt_entry_t write_cmt_entry;
  logic write_valid;

  logic write_complete;
  logic write_err;

  assign clk_i = axi_master.clk_i;

  // static/default values
  assign axi_master.atop_type = ATOMIC_NONE;
  assign axi_master.atop_subtype = '0;

  assign axi_master.awsize = $clog2(AXI_DATA_WIDTH / 8);
  assign axi_master.awburst = INCR;
  assign axi_master.awlock = 0;
  assign axi_master.awcache = '0;
  assign axi_master.awprot = '0;
  assign axi_master.awqos = '0;
  assign axi_master.awregion = '0;
  assign axi_master.awuser = '0;
  assign axi_master.awid = '0;
  // designed to be possible in 1 transaction
  assign axi_master.awlen = 0;

  assign axi_master.wid = '0;
  assign axi_master.wstrb = '1;
  assign axi_master.wuser = '0;
  // designed to be possible in 1 transaction
  assign axi_master.wlast = 1'b1;

  assign axi_master.bready = 1'b1;

  typedef enum logic [1:0] {
    IDLE,
    WAIT_W,
    WAIT_B
  } writeback_state_t;

  writeback_state_t state_q, state_d;

  //===================================
  // sequential logic
  //===================================
  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : stateQ
    if (!rst_ni) begin
      state_q <= IDLE;
    end else begin
      state_q <= state_d;
    end
  end : stateQ


  //===================================
  // combinational logic
  //===================================

  generate
    if (STORE_BUFFER_SIZE == 0) begin : gen_no_store_buffer
      assign write_capability_id = request_capability_id_i;
      assign write_cmt_entry = request_capability_i;
      assign write_valid = request_capability_id_valid_i;

      assign response_valid_o = write_complete;
      assign response_err_o = write_err;

      assign store_buffer_hazard_o = 1'b0;

      `NORTHCAPE_UNREAD(missunit_capability_id_i);
    end : gen_no_store_buffer
    else begin : gen_store_buffer
      northcape_capability_cache_store_buffer #(
          .STORE_BUFFER_SIZE(STORE_BUFFER_SIZE),
          .DEBUG_ILA(DEBUG_ILA)
      ) i_store_buffer (
          .clk_i (clk_i),
          .rst_ni(rst_ni),

          .write_capability_id_i(request_capability_id_i),
          .write_capability_i(request_capability_i),
          .write_capability_id_valid_i(request_capability_id_valid_i),
          .write_accepted_o(response_valid_o),

          .missunit_capability_id_i(missunit_capability_id_i),
          .store_buffer_hazard_o(store_buffer_hazard_o),

          .write_capability_id_o(write_capability_id),
          .write_cmt_entry_o(write_cmt_entry),
          .write_valid_o(write_valid),
          .write_commit_i(write_complete)
      );
      // TODO this SHOULD never happen anyway
      assign response_err_o = 1'b0;


      `NORTHCAPE_UNREAD(axi_master.bresp);
      `NORTHCAPE_UNREAD(write_err);
    end : gen_store_buffer
  endgenerate


  always_comb begin : outputLogic
    // can forward unconditionally
    axi_master.awaddr = gen_t::get_capability_addr(
        cmt_interface.cmt_base, cmt_interface.table_size_clog2, write_capability_id);
    axi_master.wdata = write_cmt_entry;

    axi_master.awvalid = (state_q == IDLE) && write_valid;
    axi_master.wvalid = state_q inside {IDLE, WAIT_W} && write_valid;
  end : outputLogic


  always_comb begin : responseLogic
    write_complete = axi_master.bvalid;
    write_err = axi_master.bresp != OKAY;
  end : responseLogic



  always_comb begin : stateLogic
    state_d = state_q;

    unique case (state_q)
      IDLE: begin
        if (write_valid) begin
          if (axi_master.awready) begin
            if (!axi_master.wready) begin
              state_d = WAIT_W;
            end else if (!axi_master.bvalid) begin
              state_d = WAIT_B;
            end
            // else: awready + wready + bvalid - 1-cycle transfer
          end
        end
      end
      WAIT_W: begin
        if (axi_master.wready) begin
          if (axi_master.bvalid) begin
            // done
            state_d = IDLE;
          end else begin
            state_d = WAIT_B;
          end
        end
      end
      WAIT_B: begin
        if (axi_master.bvalid) begin
          state_d = IDLE;
        end
      end
      default: ;
    endcase
  end : stateLogic

  `NORTHCAPE_UNREAD(axi_master.bid);
  `NORTHCAPE_UNREAD(axi_master.buser);
  `NORTHCAPE_UNREAD(axi_master.rst_ni);

  `NORTHCAPE_UNREAD(cmt_interface.clk_i);
  `NORTHCAPE_UNREAD(cmt_interface.reset_done);
  `NORTHCAPE_UNREAD(cmt_interface.need_flush_data_caches);
  `NORTHCAPE_UNREAD(cmt_interface.wrote_any_capability);
  `NORTHCAPE_UNREAD(cmt_interface.written_capability);

  // some bits not read
  `NORTHCAPE_UNREAD(request_capability_id_i);

endmodule
