/**
  * Testbench for directed and regression testing of the capability ops component.
  */
package northcape_cva6_mmu_randomized_test;

  import northcape_cva6_mmu_transaction::*;
  import northcape_cva6_mmu_agent::*;
  import northcape_generator::NorthcapeGenerator;
  import northcape_test::*;
  import northcape_types::*;
  import northcape_cva6_mmu_test_constants::*;
  import northcape_generic_env::NorthcapeGenericEnv;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "northcape_uvm_test_wrapper.svh"

  localparam string COMPONENT_NAME = "Northcape CVA6 MMU Unit Test";

  localparam NUMBER_RANDOMIZED_TESTS = 16384;
  localparam REPORT_EVERY_N_TRANSACTIONS_CREATED = 1024;

  typedef NorthcapeCVA6MMUAgent#(
      .INSTR_CHAN_DEVICE_ID(INSTR_CHAN_DEVICE_ID),
      .DATA_CHAN_DEVICE_ID(DATA_CHAN_DEVICE_ID),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),

    
      
      .MMU_AGENT_CONFIG_NAME(CVA6_MMU_AGENT_CONFIG_NAME),
      .TRANSACTIONS_QUEUE_NAME_AGENT(CVA6_MMU_TRANSACTION_QUEUE_NAME)
  ) agent_t;

  typedef NorthcapeCVA6MMUTransaction#(
        .INSTR_CHAN_DEVICE_ID(INSTR_CHAN_DEVICE_ID),
        .DATA_CHAN_DEVICE_ID(DATA_CHAN_DEVICE_ID),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) transaction_t;


  typedef NorthcapeGenerator#(transaction_t) gen_t;

  typedef NorthcapeGenericEnv#(
    .AGENT_TYPE(agent_t),
    .RESET_INTERFACE_NAME(CVA6_MMU_RESET_INTERFACE_NAME)
  ) env_t;


  function automatic void do_randomized_test();
    transaction_t transaction;
    uvm_queue #(transaction_t) transactions;

    if(uvm_config_db#(uvm_queue#(transaction_t))::get(null,"",CVA6_MMU_TRANSACTION_QUEUE_NAME,transactions) == 0)
    begin
      `uvm_fatal(COMPONENT_NAME,"Could not get transactions queue!");
    end

    transaction = gen_t::generate_transaction_ephemeral();


    transactions.push_back(transaction);
  endfunction

  `NORTHCAPE_UVM_TEST(cva6_mmu_randomized_test, env_t)
    for(int i = 0; i < NUMBER_RANDOMIZED_TESTS; i++)
    begin
      do_randomized_test();
      if(i % REPORT_EVERY_N_TRANSACTIONS_CREATED == 0)
      begin
        `uvm_info(COMPONENT_NAME,$sformatf("Created %d transactions!",i),UVM_MEDIUM);
      end
    end
  `NORTHCAPE_UVM_TEST_END

endpackage
