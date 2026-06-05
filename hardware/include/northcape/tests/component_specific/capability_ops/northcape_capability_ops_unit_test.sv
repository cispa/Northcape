/**
  * Testbench for directed and regression testing of the capability ops component.
  */
package northcape_capability_ops_unit_test;

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

  localparam string COMPONENT_NAME = "Northcape Capability Ops Unit Test";

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


  typedef NorthcapeGenerator#(transaction_t) gen_t;

  typedef NorthcapeNoResetEnv#(.AGENT_TYPE(agent_t)) env_t;


  localparam UNSUCCESSFULL_LOOKUP_WIDTH = $clog2(NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_32+1);

  localparam bit [AXI_ADDR_WIDTH-1:0] create_input_token_default = 64'hdeadbeef;

  function automatic void do_common_test(
    bit [AXI_ADDR_WIDTH-1:0] create_input_token = create_input_token_default,
    bit restriction_enabled = 0,
    device_id_t device_id_restriction = '0,
    task_id_t task_id_restriction = '0,
    bit [AXI_DATA_WIDTH-1:0] device_interpreted_restriction = '0,
    device_id_t device_id_current = '0,
    task_id_t task_id_current = '0,

    device_id_t device_id_input_cap = device_id_current,
    task_id_t task_id_input_cap = task_id_current,
    northcape_restriction_type_t restriction_input_cap = NORTHCAPE_RESTRICTIONS_NONE,

    bit read_perm = 1,
    bit write_perm = 1,
    bit x_perm = 1,
    bit lockable_perm = 1,
    bit irq_accessible_perm = 0,
    bit cacheable_tlb_perm = 1,
    bit cacheable_access_perm = 1,

    northcape_capability_operation_t operation = NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE,

    axi_resp_t read_resp = OKAY,
    axi_resp_t write_resp = OKAY,

    bit direction = 0,
    segment_length_t new_segment_length = 32'd420,

    northcape_physical_address_t base = '0,
    segment_length_t length = 32'hffffffff,
    bit[UNSUCCESSFULL_LOOKUP_WIDTH:0] unsuccessful_lookups = 0,
    capability_type_t capability_type = OFFSET_32_BIT,
    segment_length_t parent_offset = 32'd42,

    bit derive_force_direct = 0,
    bit derive_force_indirect = 0,

    segment_length_t length_right = 32'd420,

    int unsigned number_indirect_caps = 5,

    bit drop_make_one_capability_invalid = 1'b0,

    bit drop_force_lock_holder = 1'b0,

    northcape_restriction_type_t restriction_type = NORTHCAPE_RESTRICTIONS_NONE,

    bit use_isr_fsm = 1'b0,

    northcape_reference_count_t refcount = '0,

    bit use_rcsr_interface = 1'b0,

    northcape_cmt_entry_type_t cmt_entry_type = NORTHCAPE_CMT_INVALID

  );
    transaction_t transaction;
    uvm_queue #(transaction_t) transactions;

    if(uvm_config_db#(uvm_queue#(transaction_t))::get(null,"",CAPABILITY_OPS_TRANSACTION_QUEUE_NAME,transactions) == 0)
    begin
      `uvm_fatal(COMPONENT_NAME,"Could not get transactions queue!");
    end

    // need constraints, e.g., type of restriction, to match valid test
    do
    begin
      transaction = gen_t::generate_transaction_ephemeral();
      
      if(!transaction.valid_test)
      begin
        `uvm_info(COMPONENT_NAME,"Drop valid!",UVM_DEBUG);
        continue;
      end

      if(transaction.operation != operation)
      begin
        `uvm_info(COMPONENT_NAME,"Drop operation!",UVM_DEBUG);
        continue;
      end

      if(derive_force_direct && (operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE, NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE}) && transaction.input_cmt_entry.capability_type != NORTHCAPE_CMT_DIRECT)
      begin
        `uvm_info(COMPONENT_NAME,"Drop force direct!",UVM_DEBUG);
        continue;
      end

      if(operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP && drop_make_one_capability_invalid != transaction.drop_make_one_capability_invalid)
      begin
        `uvm_info(COMPONENT_NAME,"Drop force flip!",UVM_DEBUG);
        continue;
      end

      if(operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT} && drop_force_lock_holder == 1'b1  && transaction.input_cmt_entry.capability_type != NORTHCAPE_CMT_LOCK_HOLDER)
      begin
        `uvm_info(COMPONENT_NAME,"Drop force lock holder",UVM_DEBUG);
        continue;
      end


      break;
    end
    while(1'b1);

    transaction.input_token = create_input_token;
    
    transaction.device_id_restriction = device_id_restriction;
    transaction.task_id_restriction = task_id_restriction;
    transaction.restriction_enabled = restriction_enabled;
    transaction.device_interpreted_restriction = device_interpreted_restriction;
    transaction.restriction_type = restriction_type;

    transaction.device_id_current = device_id_current;
    transaction.task_id_current = task_id_current;

    transaction.read_perm = read_perm;
    transaction.write_perm = write_perm;
    transaction.x_perm = x_perm;
    transaction.lockable_perm = lockable_perm;
    transaction.irq_accessible_perm = irq_accessible_perm;
    transaction.cacheable_tlb_perm = cacheable_tlb_perm;
    transaction.cacheable_access_perm = cacheable_access_perm;

    transaction.operation = operation;

    transaction.read_resp = read_resp;
    transaction.write_resp = write_resp;

    transaction.direction = direction;
    transaction.new_segment_length = new_segment_length;

    transaction.input_cmt_entry.location.physical_location.base = base;
    transaction.input_cmt_entry.location.physical_location.length = length;

    // either the expected value or ignored (e.g., device-specific)
    transaction.input_cmt_entry.restrictions.restriction_type = restriction_input_cap;
    transaction.input_cmt_entry.restrictions.body.task_restriction.task_id   = task_id_input_cap;
    transaction.input_cmt_entry.restrictions.body.task_restriction.device_id = device_id_input_cap;

    transaction.input_cmt_entry.refcount = refcount;

    transaction.input_cmt_entry_right.location.physical_location.length = length_right;

    transaction.unsuccessful_lookups = unsuccessful_lookups;

    transaction.intended_capability_type = capability_type;

    transaction.parent_offset = parent_offset;

    if(derive_force_indirect)
    begin
      transaction.input_cmt_entry.capability_type = NORTHCAPE_CMT_INDIRECT;
      
      transaction.input_cmt_entry.location.indirect_location.effective_base = base;
      transaction.input_cmt_entry.location.indirect_location.length = length;
      transaction.number_indirect_caps = number_indirect_caps;
    end

    transaction.use_isr_fsm = use_isr_fsm;

    transaction.use_rcsr_interface = use_rcsr_interface;

    if(cmt_entry_type != NORTHCAPE_CMT_INVALID)
    begin
      transaction.input_cmt_entry.capability_type = cmt_entry_type;
    end

    // adapt other metadata fields
    transaction.post_randomize();

    if(operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT && drop_force_lock_holder)
    begin
      transaction.restrict_input_is_lock_holder = 1'b1;
      transaction.post_randomize();
    end

    $display("Created transaction with input cmt entry %s",print_cmt_entry(transaction.input_cmt_entry));

    transactions.push_back(transaction);
  endfunction


  function automatic void do_invalid_test(
    northcape_capability_operation_t operation = NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE,
    northcape_cmt_entry_type_t capability_type = NORTHCAPE_CMT_INVALID,
    northcape_restriction_type_t restriction_type = NORTHCAPE_RESTRICTIONS_NONE,
    northcape_restriction_type_t input_restriction_type = NORTHCAPE_RESTRICTIONS_NONE,
    device_id_t current_device = '0,
    task_id_t current_task = '0,
    device_id_t device_id_restriction = '0,
    task_id_t task_id_restriction = '0,
    device_id_t input_device_id_restriction = '0,
    task_id_t input_task_id_restriction = '0,
    bit restriction_enabled = 1'b0,
    northcape_reference_count_t refcount = '0,
    bit[UNSUCCESSFULL_LOOKUP_WIDTH:0] unsuccessful_lookups = 0,
    capability_type_t token_type = OFFSET_32_BIT
  );
    transaction_t transaction;
    uvm_queue #(transaction_t) transactions;

    if(uvm_config_db#(uvm_queue#(transaction_t))::get(null,"",CAPABILITY_OPS_TRANSACTION_QUEUE_NAME,transactions) == 0)
    begin
      `uvm_fatal(COMPONENT_NAME,"Could not get transactions queue!");
    end

    // need constraints, e.g., type of restriction, to match valid test
    // we then violate ONE of the assumptions
    do
    begin
      transaction = gen_t::generate_transaction_ephemeral();
      
      if(!transaction.valid_test)
      begin
        `uvm_info(COMPONENT_NAME,"Drop valid!",UVM_DEBUG);
        continue;
      end

      if(transaction.operation != operation)
      begin
        `uvm_info(COMPONENT_NAME,"Drop operation!",UVM_DEBUG);
        continue;
      end
      break;
    end
    while(1'b1);

    transaction.valid_test = 1'b0;
    transaction.input_cmt_entry.capability_type = capability_type;

    transaction.restriction_type = restriction_type;
    transaction.device_id_current = current_device;
    transaction.task_id_current = current_task;

    transaction.device_id_restriction = device_id_restriction;
    transaction.task_id_restriction = task_id_restriction;
    transaction.restriction_enabled = restriction_enabled;
    transaction.input_cmt_entry.refcount = refcount;
    transaction.intended_capability_type = token_type;

    transaction.unsuccessful_lookups = unsuccessful_lookups;

    if(input_restriction_type != NORTHCAPE_RESTRICTIONS_NONE)
    begin
      transaction.input_cmt_entry.restrictions.restriction_type = input_restriction_type; 
      transaction.input_cmt_entry.restrictions.body.task_restriction.task_id   = input_task_id_restriction;
      transaction.input_cmt_entry.restrictions.body.task_restriction.device_id = input_device_id_restriction;
    end

    $display("Created transaction with input cmt entry %s",print_cmt_entry(transaction.input_cmt_entry));

    transactions.push_back(transaction);
  endfunction

  // agent does reset, as reset triggers the CMT create transactions
  `NORTHCAPE_UVM_TEST(capability_ops_creates_cmt_after_reset, env_t)
  // nothing to do - agent automatically checks reset transactions
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_create_from_root_capability, env_t)
    do_common_test();
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_create_from_root_capability_via_csr_intf, env_t)
    do_common_test(.use_rcsr_interface(1'b1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_create_from_root_capability_with_1_unsuccessful_attempt, env_t)
    do_common_test(.unsuccessful_lookups(1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_create_from_root_capability_with_2_unsuccessful_attempts, env_t)
    do_common_test(.unsuccessful_lookups(2));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_destroy_root_capability, env_t)
    do_common_test(.create_input_token('0),.new_segment_length(32'hffffffff));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_create_with_different_capability_types, env_t)
    do_common_test(.capability_type(OFFSET_24_BIT));
    do_common_test(.capability_type(OFFSET_16_BIT));
    do_common_test(.capability_type(OFFSET_8_BIT));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_derive_from_root_capability, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE),.create_input_token('0), .derive_force_direct(1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_derive_from_non_root_capability, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE),.derive_force_direct(1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_derive_from_indirect_capability, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE),.derive_force_indirect(1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_drop_from_one_level_hierarchie, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP),.create_input_token('0), .derive_force_indirect(1), .number_indirect_caps(0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_drop_from_multi_level_hierarchie, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP),.create_input_token('0), .derive_force_indirect(1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_merge, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE),.length(420));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_clone_from_root_capability, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE),.create_input_token('0), .derive_force_direct(1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_clone_from_non_root_capability, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE),.derive_force_direct(1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_clone_from_indirect_capability, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE),.derive_force_indirect(1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_revoke, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE),.base(64'hdead),.length(64'hbeef));
  `NORTHCAPE_UVM_TEST_END

  /* covers several edge cases: all scenarios where segment can be written in one beat, all end edge cases for first and last beat */
  `NORTHCAPE_UVM_TEST(capability_ops_can_do_revoke_for_small_segments, env_t)
    for(int i = 1; i <= 2*AXI_DATA_WIDTH/8; i++)
    begin
      do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE),.base(64'hdead0000),.length(i));
      `uvm_info(COMPONENT_NAME, $sformatf("Generated transaction %d", i), UVM_MEDIUM);
    end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_drop_after_revoke_for_destroyed_parent, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP),.derive_force_indirect(1), .drop_make_one_capability_invalid(1), .number_indirect_caps(0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_drop_after_revoke_for_non_destroyed_parent, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP),.derive_force_indirect(1), .drop_make_one_capability_invalid(1), .number_indirect_caps(1));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP),.derive_force_indirect(1), .drop_make_one_capability_invalid(1), .number_indirect_caps(2));
  `NORTHCAPE_UVM_TEST_END

  // can lock both direct and indirect capability
  `NORTHCAPE_UVM_TEST(capability_ops_can_do_lock_indirect_cap, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK),.derive_force_indirect(1));
  `NORTHCAPE_UVM_TEST_END
  
  `NORTHCAPE_UVM_TEST(capability_ops_can_do_lock_direct_cap, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK),.derive_force_direct(1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_lock_indirect_cap_hierarchie_one, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK),.derive_force_indirect(1), .number_indirect_caps(0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_unlock_indirect_cap, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP),.derive_force_indirect(1), .drop_force_lock_holder(1));
  `NORTHCAPE_UVM_TEST_END
  
  `NORTHCAPE_UVM_TEST(capability_ops_can_do_unlock_direct_cap, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP),.derive_force_indirect(1), .drop_force_lock_holder(1), .number_indirect_caps(0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_unlock_indirect_cap_destroyed_parent, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP),.derive_force_indirect(1), .drop_force_lock_holder(1), .drop_make_one_capability_invalid(1), .number_indirect_caps(0));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP),.derive_force_indirect(1), .drop_force_lock_holder(1), .drop_make_one_capability_invalid(1), .number_indirect_caps(1));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP),.derive_force_indirect(1), .drop_force_lock_holder(1), .drop_make_one_capability_invalid(1), .number_indirect_caps(2));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_refuses_create_operations_on_lock_holder, env_t)
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE), .capability_type(NORTHCAPE_CMT_LOCK_HOLDER));
    `uvm_info(COMPONENT_NAME,"Have create transaction!",UVM_HIGH);
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_refuses_create_operations_when_references, env_t)
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE), .capability_type(NORTHCAPE_CMT_DIRECT), .refcount(1));
    `uvm_info(COMPONENT_NAME,"Have create transaction!",UVM_HIGH);
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_allows_create_operations_when_references_for_root_cap, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE), .refcount(1));
    `uvm_info(COMPONENT_NAME,"Have create transaction!",UVM_HIGH);
  `NORTHCAPE_UVM_TEST_END
  
  `NORTHCAPE_UVM_TEST(capability_ops_refuses_create_operations_on_cmt_full, env_t)
    // 32-bit capabilities start with ID 0
    do_invalid_test(.unsuccessful_lookups(NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_32 + 1), .capability_type(NORTHCAPE_CMT_DIRECT), .token_type(OFFSET_32_BIT));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_allows_derive_operations_on_lock_holder, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE), .cmt_entry_type(NORTHCAPE_CMT_LOCK_HOLDER));
    `uvm_info(COMPONENT_NAME,"Have derive transaction!",UVM_HIGH);
  `NORTHCAPE_UVM_TEST_END

  /* regression test - incorrect base */
  `NORTHCAPE_UVM_TEST(capability_ops_allows_derive_operations_on_lock_holder_direct, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE), .cmt_entry_type(NORTHCAPE_CMT_LOCK_HOLDER), .number_indirect_caps(0));
    `uvm_info(COMPONENT_NAME,"Have derive transaction!",UVM_HIGH);
  `NORTHCAPE_UVM_TEST_END
  `NORTHCAPE_UVM_TEST(capability_ops_allows_clone_operations_on_lock_holder_direct, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE), .cmt_entry_type(NORTHCAPE_CMT_LOCK_HOLDER), .number_indirect_caps(0));
    `uvm_info(COMPONENT_NAME,"Have derive transaction!",UVM_HIGH);
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_allows_lock_operations_on_lock_holder, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK), .cmt_entry_type(NORTHCAPE_CMT_LOCK_HOLDER));
    `uvm_info(COMPONENT_NAME,"Have lock transaction!",UVM_HIGH);
  `NORTHCAPE_UVM_TEST_END
  `NORTHCAPE_UVM_TEST(capability_ops_allows_clone_operations_on_lock_holder, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE), .cmt_entry_type(NORTHCAPE_CMT_LOCK_HOLDER));
    `uvm_info(COMPONENT_NAME,"Have clone transaction!",UVM_HIGH);
  `NORTHCAPE_UVM_TEST_END
  `NORTHCAPE_UVM_TEST(capability_ops_refuses_merge_operations_on_lock_holder, env_t)
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE), .capability_type(NORTHCAPE_CMT_LOCK_HOLDER));
    `uvm_info(COMPONENT_NAME,"Have merge transaction!",UVM_HIGH);
  `NORTHCAPE_UVM_TEST_END
  `NORTHCAPE_UVM_TEST(capability_ops_refuses_revoke_operations_on_lock_holder, env_t)
    // needs to run against direct capability, NOT the lock-holder token
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE), .capability_type(NORTHCAPE_CMT_LOCK_HOLDER));
    `uvm_info(COMPONENT_NAME,"Have revoke transaction!",UVM_HIGH);  
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_create_from_root_capability_with_all_restriction_types, env_t)
    do_common_test(.restriction_type(NORTHCAPE_RESTRICTIONS_NONE),.restriction_enabled(1),.task_id_restriction(32'hdead),.device_id_restriction(32'hbeef),.device_interpreted_restriction(64'hca1ab1edeadcab1e));
    do_common_test(.restriction_type(NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED),.restriction_enabled(1),.task_id_restriction(32'hdead),.device_id_restriction(32'hbeef),.device_interpreted_restriction(64'hca1ab1edeadcab1e));
    do_common_test(.restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.task_id_restriction(32'hdead),.device_id_restriction(32'hbeef),.device_interpreted_restriction(64'hca1ab1edeadcab1e));
    do_common_test(.restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID),.restriction_enabled(1),.task_id_restriction(32'hdead),.device_id_restriction(32'hbeef),.device_interpreted_restriction(64'hca1ab1edeadcab1e));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_refuses_set_task_id_for_different_id,env_t)
    // different device
    do_invalid_test(.capability_type(NORTHCAPE_CMT_DIRECT),.restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID),.restriction_enabled(1),.task_id_restriction(32'hdead),.device_id_restriction(32'hbeef),.current_device(0),.current_task(32'hdead));
    // different task
    do_invalid_test(.capability_type(NORTHCAPE_CMT_DIRECT),.restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID),.restriction_enabled(1),.task_id_restriction(32'hdead),.device_id_restriction(32'hbeef),.current_device(32'hbeef),.current_task(32'hfeed));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_inspect, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT),.derive_force_indirect(1), .drop_force_lock_holder(0), .number_indirect_caps(1));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT),.derive_force_direct(1),   .drop_force_lock_holder(0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_inspect_refcount, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT),.derive_force_indirect(1), .drop_force_lock_holder(0), .number_indirect_caps(1), .refcount(1));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT),.derive_force_direct(1),   .drop_force_lock_holder(0), .refcount(1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_inspect_refcount_isr, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT),.derive_force_indirect(1), .drop_force_lock_holder(0), .number_indirect_caps(1), .refcount(1), .use_isr_fsm(1));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT),.derive_force_direct(1),   .drop_force_lock_holder(0), .refcount(1), .use_isr_fsm(1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_inspect_in_isr, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT),.derive_force_indirect(1), .drop_force_lock_holder(0), .number_indirect_caps(1), .use_isr_fsm(1));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT),.derive_force_direct(1),   .drop_force_lock_holder(0), .use_isr_fsm(1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_derive_in_isr_mode, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE),.create_input_token('0), .derive_force_direct(1), .use_isr_fsm(1));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE),.create_input_token('0), .derive_force_direct(1), .use_isr_fsm(1), .device_id_current(0), .task_id_current(32'hdead));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE),.create_input_token('0), .derive_force_direct(1), .use_isr_fsm(1), .device_id_current(0), .task_id_current(32'hdead), .use_rcsr_interface(1'b1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_revoke_in_isr_mode, env_t)
    // length is limited due to test time
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE), .use_isr_fsm(1), .length(32'd256));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE), .use_isr_fsm(1), .device_id_current(0), .task_id_current(32'hdead), .length(32'd256));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE), .use_isr_fsm(1), .device_id_current(0), .task_id_current(32'hdead), .length(32'd256), .use_rcsr_interface(1'b1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_inspect_for_set_task_id_same_task_id, env_t)
  begin
    // set-task-id with our task ID: reveal everything
    device_id_t my_device_id = 16'hf0f0;
    task_id_t my_task_id = 32'hfff;

    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT),.derive_force_indirect(1), .drop_force_lock_holder(0), .number_indirect_caps(1), .use_isr_fsm(1), .device_id_input_cap(my_device_id), .task_id_input_cap(my_task_id), .restriction_input_cap(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .device_id_current(my_device_id), .task_id_current(my_task_id));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT),.derive_force_direct(1),   .drop_force_lock_holder(0), .device_id_input_cap(my_device_id), .task_id_input_cap(my_task_id), .restriction_input_cap(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .device_id_current(my_device_id), .task_id_current(my_task_id));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT),.derive_force_direct(1),   .drop_force_lock_holder(0), .device_id_input_cap(my_device_id), .task_id_input_cap(my_task_id), .restriction_input_cap(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .device_id_current(my_device_id), .task_id_current(my_task_id), .refcount(3));
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_inspect_for_set_task_id_different_task_id, env_t)
  begin
    // set-task-id with different task ID: reveal permissions and restrictions, hide the rest
    device_id_t my_device_id = 16'hf0f0;
    task_id_t my_task_id = 32'hfff;

    device_id_t input_cap_device_id = my_device_id + 1;
    task_id_t input_cap_task_id = my_task_id + 1;

    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT),.derive_force_indirect(1), .drop_force_lock_holder(0), .number_indirect_caps(1), .use_isr_fsm(1), .device_id_input_cap(input_cap_device_id), .task_id_input_cap(input_cap_task_id), .restriction_input_cap(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .device_id_current(my_device_id), .task_id_current(my_task_id));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT),.derive_force_direct(1),   .drop_force_lock_holder(0), .device_id_input_cap(input_cap_device_id), .task_id_input_cap(input_cap_task_id), .restriction_input_cap(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .device_id_current(my_device_id), .task_id_current(my_task_id));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT),.derive_force_direct(1),   .drop_force_lock_holder(0), .device_id_input_cap(input_cap_device_id), .task_id_input_cap(input_cap_task_id), .restriction_input_cap(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .device_id_current(my_device_id), .task_id_current(my_task_id), .refcount(3));
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_create_with_different_capability_types_full_size, env_t)
    // exception due to 32-bit encoding
    do_common_test(.capability_type(OFFSET_32_BIT),.new_segment_length((1<<32)-1));
    do_common_test(.capability_type(OFFSET_24_BIT),.new_segment_length(1<<24));
    do_common_test(.capability_type(OFFSET_16_BIT),.new_segment_length(1<<16));
    do_common_test(.capability_type(OFFSET_8_BIT),.new_segment_length(AXI5_MAX_BURST_LEN * AXI_DATA_WIDTH/8));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_restrict, env_t)
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT),.derive_force_indirect(1), .drop_force_lock_holder(0), .number_indirect_caps(1));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT),.derive_force_direct(1),   .drop_force_lock_holder(0));
    do_common_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT),.derive_force_indirect(1), .drop_force_lock_holder(1), .number_indirect_caps(1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_refuses_operations_for_task_id_bound_different_id_create,env_t)
    // different device
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device('0),.current_task(32'hdead));
    // different task
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device(32'hbeef),.current_task('0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_refuses_operations_for_task_id_bound_different_id_derive,env_t)
    // different device
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device('0),.current_task(32'hdead));
    // different task
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device(32'hbeef),.current_task('0));
    // same thing for indirect
    // different device
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE), .capability_type(NORTHCAPE_CMT_INDIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device('0),.current_task(32'hdead));
    // different task
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE), .capability_type(NORTHCAPE_CMT_INDIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device(32'hbeef),.current_task('0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_refuses_operations_for_task_id_bound_different_id_drop,env_t)
    // different device
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP), .capability_type(NORTHCAPE_CMT_INDIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device('0),.current_task(32'hdead));
    // different task
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP), .capability_type(NORTHCAPE_CMT_INDIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device(32'hbeef),.current_task('0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_refuses_operations_for_task_id_bound_different_id_merge,env_t)
    // different device
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device('0),.current_task(32'hdead));
    // different task
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device(32'hbeef),.current_task('0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_refuses_operations_for_task_id_bound_different_id_clone,env_t)
    // different device
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device('0),.current_task(32'hdead));
    // different task
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device(32'hbeef),.current_task('0));
    // same thing for indirect
    // different device
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE), .capability_type(NORTHCAPE_CMT_INDIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device('0),.current_task(32'hdead));
    // different task
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE), .capability_type(NORTHCAPE_CMT_INDIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device(32'hbeef),.current_task('0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_refuses_operations_for_task_id_bound_different_id_revoke,env_t)
    // different device
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device('0),.current_task(32'hdead));
    // different task
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device(32'hbeef),.current_task('0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_refuses_operations_for_task_id_bound_different_id_lock,env_t)
    // different device
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device('0),.current_task(32'hdead));
    // different task
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device(32'hbeef),.current_task('0));
    // same thing for indirect
    // different device
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK), .capability_type(NORTHCAPE_CMT_INDIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device('0),.current_task(32'hdead));
    // different task
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK), .capability_type(NORTHCAPE_CMT_INDIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device(32'hbeef),.current_task('0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_refuses_operations_for_task_id_bound_different_id_inspect,env_t)
    // different device
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device('0),.current_task(32'hdead));
    // different task
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device(32'hbeef),.current_task('0));
    // same thing for indirect
    // different device
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT), .capability_type(NORTHCAPE_CMT_INDIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device('0),.current_task(32'hdead));
    // different task
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT), .capability_type(NORTHCAPE_CMT_INDIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device(32'hbeef),.current_task('0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_refuses_operations_for_task_id_bound_different_id_restrict,env_t)
    // different device
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device('0),.current_task(32'hdead));
    // different task
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT), .capability_type(NORTHCAPE_CMT_DIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device(32'hbeef),.current_task('0));
    // same thing for indirect
    // different device
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT), .capability_type(NORTHCAPE_CMT_INDIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device('0),.current_task(32'hdead));
    // different task
    do_invalid_test(.operation(NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT), .capability_type(NORTHCAPE_CMT_INDIRECT),.input_restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND),.restriction_enabled(1),.input_task_id_restriction(32'hdead),.input_device_id_restriction(32'hbeef),.current_device(32'hbeef),.current_task('0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_ops_can_do_create_from_root_capability_with_all_cacheables, env_t)
    do_common_test(.cacheable_access_perm(1'b1), .cacheable_tlb_perm(1'b1));
    do_common_test(.cacheable_access_perm(1'b1), .cacheable_tlb_perm(1'b0));
    do_common_test(.cacheable_access_perm(1'b0), .cacheable_tlb_perm(1'b1));
    do_common_test(.cacheable_access_perm(1'b0), .cacheable_tlb_perm(1'b0));
  `NORTHCAPE_UVM_TEST_END

endpackage
