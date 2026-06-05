/**
  * Testbench module for Operations Module verification.
  */
module northcape_capability_ops_top;
  import northcape_capability_ops_transaction::*;
  import northcape_capability_ops_agent::NorthcapeCapabilityOpsAgentConfig;
  import northcape_generator::NorthcapeGenerator;
  import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
  import northcape_test::*;
  import northcape_types::*;
  import northcape_capability_ops_test_constants::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  logic clk_i;
  logic rst_ni;

  // clock period 20 ns = 50 MHz clock
  localparam half_clock_period_ns = 10;
  localparam clock_period_ns = 2 * half_clock_period_ns;

  localparam string COMPONENT_NAME = "Northcape Capability Ops Top";


  northcape_test_clock_generator #(
      .CLOCK_PERIOD_NS(clock_period_ns)
  ) clock_generator (
      .clk_i(clk_i)
  );


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
      axi_ops (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );

  Axi5Lite #(
      .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH)
  ) mmio (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  typedef virtual Axi5Lite #(
      .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH)
  ) axi_lite_interface_t;

  NorthcapeCMTInterface #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) cmt_interface (.clk_i(clk_i));

  NorthcapeRNGInterface #(
      .RNG_DATA_WIDTH(NORTHCAPE_CAPABILITY_OPS_RNG_INTERFACE_BITS)
  ) rng_intf (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  typedef virtual NorthcapeRNGInterface #(
      .RNG_DATA_WIDTH(NORTHCAPE_CAPABILITY_OPS_RNG_INTERFACE_BITS)
  ) rng_intf_t;

  logic test_complete_master;
  axi_test_request_result_t result_master;

  int cmt_size_clog2;
  bit [AXI_ADDR_WIDTH - 1 : 0] ops_cmt_base_addr;


  NorthcapeCapabilityCacheInterfaceOps ops_interface (.clk_i(clk_i));
  NorthcapeCapabilityCacheInterfaceResolver resolver_interface (.clk_i(clk_i));
  // not used here
  assign resolver_interface.request_valid = 1'b0;
  assign resolver_interface.request_capability_id = '0;
  assign resolver_interface.request_capability_tag = '0;
  assign resolver_interface.request_cache_flush = 1'b0;



  // queue of master test results
  typedef uvm_analysis_port#(Axi5MasterDriverResultTransaction#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )) master_analysis_port_t;

  master_analysis_port_t ops_analysis_port, cache_analysis_port;

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

  // queue of master test requests
  typedef INorthcapeAXITransactionMasterSide#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) mailbox_transaction_t;

  mailbox #(mailbox_transaction_t) requests_in_ops;
  mailbox #(mailbox_transaction_t) requests_in_cache;

  northcape_test_reset reset_intf (.clk_i(clk_i));
  assign rst_ni = reset_intf.resetn;

  initial begin
    ops_analysis_port = new("capability_ops_master_analysis_port", null);
    cache_analysis_port = new("capability_cache_master_analysis_port", null);

    requests_in_ops = new();
    requests_in_cache = new();
  end

  NorthcapeCurrentDeviceTaskInterface current_device_task_interface (.clk_i(clk_i));

  NorthcapeInterruptInterface #(
      .NUMBER_INTERRUPT_PINS(NORTHCAPE_CAPABILITY_OPS_NUM_IRQS)
  ) irq_interface (
      .clk_i(clk_i)
  );

  NorthcapeCapabilityOpsCsrIntf csr_interface (.clk_i(clk_i));


  northcape_capability_ops #(
      .HASH_TYPE(HASH_TYPE_IDENTITY),
      .HAS_CACHE_INTERFACE(HAS_CACHE_INTERFACE),

      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),

      // no consistent view on the memory - cannot check the counter
      .CAPABILITY_COUNTER_ACTIVE(1'b0),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2),
      .OPS_TAG_METHOD(OPS_TAG_METHOD),
      .BITMAP_BRAM_DATA_WIDTH(OPS_BRAM_DATA_WIDTH),
      .USE_TEST_ONLY_BRAM(1'b1),
      .PROVIDE_ERROR_CODES(1'b0)
  ) dut (
      .clk_i(clk_i),
      .rst_ni(rst_ni),

      .axi_master(axi_ops),
      .axi_slave(mmio),
      .cache_interface(ops_interface),

      .cmt_interface(cmt_interface),

      .rng_interface(rng_intf),

      .current_device_task_interface(current_device_task_interface),

      .irq_out(irq_interface),

      .memory_ready_i(1'b1),

      .csr_req_i(csr_interface.request),
      .csr_rsp_o(csr_interface.response),

      // debug unused
      .debug_state_o(),
      .debug_is_unlock_o(),
      .debug_input_capability_valid_o(),
      .debug_update_complete_o(),
      .debug_capabilities_valid_o(),
      .debug_is_revoke_o(),
      .debug_capability_token_o(),
      .debug_capability_operation_o(),
      .debug_top_state_o(),
      .zero_segment_debug_state_o(),
      .debug_zero_len_o(),
      .debug_top_state_isr_o()
  );

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

  axi5_master_driver #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH)
  ) ops_axi_driver (
      .requests_in(requests_in_ops),

      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .axi_master(axi_ops),

      .ap_i(ops_analysis_port)
  );

  axi5_master_driver #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH)
  ) cache_axi_driver (
      .requests_in(requests_in_cache),

      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .axi_master(axi_out),

      .ap_i(cache_analysis_port)
  );

  initial begin
    automatic uvm_queue #(transaction_t) transactions;
    automatic agent_config_t agent_config;

    if (HAS_CACHE_INTERFACE) begin
      // ops has an interface for writes, cache has a full interface
      agent_config = new(
          cmt_interface,
          INITIAL_CMT_BASE,
          INITIAL_CMT_SIZE_CLOG2,
          mmio,
          csr_interface,
          requests_in_ops,
          ops_analysis_port,
          requests_in_cache,
          cache_analysis_port,
          reset_intf,
          current_device_task_interface,
          irq_interface
      );
    end else begin
      // shared interface
      agent_config = new(
          cmt_interface,
          INITIAL_CMT_BASE,
          INITIAL_CMT_SIZE_CLOG2,
          mmio,
          csr_interface,
          requests_in_ops,
          ops_analysis_port,
          requests_in_ops,
          ops_analysis_port,
          reset_intf,
          current_device_task_interface,
          irq_interface
      );
    end

    transactions = new("transaction_queue");

    transactions.delete();

    uvm_config_db#(uvm_queue#(transaction_t))::set(null, "", CAPABILITY_OPS_TRANSACTION_QUEUE_NAME,
                                                   transactions);

    `uvm_info(COMPONENT_NAME, $sformatf(
              "Inserting Capability Ops Agent Config of type %s name %s into config DB!",
              $typename(
                  agent_config
              ),
              CAPABILITY_OPS_AGENT_CONFIG_NAME
              ), UVM_DEBUG);

    uvm_config_db#(agent_config_t)::set(null, "", CAPABILITY_OPS_AGENT_CONFIG_NAME, agent_config);

    uvm_config_db#(axi_lite_interface_t)::set(null, "", CAPABILITY_OPS_AXI_LITE_INTERFACE_NAME,
                                              mmio);

    uvm_config_db#(rng_intf_t)::set(null, "", CAPABILITY_OPS_RNG_INTERFACE_NAME, rng_intf);

  end
endmodule
