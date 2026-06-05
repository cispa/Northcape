`include "uvm_macros.svh"

/**
  * Top-level module that has all of the wirings for testing the capability resolver.
  */
module northcape_capability_resolver_top;
  import uvm_pkg::*;
  import northcape_capability_resolver_test_constants::*;
  import northcape_capability_resolver_transaction::*;
  import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
  import northcape_test::*;
  import northcape_types::*;
  import axi5::*;
  import northcape_capability_resolver_agent::NorthcapeCapabilityResolverAgentConfig;

  `include "axis5_assign.svh"

  logic clk_i;
  logic rst_ni;

  // clock period 10 ns = 100 MHz clock
  localparam half_clock_period_ns = 5;
  localparam clock_period_ns = 2 * half_clock_period_ns;

  northcape_test_clock_generator #(
      .CLOCK_PERIOD_NS(clock_period_ns)
  ) clock_generator (
      .clk_i(clk_i)
  );

  Axis5Test #(
      .AXIS_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_REQUEST_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH)
  ) axis_validate_request_driver (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );
  Axis5 #(
      .AXIS_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_REQUEST_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH)
  )
      axis_validate_request (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      axis_validate_request_in (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      axis_validate_request_recursion (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );

  `AXIS5_ASSIGN(assign, axis_validate_request_in, =, axis_validate_request_driver);

  Axis5 #(
      .AXIS_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_RESPONSE_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH)
  ) axis_validate_response (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  Axis5Test #(
      .AXIS_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_RESPONSE_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH)
  ) axis_validate_response_driver (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  `AXIS5_ASSIGN(assign, axis_validate_response_driver, =, axis_validate_response);

  Axi5 #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )
      axi_out (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      axi_dummy (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );


  NorthcapeCMTInterface #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) cmt_interface (.clk_i(clk_i));

  assign cmt_interface.reset_done = 1;

  int cmt_size_clog2;
  bit [AXI_ADDR_WIDTH - 1 : 0] resolver_cmt_base_addr;

  // queue of master test results
  typedef uvm_analysis_port#(Axi5MasterDriverResultTransaction#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )) master_analysis_port_t;
  master_analysis_port_t master_analysis_port;

  typedef INorthcapeAXITransactionMasterSide#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) mailbox_transaction_t;
  mailbox #(mailbox_transaction_t) requests_in_master;

  initial begin
    master_analysis_port = new("capability_resolver_master_analysis_port", null);

    requests_in_master   = new();

    uvm_config_db#(master_analysis_port_t)::set(null, "", "capability_resolver_analysis_port",
                                                master_analysis_port);
  end

  NorthcapeCapabilityCacheInterfaceResolver resolver_interface (.clk_i(clk_i));
  NorthcapeCapabilityCacheInterfaceOps ops_interface (.clk_i(clk_i));

  // not used in this scenario
  assign ops_interface.request_valid = 1'b0;
  assign ops_interface.request_capability_id = '0;
  assign ops_interface.request_capability_tag = '0;
  assign ops_interface.is_write = 1'b0;
  assign ops_interface.write_request_capability = '0;
  assign ops_interface.write_request_flush = 1'b0;
  assign ops_interface.request_is_uncacheable = 1'b0;

  northcape_capability_cache #(
      .HASH_TYPE(northcape_capability_resolver_common::HASH_TYPE_IDENTITY),
      // important for checking AXI transactions
      .CACHE_TYPE(northcape_capability_cache_common::NORTHCAPE_CAPABILITY_TYPE_COMMON_NO_CACHE),
      .SUPPORT_SPECULATIVE_RESOLVER_LOADS(SUPPORT_SPECULATIVE_RESOLVER_LOADS),
      .KEEP_TOP_CMT_ENTRIES_ONLY(KEEP_TOP_CMT_ENTRIES_ONLY),
      .STORE_BUFFER_SIZE(CACHE_STORE_BUFFER_SIZE),

      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) i_capability_cache (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .axi_master(axi_out),

      .resolver_port(resolver_interface),
      .ops_port(ops_interface),
      .cmt_interface(cmt_interface),
      .resolver_port_miss_o(  /* not checked */),
      .ops_port_miss_o(  /* not checked */),
      .missunit_stall_o(  /* not checked */),
      .ops_write_stall_o(  /* not checked */),
      .resolver_spec_fail_o(  /* not checked */)
  );

  Axis5Mux #(
      .NUMBER_IN_PORTS (2),
      .ARBITRATION_TYPE(axis5_mux::ARBITRATION_RR)
  ) i_mux (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .in_ports({axis_validate_request_in, axis_validate_request_recursion}),
      .out_port(axis_validate_request)
  );

  northcape_capability_resolver #(
      .HASH_TYPE(HASH_TYPE_IDENTITY),
      .HAS_CACHE_INTERFACE(HAS_CACHE_INTERFACE),

      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .FIFO_DEPTH_CLOG_2(FIFO_DEPTH_CLOG_2),
      .MAX_AXI_TRANSACTIONS(MAX_AXI_TRANSACTIONS),
      .CAPABILITY_RESOLVER_RECURSION_DEVICE_ID(CAPABILITY_RESOLVER_RECURSION_DEVICE_ID),

      .INPUT_PIPELINE_STAGE_ENABLED (INPUT_PIPELINE_STAGE_ENABLED),
      .PARSER_PIPELINE_STAGE_ENABLED(PARSER_PIPELINE_STAGE_ENABLED),
      .OUTPUT_PIPELINE_STAGE_ENABLED(OUTPUT_PIPELINE_STAGE_ENABLED)
  ) dut (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .validate_request(axis_validate_request),
      .axi_master(axi_dummy),
      .cache_interface(resolver_interface),
      .validate_response(axis_validate_response),
      .validate_request_recursion(axis_validate_request_recursion),

      .cmt_interface(cmt_interface)
  );

  axi5_master_driver #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH)
  ) memory_simulator (
      .requests_in(requests_in_master),

      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .axi_master(axi_out),


      .ap_i(master_analysis_port)
  );

  northcape_test_reset reset_intf (.clk_i(clk_i));

  assign rst_ni = reset_intf.resetn;

  typedef NorthcapeCapabilityResolverTransaction#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXIS_REQUEST_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH),
      .AXIS_REQUEST_TID_WIDTH  (AXIS_VALIDATE_REQUEST_TID_WIDTH),
      .AXIS_REQUEST_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
      .AXIS_REQUEST_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH),

      .AXIS_RESPONSE_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH),
      .AXIS_RESPONSE_TID_WIDTH  (AXIS_VALIDATE_RESPONSE_TID_WIDTH),
      .AXIS_RESPONSE_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH),
      .AXIS_RESPONSE_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH)
  ) transaction_t;

  initial begin
    automatic uvm_queue #(transaction_t) transactions;
    automatic agent_config_t agent_config;

    agent_config = new(
        cmt_interface,
        axis_validate_request_driver,
        axis_validate_response_driver,
        requests_in_master,
        master_analysis_port
    );


    uvm_config_db#(virtual northcape_test_reset)::set(
        null, "", CAPABILITY_RESOLVER_RESET_INTERFACE_NAME, reset_intf);

    transactions = new("transaction_queue");

    transactions.delete();

    uvm_config_db#(uvm_queue#(transaction_t))::set(
        null, "", CAPABILITY_RESOLVER_TRANSACTION_QUEUE_NAME, transactions);

    uvm_config_db#(agent_config_t)::set(null, "", CAPABILITY_RESOLVER_AGENT_CONFIG_NAME,
                                        agent_config);

  end


endmodule
