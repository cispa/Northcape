/**
  * Testbench for directed integration testing of the northcape system components (Ops-Resolver-MMU).
  */
package northcape_integration_unit_test;

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
  typedef NorthcapeIntegrationCapabilityDatabase#(AXI_ADDR_WIDTH) cap_db_t;
  
  function automatic void do_create_test(ref cap_db_t cap_db, input capability_id_t capability_id_in, input bit direction, input segment_length_t new_length, input capability_id_t capability_to_access_in_mmu = capability_id_in + 1, input northcape_restrictions_t mmu_restrictions = '0, input northcape_restrictions_t ops_restrictions = '0, bit instruction_fetch = 1'b0, bit is_irq = 1'b0, axi_test_request_type_t mmu_axi_request_type = AXI_TEST_READ);
     integration_transaction_t integration_transaction;

      uvm_queue#(integration_transaction_t) integration_queue;

      assert(uvm_config_db#(uvm_queue#(integration_transaction_t))::get(null,"",TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION,integration_queue));
      

      integration_transaction = new("integration transaction");

      integration_transaction.capability_to_operate_on = capability_id_in;
      integration_transaction.operation = NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE;
      integration_transaction.direction = direction;
      integration_transaction.new_segment_length = new_length;
      integration_transaction.capability_to_access_in_mmu = capability_to_access_in_mmu;
      integration_transaction.capability_restrictions = mmu_restrictions;
      
      integration_transaction.mmu_access_is_instruction_fetch = instruction_fetch;
      integration_transaction.mmu_access_is_irq = is_irq;

      integration_transaction.mmu_axi_request_type = mmu_axi_request_type;
      integration_transaction.capability_is_mmu_accessible = 1'b1;
      integration_transaction.capability_is_ops_accessible = 1'b1;

      // the expected value or not compared
      integration_transaction.requesting_device_id = ops_restrictions.body.task_restriction.device_id;
      integration_transaction.requesting_task_id = ops_restrictions.body.task_restriction.task_id;

      integration_queue.push_back(integration_transaction);

      cap_db.add_predicted_capability_after_operation(integration_transaction);

  endfunction
  
  function automatic void do_derive_test(ref cap_db_t cap_db, input capability_id_t capability_id_in, input segment_length_t new_length, input segment_length_t parent_offset, input capability_id_t capability_to_access_in_mmu = capability_id_in + 1, input northcape_restrictions_t ops_restrictions = '0, input northcape_restrictions_t mmu_restrictions = '0, bit instruction_fetch = 1'b0, bit is_irq = 1'b0);
    integration_transaction_t integration_transaction;

    uvm_queue#(integration_transaction_t) integration_queue;

    assert(uvm_config_db#(uvm_queue#(integration_transaction_t))::get(null,"",TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION,integration_queue));
      

    integration_transaction = new("integration transaction");

    integration_transaction.capability_to_operate_on = capability_id_in;
    integration_transaction.operation = NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE;
    integration_transaction.new_segment_length = new_length;
    integration_transaction.parent_offset = parent_offset;
    integration_transaction.capability_to_access_in_mmu = capability_to_access_in_mmu;

    integration_transaction.mmu_access_is_instruction_fetch = instruction_fetch;
    integration_transaction.mmu_access_is_irq = is_irq;
    
    
    integration_transaction.capability_restrictions = mmu_restrictions;

    integration_transaction.capability_is_mmu_accessible = 1'b1;
    integration_transaction.capability_is_ops_accessible = 1'b1;

    // the expected value or not compared
    integration_transaction.requesting_device_id = ops_restrictions.body.task_restriction.device_id;
    integration_transaction.requesting_task_id = ops_restrictions.body.task_restriction.task_id;

    integration_queue.push_back(integration_transaction);

    cap_db.add_predicted_capability_after_operation(integration_transaction);

  endfunction

  function automatic void do_clone_test(ref cap_db_t cap_db, input capability_id_t capability_id_in, input capability_id_t capability_to_access_in_mmu = capability_id_in + 1);
    integration_transaction_t integration_transaction;

    uvm_queue#(integration_transaction_t) integration_queue;

    assert(uvm_config_db#(uvm_queue#(integration_transaction_t))::get(null,"",TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION,integration_queue));
      

    integration_transaction = new("integration transaction");

    integration_transaction.capability_to_operate_on = capability_id_in;
    integration_transaction.operation = NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE;
    integration_transaction.capability_to_access_in_mmu = capability_to_access_in_mmu;

    integration_transaction.capability_restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;

    integration_transaction.capability_is_mmu_accessible = 1'b1;
    integration_transaction.capability_is_ops_accessible = 1'b1;

    integration_queue.push_back(integration_transaction);

    cap_db.add_predicted_capability_after_operation(integration_transaction);

  endfunction

  function automatic void do_drop_test(ref cap_db_t cap_db, input capability_id_t capability_id_in, input capability_id_t capability_to_access_in_mmu = capability_id_in - 1);
    integration_transaction_t integration_transaction;

    uvm_queue#(integration_transaction_t) integration_queue;

    assert(uvm_config_db#(uvm_queue#(integration_transaction_t))::get(null,"",TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION,integration_queue));
      

    integration_transaction = new("integration transaction");

    integration_transaction.capability_to_operate_on = capability_id_in;
    integration_transaction.operation = NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP;
    integration_transaction.capability_to_access_in_mmu = capability_to_access_in_mmu;

    integration_transaction.capability_restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;

    integration_transaction.capability_is_mmu_accessible = 1'b1;
    integration_transaction.capability_is_ops_accessible = 1'b1;

    integration_queue.push_back(integration_transaction);

    cap_db.add_predicted_capability_after_operation(integration_transaction);

  endfunction

  function automatic void do_merge_test(ref cap_db_t cap_db, input capability_id_t capability_id_left, input capability_id_t capability_id_right, input capability_id_t capability_to_access_in_mmu = capability_id_right + 1);
    integration_transaction_t integration_transaction;

    uvm_queue#(integration_transaction_t) integration_queue;

    assert(uvm_config_db#(uvm_queue#(integration_transaction_t))::get(null,"",TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION,integration_queue));
      

    integration_transaction = new("integration transaction");

    integration_transaction.capability_to_operate_on = capability_id_left;
    integration_transaction.capability_to_operate_on_right = capability_id_right;
    integration_transaction.operation = NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE;
    integration_transaction.capability_to_access_in_mmu = capability_to_access_in_mmu;

    integration_transaction.capability_restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;

    integration_transaction.capability_is_mmu_accessible = 1'b1;
    integration_transaction.capability_is_ops_accessible = 1'b1;

    integration_queue.push_back(integration_transaction);

    cap_db.add_predicted_capability_after_operation(integration_transaction);

  endfunction

  function automatic void do_revoke_test(ref cap_db_t cap_db, input capability_id_t capability_id_in, input capability_id_t capability_to_access_in_mmu = capability_id_in + 1);
    integration_transaction_t integration_transaction;

    uvm_queue#(integration_transaction_t) integration_queue;

    assert(uvm_config_db#(uvm_queue#(integration_transaction_t))::get(null,"",TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION,integration_queue));
      

    integration_transaction = new("integration transaction");

    integration_transaction.capability_to_operate_on = capability_id_in;
    integration_transaction.operation = NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE;
    integration_transaction.capability_to_access_in_mmu = capability_to_access_in_mmu;

    integration_transaction.capability_restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;

    integration_transaction.capability_is_mmu_accessible = 1'b1;
    integration_transaction.capability_is_ops_accessible = 1'b1;

    integration_queue.push_back(integration_transaction);

    cap_db.add_predicted_capability_after_operation(integration_transaction);

  endfunction

  function automatic void do_lock_test(ref cap_db_t cap_db, input capability_id_t capability_id_in, input capability_id_t capability_to_access_in_mmu = capability_id_in + 1);
    integration_transaction_t integration_transaction;

    uvm_queue#(integration_transaction_t) integration_queue;

    assert(uvm_config_db#(uvm_queue#(integration_transaction_t))::get(null,"",TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION,integration_queue));
      

    integration_transaction = new("integration transaction");

    integration_transaction.capability_to_operate_on = capability_id_in;
    integration_transaction.operation = NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK;
    integration_transaction.capability_to_access_in_mmu = capability_to_access_in_mmu;

    integration_transaction.capability_restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;

    integration_transaction.capability_is_mmu_accessible = 1'b1;
    integration_transaction.capability_is_ops_accessible = 1'b1;

    integration_queue.push_back(integration_transaction);

    cap_db.add_predicted_capability_after_operation(integration_transaction);

  endfunction

  function automatic void do_restrict_test(ref cap_db_t cap_db, input capability_id_t capability_id_in, input segment_length_t new_length = 0, input segment_length_t parent_offset = 0, input capability_id_t capability_to_access_in_mmu = capability_id_in, input northcape_restrictions_t mmu_restrictions = '0, input northcape_restrictions_t ops_restrictions = '0);
    integration_transaction_t integration_transaction;

    uvm_queue#(integration_transaction_t) integration_queue;

    assert(uvm_config_db#(uvm_queue#(integration_transaction_t))::get(null,"",TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION,integration_queue));
      

    integration_transaction = new("integration transaction");

    integration_transaction.capability_to_operate_on = capability_id_in;
    integration_transaction.operation = NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT;
    integration_transaction.new_segment_length = new_length;
    integration_transaction.parent_offset = parent_offset;
    integration_transaction.capability_to_access_in_mmu = capability_to_access_in_mmu;
    
    
    integration_transaction.capability_restrictions = mmu_restrictions;

    integration_transaction.capability_is_mmu_accessible = 1'b1;
    integration_transaction.capability_is_ops_accessible = 1'b1;

    // the expected value or not compared
    integration_transaction.requesting_device_id = ops_restrictions.body.task_restriction.device_id;
    integration_transaction.requesting_task_id = ops_restrictions.body.task_restriction.task_id;

    integration_queue.push_back(integration_transaction);

    cap_db.add_predicted_capability_after_operation(integration_transaction);

  endfunction

  function automatic void do_sweep_test(ref cap_db_t cap_db, input capability_id_t capability_to_access_in_mmu);
    integration_transaction_t integration_transaction;

    uvm_queue#(integration_transaction_t) integration_queue;

    assert(uvm_config_db#(uvm_queue#(integration_transaction_t))::get(null,"",TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION,integration_queue));
      

    integration_transaction = new("integration transaction");

    integration_transaction.operation = NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP;
    integration_transaction.capability_to_access_in_mmu = capability_to_access_in_mmu;
    integration_transaction.capability_restrictions = '0;
    // count orphans!
    integration_transaction.post_randomize();

    integration_queue.push_back(integration_transaction);

    cap_db.add_predicted_capability_after_operation(integration_transaction);

  endfunction

  `NORTHCAPE_UVM_TEST(northcape_can_do_root_capability_creates,env_t)
  begin
    cap_db_t cap_db;
    cap_db = cap_db_t::get_inst();

    do_create_test(cap_db, NORTHCAPE_ROOT_CAPABILITY_ID,0,32'h42);
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(northcape_can_do_stacked_creates,env_t)
  begin
    cap_db_t cap_db;
    cap_db = cap_db_t::get_inst();

    do_create_test(cap_db, NORTHCAPE_ROOT_CAPABILITY_ID,0,32'd1024);
    do_create_test(cap_db, NORTHCAPE_ROOT_CAPABILITY_ID+1,0,32'd256);
    do_create_test(cap_db, NORTHCAPE_ROOT_CAPABILITY_ID+1,0,32'd256);
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(northcape_can_do_full_size_creates,env_t)
  begin
    cap_db_t cap_db;
    cap_db = cap_db_t::get_inst();
    // each create destroys its parent, making this an important edge case especially for capability count
    do_create_test(cap_db, NORTHCAPE_ROOT_CAPABILITY_ID,0,32'd256);
    do_create_test(cap_db, NORTHCAPE_ROOT_CAPABILITY_ID+1,0,32'd256);
    do_create_test(cap_db, NORTHCAPE_ROOT_CAPABILITY_ID+2,0,32'd256);
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(northcape_can_do_stacked_derives_creates,env_t)
  begin
    cap_db_t cap_db;
    cap_db = cap_db_t::get_inst();

    do_create_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID,0,32'd1024);
    do_derive_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+1,32'd256, 32'd128);
    do_derive_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+2,32'd64, 32'd64);
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(northcape_can_do_drops,env_t)
  begin
    cap_db_t cap_db;
    cap_db = cap_db_t::get_inst();

    do_create_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID,0,32'd1024);
    do_derive_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+1,32'd256, 32'd128);
    do_drop_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+2,.capability_to_access_in_mmu(NORTHCAPE_ROOT_CAPABILITY_ID+2));

    // dropped the indirect capability
    // can do creates again
    do_create_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+1,0,32'd256,.capability_to_access_in_mmu(NORTHCAPE_ROOT_CAPABILITY_ID+3));
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(northcape_can_do_merges,env_t)
  begin
    cap_db_t cap_db;
    cap_db = cap_db_t::get_inst();

    do_create_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID,0,32'd1024);
    do_merge_test(cap_db, NORTHCAPE_ROOT_CAPABILITY_ID+1, NORTHCAPE_ROOT_CAPABILITY_ID,NORTHCAPE_ROOT_CAPABILITY_ID+2);
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(northcape_can_do_stacked_derives_clones_creates,env_t)
  begin
    cap_db_t cap_db;
    cap_db = cap_db_t::get_inst();

    do_create_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID,0,32'd1024);
    do_derive_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+1,32'd256, 32'd128);
    do_clone_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+2);
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(northcape_can_do_stacked_revoke_clones,env_t)
  begin
    cap_db_t cap_db;
    cap_db = cap_db_t::get_inst();

    do_create_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID,0,32'd1024);
    do_revoke_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+1);
    do_clone_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+2);
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(northcape_can_do_stacked_locks_derives,env_t)
  begin
    cap_db_t cap_db;
    cap_db = cap_db_t::get_inst();

    do_lock_test(cap_db,.capability_id_in(NORTHCAPE_ROOT_CAPABILITY_ID),.capability_to_access_in_mmu(NORTHCAPE_ROOT_CAPABILITY_ID+1));
    do_drop_test(cap_db,.capability_id_in(NORTHCAPE_ROOT_CAPABILITY_ID+1),.capability_to_access_in_mmu(NORTHCAPE_ROOT_CAPABILITY_ID));
    do_derive_test(cap_db,.capability_id_in(NORTHCAPE_ROOT_CAPABILITY_ID),.capability_to_access_in_mmu(NORTHCAPE_ROOT_CAPABILITY_ID+2),.new_length(32'd1024),.parent_offset(32'd1024));
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(northcape_can_lock_one_level_indirect_cap,env_t)
  begin
    cap_db_t cap_db;
    cap_db = cap_db_t::get_inst();

    do_create_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID,0,32'd1024);
    do_derive_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+1,32'd256, 32'd128);
    do_lock_test(cap_db,.capability_id_in(NORTHCAPE_ROOT_CAPABILITY_ID+2),.capability_to_access_in_mmu(NORTHCAPE_ROOT_CAPABILITY_ID+3));
    do_drop_test(cap_db,.capability_id_in(NORTHCAPE_ROOT_CAPABILITY_ID+3),.capability_to_access_in_mmu(NORTHCAPE_ROOT_CAPABILITY_ID+1));
    do_derive_test(cap_db,.capability_id_in(NORTHCAPE_ROOT_CAPABILITY_ID+1),.capability_to_access_in_mmu(NORTHCAPE_ROOT_CAPABILITY_ID+4),.new_length(32'd128),.parent_offset(32'd32));
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(northcape_can_do_root_capability_creates_with_restrictions,env_t)
  begin
    cap_db_t cap_db;
    northcape_restrictions_t restrictions;

    cap_db = cap_db_t::get_inst();

    restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED;
    restrictions.body.device_interpreted_bits = 64'hfeedbeefdeadbeef;


    do_create_test(cap_db, NORTHCAPE_ROOT_CAPABILITY_ID,0,32'h42,.mmu_restrictions(restrictions));
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(northcape_can_do_subsystem_calls,env_t)
  begin
    cap_db_t cap_db;
    northcape_restrictions_t mmu_restrictions, ops_restrictions;

    cap_db = cap_db_t::get_inst();

    ops_restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
    ops_restrictions.body.task_restriction.device_id = '0;
    ops_restrictions.body.task_restriction.task_id = '0;

    mmu_restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_SET_TASK_ID;
    mmu_restrictions.body.task_restriction.device_id = '0;
    mmu_restrictions.body.task_restriction.task_id = 32'hdead;


    do_create_test(cap_db, NORTHCAPE_ROOT_CAPABILITY_ID,0,32'd1024,.mmu_restrictions(mmu_restrictions), .ops_restrictions(ops_restrictions), .instruction_fetch(1'b1));

    mmu_restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND;
    ops_restrictions = mmu_restrictions;

    do_derive_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+1,32'd256, 32'd128, .mmu_restrictions(mmu_restrictions), .ops_restrictions(ops_restrictions));
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(northcape_can_do_restricts,env_t)
  begin
    cap_db_t cap_db;
    northcape_restrictions_t restrictions;
    cap_db = cap_db_t::get_inst();

    do_create_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID,0,32'd1024);
    do_derive_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+1,32'd256, 32'd128);

    restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
    restrictions.body.device_interpreted_bits = 64'hfeedbeefdeadbeef;

    // on create() capability
    // leaves only read permission, does not add restrictions
    do_restrict_test(cap_db, NORTHCAPE_ROOT_CAPABILITY_ID+1, .mmu_restrictions(restrictions));

    restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED;
    // leaves all permissions in tact, adds device-interpreted restriction
    // removes first 64 bytes from the segment
    do_restrict_test(cap_db, NORTHCAPE_ROOT_CAPABILITY_ID+2, .mmu_restrictions(restrictions), .parent_offset(64), .new_length(64));
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(northcape_can_do_restricts_for_locked_token,env_t)
  begin
    cap_db_t cap_db;
    northcape_restrictions_t restrictions;
    cap_db = cap_db_t::get_inst();

    restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED;
    restrictions.body.device_interpreted_bits = 64'hfeedbeefdeadbeef;

    do_create_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID,0,32'd1024);
    do_derive_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+1,32'd256, 32'd128);
    do_lock_test(cap_db,.capability_id_in(NORTHCAPE_ROOT_CAPABILITY_ID+2),.capability_to_access_in_mmu(NORTHCAPE_ROOT_CAPABILITY_ID+3));
    // offset/length not meaningfull for lock holder
    do_restrict_test(cap_db, NORTHCAPE_ROOT_CAPABILITY_ID+3, .mmu_restrictions(restrictions));
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(northcape_can_do_irq_subsystem_calls,env_t)
  begin
    cap_db_t cap_db;
    northcape_restrictions_t mmu_restrictions, ops_restrictions;

    cap_db = cap_db_t::get_inst();

    mmu_restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_SET_TASK_ID;
    mmu_restrictions.body.task_restriction.device_id = '0;
    mmu_restrictions.body.task_restriction.task_id = 32'hdead;

    ops_restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
    ops_restrictions.body.task_restriction.device_id = '0;
    ops_restrictions.body.task_restriction.task_id = '0;

    // jump INTO handler
    do_create_test(cap_db, NORTHCAPE_ROOT_CAPABILITY_ID,0,32'd1024,.mmu_restrictions(mmu_restrictions), .ops_restrictions(ops_restrictions), .instruction_fetch(1'b1), .is_irq(1'b1));

    mmu_restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND;
    ops_restrictions = mmu_restrictions;

    do_derive_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+1,32'd256, 32'd128, .mmu_restrictions(mmu_restrictions), .ops_restrictions(ops_restrictions), .is_irq(1'b1));


    mmu_restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_SET_TASK_ID;
    mmu_restrictions.body.task_restriction.device_id = '0;
    mmu_restrictions.body.task_restriction.task_id = 32'hbeef;

    ops_restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
    ops_restrictions.body.task_restriction.device_id = '0;
    ops_restrictions.body.task_restriction.task_id = '0;

    // jump FROM handler
    do_create_test(cap_db, NORTHCAPE_ROOT_CAPABILITY_ID,0,32'd1024,.mmu_restrictions(mmu_restrictions), .ops_restrictions(ops_restrictions), .instruction_fetch(1'b1), .is_irq(1'b0), .capability_to_access_in_mmu(NORTHCAPE_ROOT_CAPABILITY_ID+3));

    mmu_restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND;
    ops_restrictions = mmu_restrictions;

    do_derive_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+3,32'd256, 32'd128, .mmu_restrictions(mmu_restrictions), .ops_restrictions(ops_restrictions), .is_irq(1'b0));
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(northcape_can_do_sweeps,env_t)
  begin
    cap_db_t cap_db;
    cap_db = cap_db_t::get_inst();

    do_create_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID,0,32'd1024);
    // creates a bunch of references
    do_clone_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+1);
    do_clone_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+2);
    do_clone_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+3);
    do_clone_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+1);
    // creates orphans
    do_revoke_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+1, NORTHCAPE_ROOT_CAPABILITY_ID+6);
    // clean up references that are no longer useful
    do_sweep_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+6);
    // revoked capability should still work
    do_clone_test(cap_db,NORTHCAPE_ROOT_CAPABILITY_ID+6);
  end
  `NORTHCAPE_UVM_TEST_END

endpackage
