

import axi5::*;
import northcape_test::*;
import northcape_mmu_transaction::*;
import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axi5_assign.svh"

/**
  * Simulates an AXI master and checks soundness of the bus protocol.
  * Given a INorthcapeAXITransactionSlaveSide, also verifies that the behavior of the slave matches the expectation (data and metadata) and gives the response according to the transaction..
  * To this end, a NorthcapeMMUScoreboardChecker is used.
  */
module automatic axi5_slave_driver #(
    parameter AXI_ID_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ADDR_WIDTH = -1,
    // if 1, consider it an error if ready remains high after AWVALID/ARVALID and corresponding ready have been high for one clock
    // thereby, master (accidentally) accepted two transactions at once
    parameter AXI_FAIL_ON_AR_AW_READY_HIGH_MULTIPLE_CLOCKS = 1
) (
    input mailbox#(INorthcapeAXITransactionSlaveSide#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    )) requests_in,

    input logic clk_i,
    input logic rst_ni,

    // (to an) AXI Slave Interface
    Axi5.FROM axi_slave,

    input uvm_analysis_port#(Axi5SlaveDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    )) ap_i
);
  typedef enum {
    IDLE,
    START_TRANSACTION,
    WAIT_DATA,
    WAIT_RESPONSE,
    CHECK_TEST_RESULT,
    TEST_OK,
    TEST_ERR
  } axi5_slave_driver_state_t;

  typedef Axi5SlaveDriverResultTransaction#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) result_transaction_t;
  typedef INorthcapeAXITransactionSlaveSide#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH)
  ) transaction_t;

  localparam string COMPONENT_NAME = "Axi Slave Driver";


  axi5_slave_driver_state_t current_state, next_state;

  logic have_test_request;
  logic ar_channel_error;
  logic aw_channel_error;

  logic r_channel_data_error;
  logic r_channel_complete;

  logic b_channel_error;
  logic b_channel_complete;

  logic w_channel_beat_complete;

  transaction_t current_transaction;
  result_transaction_t current_result;

  generate
    if (AXI_ADDR_WIDTH < 1 || AXI_DATA_WIDTH < 1 || AXI_ID_WIDTH < 1 || AXI_USER_WIDTH < 1) begin
      $error("Invalid parameters!");
    end
  endgenerate

  initial begin
    // this is only used such that current_transaction is never null
    automatic
    NorthcapeMMUTransactionSlave #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    )
    test;
    test = new("");
    current_transaction = test;
    current_result = new("axi_slave_result");
  end

  int unsigned acked_write_data, accepted_read_transactions, accepted_write_transactions;


  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : testRequestExtraction
    if (rst_ni == 0) begin
      have_test_request <= 0;
    end else begin
      unique case (current_state)
        IDLE: begin
          if (requests_in.num() > 0 && !have_test_request) begin
            `uvm_info(COMPONENT_NAME, $sformatf(
                      "Slave retrieving next test request from requests_in (%d elements)!",
                      requests_in.num()
                      ), UVM_DEBUG);
            have_test_request <= requests_in.try_get(current_transaction) == 0 ? 0 : 1;
          end else begin
            have_test_request <= 0;
          end
        end
        default begin
          have_test_request <= 0;
        end
      endcase
    end
  end

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : ARChannelFFLogic
    if (rst_ni == 0) begin
      `AXI5_RESET_AR_CHANNEL_SLAVE(axi_slave);
      accepted_read_transactions <= '0;
      ar_channel_error <= 0;
      // other values can remain undefined, DUT must not use them
    end else begin
      unique case (current_state)
        START_TRANSACTION, WAIT_DATA: begin
          if(current_transaction.get_axi_request_type() == AXI_TEST_READ && (next_state == START_TRANSACTION || next_state == WAIT_DATA))
                    begin
            if (!axi_slave.arready || !axi_slave.arvalid) begin
              automatic bit [  AXI_ID_WIDTH-1:0] test_id;
              automatic bit [AXI_USER_WIDTH-1:0] test_user;

              test_id   = current_transaction.get_test_id();
              test_user = current_transaction.get_test_user();

              // not valid or not ready - set up request
              // valid cannot be lowered once raised
              axi_slave.arvalid <= axi_slave.arvalid ? 1 : !current_transaction.generate_random_delay(
                  AR_VALID
              );
              axi_slave.araddr <= current_transaction.get_slave_axi_addr();
              axi_slave.arlen <= current_transaction.get_test_len();
              axi_slave.arburst <= current_transaction.get_burst_type();

              axi_slave.arsize <= current_transaction.get_test_size();
              axi_slave.arlock <= current_transaction.get_test_lock();
              axi_slave.arcache <= current_transaction.get_test_cache();
              axi_slave.arprot <= current_transaction.get_test_prot();
              axi_slave.arqos <= current_transaction.get_test_qos();
              axi_slave.arregion <= current_transaction.get_test_region();

              axi_slave.arid <= test_id[AXI_ID_WIDTH-1 : 0];
              axi_slave.aruser <= test_user[AXI_USER_WIDTH-1 : 0];

              `uvm_info(COMPONENT_NAME, $sformatf(
                        "Setting arid %x aruser %x!",
                        test_id[AXI_ID_WIDTH-1 : 0],
                        test_user[AXI_USER_WIDTH-1 : 0]
                        ), UVM_DEBUG);

            end else begin
              accepted_read_transactions <= accepted_read_transactions + 1;
              if(AXI_FAIL_ON_AR_AW_READY_HIGH_MULTIPLE_CLOCKS && accepted_read_transactions >= 1)
                            begin
                `uvm_error(COMPONENT_NAME, "Accepted too many read transactions!");
                ar_channel_error <= 1;
              end
              // ready and valid - lower valid
              // otherwise: accept second transaction
              axi_slave.arvalid <= current_transaction.get_regression_keep_valid_high();
            end
          end else begin
            // transition into handle_data - if we keep arvalid high, the MMU might treat this as a new transaction
            axi_slave.arvalid <= 0;
            `AXI5_RESET_AR_CHANNEL_SLAVE(axi_slave);
          end
        end
        CHECK_TEST_RESULT: begin
          // do nothing and maintain error signals
          `AXI5_RESET_AR_CHANNEL_SLAVE(axi_slave);
        end
        default: begin
          `AXI5_RESET_AR_CHANNEL_SLAVE(axi_slave);
          ar_channel_error <= 0;
          accepted_read_transactions <= '0;
        end
      endcase
    end
  end

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : AWChannelFFLogic
    if (rst_ni == 0) begin
      axi_slave.awvalid <= 0;
      aw_channel_error <= 0;
      accepted_write_transactions <= '0;
      // other values can remain undefined, DUT must not use them
    end else begin
      unique case (current_state)
        START_TRANSACTION, WAIT_DATA: begin
          if(current_transaction.get_axi_request_type() == AXI_TEST_WRITE && (next_state == START_TRANSACTION || next_state == WAIT_DATA))
                    begin
            // if we hold aw
            if (!axi_slave.awready || !axi_slave.awvalid) begin
              automatic bit [  AXI_ID_WIDTH-1:0] test_id;
              automatic bit [AXI_USER_WIDTH-1:0] test_user;

              test_id   = current_transaction.get_test_id();
              test_user = current_transaction.get_test_user();
              // not valid or not ready - set up request
              // valid cannot be lowered once raised
              axi_slave.awvalid <= axi_slave.awvalid ? 1 : !current_transaction.generate_random_delay(
                  AW_VALID
              );
              axi_slave.awaddr <= current_transaction.get_slave_axi_addr();
              axi_slave.awlen <= current_transaction.get_test_len();
              axi_slave.awburst <= current_transaction.get_burst_type();

              axi_slave.awsize <= current_transaction.get_test_size();
              axi_slave.awlock <= current_transaction.get_test_lock();
              axi_slave.awcache <= current_transaction.get_test_cache();
              axi_slave.awprot <= current_transaction.get_test_prot();
              axi_slave.awqos <= current_transaction.get_test_qos();
              axi_slave.awregion <= current_transaction.get_test_region();

              axi_slave.awid <= test_id[AXI_ID_WIDTH-1 : 0];
              axi_slave.awuser <= test_user[AXI_USER_WIDTH-1 : 0];

              axi_slave.atop_type <= current_transaction.get_atomic_type().atop_type;
              axi_slave.atop_subtype <= current_transaction.get_atomic_type().atop_subtype;
            end else begin
              accepted_write_transactions <= accepted_write_transactions + 1;
              if(AXI_FAIL_ON_AR_AW_READY_HIGH_MULTIPLE_CLOCKS && accepted_write_transactions >= 1)
                            begin
                `uvm_error(COMPONENT_NAME, "Accepted too many write transactions!");
                aw_channel_error <= 1;
              end
              // ready and valid - lower valid
              // otherwise: accept second transaction
              axi_slave.awvalid <= current_transaction.get_regression_keep_valid_high();
            end
          end else begin
            // transition into handle_data - if we keep awvalid high, the MMU might treat this as a new transaction
            `AXI5_RESET_AW_CHANNEL_SLAVE(axi_slave);
          end
        end
        CHECK_TEST_RESULT: begin
          `AXI5_RESET_AW_CHANNEL_SLAVE(axi_slave);
          // do nothing and maintain error signals
        end
        default: begin
          `AXI5_RESET_AW_CHANNEL_SLAVE(axi_slave);
          aw_channel_error <= 0;
          accepted_write_transactions <= '0;
        end
      endcase
    end
  end

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : RChannelFFLogic
    if (rst_ni == 0) begin
      `AXI5_RESET_R_CHANNEL_SLAVE(axi_slave);
      r_channel_data_error <= 0;
      r_channel_complete   <= 0;
    end else begin
      unique case (current_state)
        WAIT_DATA, WAIT_RESPONSE: begin
          // we can always be ready
          axi_slave.rready <= !current_transaction.generate_random_delay(R_READY);
          if (axi_slave.rvalid && axi_slave.rready && !r_channel_complete) begin
            if(current_transaction.get_axi_request_type() == AXI_TEST_READ || (current_transaction.get_axi_request_type() == AXI_TEST_WRITE && current_transaction.get_atomic_type().atop_type != ATOMIC_NONE && current_transaction.get_atomic_type().atop_type != ATOMIC_STORE))
                        begin
              `uvm_info(
                  COMPONENT_NAME, $sformatf(
                  "Collecting read data %x on index %d!", axi_slave.rdata, current_result.data_len),
                  UVM_DEBUG);
              current_result.read_data[current_result.data_len] = axi_slave.rdata;
              if (current_result.data_len != 0) begin
                if (current_result.resp != axi_slave.rresp) begin
                  `uvm_error(COMPONENT_NAME, "rresp has changed between beats of the transfer!");
                end
                if (current_result.id != axi_slave.rid) begin
                  `uvm_error(COMPONENT_NAME, "rid has changed between beats of the transfer!");
                end
                if (current_result.user != axi_slave.ruser) begin
                  `uvm_error(COMPONENT_NAME, "ruser has changed between beats of the transfer!");
                end
              end else begin
                current_result.resp = axi_slave.rresp;
                current_result.id   = axi_slave.rid;
                current_result.user = axi_slave.ruser;

                `uvm_info(COMPONENT_NAME, $sformatf(
                          "Collecting rid %x ruser %x!", axi_slave.rid, axi_slave.ruser),
                          UVM_DEBUG);
              end

              if (axi_slave.rlast) begin
                r_channel_complete <= 1;
              end else begin
                // offset by -1
                current_result.data_len++;
              end
            end else begin
              `uvm_error(COMPONENT_NAME, "R channel should NOT be valid right now!");
              r_channel_data_error <= 1;
              // do not wait on R channel, as nothing will happen in write-only transaction
              r_channel_complete   <= 1;
            end
          end else begin
            // wait for b channel complete as well
            r_channel_complete <= r_channel_complete;
          end
        end
        CHECK_TEST_RESULT: begin
          // do nothing and maintain error signals
        end
        default: begin
          if (axi_slave.rvalid) begin
            `uvm_error(COMPONENT_NAME, "R channel should NOT be valid right now!");
            r_channel_data_error <= 1;
          end else begin
            r_channel_data_error <= 0;
          end
          r_channel_complete <= 0;
          axi_slave.rready   <= !current_transaction.generate_random_delay(R_READY);
        end
      endcase
    end
  end : RChannelFFLogic

  assign w_channel_beat_complete = axi_slave.wvalid && axi_slave.wready;

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : WChannelFFLogic
    if (rst_ni == 0) begin
      `AXI5_RESET_W_CHANNEL_SLAVE(axi_slave);
      acked_write_data <= 0;
    end else begin
      unique case (current_state)
        START_TRANSACTION, WAIT_DATA: begin
          automatic logic [8:0] len_plus_one = current_transaction.get_test_len() + 1;
          automatic bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] write_data;
          automatic bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH/8-1:0] write_strobes;
          automatic bit [AXI_ID_WIDTH-1:0] test_id;
          automatic bit [AXI_USER_WIDTH-1:0] test_user;

          // can start offering write data in parallel to AW
          // also, in case of atomic transaction, read data might come after write - in this case, we need to keep valid low
          if ((acked_write_data < {23'h0, len_plus_one})) begin
            if (axi_slave.wready) begin
              axi_slave.wvalid <= !current_transaction.generate_random_delay(W_VALID);
            end else begin
              // must hold valid once asserted
              axi_slave.wvalid <= 1;
            end
          end else begin
            // transfer complete
            axi_slave.wvalid <= 0;
            `AXI5_RESET_W_CHANNEL_SLAVE(axi_slave);
          end
          write_data = current_transaction.get_write_data();
          write_strobes = current_transaction.get_slave_write_strobes();
          axi_slave.wstrb <= write_strobes[w_channel_beat_complete ? acked_write_data + 1 : acked_write_data];
          axi_slave.wdata <= write_data[w_channel_beat_complete ? acked_write_data + 1 : acked_write_data];
          if(acked_write_data + (w_channel_beat_complete ? 1 : 0) >= {24'h0, current_transaction.get_test_len()})
                    begin
            `uvm_info(COMPONENT_NAME, "last write beat!", UVM_DEBUG);
            axi_slave.wlast <= 1;
          end else begin
            // maintain until beat confirmed
            axi_slave.wlast <= axi_slave.wlast;
          end
          test_id   = current_transaction.get_test_id();
          test_user = current_transaction.get_test_user();
          axi_slave.wid   <= test_id[AXI_ID_WIDTH-1 : 0];
          axi_slave.wuser <= test_user[AXI_USER_WIDTH-1 : 0];

          if (w_channel_beat_complete) begin
            // 1 beat was transferred
            acked_write_data <= acked_write_data + 1;
          end

          if (axi_slave.bvalid) begin
            `uvm_error(COMPONENT_NAME, "MMU must not raise bvalid before last write accepted!");
          end
        end
        CHECK_TEST_RESULT: begin
          // do nothing and maintain error signals
        end
        default: begin
          `AXI5_RESET_W_CHANNEL_SLAVE(axi_slave);
          axi_slave.wdata  <= '0;
          acked_write_data <= 0;
          axi_slave.wlast  <= 0;
        end
      endcase
    end
  end

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : BChannelFFLogic
    if (rst_ni == 0) begin
      b_channel_complete <= 0;
      axi_slave.bready   <= 0;
    end else begin
      unique case (current_state)
        WAIT_RESPONSE: begin
          if (axi_slave.bvalid && axi_slave.bready && !b_channel_complete) begin
            b_channel_complete <= 1;

            current_result.resp = axi_slave.bresp;
            current_result.id   = axi_slave.bid;
            current_result.user = axi_slave.buser;

            axi_slave.bready <= !current_transaction.generate_random_delay(B_READY);
          end else if (axi_slave.bvalid == 1'b1 && !b_channel_complete) begin
            axi_slave.bready <= !current_transaction.generate_random_delay(B_READY);
          end else if (axi_slave.bvalid == 1'b1 && b_channel_complete == 1'b1) begin
            `uvm_error(COMPONENT_NAME, "Wresp chan should not be valid now (1)!");
            b_channel_error  <= 1;
            axi_slave.bready <= !current_transaction.generate_random_delay(B_READY);
          end
        end
        default: begin
          // wresp chan can be valid if we refuse the request in the MMU...
          b_channel_error <= 0;
          b_channel_complete <= 0;
          axi_slave.bready <= !current_transaction.generate_random_delay(B_READY);
        end
      endcase
    end
  end

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : currentStateFFLogic
    if (rst_ni == 0) begin
      current_state <= IDLE;
    end else begin
      current_state <= next_state;
    end
  end

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : testReportingLogic
    unique case (current_state)
      TEST_OK, TEST_ERR: begin
        `uvm_info(COMPONENT_NAME, $sformatf("Finished with read data %x", current_result.read_data),
                  UVM_DEBUG);
        ap_i.write(current_result);
        current_result = new("axi_slave_result");
      end
      default: begin
      end
    endcase
  end : testReportingLogic

  always_comb begin : nextStateLogic
    next_state = current_state;

    unique case (current_state)
      IDLE: begin
        if (have_test_request == 1'b1) begin
          `uvm_info(COMPONENT_NAME, "Slave starting transaction!", UVM_DEBUG);
          next_state = START_TRANSACTION;
        end
      end
      START_TRANSACTION: begin
        if(current_transaction.get_axi_request_type() == AXI_TEST_READ && (!axi_slave.arready || !axi_slave.arvalid))
                begin
          next_state = START_TRANSACTION;
        end
                else if(current_transaction.get_axi_request_type() == AXI_TEST_WRITE && (!axi_slave.awready || !axi_slave.awvalid))
                begin
          `uvm_info(COMPONENT_NAME, "Slave side staying in START_TRANSACTION!", UVM_DEBUG);
          next_state = START_TRANSACTION;
        end else begin
          `uvm_info(COMPONENT_NAME, "Slave side transitioning to WAIT_DATA!", UVM_DEBUG);
          next_state = WAIT_DATA;
        end
      end
      WAIT_DATA: begin
        if (current_transaction.get_axi_request_type() == AXI_TEST_READ) begin
          if (axi_slave.rvalid && axi_slave.rready && axi_slave.rlast) begin
            // complete
            next_state = CHECK_TEST_RESULT;
          end
        end else if (current_transaction.get_axi_request_type() == AXI_TEST_WRITE) begin
          // write must be completed before rdata
          if (axi_slave.wvalid && axi_slave.wready && axi_slave.wlast) begin
            `uvm_info(COMPONENT_NAME, "Slave side transitioning to WAIT_RESPONSE!", UVM_DEBUG);
            next_state = WAIT_RESPONSE;
          end
        end
      end
      WAIT_RESPONSE: begin
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "r_channel_complete: %d b_channel_complete: %d current atop: %s",
                  r_channel_complete,
                  b_channel_complete,
                  current_transaction.get_atomic_type().atop_type.name()
                  ), UVM_DEBUG);
        if((r_channel_complete || current_transaction.get_atomic_type().atop_type == ATOMIC_NONE || current_transaction.get_atomic_type().atop_type == ATOMIC_STORE) && b_channel_complete)
                begin
          `uvm_info(COMPONENT_NAME, "Slave side transfer complete!", UVM_DEBUG);
          next_state = CHECK_TEST_RESULT;
        end
      end
      // errors in the last transfer might only become available when we would otherwise have transitioned into TEST_OK already - wait one cycle
      CHECK_TEST_RESULT: begin
        next_state = (ar_channel_error || aw_channel_error || r_channel_data_error || b_channel_error) ? TEST_ERR : TEST_OK;
      end
      TEST_OK, TEST_ERR: begin

        // have reported test status
        next_state = IDLE;
      end
      default: begin
        // nothing to do
      end
    endcase

    if (ar_channel_error || aw_channel_error) begin
      next_state = TEST_ERR;
    end
  end

endmodule
