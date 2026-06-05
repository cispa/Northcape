/**
  * Testbench for directed and regression testing of the confused deputy DMA component.
  */
package northcape_confused_deputy_dma_unit_test;


  import northcape_confused_deputy_dma_agent::NorthcapeConfusedDeputyDMATestAgent;
  import northcape_confused_deputy_dma_transaction::NorthcapeDMATransaction;
  import northcape_test::*;
  import northcape_types::*;
  import axi5::*;
  import northcape_generic_env::NorthcapeGenericEnv;

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

  localparam COMPONENT_NAME = "Northcape DMA Unit Test";


  typedef NorthcapeGenericEnv#(
    .AGENT_TYPE(dma_agent_t),
    .RESET_INTERFACE_NAME(DMA_RESET_INTERFACE_NAME)
  ) dma_env_t;

  localparam logic [AXI_DATA_WIDTH - 1 : 0] aligned_source_addr = 64'hdeadbeef;
  localparam logic [AXI_DATA_WIDTH - 1 : 0] aligned_dest_addr = 64'hdeaddead;

  localparam logic [AXI_DATA_WIDTH - 1 : 0] aligned_transfer_length = 8*(AXI_DATA_WIDTH/8);


  function automatic void do_directed_test(logic [AXI_DATA_WIDTH - 1 : 0] source_addr, logic [AXI_DATA_WIDTH - 1 : 0] dest_addr, axi_len_t transfer_length, bit read_failure, bit write_failure);
    transaction_t directed_test;
    uvm_queue#(transaction_t) queue;

    directed_test = new("directed test transaction");
    // do not care about data - start with random
    assert(directed_test.randomize());
    
    directed_test.source_addr = source_addr;
    directed_test.dst_addr = dest_addr;
    directed_test.axi_transfer_len = transfer_length;

    directed_test.read_response = read_failure ? SLVERR : OKAY;
    directed_test.write_response = write_failure ? SLVERR : OKAY;

    assert(uvm_config_db#(uvm_queue#(transaction_t))::get(null,"",DMA_TRANSACTION_QUEUE_NAME,queue));

    `uvm_info(COMPONENT_NAME,"I have pushed a directed test!",UVM_DEBUG);
    
    queue.push_back(directed_test);
  endfunction

  `NORTHCAPE_UVM_TEST(dma_can_handle_aligned_transfer,dma_env_t)
    do_directed_test(aligned_source_addr, aligned_dest_addr, aligned_transfer_length, 0, 0);
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(dma_can_handle_unaligned_transfer,dma_env_t)
    do_directed_test(aligned_source_addr, aligned_dest_addr, aligned_transfer_length - 1, 0, 0);
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(dma_can_handle_write_failure,dma_env_t)
    do_directed_test(aligned_source_addr, aligned_dest_addr, aligned_transfer_length, 0, 1);
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(dma_can_handle_read_failure,dma_env_t)
    do_directed_test(aligned_source_addr, aligned_dest_addr, aligned_transfer_length, 1, 0);
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(dma_can_handle_read_and_write_failure,dma_env_t)
    do_directed_test(aligned_source_addr, aligned_dest_addr, aligned_transfer_length, 1, 1);
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(dma_has_a_backdoor,dma_env_t)
    do_directed_test(evil_mode_trigger_address, aligned_dest_addr, aligned_transfer_length, 0, 0);
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(dma_triggers_backdoor_only_once,dma_env_t)
    do_directed_test(evil_mode_trigger_address, aligned_dest_addr, aligned_transfer_length, 0, 0);
    do_directed_test(evil_mode_trigger_address, aligned_dest_addr, aligned_transfer_length, 0, 0);
  `NORTHCAPE_UVM_TEST_END

endpackage
