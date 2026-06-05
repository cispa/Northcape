/**
  * Test class that predicts capability cache transactions and output.
  */
package northcape_capability_cache_scoreboard;
  import axi5::*;
  import northcape_capability_cache_common::*;
  import northcape_types::*;
  import northcape_test::*;
  import northcape_generic_checker::NorthcapeGenericCheckerCompItem;
  import northcape_capability_cache_transaction::*;
  import northcape_capability_cache_driver::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class automatic NorthcapeCapabilityCacheScoreboard #(
      parameter string TRANSACTIONS_QUEUE_NAME_SCOREBOARD = ""
  ) extends uvm_scoreboard;

    localparam COMPONENT_NAME = "Northcape Capability Cache Scoreboard";

    uvm_tlm_analysis_fifo #(NorthcapeCapabilityCacheResultTransaction) resolver_result_fifo;
    uvm_tlm_analysis_fifo #(NorthcapeCapabilityCacheResultTransaction) ops_result_fifo;

    // connected to our checker
    uvm_analysis_port #(NorthcapeGenericCheckerCompItem) checker_port;


    typedef NorthcapeCapabilityCacheTransaction transaction_t;

    uvm_seq_item_pull_port #(transaction_t, transaction_t) transaction_port;

    /* "golden reference" that we test against */
    northcape_cmt_entry_t simulated_mem[capability_id_t];


    function new(string name, uvm_component parent);
      super.new(name, parent);

    endfunction

    function void build_phase(uvm_phase phase);
      resolver_result_fifo = new("resolver_result_fifo", this);
      ops_result_fifo = new("ops_result_fifo", this);

      transaction_port = new("scoreboard_transaction_port", this);

      checker_port = new("checker_port", this);
    endfunction : build_phase

    task run_phase(uvm_phase phase);
      transaction_t current_transaction;
      NorthcapeCapabilityCacheResultTransaction real_result, expected_result;
      int unsigned test_id;



      forever begin : checkOneTransaction
        `uvm_info(COMPONENT_NAME, "Waiting for transaction from FIFO!", UVM_DEBUG);
        transaction_port.get_next_item(current_transaction);
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Got transaction from FIFO: %s!", current_transaction.convert2string()),
                  UVM_DEBUG);

        phase.raise_objection(this);

        expected_result = new("Expected result");

        if (current_transaction.active_port == NORTHCAPE_CAP_CACHE_RESOLVER) begin
          expected_result.response_err = 1'b0;
          expected_result.response_entry = simulated_mem[current_transaction.request_capability_id];
          if (!simulated_mem.exists(current_transaction.request_capability_id)) begin
            expected_result.response_entry = '0;
          end
          resolver_result_fifo.get(real_result);
        end else begin
          if (!current_transaction.is_write) begin
            expected_result.response_err = 1'b0;
            expected_result.response_entry = simulated_mem[current_transaction.request_capability_id];
            if (!simulated_mem.exists(current_transaction.request_capability_id)) begin
              expected_result.response_entry = '0;
            end
          end else begin
            // need to updated simulated memory
            expected_result.response_err = 1'b0;
            expected_result.response_entry = '0;
            simulated_mem[current_transaction.request_capability_id] = current_transaction.write_cmt_entry;
          end
          ops_result_fifo.get(real_result);
        end

        checker_port.write(NorthcapeGenericCheckerCompItem::new(real_result, expected_result));

        test_id++;
        `uvm_info(COMPONENT_NAME, $sformatf("Scoreboard finished transaction %d", test_id),
                  UVM_MEDIUM);


        phase.drop_objection(this);

        transaction_port.item_done();
      end : checkOneTransaction

    endtask

  endclass
endpackage
