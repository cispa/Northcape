/**
  * Generator that creates randomized transactions of the given types.
  * If functional coverage is used and covergroup lives within the transaction, we need to ensure only one transaction exists at one time.
  * Thus, both ephemeral and singleton methods provided.
  */
package northcape_generator;
  import uvm_pkg::*;
  `include "uvm_macros.svh"


  class automatic NorthcapeGenerator #(
      parameter type transaction_t = logic
  );
    // one instance such that we can sample coverage on the same coverage group

    localparam string COMPONENT_NAME = "Northcape Generator";

    localparam RANDOMIZE_ATTEMPTS = 65536;

    protected static transaction_t static_transaction;

    static function transaction_t generate_transaction_singleton();

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Generating transaction of type %s", $typename(static_transaction)), UVM_DEBUG);

      if (static_transaction == null) begin
        static_transaction = new("static_transaction");
      end

      if (static_transaction.randomize() != 1) begin
        `uvm_error(COMPONENT_NAME, "Could not randomize transaction!");
        $fatal(1);
      end else begin
        `uvm_info(COMPONENT_NAME, "Randomized transaction without issue!", UVM_DEBUG);
      end

      return static_transaction;

    endfunction

    static function transaction_t generate_transaction_ephemeral_allow_null();
      transaction_t transaction;
      int unsigned  randomize_attempts;

      randomize_attempts = 0;

      do begin

        transaction = new("ephemeral_transaction");

        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Generating transaction of type %s", $typename(transaction)), UVM_DEBUG);

        if (transaction.randomize() != 1) begin
          `uvm_warning(COMPONENT_NAME, "Could not randomize transaction!");
          randomize_attempts++;
        end else begin
          `uvm_info(COMPONENT_NAME, "Randomized transaction without issue!", UVM_DEBUG);
          return transaction;
        end
      end while (randomize_attempts < RANDOMIZE_ATTEMPTS);

      `uvm_warning(COMPONENT_NAME, "Randomization of transaction timed out!");

      return null;

    endfunction

    static function transaction_t generate_transaction_ephemeral();
      transaction_t transaction = generate_transaction_ephemeral_allow_null();

      if (transaction == null) begin
        `uvm_fatal(COMPONENT_NAME, "Could not generate transaction!");
      end

      return transaction;
    endfunction

  endclass
endpackage
