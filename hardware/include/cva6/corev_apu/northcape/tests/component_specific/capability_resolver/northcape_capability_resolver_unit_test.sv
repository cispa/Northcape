/**
  * Testbench for directed and regression testing of the capability resolver component.
  */
package northcape_capability_resolver_unit_test;

  import northcape_capability_resolver_test_constants::*;
  import northcape_capability_resolver_transaction::*;
  import northcape_capability_resolver_agent::*;
  import northcape_generator::NorthcapeGenerator;
  import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
  import northcape_test::*;
  import northcape_types::*;
  import axi5::*;
  import northcape_generic_env::*;
  import northcape_capability_resolver_common::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "northcape_uvm_test_wrapper.svh"

  northcape_cmt_entry_t test_entry;

  typedef NorthcapeCapabilityResolverTransaction#(
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),

    .AXIS_REQUEST_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH),
    .AXIS_REQUEST_TID_WIDTH(AXIS_VALIDATE_REQUEST_TID_WIDTH),
    .AXIS_REQUEST_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
    .AXIS_REQUEST_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH),

    .AXIS_RESPONSE_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH),
    .AXIS_RESPONSE_TID_WIDTH(AXIS_VALIDATE_RESPONSE_TID_WIDTH),
    .AXIS_RESPONSE_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH),
    .AXIS_RESPONSE_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH)
  ) transaction_t;

  typedef NorthcapeCapabilityResolverAgent#(
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),

    .AXIS_REQUEST_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH),
    .AXIS_REQUEST_TID_WIDTH(AXIS_VALIDATE_REQUEST_TID_WIDTH),
    .AXIS_REQUEST_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
    .AXIS_REQUEST_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH),

    .AXIS_RESPONSE_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH),
    .AXIS_RESPONSE_TID_WIDTH(AXIS_VALIDATE_RESPONSE_TID_WIDTH),
    .AXIS_RESPONSE_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH),
    .AXIS_RESPONSE_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH),

    .TRANSACTIONS_QUEUE_NAME_AGENT(CAPABILITY_RESOLVER_TRANSACTION_QUEUE_NAME)
  ) agent_t;

  typedef NorthcapeGenericEnv#(
    .AGENT_TYPE(agent_t),
    .RESET_INTERFACE_NAME(CAPABILITY_RESOLVER_RESET_INTERFACE_NAME)
  ) env_t;

  typedef NorthcapeCapabilityResolverHash#(.HASH_TYPE(HASH_TYPE_IDENTITY)) hash_t;

  localparam COMPONENT_NAME = "Northcape Capability Resolver Unit Test";

  
  typedef NorthcapeGenerator#(transaction_t) generator_t;

  localparam cmt_base_addr_default = 64'h0000000080000000;
  localparam request_task_id_default = 32'h0;
  localparam request_device_id_default = 16'h0;
  localparam capability_token_default = 64'h00000000deadbeef;
  localparam capability_token_default_non_root = 64'h12345678deadbeef;
  axi_size_t access_size_default = 3; // 8 bytes
  axi_len_t access_len_default = 0; // 1 word
  northcape_lock_key_t lock_key_default_unlocked = 64'h0000000000000000;
  northcape_lock_key_t lock_key_default_locked = 64'h000000000000dead;
  axis_validate_request_perm_t access_type_default = READ;

  function automatic void do_directed_test(
    northcape_capability_resolver_transaction_type_t test_type,
    bit [AXI_ADDR_WIDTH - 1 : 0]  cmt_base_addr=cmt_base_addr_default,
    task_id_t request_task_id = request_task_id_default,
    device_id_t request_device_id = request_device_id_default,
    bit [AXI_ADDR_WIDTH -1 : 0] capability_token = capability_token_default,
    axi_size_t access_size = access_size_default,
    axi_len_t access_len = access_len_default,
    northcape_lock_key_t lock_key = lock_key_default_unlocked,
    axis_validate_request_perm_t access_type = access_type_default,
    int unsigned number_indirect_caps = 3,
    northcape_restriction_type_t restriction_type = NORTHCAPE_RESTRICTIONS_NONE,
    bit modify_task_type_id=1'b0
  );
    transaction_t directed_test;
    uvm_queue#(transaction_t) queue;

    directed_test = generator_t::generate_transaction_ephemeral();
    directed_test.test_type = test_type;
    directed_test.cmt_base_addr = cmt_base_addr;
    directed_test.request_task_id = request_task_id;
    directed_test.request_device_id = request_device_id;
    directed_test.capability_tokens[0] = capability_token;
    directed_test.access_size = access_size;
    directed_test.access_len = access_len;
    directed_test.lock_key = lock_key;
    directed_test.access_type = access_type;
    directed_test.number_indirect_caps = number_indirect_caps;
    directed_test.restriction_type = restriction_type;

    directed_test.post_randomize();

    if(modify_task_type_id == 1'b1)
    begin
      directed_test.entries[0].task_id_provided += 1;
      directed_test.test_type = NORTHCAPE_CAPABILITY_RESOLVER_TEST_VALIDATION_ERROR;
    end

    assert(uvm_config_db#(uvm_queue#(transaction_t))::get(null,"",CAPABILITY_RESOLVER_TRANSACTION_QUEUE_NAME,queue));

    `uvm_info(COMPONENT_NAME,"I have pushed a directed test!",UVM_DEBUG);
    
    queue.push_back(directed_test);

  endfunction
  
  // 256 bit limit crucial - marks limit of BOTH the AXI bus and the MAC
  `NORTHCAPE_UVM_TEST(capability_resolver_cmt_entry_fits_in_256_bits,NorthcapeDummyEnv)
    $display("Size of capability metadata location: %d", $bits(northcape_cmt_location_t));
    $display("Size of capability metadata entry: %d", $bits(northcape_cmt_entry_t));

    if($bits(northcape_cmt_entry_t) > 256)
    begin
      `uvm_error(COMPONENT_NAME,$sformatf("CMT entry too large: %d bits!",$bits(northcape_cmt_entry_t)));
    end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_cmt_entries_can_be_generated,NorthcapeDummyEnv)
  begin
    // this fatals when unsuccessful
    automatic transaction_t transaction = generator_t::generate_transaction_singleton();

    if(transaction == null)
    begin
      `uvm_error(COMPONENT_NAME,"Could not create transaction");
    end
  end
  `NORTHCAPE_UVM_TEST_END

  // these tests are used primarily to aid in debugging
  `NORTHCAPE_UVM_TEST(capability_resolver_cmt_entries_can_be_parsed,NorthcapeDummyEnv)
    begin
        automatic bit[$bits(northcape_cmt_entry_t)-1:0] raw_entry;
        automatic northcape_cmt_entry_t parsed_entry;

        if(!$value$plusargs ("NORTHCAPE_PARSE_CMT=%x", raw_entry))
        begin
          raw_entry = 256'h4840000000000008000000000000000000000800000000000000230aa31f8020;
        end

        `uvm_info(COMPONENT_NAME,$sformatf("Parsing CMT raw entry %x",raw_entry),UVM_MEDIUM);

        parsed_entry = raw_entry;

        `uvm_info(COMPONENT_NAME,$sformatf("Entry is %s",print_cmt_entry(parsed_entry)),UVM_MEDIUM);
    end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_hashes_can_be_computed,NorthcapeDummyEnv)
    begin
        bit [AXI_ADDR_WIDTH-1:0] addr_to_parse, final_addr;
        capability_id_t parsed_id, hashed_id;
        // FPGA constant
        int unsigned cmt_size_clog2 = 10;

        addr_to_parse = 64'h1068400000000000;

        parsed_id = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(addr_to_parse);

        hashed_id = hash_t::compute_hash(parsed_id, cmt_size_clog2);

        final_addr = hashed_id * $bits(northcape_cmt_entry_t) / 8;

        `uvm_info(COMPONENT_NAME,$sformatf("Parsed capability ID is %d hashed ID is %d final addr is %x",parsed_id, hashed_id, final_addr),UVM_MEDIUM);
    end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_addrs_can_be_computed,NorthcapeDummyEnv)
    begin
        bit [AXI_ADDR_WIDTH-1:0] final_addr;
        capability_id_t parsed_id, hashed_id;
        // FPGA constant
        int unsigned cmt_size_clog2 = 10;

        parsed_id = '0;

        hashed_id = hash_t::compute_hash(parsed_id, cmt_size_clog2);

        final_addr = hashed_id * $bits(northcape_cmt_entry_t) / 8;

        `uvm_info(COMPONENT_NAME,$sformatf("Parsed capability ID is %d hashed ID is %d final addr is %x",parsed_id, hashed_id, final_addr),UVM_MEDIUM);
    end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_can_handle_root_capability,env_t)
    do_directed_test(NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_ROOT_CAPABILITY);
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_can_handle_root_capability_for_non_zero_device,env_t)
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_ROOT_CAPABILITY),.request_task_id(32'h1),.request_device_id(32'h2));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_can_handle_direct_capability_for_non_zero_device,env_t)
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_DIRECT_CAPABILITY),.request_task_id(32'h1),.request_device_id(32'h2),.capability_token(capability_token_default_non_root));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_can_handle_indirect_capability_for_non_zero_device,env_t)
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_INDIRECT_CAPABILITY),.request_task_id(32'h1),.request_device_id(32'h2),.capability_token(capability_token_default_non_root));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_can_handle_lock_holder_capability_for_non_zero_device,env_t)
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_OK),.request_task_id(32'h1),.request_device_id(32'h2),.capability_token(capability_token_default_non_root),.lock_key(64'd1234567890));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_can_handle_invalid_entry,env_t)
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_INVALID_ENTRY));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_can_handle_locked_fail,env_t)
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_FAIL),.lock_key(64'hdead));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_can_handle_bus_error,env_t)
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_BUS_ERROR));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_can_handle_permission_error,env_t)
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_VALIDATION_ERROR),.restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_refuses_read_on_set_task_id_with_different_identity,env_t)
    // test type will be overwritten to error
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_DIRECT_CAPABILITY), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .modify_task_type_id(1'b1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_can_handle_multiple_indirect_capabilities,env_t)
  begin
    for(int i = 0; i < 16; i++)
    begin
      do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_INDIRECT_CAPABILITY),.request_task_id(32'h1),.request_device_id(32'h2),.capability_token(capability_token_default_non_root));
    end
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_fails_on_parent_out_of_bounds,env_t)
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_FRONT));
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_BACK));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_fails_on_parent_out_of_bounds_locked,env_t)
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_FRONT));
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_BACK));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_can_do_multi_locking,env_t)
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_CHILD));
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE));
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE_CHILD));
  `NORTHCAPE_UVM_TEST_END

  /* regression test */
  `NORTHCAPE_UVM_TEST(capability_resolver_can_do_multi_locking_1_indirect,env_t)
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_CHILD), .number_indirect_caps(1));
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE), .number_indirect_caps(1));
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE_CHILD), .number_indirect_caps(1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(capability_resolver_fails_on_revocation_entry,env_t)
    do_directed_test(.test_type(NORTHCAPE_CAPABILITY_RESOLVER_TEST_REVOCATION_CAPABILITY));
  `NORTHCAPE_UVM_TEST_END

endpackage
