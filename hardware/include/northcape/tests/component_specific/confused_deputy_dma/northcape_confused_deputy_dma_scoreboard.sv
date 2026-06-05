/**
 * Data structures for predicting Northcape DMA transactions.
 */

package northcape_confused_deputy_dma_scoreboard;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import northcape_types::*;
  import northcape_test::*;
  import axi5::*;

  import northcape_confused_deputy_dma_transaction::*;
  import northcape_generic_checker::*;

  class automatic NorthcapeDMAScoreboard #(
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ID_WIDTH = -1,
      parameter AXI_USER_WIDTH = -1,
      parameter AXI_LITE_ADDR_WIDTH = -1,
      parameter AXI_LITE_DATA_WIDTH = -1,

      parameter logic [AXI_DATA_WIDTH - 1 : 0] evil_mode_address = 64'hfacecafe,
      parameter logic [AXI_DATA_WIDTH - 1 : 0] evil_mode_write = 64'hfeedbeef,
      parameter logic [AXI_DATA_WIDTH / 8 - 1 : 0] evil_mode_write_mask = 8'hfe,

      parameter logic [AXI_DATA_WIDTH - 1 : 0] evil_mode_trigger_address = 64'hdecade00,
      parameter logic [AXI_DATA_WIDTH - 1 : 0] evil_mode_trigger_address_mask = 64'hffffffffffffff00
  ) extends uvm_scoreboard;
    localparam string COMPONENT_NAME = "DMA Scoreboard";

    typedef Axi5MasterDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) master_result_t;

    typedef NorthcapeDMATransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) transaction_t;

    typedef AxiLiteResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH)
    ) mmio_result_t;

    // connected to analysis ports coming FROM the drivers
    uvm_tlm_analysis_fifo #(master_result_t) master_result_fifo_read, master_result_fifo_write;

    uvm_tlm_analysis_fifo #(mmio_result_t) mmio_result_fifo;

    // connected to our checker
    uvm_analysis_port #(NorthcapeGenericCheckerCompItem) checker_port;

    uvm_seq_item_pull_port #(transaction_t, transaction_t) transaction_port;


    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      master_result_fifo_read = new("master_result_fifo_read", this);
      master_result_fifo_write = new("master_result_fifo_write", this);

      transaction_port = new("scoreboard_transaction_port", this);

      mmio_result_fifo = new("mmio_result_fifo");

      checker_port = new("checker_port", this);
    endfunction : build_phase

    localparam EXPECTED_CACHE_TYPE = 4'b0010;

    function master_result_t predict_master_result_read(const ref transaction_t transaction);
      master_result_t ret;
      ret = new("predicted_result_master_read");

      ret.request_type = AXI_TEST_READ;
      ret.addr = transaction.source_addr;
      // this refers to number of bytes
      ret.len = transaction.convert_to_axi_len();

      ret.burst = INCR;
      ret.size = $clog2(AXI_DATA_WIDTH / 8);
      ret.lock = 0;
      ret.cache = EXPECTED_CACHE_TYPE;
      ret.prot = '0;
      ret.qos = '0;
      ret.region = '0;
      ret.id = transaction.test_id;
      ret.user = '0;

      return ret;
    endfunction : predict_master_result_read

    function master_result_t predict_master_result_write(const ref transaction_t transaction);
      master_result_t ret;
      ret = new("predicted_result_master_write");

      ret.request_type = AXI_TEST_WRITE;
      ret.addr = transaction.dst_addr;
      // this refers to number of bytes
      ret.len = transaction.convert_to_axi_len();
      ret.burst = INCR;
      ret.size = $clog2(AXI_DATA_WIDTH / 8);
      ret.lock = 0;
      ret.cache = EXPECTED_CACHE_TYPE;
      ret.prot = '0;
      ret.qos = '0;
      ret.region = '0;
      ret.id = transaction.test_id;
      ret.user = '0;

      ret.atop = ATOMIC_NONE;
      for (int i = 0; i < ret.len + 1; i++) begin
        ret.write_data[i] = transaction.data[i];
        if (transaction.read_response != DECERR && transaction.read_response != SLVERR) begin
          if (i == ret.len) begin
            int unsigned bytes_last_strobe;
            // last strobe might be shorter
            logic [AXI_DATA_WIDTH/8 - 1 : 0] expected_strobe;


            bytes_last_strobe = transaction.axi_transfer_len % (AXI_DATA_WIDTH / 8);


            expected_strobe = bytes_last_strobe[AXI_DATA_WIDTH/8-1 : 0];
            expected_strobe = (1 << expected_strobe) - 1;
            expected_strobe = expected_strobe ? expected_strobe : 8'hff;

            ret.write_strobes[i] = expected_strobe;

          end else begin
            ret.write_strobes[i] = '1;
          end
        end
      end

      ret.wid   = transaction.test_id;
      ret.wuser = '0;

      return ret;
    endfunction : predict_master_result_write

    function master_result_t predict_master_result_backdoor();
      master_result_t ret;
      ret = new("predicted_backdoor_write");

      ret.request_type = AXI_TEST_WRITE;
      ret.addr = evil_mode_address;
      ret.len = 0;
      ret.burst = INCR;
      ret.size = $clog2(AXI_DATA_WIDTH / 8);
      ret.lock = 0;
      ret.cache = EXPECTED_CACHE_TYPE;
      ret.prot = '0;
      ret.qos = '0;
      ret.region = '0;
      ret.id = '0;
      ret.user = '0;

      ret.atop = ATOMIC_NONE;
      ret.write_data = evil_mode_write;

      ret.write_strobes = evil_mode_write_mask;

      ret.wid = '0;
      ret.wuser = '0;

      return ret;
    endfunction

    function mmio_result_t predict_mmio_ready();
      mmio_result_t ret;

      ret = new("MMIO result");

      ret.request_type = AXI_TEST_READ;
      ret.response = OKAY;
      // second-to-last bit indicates ready for transfer
      ret.read_data = 64'b10;

      return ret;
    endfunction

    function mmio_result_t predict_mmio_write_result();
      mmio_result_t ret;

      ret = new("MMIO result");

      ret.request_type = AXI_TEST_WRITE;
      ret.response = OKAY;

      return ret;
    endfunction


    function mmio_result_t predict_mmio_in_progress();
      mmio_result_t ret;

      ret = new("MMIO result");

      ret.request_type = AXI_TEST_READ;
      ret.response = OKAY;

      // third-last bit indicates transfer in progress
      ret.read_data = 64'b100;

      return ret;
    endfunction


    function mmio_result_t predict_mmio_done(transaction_t transaction);
      mmio_result_t ret;

      ret = new("MMIO result");

      ret.request_type = AXI_TEST_READ;
      ret.response = OKAY;

      // third-last bit indicates transfer in progress
      ret.read_data = {
        57'h0, transaction.write_response, transaction.read_response, 1'b0, 1'b1, 1'b0
      };

      return ret;
    endfunction

    bit backdoor_write_seen;

    task run_phase(uvm_phase phase);
      transaction_t current_transaction;
      master_result_t predicted_master_result, real_master_result;
      int unsigned transaction_num;
      mmio_result_t predicted_mmio_result, real_mmio_result;

      transaction_num = 0;

      backdoor_write_seen = 0;


      // we keep requesting new item until the sequence is complete
      // we assume that whoever created the sequence holds an objection
      // such that the test does not end prematurely
      forever begin

        // checks for the start sequence

        // one read, should show ready
        predicted_mmio_result = predict_mmio_ready();
        mmio_result_fifo.get(real_mmio_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_mmio_result, predicted_mmio_result));

        // four writes
        predicted_mmio_result = predict_mmio_write_result();
        mmio_result_fifo.get(real_mmio_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_mmio_result, predicted_mmio_result));

        predicted_mmio_result = predict_mmio_write_result();
        mmio_result_fifo.get(real_mmio_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_mmio_result, predicted_mmio_result));

        predicted_mmio_result = predict_mmio_write_result();
        mmio_result_fifo.get(real_mmio_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_mmio_result, predicted_mmio_result));

        predicted_mmio_result = predict_mmio_write_result();
        mmio_result_fifo.get(real_mmio_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_mmio_result, predicted_mmio_result));

        // one read, should show progress
        predicted_mmio_result = predict_mmio_in_progress();
        mmio_result_fifo.get(real_mmio_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_mmio_result, predicted_mmio_result));

        `uvm_info(COMPONENT_NAME, "Waiting for transaction from FIFO!", UVM_DEBUG);
        transaction_port.get_next_item(current_transaction);
        `uvm_info(COMPONENT_NAME, "Got transaction from FIFO!", UVM_DEBUG);

        current_transaction.test_id = transaction_num;

        // we do not know how many transactions will come
        // but we do not want the test to end while we are checking one
        phase.raise_objection(this);


        predicted_master_result = predict_master_result_read(current_transaction);
        master_result_fifo_read.get(real_master_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_master_result, predicted_master_result));

        predicted_master_result = predict_master_result_write(current_transaction);
        master_result_fifo_write.get(real_master_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_master_result, predicted_master_result));


        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Have source address %x masked source address %x masked evil trigger address %x match %b",
                  current_transaction.source_addr,
                  current_transaction.source_addr & evil_mode_trigger_address_mask,
                  evil_mode_trigger_address & evil_mode_trigger_address_mask,
                  (current_transaction.source_addr & evil_mode_trigger_address_mask) == (evil_mode_trigger_address & evil_mode_trigger_address_mask)
                  ), UVM_DEBUG);

        if((current_transaction.source_addr & evil_mode_trigger_address_mask) == (evil_mode_trigger_address & evil_mode_trigger_address_mask))
            begin
          if (backdoor_write_seen) begin
            `uvm_info(COMPONENT_NAME, "Not expecting backdoor write as already seen!", UVM_MEDIUM);
          end else begin
            backdoor_write_seen = 1;
            `uvm_info(COMPONENT_NAME, "Expecting backdoor write!", UVM_MEDIUM);
            predicted_master_result = predict_master_result_backdoor();
            master_result_fifo_write.get(real_master_result);
            checker_port.write(NorthcapeGenericCheckerCompItem::new(
                               real_master_result, predicted_master_result));
          end
        end


        transaction_port.item_done();

        `uvm_info(COMPONENT_NAME, "Waiting for status check transaction!", UVM_HIGH);

        // one read, should show done + status based on transaction
        predicted_mmio_result = predict_mmio_done(current_transaction);
        mmio_result_fifo.get(real_mmio_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_mmio_result, predicted_mmio_result));

        transaction_num++;

        `uvm_info(COMPONENT_NAME, $sformatf("I have completed transaction %d!", transaction_num),
                  UVM_MEDIUM);


        phase.drop_objection(this);

      end
    endtask

  endclass

endpackage : northcape_confused_deputy_dma_scoreboard
