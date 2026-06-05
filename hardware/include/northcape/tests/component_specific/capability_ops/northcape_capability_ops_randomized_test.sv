/**
  * Testbench for directed and regression testing of the capability ops component.
  */
package northcape_capability_ops_randomized_test;

  import northcape_capability_ops_transaction::*;
  import northcape_capability_ops_agent::*;
  import northcape_generator::NorthcapeGenerator;
  import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
  import northcape_test::*;
  import northcape_types::*;
  import northcape_capability_ops_test_constants::*;
  import northcape_generic_env::NorthcapeNoResetEnv;
  import axi5::*;
  import northcape_capability_ops_common::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "northcape_uvm_test_wrapper.svh"

  localparam string COMPONENT_NAME = "Northcape Capability Ops Randomized Test";

  localparam NUMBER_RANDOMIZED_TESTS=16384;

  localparam REPORT_EVERY_N_TRANSACTIONS_CREATED=4096;

  typedef NorthcapeCapabilityOpsAgent#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),

      .HASH_TYPE(HASH_TYPE_IDENTITY),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2),
      .TRANSACTIONS_QUEUE_NAME_AGENT(CAPABILITY_OPS_TRANSACTION_QUEUE_NAME),
      .CAPABILITY_OPS_AGENT_CONFIG_NAME(CAPABILITY_OPS_AGENT_CONFIG_NAME),
      .AXI_LITE_INTERFACE_NAME(CAPABILITY_OPS_AXI_LITE_INTERFACE_NAME),
      // no integration test
      .CHECK_AXI_TRANSACTIONS(1),

      .RNG_INTERFACE_NAME(CAPABILITY_OPS_RNG_INTERFACE_NAME),
      .PROVIDE_RNG_INTERFACE(1),
      .OPS_TAG_METHOD(OPS_TAG_METHOD),
      .BRAM_DATA_WIDTH(OPS_BRAM_DATA_WIDTH),
      .BRAM_DATA_DEPTH((2**INITIAL_CMT_SIZE_CLOG2)/OPS_BRAM_DATA_WIDTH)
  ) agent_t;

  typedef NorthcapeCapabilityOpsTransaction#(
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH  (AXI_ID_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),

    .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
    .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),

    .HASH_TYPE(HASH_TYPE_IDENTITY),

    .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
    .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
  ) transaction_t;

  typedef NorthcapeGenerator#(transaction_t) generator_t;

  typedef NorthcapeNoResetEnv#(.AGENT_TYPE(agent_t)) env_t;

  localparam bit [AXI_ADDR_WIDTH-1:0] create_input_token_default = 64'hdeadbeef;

  function bit do_randomized_test();
    transaction_t transaction;
    uvm_queue #(transaction_t) transactions;

    if(uvm_config_db#(uvm_queue#(transaction_t))::get(null,"",CAPABILITY_OPS_TRANSACTION_QUEUE_NAME,transactions) == 0)
    begin
      `uvm_fatal(COMPONENT_NAME,"Could not get transactions queue!");
    end

    transaction = generator_t::generate_transaction_ephemeral();

    transactions.push_back(transaction);

    return 1'b1;
  endfunction

  // agent does reset, as reset triggers the CMT create transactions
  `NORTHCAPE_UVM_TEST(capability_ops_randomized_test, env_t)
    for(int i = 0; i < NUMBER_RANDOMIZED_TESTS; i++)
    begin
      bit ret;
      do
      begin
        ret = do_randomized_test();
      end
      while(~ret);

      if(i % REPORT_EVERY_N_TRANSACTIONS_CREATED == 0)
      begin
        `uvm_info(COMPONENT_NAME,$sformatf("Created %d transactions!",i),UVM_MEDIUM);
      end
    end
  `NORTHCAPE_UVM_TEST_END
endpackage
