/**
  * Capability cache missunit: retrieves capabilities from memory
  */
module northcape_capability_cache_missunit #(
    parameter int HASH_TYPE = -1,
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1
) (
    input logic rst_ni,

    Axi5ReadOnly.FROM axi_master,

    NorthcapeCMTInterface.CONSUMER cmt_interface,

    input northcape_types::capability_id_t request_capability_id_i,
    input logic request_capability_id_valid_i,

    input logic response_ready_i,

    output northcape_types::northcape_cmt_entry_t response_capability_o,
    output logic response_valid_o,
    output logic response_err_o
);

  import northcape_types::*;
  import axi5::*;
  import northcape_capability_ops_common::NorthcapeCapabilityOpsGenerator;
  `include "northcape_unread.vh"


  //===================================
  // declarations and static assignments
  //===================================
  logic clk_i;

  assign clk_i = axi_master.clk_i;

  // static/default values
  assign axi_master.arid = '0;
  assign axi_master.arlen = '0;
  assign axi_master.arsize = $clog2(AXI_DATA_WIDTH / 8);
  assign axi_master.arburst = INCR;
  assign axi_master.arlock = '0;
  assign axi_master.arcache = '0;
  assign axi_master.arprot = '0;
  assign axi_master.arqos = '0;
  assign axi_master.arregion = '0;
  assign axi_master.aruser = '0;

  assign axi_master.rready = response_ready_i;

  typedef enum logic {
    IDLE,
    WAIT_R
  } missunit_state_t;

  missunit_state_t state_q, state_d;

  typedef NorthcapeCapabilityOpsGenerator#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .HASH_TYPE(HASH_TYPE)
  ) gen_t;


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


  always_comb begin : outputLogic
    // can forward unconditionally
    axi_master.araddr = gen_t::get_capability_addr(
        cmt_interface.cmt_base, cmt_interface.table_size_clog2, request_capability_id_i);

    axi_master.arvalid = (state_q == IDLE) && request_capability_id_valid_i;
  end : outputLogic


  always_comb begin : responseLogic
    response_valid_o = axi_master.rvalid;
    response_err_o = axi_master.rresp != OKAY;
    response_capability_o = axi_master.rdata;
  end : responseLogic



  always_comb begin : stateLogic
    state_d = state_q;

    unique case (state_q)
      IDLE: begin
        if (request_capability_id_valid_i) begin
          if (axi_master.arready) begin
            if (!axi_master.rvalid) begin
              state_d = WAIT_R;
            end
            // else: arready + rvalid - 1-cycle transfer
          end
        end
      end
      WAIT_R: begin
        if (axi_master.rvalid && axi_master.rready) begin
          // done
          state_d = IDLE;
        end
      end
      default: ;
    endcase
  end : stateLogic


  `NORTHCAPE_UNREAD(axi_master.rid);
  `NORTHCAPE_UNREAD(axi_master.ruser);
  `NORTHCAPE_UNREAD(axi_master.rlast);

  `NORTHCAPE_UNREAD(axi_master.rst_ni);

  `NORTHCAPE_UNREAD(cmt_interface.clk_i);
  `NORTHCAPE_UNREAD(cmt_interface.reset_done);
  `NORTHCAPE_UNREAD(cmt_interface.need_flush_data_caches);
  `NORTHCAPE_UNREAD(cmt_interface.wrote_any_capability);
  `NORTHCAPE_UNREAD(cmt_interface.written_capability);

  // some bits
  `NORTHCAPE_UNREAD(request_capability_id_i);

endmodule
