/**
  * Generates a sequence of given transation, which instruct the tester what to expect.
  * Can be either randomized or directed (based on what the test provided).
  */
package northcape_sequence;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  /**
      * Generates a sequence for a directed test: fetches prepared transactions from a queue.
      */
  class automatic NorthcapeDirectSequence #(
      parameter type TRANSACTION_TYPE = logic,
      parameter string TRANSACTION_QUEUE_NAME = ""
  ) extends uvm_sequence #(TRANSACTION_TYPE);
    `uvm_object_param_utils(NorthcapeDirectSequence#(TRANSACTION_TYPE, TRANSACTION_QUEUE_NAME));

    function new(string name = "");
      super.new(name);
    endfunction

    localparam COMPONENT_NAME = "Northcape Sequence";

    task body();
      TRANSACTION_TYPE transaction;

      uvm_queue #(TRANSACTION_TYPE) transactions;

      if (!uvm_config_db#(uvm_queue#(TRANSACTION_TYPE))::get(
              null, "", TRANSACTION_QUEUE_NAME, transactions
          )) begin
        `uvm_fatal(COMPONENT_NAME, "Failed to get transactions object!");
      end

      `uvm_info({COMPONENT_NAME, " ", TRANSACTION_QUEUE_NAME}, $sformatf(
                "Queue len is %d for queue %s", transactions.size(), TRANSACTION_QUEUE_NAME),
                UVM_HIGH);

      while (transactions.size() > 0) begin
        transaction = transactions.pop_front();

        `uvm_info({COMPONENT_NAME, " ", TRANSACTION_QUEUE_NAME},
                  "Sending a transaction to sequencer!", UVM_HIGH);

        // transactions come prepared
        start_item(transaction);
        finish_item(transaction);

        `uvm_info({COMPONENT_NAME, " ", TRANSACTION_QUEUE_NAME}, "Item is done in sequencer!",
                  UVM_HIGH);

      end

    endtask

  endclass


  /**
      * Generates a sequence from a single transaction.
      */
  class automatic NorthcapeSingleSequence #(
      parameter type TRANSACTION_TYPE = logic
  ) extends uvm_sequence #(TRANSACTION_TYPE);
    `uvm_object_param_utils(NorthcapeSingleSequence#(TRANSACTION_TYPE));

    TRANSACTION_TYPE transaction;

    function new(string name = "");
      super.new(name);
    endfunction

    localparam COMPONENT_NAME = "Northcape Single Sequence";

    task body();

      // transaction comes prepared
      start_item(transaction);
      finish_item(transaction);

    endtask

  endclass

endpackage
