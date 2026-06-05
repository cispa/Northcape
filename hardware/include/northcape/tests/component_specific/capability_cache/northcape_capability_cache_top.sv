/**
  * Top level test for capability cache: connects cache against a simulated memory.
  */
module northcape_capability_cache_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import northcape_types::*;
  import northcape_capability_cache_test_constants::*;
  import northcape_capability_cache_transaction::NorthcapeCapabilityCacheTransaction;

  logic clk_i;
  logic rst_ni;

  // clock period 10 ns = 100 MHz clock
  localparam half_clock_period_ns = 5;
  localparam clock_period_ns = 2 * half_clock_period_ns;

  localparam string COMPONENT_NAME = "Northcape Capability Cache Top";

  typedef northcape_cmt_entry_t mem_content_t[$];
  typedef logic [AXI_ADDR_WIDTH-1:0] mem_index_t;

  typedef NorthcapeCapabilityCacheTransaction transaction_t;

  typedef NorthcapeSparseMem#(
      .QUEUE_TYPE(mem_content_t),
      .DATA_TYPE(northcape_cmt_entry_t),
      .INDEX_TYPE(mem_index_t),
      .AXI_DATA_WIDTH($bits(northcape_cmt_entry_t)),
      .ZERO_IF_NOT_EXISTS(1'b1)
  ) sparse_mem_t;

  sparse_mem_t sparse_mem;

  northcape_test_reset reset_intf (.clk_i(clk_i));
  assign rst_ni = reset_intf.resetn;

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
  ) axi_master (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  NorthcapeCapabilityCacheInterfaceResolverTest resolver_interface_test (.clk_i(clk_i));
  NorthcapeCapabilityCacheInterfaceResolver resolver_interface (.clk_i(clk_i));
  NorthcapeCapabilityCacheInterfaceOpsTest ops_interface_test (.clk_i(clk_i));
  NorthcapeCapabilityCacheInterfaceOps ops_interface (.clk_i(clk_i));

  // mapping between test and synthesizable interfaces
  assign resolver_interface.request_valid = resolver_interface_test.request_valid;
  assign resolver_interface.request_capability_id = resolver_interface_test.request_capability_id;
  assign resolver_interface.request_capability_tag = resolver_interface_test.request_capability_tag;
  assign resolver_interface.request_is_recursion = resolver_interface_test.request_is_recursion;
  assign resolver_interface.response_ready = resolver_interface_test.response_ready;
  assign resolver_interface.request_cache_flush = resolver_interface_test.request_cache_flush;
  assign resolver_interface.request_close_speculation_window = resolver_interface_test.request_close_speculation_window;
  assign resolver_interface_test.response_valid = resolver_interface.response_valid;
  assign resolver_interface_test.response_err = resolver_interface.response_err;
  assign resolver_interface_test.response_cmt_entry = resolver_interface.response_cmt_entry;

  assign ops_interface.request_valid = ops_interface_test.request_valid;
  assign ops_interface.request_capability_id = ops_interface_test.request_capability_id;
  assign ops_interface.request_capability_tag = ops_interface_test.request_capability_tag;
  assign ops_interface.is_write = ops_interface_test.is_write;
  assign ops_interface.write_request_capability = ops_interface_test.write_request_capability;
  assign ops_interface.write_request_flush = ops_interface_test.write_request_flush;
  assign ops_interface.request_is_uncacheable = ops_interface_test.request_is_uncacheable;
  assign ops_interface_test.response_valid = ops_interface.response_valid;
  assign ops_interface_test.response_err = ops_interface.response_err;
  assign ops_interface_test.response_cmt_entry = ops_interface.response_cmt_entry;

  NorthcapeCMTInterface #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) cmt_interface (.clk_i(clk_i));

  assign cmt_interface.table_size_clog2 = INITIAL_CMT_SIZE_CLOG2;
  assign cmt_interface.cmt_base = INITIAL_CMT_BASE;
  assign cmt_interface.reset_done = 1'b0;
  assign cmt_interface.need_flush_data_caches = 1'b0;  // ignored
  assign cmt_interface.wrote_any_capability = 1'b0;
  assign cmt_interface.written_capability = '0;

  axi5_mem_adapter #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .MEM_TYPE(sparse_mem_t)
  ) ops_mem_adapter (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .ignore_write_i(1'b0),

      .axi_slave(axi_master),
      .memory_i (sparse_mem)
  );


  northcape_capability_cache #(
      .HASH_TYPE(northcape_capability_resolver_common::HASH_TYPE_IDENTITY),
      .CACHE_TYPE(northcape_capability_cache_common::NORTHCAPE_CAPABILITY_TYPE_WT_N_ASSOC_BRAM),
      .ASSOCIATIVITY(CACHE_ASSOCIATIVITY),
      .NUM_ENTRIES(NUM_ENTRIES),
      .STORE_BUFFER_SIZE(CACHE_STORE_BUFFER_SIZE),
      .SUPPORT_SPECULATIVE_RESOLVER_LOADS(SUPPORT_SPECULATIVE_RESOLVER_LOADS),
      .KEEP_TOP_CMT_ENTRIES_ONLY(KEEP_TOP_CMT_ENTRIES_ONLY),

      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) i_capability_cache (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .axi_master(axi_master),

      .resolver_port(resolver_interface),
      .ops_port(ops_interface),
      .cmt_interface(cmt_interface),
      .resolver_port_miss_o(  /* not checked */),
      .ops_port_miss_o(  /* not checked */),
      .missunit_stall_o(  /* not checked */),
      .ops_write_stall_o(  /* not checked */),
      .resolver_spec_fail_o(  /* not checked */)
  );


  initial begin
    automatic uvm_queue #(transaction_t) transactions;
    automatic agent_config_t agent_config;

    agent_config = new(
        cmt_interface,
        INITIAL_CMT_BASE,
        INITIAL_CMT_SIZE_CLOG2,
        resolver_interface_test,
        ops_interface_test,
        reset_intf
    );

    sparse_mem = new;

    transactions = new("transaction_queue");

    transactions.delete();

    uvm_config_db#(uvm_queue#(transaction_t))::set(
        null, "", CAPABILITY_CACHE_TRANSACTION_QUEUE_NAME, transactions);

    `uvm_info(COMPONENT_NAME, $sformatf(
              "Inserting Capability Cache Agent Config of type %s name %s into config DB!",
              $typename(
                  agent_config
              ),
              CAPABILITY_CACHE_AGENT_CONFIG_NAME
              ), UVM_DEBUG);

    uvm_config_db#(agent_config_t)::set(null, "", CAPABILITY_CACHE_AGENT_CONFIG_NAME, agent_config);
  end


endmodule
