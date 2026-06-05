
`include "northcape_uvm_test_wrapper.svh"

/**
  * Testbench for randomized testing and functional coverage collection.
  * Runs Northcape MMU tests with a random NorthcapeAxitTransaction either TEST_REPETITIONS times or until a test fails, employing the test helper modules to verify the behavior of the component.
  */

package northcape_mmu_randomized_test;
  import northcape_mmu_transaction::*;
  import northcape_types::*;
  import northcape_test::*;
  import axi5::*;
  import uvm_pkg::*;
  import northcape_generic_env::NorthcapeGenericEnv;
  import northcape_generator::NorthcapeGenerator;
  import northcape_sequence::NorthcapeDirectSequence;
  import northcape_mmu_test_constants::*;

`ifdef NORTHCAPE_TEST_COVERAGE
  // (at least in Vivado), there is a limit on how much coverage data can be collected, leading to simulator crash...
  localparam TEST_REPETITIONS = 20000;
`else
  localparam TEST_REPETITIONS = 1 << 16;
`endif

`ifdef REPEAT_TEST
  `undef REPEAT_TEST
`endif

  `define REPEAT_TEST(TEST_COMMAND) \
    for(int test_repetition_counter = 0; test_repetition_counter < TEST_REPETITIONS; test_repetition_counter++)  \
    begin  \
      TEST_COMMAND;  \
      if((test_repetition_counter + 1) % 10 == 0) \
      begin \
        `uvm_info(COMPONENT_NAME,$sformatf("Generated %d tests!",test_repetition_counter+1),UVM_MEDIUM);\
      end \
    end

  localparam string COMPONENT_NAME = "MMU Randomized Test";



  typedef NorthcapeGenericEnv#(
      .AGENT_TYPE(mmu_agent_t),
      .RESET_INTERFACE_NAME(MMU_RESET_INTERFACE_NAME)
  ) mmu_env_t;

  typedef NorthcapeMMUTransaction#(
      .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
      .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .CHECK_CMT_OVERLAP(1)
  ) transaction_t;

  typedef NorthcapeGenerator#(transaction_t) generator_t;


  function automatic void do_randomized_test();
    transaction_t new_request;
    uvm_queue #(transaction_t) queue;

    new_request = generator_t::generate_transaction_ephemeral();

    assert (uvm_config_db#(uvm_queue#(transaction_t))::get(
        null, "", MMU_TRANSACTION_QUEUE_NAME, queue
    ));

    queue.push_back(new_request);

  endfunction

  `NORTHCAPE_UVM_TEST(mmu_randomized, mmu_env_t)
  `uvm_info(COMPONENT_NAME, "Generating randomized tests!", UVM_MEDIUM);
  `REPEAT_TEST(do_randomized_test());
  `uvm_info(COMPONENT_NAME, "Waiting for tests to actually complete!", UVM_MEDIUM);

  `NORTHCAPE_UVM_TEST_END

endpackage
