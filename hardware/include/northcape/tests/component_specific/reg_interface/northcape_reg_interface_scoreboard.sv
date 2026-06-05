/**
 * Data structures for predicting Northcape register interface transactions.
 */
package northcape_reg_interface_scoreboard;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import northcape_types::*;
  import northcape_test::*;
  import axi5::*;

  import northcape_reg_interface_transaction::*;
  import northcape_generic_checker::*;

  class automatic NorthcapeRegInterfaceScoreboard #(
      parameter NUM_REGS = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1
  ) extends uvm_scoreboard;
    localparam string COMPONENT_NAME = "Reg Interface Scoreboard";

    typedef NorthcapeRegInterfaceTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .NUM_REGS(NUM_REGS)
    ) transaction_t;

    typedef AxiLiteResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) mmio_result_t;

    typedef RegInterfaceResultTransaction#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .NUM_REGS(NUM_REGS)
    ) reg_result_t;

    uvm_tlm_analysis_fifo #(mmio_result_t) mmio_result_fifo;

    uvm_tlm_analysis_fifo #(reg_result_t) reg_result_fifo;

    // connected to our checker
    uvm_analysis_port #(NorthcapeGenericCheckerCompItem) checker_port;

    uvm_seq_item_pull_port #(transaction_t, transaction_t) transaction_port;


    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);

      transaction_port = new("scoreboard_transaction_port", this);

      mmio_result_fifo = new("mmio_result_fifo");

      reg_result_fifo = new("reg_result_fifo");

      checker_port = new("checker_port", this);
    endfunction : build_phase

    function mmio_result_t predict_mmio_result(const ref transaction_t transaction);
      mmio_result_t ret;

      ret = new("mmio_result");

      ret.request_type = transaction.axi_lite_transaction.transaction_type;
      ret.response = OKAY;  // currently no error cases implemented

      ret.read_data = (ret.request_type == AXI_TEST_READ) ? transaction.axi_lite_transaction.transaction_data : '0;

      return ret;
    endfunction

    function reg_result_t predict_reg_result(const ref transaction_t transaction);
      reg_result_t ret;

      ret = new("reg_result");

      ret.current_data = transaction.transaction_regs_out;

      if (transaction.axi_lite_transaction.transaction_type == AXI_TEST_WRITE) begin
        ret.current_data[transaction.get_reg_index()] = transaction.axi_lite_transaction.transaction_data;
      end

      return ret;
    endfunction

    task run_phase(uvm_phase phase);
      transaction_t current_transaction;
      int unsigned  transaction_num;
      mmio_result_t predicted_mmio_result, real_mmio_result;
      reg_result_t predicted_reg_result, real_reg_result;

      transaction_num = 0;

      // we keep requesting new item until the sequence is complete
      // we assume that whoever created the sequence holds an objection
      // such that the test does not end prematurely
      forever begin
        `uvm_info(COMPONENT_NAME, "Waiting for transaction from FIFO!", UVM_DEBUG);
        transaction_port.get_next_item(current_transaction);
        `uvm_info(COMPONENT_NAME, "Got transaction from FIFO!", UVM_DEBUG);

        // we do not know how many transactions will come
        // but we do not want the test to end while we are checking one
        phase.raise_objection(this);


        predicted_mmio_result = predict_mmio_result(current_transaction);
        mmio_result_fifo.get(real_mmio_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_mmio_result, predicted_mmio_result));

        predicted_reg_result = predict_reg_result(current_transaction);
        reg_result_fifo.get(real_reg_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_reg_result, predicted_reg_result));




        transaction_port.item_done();

        transaction_num++;

        `uvm_info(COMPONENT_NAME, $sformatf("I have completed transaction %d!", transaction_num),
                  UVM_MEDIUM);

        phase.drop_objection(this);

      end
    endtask

  endclass

endpackage : northcape_reg_interface_scoreboard
