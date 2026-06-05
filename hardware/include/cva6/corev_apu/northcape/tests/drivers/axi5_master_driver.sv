import northcape_test::*;
import axi5::*;
import northcape_mmu_transaction::*;

/**
  * Simulates an AXI slave and checks soundness of the bus protocol.
  * Given a NorthcapeMMUScoreboard, also verifies that the behavior of the master matches the expectation (data and metadata) and gives the response according to the transaction..
  * To this end, a NorthcapeMMUScoreboardChecker is used.
  */
module axi5_master_driver #(
    parameter     AXI_ID_WIDTH   = -1,
    parameter     AXI_USER_WIDTH = -1,
    parameter     AXI_DATA_WIDTH = -1,
    parameter     AXI_ADDR_WIDTH = -1,
    parameter bit MONITOR_MODE   = 1'b0
) (
    input mailbox#(INorthcapeAXITransactionMasterSide#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    )) requests_in,

    input logic clk_i,
    input logic rst_ni,

    // (to an) AXI Master Interface
    Axi5.TO axi_master,

    input uvm_analysis_port#(Axi5MasterDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    )) ap_i
);
  typedef enum {
    IDLE,
    START_TRANSACTION,
    HANDLE_DATA,
    GIVE_RESPONSE,
    CHECK_TEST_RESULT,
    TEST_OK,
    TEST_ERR
  } axi5_master_driver_state_t;

  generate
    if (AXI_ADDR_WIDTH < 1 || AXI_DATA_WIDTH < 1 || AXI_ID_WIDTH < 1 || AXI_USER_WIDTH < 1) begin
      $error("Invalid parameters!");
    end
  endgenerate

  localparam string COMPONENT_NAME = "Axi Master Driver";

  axi5_master_driver_state_t current_state, next_state;

  logic ar_channel_error;
  logic aw_channel_error;

  logic have_test_request;
  logic r_channel_complete;
  logic r_channel_beat_complete;

  logic w_channel_error;
  logic w_channel_complete;

  logic b_channel_complete;

  typedef Axi5MasterDriverResultTransaction#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) result_transaction_t;
  typedef INorthcapeAXITransactionMasterSide#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH)
  ) transaction_t;

  transaction_t current_transaction;
  result_transaction_t current_result;


  initial begin
    automatic
    NorthcapeMMUTransactionMaster #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    )
    test_transaction;
    test_transaction = new("");
    current_transaction = test_transaction;
    current_result = new("master_result");
  end


  int unsigned provided_read_data, collected_write_data;

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : testRequestExtraction
    if (rst_ni == 0) begin
      have_test_request <= 0;
    end else begin
      unique case (current_state)
        IDLE: begin
          if (requests_in.num() > 0 && !have_test_request) begin
            `uvm_info(COMPONENT_NAME, $sformatf(
                      "Master retrieving next test request from requests_in (%d elements)!",
                      requests_in.num()
                      ), UVM_DEBUG);
            have_test_request <= requests_in.try_get(current_transaction) == 0 ? 0 : 1;
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
      if (!MONITOR_MODE) begin
        `AXI5_RESET_AR_CHANNEL_MASTER(axi_master);
      end
      ar_channel_error <= 0;
      // other values are inputs
    end else begin
      unique case (current_state)
        START_TRANSACTION: begin
          if (current_transaction.get_axi_request_type() == AXI_TEST_READ) begin
            if (axi_master.arvalid && axi_master.arready) begin
              ar_channel_error <= 0;

              current_result.request_type = AXI_TEST_READ;
              current_result.addr = axi_master.araddr;
              current_result.len = axi_master.arlen;
              current_result.burst = axi_master.arburst;
              current_result.size = axi_master.arsize;
              current_result.lock = axi_master.arlock;
              current_result.cache = axi_master.arcache;
              current_result.prot = axi_master.arprot;
              current_result.qos = axi_master.arqos;
              current_result.region = axi_master.arregion;
              current_result.id = axi_master.arid;
              current_result.user = axi_master.aruser;

              if (!MONITOR_MODE) begin
                axi_master.arready <= !current_transaction.generate_random_delay(AR_READY);
              end
            end else begin
              if (!MONITOR_MODE) begin
                axi_master.arready <= !current_transaction.generate_random_delay(AR_READY) ||
                    current_transaction.get_regression_ready_before_valid();
              end
            end
          end else if (axi_master.arvalid) begin
            // immediate back-to-back query might cause this
            `uvm_warning(COMPONENT_NAME, "Did not expect master raddr chan to go valid!");
            if (!MONITOR_MODE) begin
              `AXI5_RESET_AR_CHANNEL_MASTER(axi_master);
            end
          end
        end
        CHECK_TEST_RESULT: begin
          // maintain error flags
        end
        IDLE: begin
          ar_channel_error <= 0;
          if (!MONITOR_MODE) begin
            `AXI5_RESET_AR_CHANNEL_MASTER(axi_master);
          end
        end
        default: begin
          if (axi_master.arvalid) begin
            // immediate back-to-back query might cause this
            `uvm_warning(COMPONENT_NAME, "Did not expect master raddr chan to go valid!");
          end else begin
            ar_channel_error <= ar_channel_error;
          end

          if (!MONITOR_MODE) begin
            `AXI5_RESET_AR_CHANNEL_MASTER(axi_master);
          end

        end
      endcase
    end
  end

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : AWChannelFFLogic
    if (rst_ni == 0) begin
      if (!MONITOR_MODE) begin
        `AXI5_RESET_AW_CHANNEL_MASTER(axi_master);
      end
      aw_channel_error <= 0;
      // other values can remain undefined, DUT must not use them
    end else begin
      unique case (current_state)
        START_TRANSACTION: begin
          if (current_transaction.get_axi_request_type() == AXI_TEST_WRITE) begin
            if (axi_master.awvalid && axi_master.awready) begin
              aw_channel_error <= 0;

              current_result.request_type = AXI_TEST_WRITE;
              current_result.addr = axi_master.awaddr;
              current_result.len = axi_master.awlen;
              current_result.burst = axi_master.awburst;
              current_result.size = axi_master.awsize;
              current_result.lock = axi_master.awlock;
              current_result.cache = axi_master.awcache;
              current_result.prot = axi_master.awprot;
              current_result.qos = axi_master.awqos;
              current_result.region = axi_master.awregion;
              current_result.id = axi_master.awid;
              current_result.user = axi_master.awuser;

              current_result.atop = {axi_master.atop_type, axi_master.atop_subtype};

              if (!MONITOR_MODE) begin
                axi_master.awready <= !current_transaction.generate_random_delay(AW_READY);
              end
            end else begin
              if (!MONITOR_MODE) begin
                axi_master.awready <= !current_transaction.generate_random_delay(AW_READY) ||
                    current_transaction.get_regression_ready_before_valid();
              end
              aw_channel_error <= aw_channel_error;
            end
          end else if (axi_master.awvalid == 1'b1) begin
            `uvm_error(COMPONENT_NAME, $sformatf(
                       "Did not expect master waddr chan to go valid with current transaction type %s response data %x!",
                       current_transaction.get_axi_request_type().name(),
                       current_transaction.get_response_data()
                       ));
            aw_channel_error <= 1;
          end
        end
        CHECK_TEST_RESULT: begin
          // maintain error flags
        end
        IDLE: begin
          aw_channel_error <= 0;
          // capability ops module may start writing before we can accept / check the request
          if (!MONITOR_MODE) begin
            `AXI5_RESET_AW_CHANNEL_MASTER(axi_master);
          end
        end
        default: begin
          // in case the DUT immediately does a second write (e.g., AXI DMA), we need to sit it out and wait for the next data to arrive
          aw_channel_error <= aw_channel_error;
          if (!MONITOR_MODE) begin
            `AXI5_RESET_AW_CHANNEL_MASTER(axi_master);
          end
        end
      endcase
    end
  end

  assign r_channel_beat_complete = (axi_master.rvalid && axi_master.rready);

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : RChannelFFLogic
    if (rst_ni == 0) begin
      if (!MONITOR_MODE) begin
        `AXI5_RESET_R_CHANNEL_MASTER(axi_master);
      end
      // other values need not be initialized
      provided_read_data <= 0;
      r_channel_complete <= 0;
    end else begin
      unique case (current_state)
        HANDLE_DATA, GIVE_RESPONSE: begin
          if (!r_channel_complete) begin
            automatic axi_atop_t current_atop;

            current_atop = current_transaction.get_atomic_type();

            `uvm_info(COMPONENT_NAME, $sformatf("Current atop type: %s", current_atop.name()),
                      UVM_DEBUG);

            if((current_transaction.get_axi_request_type() == AXI_TEST_READ || (current_transaction.get_axi_request_type() == AXI_TEST_WRITE && current_atop != ATOMIC_NONE && current_atop != ATOMIC_STORE)) && !MONITOR_MODE)
                        begin
              automatic bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] response_data;
              response_data = current_transaction.get_response_data();
              provided_read_data <= provided_read_data + (r_channel_beat_complete ? 1 : 0);
              axi_master.rresp <= current_transaction.get_given_response();
              axi_master.rdata <= response_data[r_channel_beat_complete ? provided_read_data + 1 : provided_read_data];
              if(provided_read_data + (r_channel_beat_complete ? 1 : 0) >= {24'h0,current_transaction.get_test_len()})
                            begin
                `uvm_info(COMPONENT_NAME, $sformatf(
                          "Last beat in read transaction after transferring %d beats with target %d",
                          provided_read_data + (r_channel_beat_complete ? 1 : 0),
                          current_transaction.get_test_len()
                          ), UVM_DEBUG);
                axi_master.rlast <= 1;
              end else begin
                `uvm_info(COMPONENT_NAME, $sformatf("Keeping last value at %b", axi_master.rlast),
                          UVM_DEBUG);
                // needs to be kept until the beat is complete
                if (!MONITOR_MODE) begin
                  axi_master.rlast <= axi_master.rlast;
                end
              end
              if (r_channel_beat_complete && axi_master.rlast) begin
                r_channel_complete <= 1;
                if (!MONITOR_MODE) begin
                  `AXI5_RESET_R_CHANNEL_MASTER(axi_master);
                end
              end else begin
                automatic logic next_valid;
                // AMBA spec: the master is not allowed to pull valid down once raised
                if (axi_master.rready) begin
                  next_valid = !current_transaction.generate_random_delay(R_VALID);
                  `uvm_info(COMPONENT_NAME, $sformatf("Generating random valid %b!", next_valid),
                            UVM_DEBUG);
                end else begin
                  next_valid = 1;
                end
                if (!MONITOR_MODE) begin
                  axi_master.rvalid <= next_valid;
                end


              end

              if (!MONITOR_MODE) begin
                axi_master.rid   <= current_transaction.get_test_id();
                axi_master.ruser <= current_transaction.get_test_user();
              end
            end
          end else begin
            if (!MONITOR_MODE) begin
              `AXI5_RESET_R_CHANNEL_MASTER(axi_master);
            end
            r_channel_complete <= r_channel_complete;
          end
        end
        default: begin
          provided_read_data <= 0;
          r_channel_complete <= 0;
          if (!MONITOR_MODE) begin
            `AXI5_RESET_R_CHANNEL_MASTER(axi_master);
          end
        end
      endcase
    end
  end : RChannelFFLogic

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : WChannelFFLogic
    if (rst_ni == 0) begin
      if (!MONITOR_MODE) begin
        `AXI5_RESET_W_CHANNEL_MASTER(axi_master);
      end
      w_channel_complete <= 0;
      w_channel_error <= 0;
      collected_write_data <= 0;
    end else begin
      unique case (current_state)
        START_TRANSACTION, HANDLE_DATA: begin
          if (axi_master.wvalid && axi_master.wready && !w_channel_complete) begin
            if (current_transaction.get_axi_request_type() == AXI_TEST_WRITE) begin
              current_result.write_data[collected_write_data] = axi_master.wdata;
              current_result.write_strobes[collected_write_data] = axi_master.wstrb;

              if (collected_write_data == 0) begin
                current_result.wid   <= axi_master.wid;
                current_result.wuser <= axi_master.wuser;
              end else begin
                if (current_result.wid != axi_master.wid) begin
                  `uvm_error(COMPONENT_NAME, "Axi master wid changed between beats!");
                end
                if (current_result.wuser != axi_master.wuser) begin
                  `uvm_error(COMPONENT_NAME, "Axi master wuser changed between beats!");
                end
              end

              collected_write_data <= collected_write_data + 1;


              w_channel_complete   <= axi_master.wlast;

              if (axi_master.wlast && current_result.len != collected_write_data) begin
                `uvm_error(COMPONENT_NAME, $sformatf(
                           "AXI master did not receive wlast at the expected time: Result len %d seen data %d!",
                           current_result.len,
                           collected_write_data
                           ));

                w_channel_error <= 1'b1;
              end


            end
            if (!MONITOR_MODE) begin
              axi_master.wready <= !current_transaction.generate_random_delay(W_READY);
            end
          end else begin
            // ready can lead valid...
            // however, cannot be w ready when not aw ready
            if (!MONITOR_MODE) begin
              axi_master.wready <= (!current_transaction.generate_random_delay(W_READY) ||
                                    current_transaction.get_regression_ready_before_valid()) &&
                  !(axi_master.awvalid && !axi_master.awready);
            end

            if (axi_master.wvalid && w_channel_complete) begin
              `uvm_error(COMPONENT_NAME, "W channel should NOT be valid right now!");
              w_channel_error <= 1;
            end
          end
        end
        GIVE_RESPONSE, CHECK_TEST_RESULT: begin
          // maintain error flags
          axi_master.wready <= 1'b0;
        end
        IDLE: begin
          // cannot accept data now
          w_channel_complete <= 0;
          w_channel_error <= 0;
          if (!MONITOR_MODE) begin
            `AXI5_RESET_W_CHANNEL_MASTER(axi_master);
          end
          collected_write_data <= 0;
        end
        default: begin
          w_channel_complete <= 0;
          w_channel_error <= 0;
          if (!MONITOR_MODE) begin
            // cannot handle transaction currently
            axi_master.wready <= 0;
          end
        end
      endcase
    end
  end

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : BChannelFFLogic
    if (rst_ni == 0) begin
      b_channel_complete <= 0;
      if (!MONITOR_MODE) begin
        `AXI5_RESET_B_CHANNEL_MASTER(axi_master);
      end
    end else begin
      unique case (current_state)
        GIVE_RESPONSE: begin
          if (axi_master.bvalid && axi_master.bready && !b_channel_complete) begin
            b_channel_complete <= 1;
            if (!MONITOR_MODE) begin
              `AXI5_RESET_B_CHANNEL_MASTER(axi_master);
            end
          end else begin
            if (b_channel_complete) begin
              if (!MONITOR_MODE) begin
                axi_master.bvalid <= 0;
              end
            end else begin
              if (!MONITOR_MODE) begin
                axi_master.bvalid <= axi_master.bvalid ? 1 : !current_transaction.generate_random_delay(
                    B_VALID);
              end
            end
            if (!MONITOR_MODE) begin
              axi_master.bresp <= current_transaction.get_given_response();
              axi_master.bid   <= current_transaction.get_test_id();
              axi_master.buser <= current_transaction.get_test_user();
            end
          end
        end
        default: begin
          if (!MONITOR_MODE) begin
            `AXI5_RESET_B_CHANNEL_MASTER(axi_master);
          end
          b_channel_complete <= 0;
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
        `uvm_info(COMPONENT_NAME, "master finished!", UVM_DEBUG);
        ap_i.write(current_result);
        current_result = new("master_driver_result");
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
          `uvm_info(COMPONENT_NAME, "Master starting transaction!", UVM_DEBUG);
          next_state = START_TRANSACTION;
        end
      end
      START_TRANSACTION: begin
        if(current_transaction.get_axi_request_type() == AXI_TEST_READ && (!axi_master.arready || !axi_master.arvalid))
                begin
          next_state = ar_channel_error ? CHECK_TEST_RESULT : START_TRANSACTION;
        end
                else if(current_transaction.get_axi_request_type() == AXI_TEST_WRITE && (!axi_master.awready || !axi_master.awvalid))
                begin
          `uvm_info(COMPONENT_NAME, "Master side staying in START_TRANSACTION!", UVM_DEBUG);
          next_state = aw_channel_error ? CHECK_TEST_RESULT : START_TRANSACTION;
          // W channel can be completed BEFORE or CONCURRENT WITH AW channel
        end else if(current_transaction.get_axi_request_type() == AXI_TEST_WRITE && (w_channel_complete || axi_master.wvalid && axi_master.wready && axi_master.wlast) && axi_master.awvalid && axi_master.awready)
        begin
          `uvm_info(COMPONENT_NAME, "Master side going to GIVE_RESPONSE directly!", UVM_DEBUG);
          next_state = (aw_channel_error || w_channel_error) ? CHECK_TEST_RESULT : GIVE_RESPONSE;
        end else begin
          next_state = (aw_channel_error || ar_channel_error) ? CHECK_TEST_RESULT : HANDLE_DATA;
          `uvm_info(COMPONENT_NAME, $sformatf("Master side transitioning to %s!", next_state.name()
                    ), UVM_DEBUG);
        end
      end
      HANDLE_DATA: begin
        if (current_transaction.get_axi_request_type() == AXI_TEST_READ) begin
          if ((axi_master.rvalid && axi_master.rready && axi_master.rlast) || r_channel_complete) begin
            // complete
            next_state = TEST_OK;
          end
        end else if (current_transaction.get_axi_request_type() == AXI_TEST_WRITE) begin
          // write must be completed before rdata
          if ((axi_master.wvalid && axi_master.wready && axi_master.wlast) || w_channel_complete) begin
            `uvm_info(COMPONENT_NAME, "Info: Master side transitioning to GIVE_RESPONSE!",
                      UVM_DEBUG);
            next_state = w_channel_error ? CHECK_TEST_RESULT : GIVE_RESPONSE;
          end
        end
      end
      GIVE_RESPONSE: begin
        automatic axi_atop_t current_atop;

        current_atop = current_transaction.get_atomic_type();

        if((r_channel_complete || current_atop == ATOMIC_NONE || current_atop == ATOMIC_STORE) && b_channel_complete)
                begin
          next_state = CHECK_TEST_RESULT;
          ;
        end
      end
      CHECK_TEST_RESULT: begin
        // last transaction might be incorrect - wait one cycle before deciding whether test was OK
        next_state = (aw_channel_error || ar_channel_error || w_channel_error) ? TEST_ERR : TEST_OK;
      end
      TEST_OK, TEST_ERR: begin
        // have reported test status
        next_state = IDLE;
      end
      default: begin
        // nothing to do
      end
    endcase
  end

endmodule
