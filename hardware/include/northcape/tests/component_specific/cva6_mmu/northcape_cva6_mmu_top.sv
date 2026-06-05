
`include "uvm_macros.svh"

/**
  * Top-level module that has all of the wirings for testing the cva6 MMU.
  */
module northcape_cva6_mmu_top;
  import northcape_types::*;
  import northcape_test::*;
  import uvm_pkg::*;
  import uvm_test_discovery::test_northcape_discover_tests;
  import northcape_cva6_mmu_agent::NorthcapeCVA6MMUAgentConfig;
  import northcape_cva6_mmu_test_constants::*;
  import northcape_cva6_mmu_transaction::NorthcapeCVA6MMUTransaction;

  typedef virtual northcape_test_reset reset_intf_t;

  logic clk_i;
  logic rst_ni;


  Axis5 #(
      .AXIS_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_REQUEST_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH)
  )
      axis_validate_request_instr (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      axis_validate_request_data (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );
  Axis5 #(
      .AXIS_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_RESPONSE_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH)
  )
      axis_validate_response_instr (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      axis_validate_response_data (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );


  // CMT metadata from test / ops module
  NorthcapeCMTInterface #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) cmt_interface (.clk_i(clk_i));

  assign cmt_interface.reset_done = 1;

  // queue of validate requests
  mailbox #(INorthcapeCapabilityResolverTransaction)
      validate_requests_instr, validate_requests_data;

  initial begin
    validate_requests_instr = new;
    validate_requests_data  = new;
  end

  northcape_test_clock_generator #(.CLOCK_PERIOD_NS(10)) clock_generator (.clk_i(clk_i));

  typedef uvm_analysis_port#(AxisValidateResultTransaction) resolver_analysis_port_t;



  resolver_analysis_port_t instr_resolver_analysis_port;
  resolver_analysis_port_t data_resolver_analysis_port;

  initial begin
    instr_resolver_analysis_port = new("instr_resolver_analysis_port", null);
    data_resolver_analysis_port  = new("data_resolver_analysis_port", null);
  end

  NorthcapeCva6MMUInterface #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH))
      cva6_intf_instr (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      cva6_intf_data (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );

  wire [NORTHCAPE_TASK_ID_WIDTH-1:0] current_task_id_irq;
  wire [NORTHCAPE_TASK_ID_WIDTH-1:0] current_task_id_non_irq;
  logic is_subsystem_call;

  assign cva6_intf_instr.is_subsystem_call = is_subsystem_call;

  northcape_cva6_mmu #(
      .XLEN(AXI_ADDR_WIDTH),
      .IS_EXECUTE(1'b1),
      .DEVICE_ID(INSTR_CHAN_DEVICE_ID),
      .CAN_HANDLE_MISPREDICT(1'b1)
  ) i_instr_mmu (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .data_address_i(cva6_intf_instr.data_address),
      .data_is_store_i(cva6_intf_instr.data_is_store),
      .data_access_size_i(cva6_intf_instr.data_access_size),
      .data_is_immediate_i(cva6_intf_instr.data_is_immediate),
      .data_is_irq_i(cva6_intf_instr.data_is_irq),
      .data_is_atomic_i(cva6_intf_instr.data_is_atomic),
      .data_is_valid_i(cva6_intf_instr.data_is_valid),
      .data_is_branch_predict_i(cva6_intf_instr.data_is_branch_predict),
      .data_is_mispredict_i(cva6_intf_instr.data_is_mispredict),
      .data_is_correct_predict_i(cva6_intf_instr.data_is_correct_predict),
      .data_abort_i(1'b0),  // tested in cva6 integration test
      .task_id_overwrite_active_i(1'b0),
      .task_id_overwrite_i('0),
      // tested in cva6 integration test
      .northcape_cache_flush_i(1'b0),

      .translated_address_o(cva6_intf_instr.translated_address),
      .translation_error_o(cva6_intf_instr.translation_error),
      .translation_valid_o(cva6_intf_instr.translation_valid),
      .translation_immediate_o(cva6_intf_instr.translation_hit),
      .translation_requires_non_cacheable_o(cva6_intf_instr.translation_requires_non_cacheable),
      .translation_device_specific_restriction_o(cva6_intf_instr.translation_device_interpreted),
      .translation_is_subsystem_call_o(is_subsystem_call),
      .translation_is_subsystem_call_self_o(cva6_intf_instr.is_subsystem_call_self),
      .translation_cache_miss_event_o(  /* open */),
      .translation_cbo_misaligned_o(  /*open*/),


      .current_task_id_irq_i('0),
      .current_task_id_non_irq_i('0),
      .is_subsystem_call_i(1'b0),

      .current_task_id_irq_o(current_task_id_irq),
      .current_task_id_non_irq_o(current_task_id_non_irq),

      .axis_validate_request (axis_validate_request_instr.TRANSMITTER),
      .axis_validate_response(axis_validate_response_instr.RECEIVER),

      .final_error_o(  /*open*/),

      // aux interface - unused
      .aux_addr_i('0),
      .aux_expected_length_i('0),
      .aux_access_length_i('0),
      .aux_access_type_i(ACCESS_NONE),
      .aux_check_task_id_i('0),
      .aux_addr_valid_i(1'b0),

      .aux_translated_addr_o(),
      .aux_translated_addr_valid_o(),
      .aux_translated_addr_err_o(),


      .cmt_interface(cmt_interface),
      // debug ports - unused
      .dbg_cache_write_o(),
      .dbg_cache_write_phys_addr_o(),
      .dbg_cache_write_segment_length_o(),
      .dbg_state_o(),
      .dbg_cache_read_phys_addr_o(),
      .dbg_cache_read_segment_length_o()
  );

  assign cva6_intf_instr.task_id_irq = current_task_id_irq;
  assign cva6_intf_instr.task_id_non_irq = current_task_id_non_irq;

  northcape_cva6_mmu #(
      .XLEN(AXI_ADDR_WIDTH),
      .IS_EXECUTE(1'b0),
      .DEVICE_ID(DATA_CHAN_DEVICE_ID),
      .CAN_HANDLE_MISPREDICT(1'b1)
  ) i_data_mmu (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .data_address_i(cva6_intf_data.data_address),
      .data_is_store_i(cva6_intf_data.data_is_store),
      .data_access_size_i(cva6_intf_data.data_access_size),
      .data_is_immediate_i(cva6_intf_data.data_is_immediate),
      .data_is_irq_i(cva6_intf_data.data_is_irq),
      .data_is_atomic_i(cva6_intf_data.data_is_atomic),
      .data_is_valid_i(cva6_intf_data.data_is_valid),
      .data_is_branch_predict_i(cva6_intf_data.data_is_branch_predict),
      .data_is_mispredict_i(cva6_intf_data.data_is_mispredict),
      .data_abort_i(1'b0),  // tested in cva6 integration test
      .northcape_cache_flush_i(1'b0),  // tested in cva6 integration test
      .task_id_overwrite_active_i(1'b0),
      .task_id_overwrite_i('0),
      .data_is_correct_predict_i(cva6_intf_data.data_is_correct_predict),

      .translated_address_o(cva6_intf_data.translated_address),
      .translation_error_o(cva6_intf_data.translation_error),
      .translation_valid_o(cva6_intf_data.translation_valid),
      .translation_immediate_o(cva6_intf_data.translation_hit),
      .translation_requires_non_cacheable_o(cva6_intf_data.translation_requires_non_cacheable),
      .translation_device_specific_restriction_o(cva6_intf_data.translation_device_interpreted),
      .translation_is_subsystem_call_o(cva6_intf_data.is_subsystem_call),
      .translation_is_subsystem_call_self_o(cva6_intf_data.is_subsystem_call_self),
      .translation_cache_miss_event_o(  /* open */),
      .translation_cbo_misaligned_o(  /* open */),

      .current_task_id_irq_i(current_task_id_irq),
      .current_task_id_non_irq_i(current_task_id_non_irq),
      .is_subsystem_call_i(is_subsystem_call),
      .current_task_id_irq_o(  /* not needed */),
      .current_task_id_non_irq_o(  /* not needed */),

      .axis_validate_request (axis_validate_request_data.TRANSMITTER),
      .axis_validate_response(axis_validate_response_data.RECEIVER),

      .final_error_o(  /*open*/),
      // aux interface - unused
      .aux_addr_i('0),
      .aux_expected_length_i('0),
      .aux_access_length_i('0),
      .aux_access_type_i(ACCESS_NONE),
      .aux_check_task_id_i('0),
      .aux_addr_valid_i(1'b0),

      .aux_translated_addr_o(),
      .aux_translated_addr_valid_o(),
      .aux_translated_addr_err_o(),


      .cmt_interface(cmt_interface),
      // debug ports - unused
      .dbg_cache_write_o(),
      .dbg_cache_write_phys_addr_o(),
      .dbg_cache_write_segment_length_o(),
      .dbg_state_o(),
      .dbg_cache_read_phys_addr_o(),
      .dbg_cache_read_segment_length_o()
  );

  assign cva6_intf_data.task_id_irq = current_task_id_irq;
  assign cva6_intf_data.task_id_non_irq = current_task_id_non_irq;

  northcape_axis_validate_driver instr_resolver (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .requests_in(validate_requests_instr),

      .axis_validate_request (axis_validate_request_instr.RECEIVER),
      .axis_validate_response(axis_validate_response_instr.TRANSMITTER),

      .ap_i(instr_resolver_analysis_port)
  );

  northcape_axis_validate_driver data_resolver (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .requests_in(validate_requests_data),

      .axis_validate_request (axis_validate_request_data.RECEIVER),
      .axis_validate_response(axis_validate_response_data.TRANSMITTER),

      .ap_i(data_resolver_analysis_port)
  );

  typedef NorthcapeCVA6MMUAgentConfig#(
      .INSTR_CHAN_DEVICE_ID(INSTR_CHAN_DEVICE_ID),
      .DATA_CHAN_DEVICE_ID(DATA_CHAN_DEVICE_ID),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
  ) agent_config_t;

  northcape_test_reset reset_intf (.clk_i(clk_i));

  assign rst_ni = reset_intf.resetn;

  typedef NorthcapeCVA6MMUTransaction#(
      .DATA_CHAN_DEVICE_ID(DATA_CHAN_DEVICE_ID),
      .INSTR_CHAN_DEVICE_ID(INSTR_CHAN_DEVICE_ID),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
  ) transaction_t;

  initial begin
    automatic agent_config_t agent_config;
    automatic uvm_queue #(transaction_t) transactions;

    agent_config = new(
        cva6_intf_instr.CVA6,
        cva6_intf_data.CVA6,
        validate_requests_instr,
        validate_requests_data,
        cmt_interface,
        instr_resolver_analysis_port,
        data_resolver_analysis_port
    );
    uvm_config_db#(agent_config_t)::set(null, "", CVA6_MMU_AGENT_CONFIG_NAME, agent_config);

    uvm_config_db#(reset_intf_t)::set(null, "", CVA6_MMU_RESET_INTERFACE_NAME, reset_intf);

    transactions = new("transaction_queue");

    transactions.delete();

    uvm_config_db#(uvm_queue#(transaction_t))::set(null, "", CVA6_MMU_TRANSACTION_QUEUE_NAME,
                                                   transactions);
  end

endmodule
