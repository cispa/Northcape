/**
  * Testbench for directed integration testing of the northcape system components (Ops-Resolver-MMU).
  */
package northcape_integration_randomized_test;

  import northcape_capability_ops_transaction::*;
  import northcape_capability_ops_agent::*;
  import northcape_generator::NorthcapeGenerator;
  import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
  import northcape_sparse_mem_sim::*;
  import northcape_integration_agent::NorthcapeIntegrationAgent;
  import northcape_types::*;
  import northcape_test::*;
  import northcape_integration_test_constants::*;
  import northcape_generic_env::NorthcapeGenericEnv;
  import axi5::*;
  import northcape_capability_ops_common::*;
  import northcape_integration_transaction::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  `include "northcape_uvm_test_wrapper.svh"

  localparam COMPONENT_NAME = "Northcape System Randomized Test";

  typedef logic[AXI_DATA_WIDTH_MEM-1:0] mem_content_t[$];
  typedef logic[AXI_ADDR_WIDTH-1:0] mem_index_t;
  
  typedef NorthcapeSparseMem#(.QUEUE_TYPE(mem_content_t),.DATA_TYPE(logic[AXI_DATA_WIDTH_MEM-1:0]),.INDEX_TYPE(mem_index_t),.AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM)) sparse_mem_t;

  typedef NorthcapeIntegrationAgent#(
    .AXI_DATA_WIDTH_MMU(AXI_DATA_WIDTH_MMU),
    .AXI_ADDR_WIDTH_MMU(AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH_MMU(AXI_ID_WIDTH),
    .AXI_USER_WIDTH_MMU(AXI_USER_WIDTH),

    .AXI_DATA_WIDTH_OPS(AXI_DATA_WIDTH_MEM),
    .AXI_ADDR_WIDTH_OPS(AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH_OPS(AXI_ID_WIDTH),
    .AXI_USER_WIDTH_OPS(AXI_USER_WIDTH),

    .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
    .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),

    .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
    .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),

    .HASH_TYPE(HASH_TYPE_IDENTITY),

    .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
    .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2),

    .TRANSACTIONS_QUEUE_NAME_AGENT_MMU(TRANSACTIONS_QUEUE_NAME_AGENT_MMU),
    .TRANSACTIONS_QUEUE_NAME_AGENT_OPS(TRANSACTIONS_QUEUE_NAME_AGENT_OPS),
    .TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION(TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION),
    .CAPABILITY_OPS_AGENT_CONFIG_NAME(CAPABILITY_OPS_AGENT_CONFIG_NAME),
    .MMU_AGENT_CONFIG_NAME(MMU_AGENT_CONFIG_NAME),
    .CAPABILITY_OPS_AXI_LITE_INTERFACE_NAME(INTEGRATION_TEST_CAPABILITY_OPS_AXI_LITE_INTERFACE_NAME),
    .INTEGRATION_AGENT_CONFIG_NAME(INTEGRATION_AGENT_CONFIG_NAME),
    .HAS_CACHE_INTERFACE(HAS_CACHE_INTERFACE),
    .OPS_TAG_METHOD(OPS_TAG_METHOD),
    .BRAM_DATA_WIDTH(OPS_BRAM_DATA_WIDTH),
    .BRAM_DATA_DEPTH((2**INITIAL_CMT_SIZE_CLOG2)/OPS_BRAM_DATA_WIDTH)
  ) integration_agent_t;

  typedef NorthcapeGenericEnv#(
    .AGENT_TYPE(integration_agent_t),
    .RESET_INTERFACE_NAME(INTEGRATION_TEST_RESET_INTERFACE_NAME)
  ) env_t;

  typedef NorthcapeIntegrationTransaction#(AXI_ADDR_WIDTH) integration_transaction_t;

  typedef NorthcapeGenerator#(integration_transaction_t) gen_t;
  
  localparam NUMBER_TRANSACTIONS=1024;

  typedef NorthcapeIntegrationCapabilityDatabase#(AXI_ADDR_WIDTH) cap_db_t;
  typedef NorthcapeIntegrationCapabilityDatabaseEntry#(AXI_ADDR_WIDTH) cap_db_entry_t;
  
  function automatic void do_randomized_test(ref cap_db_t cap_db);
     integration_transaction_t integration_transaction;


      uvm_queue#(integration_transaction_t) integration_queue;

      assert(uvm_config_db#(uvm_queue#(integration_transaction_t))::get(null,"",TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION,integration_queue));
      
      do
      begin
        integration_transaction = gen_t::generate_transaction_ephemeral_allow_null();
        if(integration_transaction == null)
        begin
          `uvm_warning(COMPONENT_NAME, "Could not generate a transaction!");
          return;
        end
      end
      while(!cap_db.get_capability(integration_transaction.capability_to_operate_on));

      `uvm_info(COMPONENT_NAME,$sformatf("I have create a transaction %s",integration_transaction.convert2string()),UVM_DEBUG);

      integration_queue.push_back(integration_transaction);

      cap_db.add_predicted_capability_after_operation(integration_transaction);

  endfunction
  
  `NORTHCAPE_UVM_TEST(northcape_whole_system_randomized_test,env_t)
    begin
      cap_db_t cap_db;
      cap_db = cap_db_t::get_inst();

      for(int i = 0; i < NUMBER_TRANSACTIONS; i++)
      begin
        do_randomized_test(cap_db);
        `uvm_info(COMPONENT_NAME,$sformatf("I have created %d randomized transactions!",(i+1)),UVM_MEDIUM);
      end
    end
  `NORTHCAPE_UVM_TEST_END

endpackage
