/**
 * Testbench module for Northcape integration testing.
 */
module northcape_integration_top;


  `include "axi5_assign.svh"
  import northcape_capability_ops_transaction::*;
  import northcape_capability_ops_agent::NorthcapeCapabilityOpsAgentConfig;
  import northcape_generator::NorthcapeGenerator;
  import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
  import northcape_sparse_mem_sim::*;
  import northcape_integration_agent::NorthcapeIntegrationAgent;
  import northcape_types::*;
  import northcape_test::*;
  import northcape_mmu_transaction::NorthcapeMMUTransaction;
  import northcape_integration_test_constants::*;
  import northcape_mmu_agent::NorthcapeMMUAgentConfig;
  import northcape_integration_transaction::NorthcapeIntegrationTransaction;
  import northcape_integration_agent::NorthcapeIntegrationAgentConfig;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  logic clk_i;
  logic rst_ni;

  logic is_revoke;

  // clock period 10 ns = 100 MHz clock
  localparam half_clock_period_ns = 5;
  localparam clock_period_ns = 2 * half_clock_period_ns;

  northcape_test_clock_generator #(
      .CLOCK_PERIOD_NS(clock_period_ns)
  ) clock_generator (
      .clk_i(clk_i)
  );

  Axi5 #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )
      ops_axi_out (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      resolver_axi_out (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      cache_axi_out (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );
  Axi5 #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MMU),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )
      mmu_in (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      mmu_out (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );

  Axi5Lite #(
      .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH)
  ) ops_mmio (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  typedef virtual Axi5Lite #(
      .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH)
  ) axi_lite_interface_t;

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
      axis_validate_request_read (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      axis_validate_request_write (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      axis_validate_request_recursion (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );
  Axis5 #(
      .AXIS_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_RESPONSE_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH)
  )
      axis_validate_response (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      axis_validate_response_read (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      axis_validate_response_write (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );

  NorthcapeCMTInterface #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) cmt_interface (.clk_i(clk_i));
  NorthcapeCurrentDeviceTaskInterface current_device_task_interface (.clk_i(clk_i));


  NorthcapeInterruptInterface #(
      .NUMBER_INTERRUPT_PINS(NORTHCAPE_CAPABILITY_OPS_NUM_IRQS)
  ) irq_interface (
      .clk_i(clk_i)
  );

  logic test_complete_master, test_complete_slave;
  axi_test_request_result_t result_master, result_slave;

  int cmt_size_clog2;
  bit [AXI_ADDR_WIDTH - 1 : 0] ops_cmt_base_addr;

  typedef logic [AXI_DATA_WIDTH_MEM-1:0] mem_content_t[$];
  typedef logic [AXI_ADDR_WIDTH-1:0] mem_index_t;

  typedef NorthcapeSparseMem#(
      .QUEUE_TYPE(mem_content_t),
      .DATA_TYPE(logic [AXI_DATA_WIDTH_MEM-1:0]),
      .INDEX_TYPE(mem_index_t),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
      // init writes go via ops interface and are ignored here
      .ZERO_IF_NOT_EXISTS(HAS_CACHE_INTERFACE)
  ) sparse_mem_t;

  sparse_mem_t sparse_mem;

  class NorthcapeIntegrationCountCapabilities implements NorthcapeSparseMemUpdateCallback#(
      .DATA_TYPE (logic [AXI_DATA_WIDTH_MEM-1:0]),
      .INDEX_TYPE(mem_index_t)
  );
    bit [AXI_LITE_DATA_WIDTH-1:0] capability_count;

    localparam string COMPONENT_NAME = "NorthcapeIntegrationCountCapabilities";

    virtual function void data_updated(mem_index_t addr, logic [AXI_DATA_WIDTH_MEM-1:0] old_value,
                                       logic [AXI_DATA_WIDTH_MEM-1:0] new_value);
      if (old_value == 'x && new_value == '0) begin
        // initial write
        return;
      end

      if (old_value == '0 && new_value != '0) begin
        if (capability_count == '1) begin
          `uvm_error(COMPONENT_NAME, "Count overflow!");
        end
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Seen old value %x new value %x - one new capability!", old_value, new_value),
                  UVM_DEBUG);
        capability_count++;
      end

      if (old_value != '0 && new_value == '0) begin
        if (capability_count == '0) begin
          `uvm_error(COMPONENT_NAME, "Count underflow!");
        end
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Seen old value %x new value %x - one less capability!", old_value, new_value),
                  UVM_DEBUG);
        capability_count--;
      end

      uvm_config_db#(bit [AXI_LITE_DATA_WIDTH-1:0])::set(
          null, "", northcape_test::NORTHCAPE_CAPABILITY_COUNT_CONFIG_NAME, capability_count);
    endfunction

    function new();
      capability_count = 0;
      // to make sure that the scoreboard knows the value exists...
      uvm_config_db#(bit [AXI_LITE_DATA_WIDTH-1:0])::set(
          null, "", northcape_test::NORTHCAPE_CAPABILITY_COUNT_CONFIG_NAME, capability_count);
    endfunction
  endclass

  // queue of master test requests
  mailbox #(INorthcapeAXITransactionMasterSide #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MMU),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )) requests_in_master;

  mailbox #(INorthcapeAXITransactionMasterSide #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )) requests_in_revocation;

  mailbox #(INorthcapeAXITransactionSlaveSide #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MMU),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )) requests_in_slave;


  typedef uvm_analysis_port#(Axi5SlaveDriverResultTransaction#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MMU),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )) slave_analysis_port_t;

  typedef uvm_analysis_port#(Axi5MasterDriverResultTransaction#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MMU),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )) master_analysis_port_t;

  typedef uvm_analysis_port#(Axi5MasterDriverResultTransaction#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )) master_analysis_port_revocation_t;

  typedef uvm_analysis_port#(AxisValidateResultTransaction) resolver_analysis_port_t;

  NorthcapeCapabilityCacheInterfaceResolver resolver_interface (.clk_i(clk_i));
  NorthcapeCapabilityCacheInterfaceOps ops_interface (.clk_i(clk_i));



  slave_analysis_port_t slave_analysis_port;
  master_analysis_port_t master_analysis_port;
  master_analysis_port_revocation_t revocation_analysis_port;
  NorthcapeIntegrationCountCapabilities counter;

  initial begin
    requests_in_master = new;
    requests_in_slave = new;
    requests_in_revocation = new;
    counter = new;

    slave_analysis_port = new("integration_mmu_slave_analysis_port", null);
    master_analysis_port = new("integration_mmu_master_analysis_port", null);


    revocation_analysis_port = new("integration_ops_revocation_analysis_port", null);

    sparse_mem = new(counter);

  end

  NorthcapeRNGInterface #(
      .RNG_DATA_WIDTH(NORTHCAPE_CAPABILITY_OPS_RNG_INTERFACE_BITS)
  ) rng_intf (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );
  northcape_rng #(
      .RNG_DATA_WIDTH(NORTHCAPE_CAPABILITY_OPS_RNG_INTERFACE_BITS)
  ) i_rng (
      .intf(rng_intf)
  );

  NorthcapeCapabilityOpsCsrIntf csr_interface (.clk_i(clk_i));

  northcape_capability_ops #(
      .HASH_TYPE(HASH_TYPE_IDENTITY),
      .HAS_CACHE_INTERFACE(HAS_CACHE_INTERFACE),

      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),

      .CAPABILITY_COUNTER_ACTIVE(1'b1),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2),
      .OPS_TAG_METHOD(OPS_TAG_METHOD),
      .BITMAP_BRAM_DATA_WIDTH(OPS_BRAM_DATA_WIDTH),
      .USE_TEST_ONLY_BRAM(1'b0),
      .PROVIDE_ERROR_CODES(1'b0)
  ) dut_ops (
      .clk_i(clk_i),
      .rst_ni(rst_ni),

      .axi_master(ops_axi_out),
      .axi_slave(ops_mmio),
      .cache_interface(ops_interface),

      .cmt_interface(cmt_interface),
      .rng_interface(rng_intf),

      .current_device_task_interface(current_device_task_interface),
      .irq_out(irq_interface),


      .csr_req_i(csr_interface.request),
      .csr_rsp_o(csr_interface.response),

      .memory_ready_i(1'b1),

      .debug_state_o(),
      .debug_is_unlock_o(),
      .debug_input_capability_valid_o(),
      .debug_update_complete_o(),
      .debug_capabilities_valid_o(),

      .debug_is_revoke_o(is_revoke),
      .debug_capability_token_o(),
      .debug_capability_operation_o(),
      .debug_top_state_o(),
      .zero_segment_debug_state_o(),
      .debug_zero_len_o(),
      .debug_top_state_isr_o()

  );

  axi5_mem_adapter #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .MEM_TYPE(sparse_mem_t)
  ) ops_mem_adapter (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      // in case of cache interface, only revoke and zero-out writes
      .ignore_write_i(is_revoke || HAS_CACHE_INTERFACE),

      .axi_slave(ops_axi_out),
      .memory_i (sparse_mem)
  );

  Axis5Mux #(
      .NUMBER_IN_PORTS (3),
      .ARBITRATION_TYPE(axis5_mux::ARBITRATION_RR)
  ) i_mux (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .in_ports({
        axis_validate_request_read, axis_validate_request_write, axis_validate_request_recursion
      }),
      .out_port(axis_validate_request)
  );

  northcape_capability_resolver #(
      .HASH_TYPE(HASH_TYPE_IDENTITY),
      .HAS_CACHE_INTERFACE(HAS_CACHE_INTERFACE),
      .CACHE_RECURSION_SKIP(CACHE_RECURSION_SKIP),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .FIFO_DEPTH_CLOG_2(FIFO_DEPTH_CLOG_2),
      .MAX_AXI_TRANSACTIONS(MAX_AXI_TRANSACTIONS),
      .INPUT_PIPELINE_STAGE_ENABLED(INPUT_PIPELINE_STAGE_ENABLED),
      .PARSER_PIPELINE_STAGE_ENABLED(PARSER_PIPELINE_STAGE_ENABLED),
      .OUTPUT_PIPELINE_STAGE_ENABLED(OUTPUT_PIPELINE_STAGE_ENABLED)
  ) dut_resolver (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .validate_request(axis_validate_request),
      .axi_master(resolver_axi_out),
      .cache_interface(resolver_interface),
      .validate_response(axis_validate_response),
      .validate_request_recursion(axis_validate_request_recursion),

      .cmt_interface(cmt_interface)
  );

  axi5_mem_adapter #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .MEM_TYPE(sparse_mem_t)
  ) resolver_mem_adapter (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .ignore_write_i(1'b0),

      .axi_slave(resolver_axi_out),
      .memory_i (sparse_mem)
  );

  Axis5Demux #(
      .NUMBER_OUT_PORTS(2)
  ) i_demux (
      .in_port  (axis_validate_response),
      .out_ports({axis_validate_response_read, axis_validate_response_write})
  );

  northcape_capability_cache #(
      .HASH_TYPE(northcape_capability_resolver_common::HASH_TYPE_IDENTITY),
      .CACHE_TYPE(northcape_capability_cache_common::NORTHCAPE_CAPABILITY_TYPE_WT_N_ASSOC_BRAM),
      .ASSOCIATIVITY(CACHE_ASSOCIATIVITY),
      .NUM_ENTRIES(NUM_CACHE_ENTRIES),
      .SUPPORT_SPECULATIVE_RESOLVER_LOADS(SUPPORT_SPECULATIVE_RESOLVER_LOADS),
      .KEEP_TOP_CMT_ENTRIES_ONLY(KEEP_TOP_CMT_ENTRIES_ONLY),
      .STORE_BUFFER_SIZE(CACHE_STORE_BUFFER_SIZE),

      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) i_capability_cache (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .axi_master(cache_axi_out),

      .resolver_port(resolver_interface),
      .ops_port(ops_interface),
      .cmt_interface(cmt_interface),
      .resolver_port_miss_o(  /* not checked */),
      .ops_port_miss_o(  /* not checked */),
      .missunit_stall_o(  /* not checked */),
      .ops_write_stall_o(  /* not checked */),
      .resolver_spec_fail_o(  /* not checked */)
  );

  axi5_mem_adapter #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .MEM_TYPE(sparse_mem_t)
  ) cache_mem_adapter (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .ignore_write_i(1'b0),

      .axi_slave(cache_axi_out),
      .memory_i (sparse_mem)
  );

  northcape_mmu #(
`ifdef NORTHCAPE_MMU_NO_AXI_WRAP
      .ACCEPT_AXI_WRAP_BURSTS(0),
`endif
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MMU),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
      .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
      // this is already tested in MMU test bench
      // nothing to gain testing this again
      .SELF_PRESERVATION_MODE_ACTIVE(0),
      .DEVICE_INDICATES_EXECUTE(1'b1)
  ) dut_mmu (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      // AXI Slave interface
      .axi_slave(mmu_in),

      // AXI Master interface
      .axi_master(mmu_out),

      .axis_validate_request_read  (axis_validate_request_read.TRANSMITTER),
      .axis_validate_response_read (axis_validate_response_read.RECEIVER),
      .axis_validate_request_write (axis_validate_request_write.TRANSMITTER),
      .axis_validate_response_write(axis_validate_response_write.RECEIVER),

      .cmt_interface(cmt_interface)
  );

  // handles MMU IN interface
  axi5_slave_driver #(
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MMU),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
  ) mmu_slave_driver (
      .requests_in(requests_in_slave),

      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .axi_slave(mmu_in),

      .ap_i(slave_analysis_port)
  );

  // handles MMU OUT interface
  axi5_master_driver #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MMU),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH)
  ) mmu_master_driver (
      .requests_in(requests_in_master),

      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .axi_master(mmu_out),


      .ap_i(master_analysis_port)
  );


  typedef NorthcapeMMUAgentConfig#(
      .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
      .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MMU),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .CHECK_CMT_OVERLAP(0)
  ) mmu_agent_config_t;

  northcape_test_reset reset_intf (.clk_i(clk_i));

  assign rst_ni = reset_intf.resetn;

  typedef virtual northcape_test_reset reset_intf_t;

  typedef NorthcapeMMUTransaction#(
      .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
      .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MMU),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .CHECK_CMT_OVERLAP(0)
  ) mmu_transaction_t;

  typedef NorthcapeCapabilityOpsAgentConfig#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
      .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),

      .HASH_TYPE(HASH_TYPE_IDENTITY),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
  ) ops_agent_config_t;

  typedef NorthcapeCapabilityOpsTransaction#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
      .HASH_TYPE(HASH_TYPE_IDENTITY),


      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
  ) ops_transaction_t;

  typedef NorthcapeIntegrationAgentConfig#(
      .AXI_DATA_WIDTH_OPS (AXI_DATA_WIDTH_MEM),
      .AXI_ADDR_WIDTH_OPS (AXI_ADDR_WIDTH),
      .HAS_CACHE_INTERFACE(HAS_CACHE_INTERFACE)
  ) integration_agent_config_t;

  typedef NorthcapeIntegrationTransaction#(AXI_ADDR_WIDTH) integration_transaction_t;


  axi5_master_driver #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .MONITOR_MODE(1'b1)  // writes are handled by the memory simulator
  ) revocation_checker (
      .requests_in(requests_in_revocation),
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .axi_master(ops_axi_out),
      .ap_i(revocation_analysis_port)
  );

  initial begin
    automatic mmu_agent_config_t mmu_agent_config;
    automatic uvm_queue #(mmu_transaction_t) mmu_transactions;

    automatic ops_agent_config_t ops_agent_config;
    automatic uvm_queue #(ops_transaction_t) ops_transactions;

    automatic integration_agent_config_t integration_agent_config;
    automatic uvm_queue #(integration_transaction_t) integration_transactions;

    mmu_agent_config = new(
        requests_in_slave,
        requests_in_master,
        null,
        null,
        null,
        slave_analysis_port,
        master_analysis_port,
        null,
        null
    );
    uvm_config_db#(mmu_agent_config_t)::set(null, "", MMU_AGENT_CONFIG_NAME, mmu_agent_config);

    ops_agent_config = new(
        cmt_interface,
        INITIAL_CMT_BASE,
        INITIAL_CMT_SIZE_CLOG2,
        ops_mmio,
        csr_interface,
        requests_in_revocation,
        revocation_analysis_port,
        null,
        null,
        null,
        current_device_task_interface,
        irq_interface
    );
    uvm_config_db#(ops_agent_config_t)::set(null, "", CAPABILITY_OPS_AGENT_CONFIG_NAME,
                                            ops_agent_config);

    integration_agent_config = new(sparse_mem);
    uvm_config_db#(integration_agent_config_t)::set(null, "", INTEGRATION_AGENT_CONFIG_NAME,
                                                    integration_agent_config);


    uvm_config_db#(reset_intf_t)::set(null, "", INTEGRATION_TEST_RESET_INTERFACE_NAME, reset_intf);

    mmu_transactions = new("integration_mmu_transaction_queue");
    mmu_transactions.delete();
    uvm_config_db#(uvm_queue#(mmu_transaction_t))::set(null, "", TRANSACTIONS_QUEUE_NAME_AGENT_MMU,
                                                       mmu_transactions);

    ops_transactions = new("integration_ops_transaction_queue");
    ops_transactions.delete();
    uvm_config_db#(uvm_queue#(ops_transaction_t))::set(null, "", TRANSACTIONS_QUEUE_NAME_AGENT_OPS,
                                                       ops_transactions);

    integration_transactions = new("integration_agent_transaction_queue");
    integration_transactions.delete();
    uvm_config_db#(uvm_queue#(integration_transaction_t))::set(
        null, "", TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION, integration_transactions);

    uvm_config_db#(axi_lite_interface_t)::set(
        null, "", INTEGRATION_TEST_CAPABILITY_OPS_AXI_LITE_INTERFACE_NAME, ops_mmio);
  end

endmodule
