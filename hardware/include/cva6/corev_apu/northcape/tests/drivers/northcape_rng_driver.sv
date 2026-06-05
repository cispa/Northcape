`ifndef VERILATOR
/**
  * UVM driver for RNG, for unit tests
  */
package northcape_rng_driver;

  import northcape_test::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class automatic NorthcapeRNGDriver #(
      parameter RNG_DATA_WIDTH = -1,
      parameter string INTERFACE_NAME = "",
      // should implement IRNGSeedTransaction
      parameter type SEQUENCE_ITEM_TYPE = logic,

      parameter bit IS_ACTIVE = 1
  ) extends uvm_driver #(SEQUENCE_ITEM_TYPE);

    rand bit [RNG_DATA_WIDTH - 1 : 0] rng;

    typedef virtual NorthcapeRNGInterface #(RNG_DATA_WIDTH) rng_intf_t;

    rng_intf_t rng_intf;

    localparam COMPONENT_NAME = "Northcape RNG Driver";

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction


    function void build_phase(uvm_phase phase);

      if (IS_ACTIVE) begin
        if (!uvm_config_db#(rng_intf_t)::get(null, "", INTERFACE_NAME, rng_intf)) begin
          `uvm_fatal(COMPONENT_NAME, "Could not get interface!");
        end
      end

    endfunction

    function void seed_self(IRNGSeedTransaction transaction);
      this.srandom(transaction.get_rng_seed());
    endfunction

    function bit [RNG_DATA_WIDTH - 1 : 0] generate_random_output();
      if (this.randomize() != 1) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize myself!");
      end
      return this.rng;
    endfunction

    task run_phase(uvm_phase phase);
      IRNGSeedTransaction transaction;

      if (IS_ACTIVE) begin

        rng_intf.test_producer_clocking.rng_out   <= '0;
        rng_intf.test_producer_clocking.rng_valid <= 0;

        forever begin : rng

          seq_item_port.get_next_item(transaction);

          phase.raise_objection(this);

          seed_self(transaction);

          for (int i = 0; i < transaction.get_number_expected_rng_invocations(); i++) begin


            @(rng_intf.test_producer_clocking iff rng_intf.test_producer_clocking.rng_consumer_ready == 1);

            rng_intf.test_producer_clocking.rng_valid <= 1;
            rng_intf.test_producer_clocking.rng_out   <= generate_random_output();

            @(rng_intf.test_producer_clocking);
            rng_intf.test_producer_clocking.rng_valid <= 0;


          end

          seq_item_port.item_done();

          phase.drop_objection(this);

        end : rng
      end

    endtask

  endclass

endpackage

`endif
