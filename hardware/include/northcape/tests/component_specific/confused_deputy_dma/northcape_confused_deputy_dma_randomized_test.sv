/**
  * Testbench for directed and regression testing of the confused deputy DMA component.
  */
package northcape_confused_deputy_dma_randomized_test;


  import northcape_confused_deputy_dma_agent::NorthcapeConfusedDeputyDMATestAgent;
  import northcape_confused_deputy_dma_transaction::NorthcapeDMATransaction;
  import northcape_test::*;
  import northcape_types::*;
  import axi5::*;
  import northcape_generic_env::NorthcapeGenericEnv;

  import northcape_generator::NorthcapeGenerator;

  import northcape_confused_deputy_dma_test_constants::*;

  import uvm_pkg::*;

  `include "uvm_macros.svh"

  `include "northcape_uvm_test_wrapper.svh"

  typedef NorthcapeDMATransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) transaction_t;
  
  typedef NorthcapeGenerator#(transaction_t) generator_t;

  localparam test_num = 4096;
  localparam string COMPONENT_NAME = "Northcape DMA Randomized Test";

  typedef NorthcapeGenericEnv#(
    .AGENT_TYPE(dma_agent_t),
    .RESET_INTERFACE_NAME(DMA_RESET_INTERFACE_NAME)
  ) dma_env_t;

  function automatic void do_randomized_test();
    transaction_t randomized_test, cloned_test;
    uvm_object cloned_test_object;
    uvm_queue#(transaction_t) queue;

    // only one transaction such that we can sample
    randomized_test = generator_t::generate_transaction_singleton();
    randomized_test.sample_coverage();

    assert(uvm_config_db#(uvm_queue#(transaction_t))::get(null,"",DMA_TRANSACTION_QUEUE_NAME,queue));

    cloned_test_object = randomized_test.clone();

    assert($cast(cloned_test,cloned_test_object));

    `uvm_info(COMPONENT_NAME,"I have pushed a directed test!",UVM_DEBUG);
    // need to make sure we are using more than one test, actually
    queue.push_back(cloned_test);
  endfunction

  `NORTHCAPE_UVM_TEST(dma_randomized_test,dma_env_t)
    for(int unsigned i = 0; i < test_num; i++)
    begin
      `uvm_info(COMPONENT_NAME,$sformatf("Test repetition %d of %d",i+1,test_num),UVM_MEDIUM);
      do_randomized_test();
    end
    `uvm_info(COMPONENT_NAME,"Now waiting for tests to actually finish!",UVM_MEDIUM);
  `NORTHCAPE_UVM_TEST_END

endpackage
