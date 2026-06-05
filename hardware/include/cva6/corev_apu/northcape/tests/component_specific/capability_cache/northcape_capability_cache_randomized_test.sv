/**
  * Testbench for directed and regression testing of the capability cache component.
  */
package northcape_capability_cache_randomized_test;

  import northcape_capability_cache_transaction::*;
  import northcape_capability_cache_agent::*;
  import northcape_generator::NorthcapeGenerator;
  import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
  import northcape_test::*;
  import northcape_types::*;
  import northcape_capability_cache_test_constants::*;
  import northcape_generic_env::NorthcapeNoResetEnv;
  import axi5::*;
  import northcape_capability_cache_common::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "northcape_uvm_test_wrapper.svh"

  localparam string COMPONENT_NAME = "Northcape Capability Cache Randomized Test";

  localparam NUMBER_RANDOMIZED_TESTS=(1<<20);
  localparam REPORT_EVERY_N_TRANSACTIONS_CREATED=4096;

  typedef NorthcapeCapabilityCacheAgent#(
      
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),

      .HASH_TYPE(HASH_TYPE_IDENTITY),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2),
      .TRANSACTIONS_QUEUE_NAME_AGENT(CAPABILITY_CACHE_TRANSACTION_QUEUE_NAME),
      .CAPABILITY_CACHE_AGENT_CONFIG_NAME(CAPABILITY_CACHE_AGENT_CONFIG_NAME)
  ) agent_t;

  typedef NorthcapeCapabilityCacheTransaction transaction_t;

  typedef NorthcapeGenerator#(transaction_t) generator_t;

  typedef NorthcapeNoResetEnv#(.AGENT_TYPE(agent_t)) env_t;


  function void do_randomized_test();
    transaction_t transaction;
    uvm_queue #(transaction_t) transactions;

    if(uvm_config_db#(uvm_queue#(transaction_t))::get(null,"",CAPABILITY_CACHE_TRANSACTION_QUEUE_NAME,transactions) == 0)
    begin
      `uvm_fatal(COMPONENT_NAME,"Could not get transactions queue!");
    end

    transaction = generator_t::generate_transaction_ephemeral();

    transactions.push_back(transaction);
  endfunction

  // agent does reset, as reset triggers the CMT create transactions
  `NORTHCAPE_UVM_TEST(capability_cache_randomized_test, env_t)
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
