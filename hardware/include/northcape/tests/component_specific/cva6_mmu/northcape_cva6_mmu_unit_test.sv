/**
  * Testbench for directed and regression testing of the capability ops component.
  */
package northcape_cva6_mmu_unit_test;

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

  localparam logic [31:0] CMT_BASE = 32'h80000000;


  function automatic void do_common_test(
    bit valid_test,
    bit is_execute,
    // input parameters to the CVA6 MMU
    logic [AXI_ADDR_WIDTH-1:0] data_address,
    logic data_is_store = 1'b0,
    bit  data_is_atomic = 1'b0,
    logic [$clog2(AXI_ADDR_WIDTH/8)-1:0] data_access_size = 3'b11,
    logic data_is_immediate = 1'b0,
    logic data_is_irq = 1'b0,

    // for response generation
    segment_base_addr_t segment_base = '0,
    segment_length_t segment_length = 32'hffffffff,

    // bounds of capability metadata table
    northcape_physical_address_t cmt_base_addr = CMT_BASE,
    int unsigned cmt_size_clog2 = 12,


    // for restrictions
    // will be adapted by agent to global state if needed
    northcape_restriction_body_t restriction_body = '0,
    northcape_restriction_type_t restriction_type = NORTHCAPE_RESTRICTIONS_NONE,

    bit is_cacheable_data = 1'b1,
    bit is_branch_predict = 1'b0,
    bit is_mispredict = 1'b0,
    int predict_cycles = 0
  );
    transaction_t transaction;
    uvm_queue #(transaction_t) transactions;

    if(uvm_config_db#(uvm_queue#(transaction_t))::get(null,"",CVA6_MMU_TRANSACTION_QUEUE_NAME,transactions) == 0)
    begin
      `uvm_fatal(COMPONENT_NAME,"Could not get transactions queue!");
    end

    transaction = new;

    transaction.valid_test = valid_test;
    transaction.is_execute = is_execute;
    transaction.data_is_atomic = data_is_atomic;
    transaction.data_address = data_address;
    transaction.capability_offset = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(data_address);
    transaction.data_is_store = data_is_store;
    transaction.data_access_size = data_access_size;
    transaction.data_is_immediate = data_is_immediate;
    transaction.data_is_irq = data_is_irq;
    transaction.segment_base = segment_base;
    transaction.segment_length = segment_length;
    transaction.cmt_base_addr = cmt_base_addr;
    transaction.cmt_size_clog2 = cmt_size_clog2;

    transaction.restriction_body = restriction_body;
    transaction.restriction_type = restriction_type;

    transaction.is_cacheable_data = is_cacheable_data;
    transaction.branch_predict = is_branch_predict;
    transaction.branch_mispredict = is_mispredict;
    transaction.predict_cycles = predict_cycles;

    transaction.post_randomize();


    transactions.push_back(transaction);
  endfunction

  `NORTHCAPE_UVM_TEST(cva6_mmu_can_translate_root_cap, env_t)
    // read
    do_common_test(1'b1, 1'b0, 64'h100);
    // execute
    do_common_test(1'b1, 1'b1, 64'h104);
    // store
    do_common_test(1'b1, 1'b0, 64'h108, .data_is_store(1'b1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(cva6_mmu_can_translate_simple_cap, env_t)
    // read
    do_common_test(1'b1, 1'b0, 64'h100, .segment_base(32'h1000), .segment_length(32'h108));
    // execute
    do_common_test(1'b1, 1'b1, 64'h100, .segment_base(32'h1000), .segment_length(32'h108));
    // store
    do_common_test(1'b1, 1'b0, 64'h108, .data_is_store(1'b1), .segment_base(32'h1000), .segment_length(32'h116));
  `NORTHCAPE_UVM_TEST_END


  `NORTHCAPE_UVM_TEST(cva6_mmu_can_translate_simple_cap_non_cacheable, env_t)
    // read
    do_common_test(1'b1, 1'b0, 64'h100, .segment_base(32'h1000), .segment_length(32'h108), .is_cacheable_data(1'b0));
    // execute
    do_common_test(1'b1, 1'b1, 64'h100, .segment_base(32'h1000), .segment_length(32'h108), .is_cacheable_data(1'b0));
    // store
    do_common_test(1'b1, 1'b0, 64'h108, .data_is_store(1'b1), .segment_base(32'h1000), .segment_length(32'h116), .is_cacheable_data(1'b0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(cva6_mmu_can_detect_offset_overflow, env_t)
    // read
    do_common_test(1'b0, 1'b0, 64'h100, .segment_base(32'h1000), .segment_length(32'h100));
    // execute
    do_common_test(1'b0, 1'b1, 64'h100, .segment_base(32'h1000), .segment_length(32'h100));
    // store
    do_common_test(1'b0, 1'b0, 64'h108, .data_is_store(1'b1), .segment_base(32'h1000), .segment_length(32'h108));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(cva6_mmu_can_detect_length_overflow, env_t)
    // read
    do_common_test(1'b0, 1'b0, 64'd100, .segment_base(32'h1000), .segment_length(32'd107));
    // execute
    do_common_test(1'b0, 1'b1, 64'd100, .segment_base(32'h1000), .segment_length(32'd107));
    // store
    do_common_test(1'b0, 1'b0, 64'd108, .data_is_store(1'b1), .segment_base(32'h1000), .segment_length(32'd115));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(cva6_mmu_can_handle_zero_length, env_t)
    // read
    do_common_test(1'b0, 1'b0, 64'd100, .segment_length(32'h0));
    // execute
    do_common_test(1'b0, 1'b1, 64'd100, .segment_length(32'h0));
    // store
    do_common_test(1'b0, 1'b0, 64'd108, .data_is_store(1'b1), .segment_base(32'h1000), .segment_length(32'h0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(cva6_mmu_refuses_subsystem_call_for_non_zero_byte, env_t)
  begin
    northcape_restriction_body_t restr_body;
    restr_body.task_restriction.task_id = 32'hdead;
    restr_body.task_restriction.device_id = INSTR_CHAN_DEVICE_ID>>1;

    do_common_test(1'b0, 1'b1, 64'h8, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID));
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(cva6_mmu_can_do_subsystem_calls, env_t)
  begin
    northcape_restriction_body_t restr_body;
    restr_body.task_restriction.task_id = 32'hdead;
    restr_body.task_restriction.device_id = INSTR_CHAN_DEVICE_ID>>1;

    // subsystem call
    do_common_test(1'b1, 1'b1, 64'h0, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID));
    // X
    do_common_test(1'b1, 1'b1, 64'h8, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID));
    // R
    do_common_test(1'b1, 1'b0, 64'h8, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID));
    // W
    do_common_test(1'b1, 1'b0, 64'h8, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .data_is_store(1'b1));
  end
  `NORTHCAPE_UVM_TEST_END
  

  `NORTHCAPE_UVM_TEST(cva6_mmu_can_do_subsystem_calls_in_irq, env_t)
  begin
    northcape_restriction_body_t restr_body;
    restr_body.task_restriction.task_id = 32'hdead;
    restr_body.task_restriction.device_id = INSTR_CHAN_DEVICE_ID>>1;

    // subsystem call
    do_common_test(1'b1, 1'b1, 64'h0, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID));
    // X
    do_common_test(1'b1, 1'b1, 64'h8, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID));

    restr_body.task_restriction.task_id++;
    
    // subsystem call in IRQ mode
    do_common_test(1'b1, 1'b1, 64'h0, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .data_is_irq(1'b1));
    // X
    do_common_test(1'b1, 1'b1, 64'h8, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID),  .data_is_irq(1'b1));
    // R
    do_common_test(1'b1, 1'b0, 64'h8, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .data_is_irq(1'b1));
    // W
    do_common_test(1'b1, 1'b0, 64'h8, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .data_is_irq(1'b1), .data_is_store(1'b1));

    restr_body.task_restriction.task_id--;

    // again in non-IRQ context
    // R
    do_common_test(1'b1, 1'b0, 64'h8, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID));
    // W
    do_common_test(1'b1, 1'b0, 64'h8, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .data_is_store(1'b1));
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(cva6_mmu_can_convey_device_specific_restriction, env_t)
  begin
    northcape_restriction_body_t restr_body;
    restr_body.device_interpreted_bits = 64'hfeedbeefdeadbeef;
    // X
    do_common_test(1'b1, 1'b1, 64'h8, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED));
    // R
    do_common_test(1'b1, 1'b0, 64'h8, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED));
    // W
    do_common_test(1'b1, 1'b0, 64'h8, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED), .data_is_store(1'b1));
  end
  `NORTHCAPE_UVM_TEST_END


  `NORTHCAPE_UVM_TEST(cva6_mmu_can_do_subsystem_calls_with_predict_mispredict, env_t)
  begin
    northcape_restriction_body_t restr_body;
    restr_body.task_restriction.task_id = 32'hdead;
    restr_body.task_restriction.device_id = INSTR_CHAN_DEVICE_ID>>1;

    // subsystem call
    do_common_test(1'b1, 1'b1, 64'h0, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .is_branch_predict(1'b1), .is_mispredict(1'b0), .predict_cycles(10));
    // X - check that task ID changed
    do_common_test(1'b1, 1'b1, 64'h8, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND));
    restr_body.task_restriction.task_id++;
    // fail - should not change task id
    do_common_test(1'b1, 1'b1, 64'h0, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .is_branch_predict(1'b1), .is_mispredict(1'b1), .predict_cycles(10));
    restr_body.task_restriction.task_id--;
    // x - should use old task ID
    do_common_test(1'b1, 1'b1, 64'h8, .segment_length(32'h100), .restriction_body(restr_body), .restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND));
  end
  `NORTHCAPE_UVM_TEST_END


endpackage
