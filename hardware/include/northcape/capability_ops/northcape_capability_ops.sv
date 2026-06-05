/**
  * Northcape capability operations module.
  * Provides MMIO interface that allows modification of capabilities.
  */
module northcape_capability_ops #(
    parameter HASH_TYPE = -1,
    parameter HAS_CACHE_INTERFACE = 1'b0,

    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_ID_WIDTH   = -1,
    parameter AXI_USER_WIDTH = -1,

    parameter AXI_LITE_ADDR_WIDTH = -1,
    parameter AXI_LITE_DATA_WIDTH = -1,

    parameter bit CAPABILITY_COUNTER_ACTIVE = 1'b1,
    parameter logic [AXI_ADDR_WIDTH-1:0] INITIAL_CMT_BASE = -1,
    parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1,

    parameter bit WAIT_FOR_MEMORY_READY = 1'b0,

    parameter bit MMIO_INTERFACE_SUPPORTED = 1'b1,
    parameter bit CSR_INTERFACE_SUPPORTED = 1'b1,
    // use CBC MAC of CMT entry or a CTR of the nonce for the tag
    parameter northcape_capability_ops_common::northcape_capability_ops_tag_method_t OPS_TAG_METHOD = northcape_capability_ops_common::NORTHCAPE_CAPABILITY_OPS_CBC,
    // use simulated / test BRAM. Only for Ops UVM tests!
    parameter bit USE_TEST_ONLY_BRAM = 1'b0,
    // width of the BRAM used for the CMT bitmap. Performace/Area Tradeoff.
    parameter int BITMAP_BRAM_DATA_WIDTH = 64,
    // should the ops provide detailed error codes on failed operations?
    parameter bit PROVIDE_ERROR_CODES = 1'b1,
    // how many ops cycles to wait between cs 1->0 and sclk 0->1
    parameter int unsigned TPM_CS_WAIT_CYCLES = 16
) (
    input logic clk_i,
    input logic rst_ni,

    Axi5.FROM   axi_master,
    Axi5Lite.TO axi_slave,

    input  northcape_types::northcape_cap_ops_rcsr_req_t  csr_req_i,
    output northcape_types::northcape_cap_ops_rcsr_resp_t csr_rsp_o,

    NorthcapeCapabilityCacheInterfaceOps.OPS_INTERFACE cache_interface,

    input logic memory_ready_i,

    NorthcapeCMTInterface.OPS_INTERFACE cmt_interface,

    NorthcapeRNGInterface.RNG_CONSUMER rng_interface,

    NorthcapeCurrentDeviceTaskInterface.OPS_INTERFACE current_device_task_interface,


    // one IRQ for operation completed
    // primarily intended for testing
    NorthcapeInterruptInterface.IRQ_PRODUCER irq_out,

    output logic [4:0] debug_state_o,
    output logic [3:0] debug_top_state_o,
    output logic [3:0] debug_top_state_isr_o,
    output logic debug_is_unlock_o,
    output logic debug_input_capability_valid_o,
    output logic [1:0] debug_update_complete_o,
    output logic [2:0] debug_capabilities_valid_o,
    // are we currently overwriting a main memory segment?
    output logic debug_is_revoke_o,
    output logic [AXI_ADDR_WIDTH-1:0] debug_capability_token_o,
    output northcape_capability_ops_common::northcape_capability_operation_t debug_capability_operation_o,
    output logic [2:0] zero_segment_debug_state_o,
    output logic [8:0] debug_zero_len_o
);
  import northcape_types::*;
  import axi5::*;
  import northcape_capability_ops_common::*;
  `include "axi5_assign.svh"
  `include "northcape_unread.vh"

  typedef NorthcapeCapabilityOpsGenerator#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .HASH_TYPE(HASH_TYPE)
  ) gen_t;

  typedef enum {
    RESET,
    ZERO_CMT,
    CREATE_ROOT_CAP,
    MMIO_LOCKED,
    MMIO_PARSE_OPERATION,
    CREATE_CAP,
    CREATE_CAP_RETURN_RESULT,
    CREATE_CAP_RETURN_RESULT_WAIT_READ_COMPLETE,
    CREATE_CAP_REVOKE,
    IDLE,
    REPORT_ERROR
  } northcape_capability_ops_state_t;

  typedef enum logic [0:0] {
    INTERFACE_IDLE,
    INTERFACE_BUSY_READ
  } northcape_capability_ops_interface_state_t;


  localparam logic [5:0] REG_INTERFACE_TOKEN_INPUT_REG_OFFSET = 6'h0;
  localparam logic [5:0] REG_INTERFACE_TOKEN_OUTPUT_REG_OFFSET = 6'h8;
  localparam logic [5:0] REG_INTERFACE_RESTRICTION_REG_OFFSET = 6'h10;
  localparam logic [5:0] REG_INTERFACE_TOKEN_CTRL_STATUS_REG_OFFSET = 6'h18;
  localparam logic [5:0] REG_INTERFACE_AUX1_REG_OFFSET = 6'h20;
  localparam logic [5:0] REG_INTERFACE_COUNT_CTRL_STATUS_REG = 6'h28;
  localparam logic [5:0] REG_INTERFACE_COUNT_TRNG_REG = 6'h30;
  localparam logic [5:0] REG_INTERFACE_COUNT_STATS_REG = 6'h38;


  localparam logic [63:0] REG_INTERFACE_TOKEN_INPUT_REG = {
    58'h0, REG_INTERFACE_TOKEN_INPUT_REG_OFFSET
  };
  localparam logic [63:0] REG_INTERFACE_TOKEN_OUTPUT_REG = {
    58'h0, REG_INTERFACE_TOKEN_OUTPUT_REG_OFFSET
  };
  localparam logic [63:0] REG_INTERFACE_RESTRICTION_REG = {
    58'h0, REG_INTERFACE_RESTRICTION_REG_OFFSET
  };
  localparam logic [63:0] REG_INTERFACE_TOKEN_CTRL_STATUS_REG = {
    58'h0, REG_INTERFACE_TOKEN_CTRL_STATUS_REG_OFFSET
  };
  localparam logic [63:0] REG_INTERFACE_AUX1_REG = {58'h0, REG_INTERFACE_AUX1_REG_OFFSET};

  // same mapping, higher 64 bits of the address space
  localparam logic [63:0] REG_INTERFACE_TOKEN_INPUT_REG_ISR = {
    58'h1, REG_INTERFACE_TOKEN_INPUT_REG_OFFSET
  };
  localparam logic [63:0] REG_INTERFACE_TOKEN_OUTPUT_REG_ISR = {
    58'h1, REG_INTERFACE_TOKEN_OUTPUT_REG_OFFSET
  };
  localparam logic [63:0] REG_INTERFACE_RESTRICTION_REG_ISR = {
    58'h1, REG_INTERFACE_RESTRICTION_REG_OFFSET
  };
  localparam logic [63:0] REG_INTERFACE_TOKEN_CTRL_STATUS_REG_ISR = {
    58'h1, REG_INTERFACE_TOKEN_CTRL_STATUS_REG_OFFSET
  };
  localparam logic [63:0] REG_INTERFACE_AUX1_REG_ISR = {58'h1, REG_INTERFACE_AUX1_REG_OFFSET};

  // 6 bits register + 1 bit IRQ/non-IRQ
  localparam AXI_LITE_COMPARE_WIDTH = 8;

  // main state machine
  northcape_capability_ops_state_t state_q, state_d;
  // ISR state machine: simplified version of the state machine, assumes operations are non-interrupted
  northcape_capability_ops_state_t isr_state_q, isr_state_d;

  // start/stop for hierarchical FSM for creating capabilities
  logic create_cap_start, create_cap_done, create_cap_error;
  // copy for ISR version
  logic create_cap_start_isr, create_cap_done_isr, create_cap_error_isr;

  logic reset_done_q, reset_done_d;

  logic [AXI_LITE_COMPARE_WIDTH-1:0]
      last_araddr_q, last_araddr_d, last_awaddr_q, comp_addr_wr, csr_addr;

  logic [AXI_LITE_DATA_WIDTH-1:0] data_in;
  logic data_in_valid;

  northcape_restrictions_t
      inspect_restrictions_d,
      inspect_restrictions_isr_d,
      inspect_restrictions_d1,
      inspect_restrictions_isr_d1,
      inspect_restrictions_q,
      inspect_restrictions_isr_q;
  segment_length_t
      inspect_length_d, inspect_length_isr_d, inspect_length_isr_d1, inspect_length_isr_q;
  segment_base_addr_t inspect_base_d, inspect_base_isr_d, inspect_base_isr_d1, inspect_base_isr_q;
  northcape_direct_capability_permissions_t
      inspect_permissions_d,
      inspect_permissions_isr_d,
      inspect_permissions_isr_d1,
      inspect_permissions_isr_q;
  northcape_reference_count_t
      inspect_refcount_isr_q, inspect_refcount_isr_d, inspect_refcount_d, inspect_refcount_isr_d1;

  // for tracking of interface state, used in arbitration
  northcape_capability_ops_interface_state_t interface_state_q, interface_state_d;

  // for determining whether we have a leak, passed through to MMIO
  logic [AXI_LITE_DATA_WIDTH-3:0] capability_count;

  logic current_operation_is_isr;

  logic cap_ops_initialized;

  // performance counters for this operation
  logic [AXI_LITE_DATA_WIDTH/2-1:0] idle_check_count_d, idle_check_count_q;
  logic [AXI_LITE_DATA_WIDTH/2-1:0] create_cycles_d, create_cycles_q;
  logic [AXI_LITE_DATA_WIDTH/2-1:0] idle_check_count_isr_d, idle_check_count_isr_q;
  logic [AXI_LITE_DATA_WIDTH/2-1:0] create_cycles_isr_d, create_cycles_isr_q;

  logic idle_check_occupied_event;

  NorthcapeCapabilityCacheInterfaceOps
      ops_interface_create_caps (.clk_i(clk_i)), ops_interface_irq (.clk_i(clk_i));

  typedef struct packed {
    capability_id_t request_capability_id;
    capability_tag_t request_capability_tag;
    logic is_write;
    northcape_cmt_entry_t write_request_capability;
    logic write_request_flush;
    logic request_is_uncacheable;
  } cache_interface_in_t;

  // AXI interface that goes to capability creation FSM
  Axi5 #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )
      cap_creation_intf (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      cap_creation_intf_isr (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );
  ;

  Axi5WriteOnly #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) revocation_intf (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  // 8 * non-IRQ, 8 * IRQ
  localparam NUM_REGS = 16;

  NorthcapeRegInterfaceIO #(
      .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
      .NUM_REGS(NUM_REGS)
  ) reg_interface (
      .clk_i(clk_i)
  );
  // parsed values from MMIO
  // MMIO only presents new token for exactly one read to prevent leaking it
  logic [AXI_ADDR_WIDTH - 1 : 0]
      input_capability_token_q,
      input_capability_token_d,
      input_capability_token_isr_q,
      input_capability_token_isr_d,
      output_capability_token_d1,
      output_capability_token_mmio_isr_q,
      output_capability_token_mmio_isr_d;
  northcape_capability_operation_t
      requested_operation_q,
      requested_operation_isr_q,
      requested_operation_d,
      requested_operation_isr_d;

  logic restriction_enabled_q, restriction_enabled_d;
  logic restriction_enabled_isr_q, restriction_enabled_isr_d;
  northcape_restriction_type_t restriction_type_q, restriction_type_d;
  northcape_restriction_type_t restriction_type_isr_q, restriction_type_isr_d;
  device_id_t restriction_device_id_d;
  task_id_t restriction_task_id_d;
  device_id_t restriction_device_id_isr_d;
  task_id_t restriction_task_id_isr_d;
  northcape_device_interpreted_restriction_t restriction_device_interpreted_restriction_d;
  northcape_device_interpreted_restriction_t restriction_device_interpreted_restriction_isr_d;
  bit [AXI_LITE_DATA_WIDTH-1:0] restriction_register_q, restriction_register_d;
  bit [AXI_LITE_DATA_WIDTH-1:0] restriction_register_isr_q, restriction_register_isr_d;

  logic read_perm_q, read_perm_d;
  logic write_perm_q, write_perm_d;
  logic x_perm_q, x_perm_d;
  logic lockable_perm_q, lockable_perm_d;
  logic irq_accessible_perm_q, irq_accessible_perm_d;
  logic cacheable_tlb_perm_q, cacheable_tlb_perm_d;
  logic cacheable_access_perm_q, cacheable_access_perm_d;

  logic read_perm_isr_q, read_perm_isr_d;
  logic write_perm_isr_q, write_perm_isr_d;
  logic x_perm_isr_q, x_perm_isr_d;
  logic lockable_perm_isr_q, lockable_perm_isr_d;
  logic irq_accessible_perm_isr_q, irq_accessible_perm_isr_d;
  logic cacheable_tlb_perm_isr_q, cacheable_tlb_perm_isr_d;
  logic cacheable_access_perm_isr_q, cacheable_access_perm_isr_d;

  logic direction_q, direction_d;
  segment_length_t new_segment_length_q, new_segment_length_d;
  segment_length_t parent_offset;
  logic [AXI_LITE_DATA_WIDTH-1:0] aux1_reg_q, aux1_reg_d;

  logic direction_isr_q, direction_isr_d;
  segment_length_t new_segment_length_isr_q, new_segment_length_isr_d;
  segment_length_t parent_offset_isr;
  logic [AXI_LITE_DATA_WIDTH-1:0] aux1_reg_isr_q, aux1_reg_isr_d;

  // size of the offset that we want
  capability_type_t intended_capability_type_q, intended_capability_type_d;
  capability_type_t intended_capability_type_isr_q, intended_capability_type_isr_d;

  northcape_physical_address_t
      zero_segment_phys_addr_create, zero_segment_phys_addr_cmt, zero_segment_phys_addr;
  segment_length_t zero_segment_length_create, zero_segment_length_cmt, zero_segment_length;

  logic zero_segment_start, zero_segment_done;

  device_id_t current_device_id_q, current_device_id_d;
  task_id_t current_task_id_q, current_task_id_d;

  device_id_t current_device_id_isr_q, current_device_id_isr_d;
  task_id_t current_task_id_isr_q, current_task_id_isr_d;

  logic [AXI_DATA_WIDTH-1:0] trng_reg;
  logic trng_reg_clear;

  logic create_cap_rng_consumer_ready, rng_reg_consumer_ready;

  logic create_caps_wrote_any_capability;
  capability_id_t create_caps_written_capability;

  logic [AXI_LITE_DATA_WIDTH-1:0] regs_in[NUM_REGS], regs_in_mmio[NUM_REGS];

  // output buffer for non-ISR operations - used to preserve operation output on NMI
  logic [AXI_ADDR_WIDTH-1:0] create_cap_output_token_buf_d, create_cap_output_token_buf_q;
  northcape_restrictions_t
      create_cap_inspect_restrictions_buf_d, create_cap_inspect_restrictions_buf_q;
  segment_length_t create_cap_inspect_length_buf_d, create_cap_inspect_length_buf_q;
  segment_base_addr_t create_cap_inspect_base_buf_d, create_cap_inspect_base_buf_q;
  northcape_direct_capability_permissions_t
      create_cap_inspect_permissions_buf_d, create_cap_inspect_permissions_buf_q;
  northcape_reference_count_t create_cap_inspect_refcount_buf_d, create_cap_inspect_refcount_buf_q;


  northcape_error_code_t error_code_create_caps, error_code_isr_create_caps;
  northcape_error_code_t error_code_d, error_code_q, error_code_isr_d, error_code_isr_q;


  typedef enum {
    NO_GRANT,
    MMIO_GRANT,
    CSR_GRANT
  } mmio_csr_arb_t;

  mmio_csr_arb_t arbiter_grant;

  NorthcapeCMTInterface #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) cmt_interface_consumers (.clk_i(clk_i));

  generate
    if (INITIAL_CMT_SIZE_CLOG2 <= 0) begin
      $error("Invalid initial size!");
    end
  endgenerate

  assign cmt_interface_consumers.table_size_clog2 = cmt_interface.table_size_clog2;
  assign cmt_interface_consumers.cmt_base = cmt_interface.cmt_base;
  assign cmt_interface_consumers.reset_done = cmt_interface.reset_done;
  assign cmt_interface_consumers.need_flush_data_caches = cmt_interface.need_flush_data_caches;
  assign cmt_interface_consumers.wrote_any_capability = cmt_interface.wrote_any_capability;
  assign cmt_interface_consumers.written_capability = cmt_interface.written_capability;


  assign rng_interface.rng_consumer_ready = create_cap_rng_consumer_ready | rng_reg_consumer_ready;
  assign reg_interface.regs_in = regs_in_mmio;

  // sub modules

  //===================================
  // MMIO Interface
  //===================================

  generate
    if (MMIO_INTERFACE_SUPPORTED) begin : gen_northcape_reg_interface
      northcape_reg_interface #(
          .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
          .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
          .NUM_REGS(NUM_REGS)
      ) i_northcape_reg_interface (
          .s_axi(axi_slave),
          .reg_intf(reg_interface)
      );
    end : gen_northcape_reg_interface
    else begin : gen_no_reg_interface
      always_comb begin : regInterfaceDefaultAssignments
        for (int i = 0; i < NUM_REGS; i++) begin : gen_assignment
          reg_interface.regs_out[i] = '0;
        end : gen_assignment
      end : regInterfaceDefaultAssignments

      assign axi_slave.awready = 1'b0;
      assign axi_slave.wready  = 1'b0;
      assign axi_slave.bresp   = SLVERR;
      assign axi_slave.bvalid  = 1'b0;
      assign axi_slave.arready = 1'b0;
      assign axi_slave.rdata   = '0;
      assign axi_slave.rresp   = SLVERR;
      assign axi_slave.rvalid  = 1'b0;


      `NORTHCAPE_UNREAD(axi_slave.awvalid);
      `NORTHCAPE_UNREAD(axi_slave.awaddr);
      `NORTHCAPE_UNREAD(axi_slave.awprot);

      `NORTHCAPE_UNREAD(axi_slave.wvalid);
      `NORTHCAPE_UNREAD(axi_slave.wdata);
      `NORTHCAPE_UNREAD(axi_slave.wstrb);

      `NORTHCAPE_UNREAD(axi_slave.bready);

      `NORTHCAPE_UNREAD(axi_slave.arvalid);
      `NORTHCAPE_UNREAD(axi_slave.araddr);
      `NORTHCAPE_UNREAD(axi_slave.arprot);

      `NORTHCAPE_UNREAD(axi_slave.rready);
    end : gen_no_reg_interface
  endgenerate

  //===================================
  // Capability creation module
  //===================================
  northcape_capability_ops_create_caps #(
      .HASH_TYPE(HASH_TYPE),
      .HAS_CACHE_INTERFACE(HAS_CACHE_INTERFACE),

      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .CAPABILITY_COUNTER_WIDTH (AXI_LITE_DATA_WIDTH - 2),
      .CAPABILITY_COUNTER_ACTIVE(CAPABILITY_COUNTER_ACTIVE),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2),
      .IS_ISR_ONLY(1'b0),
      .OPS_TAG_METHOD(OPS_TAG_METHOD),
      .USE_TEST_ONLY_BRAM(USE_TEST_ONLY_BRAM),
      .BITMAP_BRAM_DATA_WIDTH(BITMAP_BRAM_DATA_WIDTH)
  ) i_northcape_capability_ops_create_caps (
      .axi_master(cap_creation_intf),
      .cmt_interface(cmt_interface_consumers),
      .start_i(create_cap_start),
      .done_o(create_cap_done),
      .error_o(create_cap_error),
      .is_root_capability_i(state_q == CREATE_ROOT_CAP),

      .capability_token_i(current_operation_is_isr ? input_capability_token_isr_q : input_capability_token_q),
      .capability_token_o(output_capability_token_d1),
      .operation_i(current_operation_is_isr ? requested_operation_isr_q : requested_operation_q),

      .restriction_enabled_i(current_operation_is_isr ? restriction_enabled_isr_q : restriction_enabled_q),
      .restriction_device_id_i(current_operation_is_isr ? restriction_device_id_isr_d : restriction_device_id_d),
      .restriction_task_id_i(current_operation_is_isr ? restriction_task_id_isr_d : restriction_task_id_d),
      .device_interpreted_restriction_i(current_operation_is_isr ? restriction_device_interpreted_restriction_isr_d : restriction_device_interpreted_restriction_d),
      .restriction_type_i(current_operation_is_isr ? restriction_type_isr_q : restriction_type_q),

      .read_perm_i(current_operation_is_isr ? read_perm_isr_q : read_perm_q),
      .write_perm_i(current_operation_is_isr ? write_perm_isr_q : write_perm_q),
      .x_perm_i(current_operation_is_isr ? x_perm_isr_q : x_perm_q),
      .lockable_perm_i(current_operation_is_isr ? lockable_perm_isr_q : lockable_perm_q),
      .irq_accessible_perm_i(current_operation_is_isr ? irq_accessible_perm_isr_q : irq_accessible_perm_q),
      .cacheable_tlb_perm_i(current_operation_is_isr ? cacheable_tlb_perm_isr_q : cacheable_tlb_perm_q),
      .cacheable_access_perm_i(current_operation_is_isr ? cacheable_access_perm_isr_q : cacheable_access_perm_q),

      .direction_i(current_operation_is_isr ? direction_isr_q : direction_q),
      .segment_length_i(current_operation_is_isr ? new_segment_length_isr_q : new_segment_length_q),
      .parent_offset_i(current_operation_is_isr ? parent_offset_isr : parent_offset),
      .capability_type_i(current_operation_is_isr ? intended_capability_type_isr_q : intended_capability_type_q),

      .rng_interface_rng_valid(rng_interface.rng_valid),
      .rng_interface_rng_out(rng_interface.rng_out),
      .rng_interface_rng_consumer_ready(create_cap_rng_consumer_ready),

      .idle_check_occupied_event_o(idle_check_occupied_event),

      .device_id_i(current_operation_is_isr ? current_device_id_isr_q : current_device_id_q),
      .task_id_i  (current_operation_is_isr ? current_task_id_isr_q : current_task_id_q),

      .is_irq_i(current_operation_is_isr),

      .capability_token_right_i(current_operation_is_isr ? aux1_reg_isr_q : aux1_reg_q),

      .zero_segment_phys_addr_o(zero_segment_phys_addr_create),
      .zero_segment_length_o(zero_segment_length_create),

      // this is NOT shared with the ISR FSM
      .inspect_restrictions_o(inspect_restrictions_d),
      .inspect_length_o(inspect_length_d),
      .inspect_permissions_o(inspect_permissions_d),
      .inspect_base_o(inspect_base_d),
      .inspect_refcount_o(inspect_refcount_d),
      // this is THE SAME AS for the ISR FSM
      .capability_count_o(capability_count),

      .cache_interface(ops_interface_create_caps),

      .wrote_any_capability_o(create_caps_wrote_any_capability),
      .written_capability_o  (create_caps_written_capability),


      .error_code_o(error_code_create_caps),

      .debug_state_o(debug_state_o),
      .debug_is_unlock_o(debug_is_unlock_o),
      .debug_input_capability_valid_o(debug_input_capability_valid_o),
      .debug_update_complete_o(debug_update_complete_o),
      .debug_capabilities_valid_o(debug_capabilities_valid_o),
      .debug_capability_token_o(debug_capability_token_o),
      .debug_capability_operation_o(debug_capability_operation_o)
  );

  // copy for use in interrupt service routines - driven by copy of registers, only provides inspect operation
  northcape_capability_ops_create_caps #(
      .HASH_TYPE(HASH_TYPE),
      .HAS_CACHE_INTERFACE(HAS_CACHE_INTERFACE),

      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      // not used
      .CAPABILITY_COUNTER_WIDTH (1),
      .CAPABILITY_COUNTER_ACTIVE(1'b0),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2),
      .IS_ISR_ONLY(1'b1),
      .OPS_TAG_METHOD(OPS_TAG_METHOD)
  ) i_northcape_capability_ops_create_caps_isr (
      .axi_master(cap_creation_intf_isr),
      .cmt_interface(cmt_interface_consumers),
      .start_i(create_cap_start_isr),
      .done_o(create_cap_done_isr),
      .error_o(create_cap_error_isr),
      .is_root_capability_i(1'b0),  // initialization done by non-IRQ FSM

      .capability_token_i(input_capability_token_isr_q),
      // not used
      .capability_token_o(),
      // only inspect is supported
      .operation_i(northcape_capability_ops_common::NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT),

      // not used
      .restriction_enabled_i(1'b0),
      .restriction_device_id_i('0),
      .restriction_task_id_i('0),
      .device_interpreted_restriction_i('0),
      .restriction_type_i(NORTHCAPE_RESTRICTIONS_NONE),


      // not used
      .read_perm_i(1'b0),
      .write_perm_i(1'b0),
      .x_perm_i(1'b0),
      .lockable_perm_i(1'b0),
      .irq_accessible_perm_i(1'b0),
      .cacheable_tlb_perm_i(1'b0),
      .cacheable_access_perm_i(1'b0),

      // read-only
      .capability_count_o(),

      // read-only
      .idle_check_occupied_event_o(),

      // only accessible in ISR context
      .is_irq_i(1'b1),


      // not used
      .direction_i(1'b0),
      .segment_length_i('0),
      .parent_offset_i('0),
      // arbitrary selection; no error type
      // not used in the FSM
      .capability_type_i(OFFSET_16_BIT),

      .rng_interface_rng_valid(1'b0),
      .rng_interface_rng_out(64'h0),
      .rng_interface_rng_consumer_ready(),

      // always refers to last request - can be shared
      .device_id_i(current_device_id_q),
      .task_id_i  (current_task_id_q),

      // not used
      .capability_token_right_i('0),

      // not used
      .zero_segment_phys_addr_o(),
      .zero_segment_length_o(),

      .inspect_restrictions_o(inspect_restrictions_isr_d),
      .inspect_length_o(inspect_length_isr_d),
      .inspect_permissions_o(inspect_permissions_isr_d),
      .inspect_base_o(inspect_base_isr_d),
      .inspect_refcount_o(inspect_refcount_isr_d),

      .cache_interface(ops_interface_irq),

      // never writes
      .wrote_any_capability_o(),
      .written_capability_o  (),

      .error_code_o(error_code_isr_create_caps),


      .debug_state_o(),
      .debug_is_unlock_o(),
      .debug_input_capability_valid_o(),
      .debug_update_complete_o(),
      .debug_capabilities_valid_o(),
      .debug_capability_token_o(),
      .debug_capability_operation_o()
  );

  //===================================
  // Cache interface arbitration
  //===================================

  generate
    if (HAS_CACHE_INTERFACE) begin : gen_cache_interface_arbiter
      // we re-use the static arbiter from the cache, but use the time-critical IRQ port instead of the resolver
      cache_interface_in_t in_create_caps;
      cache_interface_in_t in_irq;
      cache_interface_in_t out_arbited;
      logic any_request;
      northcape_capability_cache_common::northcape_capability_cache_arbitration_type_t
          arbitration_d, arbitration_q;

      /* pipeline stage for cache interface */
      logic cache_interface_request_valid_d, cache_interface_request_valid_q;
      capability_id_t
          cache_interface_request_capability_id_d, cache_interface_request_capability_id_q;
      capability_tag_t
          cache_interface_request_capability_tag_d, cache_interface_request_capability_tag_q;
      logic cache_interface_is_write_d, cache_interface_is_write_q;
      northcape_cmt_entry_t
          cache_interface_write_request_capability_d, cache_interface_write_request_capability_q;
      logic cache_interface_write_request_flush_d, cache_interface_write_request_flush_q;
      logic cache_interface_request_is_uncacheable_d, cache_interface_request_is_uncacheable_q;
      logic cache_interface_response_valid_d, cache_interface_response_valid_q;
      logic cache_interface_response_err_d, cache_interface_response_err_q;
      northcape_cmt_entry_t
          cache_interface_response_cmt_entry_d, cache_interface_response_cmt_entry_q;


      assign in_create_caps.request_capability_id = ops_interface_create_caps.request_capability_id;
      assign in_create_caps.request_capability_tag = ops_interface_create_caps.request_capability_tag;
      assign in_create_caps.is_write = ops_interface_create_caps.is_write;
      assign in_create_caps.write_request_capability = ops_interface_create_caps.write_request_capability;
      assign in_create_caps.write_request_flush = ops_interface_create_caps.write_request_flush;
      assign in_create_caps.request_is_uncacheable = ops_interface_create_caps.request_is_uncacheable;

      assign in_irq.request_capability_id = ops_interface_irq.request_capability_id;
      assign in_irq.request_capability_tag = ops_interface_irq.request_capability_tag;
      assign in_irq.is_write = ops_interface_irq.is_write;
      assign in_irq.write_request_capability = ops_interface_irq.write_request_capability;
      assign in_irq.write_request_flush = ops_interface_irq.write_request_flush;
      assign in_irq.request_is_uncacheable = ops_interface_irq.request_is_uncacheable;

      northcape_capability_cache_arbiter #(
          .arbitration_type_t(cache_interface_in_t)
      ) i_cache_interface_arbiter (
          .clk_i(clk_i),
          .rst_ni(rst_ni),
          .input_resolver_i(in_irq),
          .input_ops_i(in_create_caps),
          .request_resolver_i(ops_interface_irq.request_valid),
          .request_ops_i(ops_interface_create_caps.request_valid),
          /* it is only over when the requester has SEEN the response */
          .operation_complete_i(cache_interface_response_valid_q),

          .arbited_input_o(out_arbited),
          .any_request_o(any_request),
          .arbitration_result_o(arbitration_d)
      );

      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : cachePipelineRegs
        if (~rst_ni) begin
          cache_interface_request_valid_q <= 1'b0;
          cache_interface_request_capability_id_q <= '0;
          cache_interface_request_capability_tag_q <= '0;
          cache_interface_is_write_q <= 1'b0;
          cache_interface_write_request_capability_q <= '0;
          cache_interface_write_request_flush_q <= 1'b0;
          cache_interface_request_is_uncacheable_q <= 1'b0;
          cache_interface_response_valid_q <= 1'b0;
          cache_interface_response_err_q <= 1'b0;
          cache_interface_response_cmt_entry_q <= '0;
          arbitration_q <= northcape_capability_cache_common::NORTHCAPE_CAP_CACHE_RESOLVER;
        end else begin
          cache_interface_request_valid_q <= cache_interface_request_valid_d;
          cache_interface_request_capability_id_q <= cache_interface_request_capability_id_d;
          cache_interface_request_capability_tag_q <= cache_interface_request_capability_tag_d;
          cache_interface_is_write_q <= cache_interface_is_write_d;
          cache_interface_write_request_capability_q <= cache_interface_write_request_capability_d;
          cache_interface_write_request_flush_q <= cache_interface_write_request_flush_d;
          cache_interface_request_is_uncacheable_q <= cache_interface_request_is_uncacheable_d;
          cache_interface_response_valid_q <= cache_interface_response_valid_d;
          cache_interface_response_err_q <= cache_interface_response_err_d;
          cache_interface_response_cmt_entry_q <= cache_interface_response_cmt_entry_d;
          arbitration_q <= arbitration_d;
        end
      end : cachePipelineRegs

      always_comb begin : cachePipelineLogic
        cache_interface_request_valid_d = cache_interface_request_valid_q;
        cache_interface_request_capability_id_d = cache_interface_request_capability_id_q;
        cache_interface_request_capability_tag_d = cache_interface_request_capability_tag_q;
        cache_interface_is_write_d = cache_interface_is_write_q;
        cache_interface_write_request_capability_d = cache_interface_write_request_capability_q;
        /* can only come from "real" create caps, and technically after arbitration */
        cache_interface_write_request_flush_d = ops_interface_create_caps.write_request_flush;
        cache_interface_request_is_uncacheable_d = cache_interface_request_is_uncacheable_q;

        /* always forward to registers */
        cache_interface_response_valid_d = cache_interface.response_valid;
        cache_interface_response_err_d = cache_interface.response_err;
        cache_interface_response_cmt_entry_d = cache_interface.response_cmt_entry;

        if (cache_interface_response_valid_q || cache_interface.response_valid) begin
          /* pipelined response -> do NOT request the same ID again, this will cause a race condition in the cache */
          cache_interface_request_valid_d = 1'b0;
        end else begin
          /* forward arbited request */
          cache_interface_request_valid_d = any_request;
          cache_interface_request_capability_id_d = out_arbited.request_capability_id;
          cache_interface_request_capability_tag_d = out_arbited.request_capability_tag;
          cache_interface_is_write_d = out_arbited.is_write;
          cache_interface_write_request_capability_d = out_arbited.write_request_capability;
          cache_interface_request_is_uncacheable_d = out_arbited.request_is_uncacheable;
        end
      end : cachePipelineLogic

      assign cache_interface.request_valid = cache_interface_request_valid_q;
      assign cache_interface.request_capability_id = cache_interface_request_capability_id_q;
      assign cache_interface.request_capability_tag = cache_interface_request_capability_tag_q;
      assign cache_interface.is_write = cache_interface_is_write_q;
      assign cache_interface.write_request_capability = cache_interface_write_request_capability_q;
      assign cache_interface.write_request_flush = cache_interface_write_request_flush_q;
      assign cache_interface.request_is_uncacheable = cache_interface_request_is_uncacheable_q;


      assign ops_interface_create_caps.response_valid = (arbitration_q == northcape_capability_cache_common::NORTHCAPE_CAP_CACHE_OPS) & cache_interface_response_valid_q;
      assign ops_interface_create_caps.response_err = cache_interface_response_err_q;
      assign ops_interface_create_caps.response_cmt_entry = cache_interface_response_cmt_entry_q;

      assign ops_interface_irq.response_valid = (arbitration_q == northcape_capability_cache_common::NORTHCAPE_CAP_CACHE_RESOLVER) & cache_interface_response_valid_q;
      assign ops_interface_irq.response_err = cache_interface_response_err_q;
      assign ops_interface_irq.response_cmt_entry = cache_interface_response_cmt_entry_q;

    end : gen_cache_interface_arbiter
    else begin : gen_cache_interface_tieoffs
      assign cache_interface.request_valid = 1'b0;
      assign cache_interface.request_capability_id = '0;
      assign cache_interface.request_capability_tag = '0;
      assign cache_interface.is_write = 1'b0;
      assign cache_interface.write_request_capability = '0;
      assign cache_interface.write_request_flush = 1'b0;
      assign cache_interface.request_is_uncacheable = 1'b0;

      assign ops_interface_create_caps.response_valid = 1'b0;
      assign ops_interface_create_caps.response_err = 1'b0;
      assign ops_interface_create_caps.response_cmt_entry = '0;

      assign ops_interface_irq.response_valid = 1'b0;
      assign ops_interface_irq.response_err = 1'b0;
      assign ops_interface_irq.response_cmt_entry = '0;
    end : gen_cache_interface_tieoffs
  endgenerate
  //===================================
  // Capability/CMT zero module
  //===================================
  northcape_capability_ops_zero_main_mem_segment #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) i_northcape_capability_ops_zero_main_mem_segment (
      .axi_master(revocation_intf),

      .segment_phys_addr_i(zero_segment_phys_addr),
      .segment_length_i(zero_segment_length),

      .start_i(zero_segment_start),
      .done_o(zero_segment_done),
      .debug_state_o(zero_segment_debug_state_o),
      .debug_zero_len_o(debug_zero_len_o)
  );
  //===================================
  // TRNG register module
  //===================================
  northcape_capability_ops_trng_reg #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
  ) i_northcape_capability_ops_trng_reg (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      /* prevent using the same RNG output for register and key */
      .rng_interface_rng_valid(rng_interface.rng_valid & reset_done_d),
      .rng_interface_rng_out(rng_interface.rng_out),
      .rng_interface_rng_consumer_ready(rng_reg_consumer_ready),
      .trng_reg_o(trng_reg),
      .clear_i(trng_reg_clear)
  );

  // FF for FSM
  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : stateQFF
    if (rst_ni == 0) begin
      state_q <= RESET;
      // reset handled by main state machine
      isr_state_q <= IDLE;
      error_code_q <= NORTHCAPE_NO_ERROR;
      error_code_isr_q <= NORTHCAPE_NO_ERROR;
    end else begin
      state_q <= state_d;
      isr_state_q <= isr_state_d;
      error_code_q <= error_code_d;
      error_code_isr_q <= error_code_isr_d;
    end
  end : stateQFF

  assign cmt_interface.reset_done = reset_done_q;
  assign cmt_interface.cmt_base = INITIAL_CMT_BASE;
  assign cmt_interface.table_size_clog2 = INITIAL_CMT_SIZE_CLOG2;
  // flush caches when we finish writing zeros to prevent data being leaked through caches
  assign cmt_interface.need_flush_data_caches = zero_segment_done;
  assign cmt_interface.wrote_any_capability = create_caps_wrote_any_capability;
  assign cmt_interface.written_capability = create_caps_written_capability;

  assign reset_done_d = (state_q == IDLE) ? 1'b1 : reset_done_q;

  // FF for reset done
  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : resetDoneFF
    if (rst_ni == 0) begin
      reset_done_q <= 0;
    end else begin
      reset_done_q <= reset_done_d;
    end
  end : resetDoneFF

  // FF for interface state
  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : interfaceStateFF
    if (rst_ni == 1'b0) begin
      interface_state_q <= INTERFACE_IDLE;
    end else begin
      interface_state_q <= interface_state_d;
    end
  end : interfaceStateFF

  // FFs for ISR inspect metadata out
  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : ISRinspectFFs
    if (rst_ni == 0) begin
      inspect_base_isr_q <= '0;
      inspect_length_isr_q <= '0;
      inspect_restrictions_isr_q <= '0;
      inspect_permissions_isr_q <= '0;
      inspect_refcount_isr_q <= '0;
    end else begin
      inspect_base_isr_q <= inspect_base_isr_d1;
      inspect_length_isr_q <= inspect_length_isr_d1;
      inspect_restrictions_isr_q <= inspect_restrictions_isr_d1;
      inspect_permissions_isr_q <= inspect_permissions_isr_d1;
      inspect_refcount_isr_q <= inspect_refcount_isr_d1;
    end
  end : ISRinspectFFs

  generate
    // CSR interface is 1-cycle, so no need to buffer address
    if (MMIO_INTERFACE_SUPPORTED) begin : gen_addr_regs
      // FFs for last addresses
      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : lastAddrFFs
        if (rst_ni == 0) begin
          last_araddr_q <= '0;
          last_awaddr_q <= '0;
        end else begin
          last_araddr_q <= last_araddr_d;
          // TODO there is a tooling bug in XSim
          // I cannot move this to combinational logic without breaking it
          last_awaddr_q <= axi_slave.awvalid && !axi_slave.awready ? axi_slave.awaddr : last_awaddr_q;
        end
      end
    end : gen_addr_regs
    else begin : gen_no_addr_regs
      assign last_araddr_q = '0;
      assign last_awaddr_q = '0;
    end : gen_no_addr_regs
  endgenerate

  // FFs for device/task
  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : deviceTaskFFs
    if (rst_ni == 0) begin
      current_device_id_q <= 0;
      current_task_id_q <= 0;

      current_device_id_isr_q <= 0;
      current_task_id_isr_q <= 0;
    end else begin
      current_device_id_q <= current_device_id_d;
      current_task_id_q <= current_task_id_d;

      current_device_id_isr_q <= current_device_id_isr_d;
      current_task_id_isr_q <= current_task_id_isr_d;
    end
  end : deviceTaskFFs

  function capability_type_t decode_capability_type(logic [1:0] capability_type);
    unique case (capability_type)
      OFFSET_24_BIT: return OFFSET_24_BIT;
      OFFSET_16_BIT: return OFFSET_16_BIT;
      OFFSET_8_BIT: return OFFSET_8_BIT;
      default: return OFFSET_32_BIT;
    endcase
  endfunction

  function northcape_restriction_type_t decode_restriction_type(logic [2:0] restriction_type);
    unique case (restriction_type)
      NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED: return NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED;
      NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND: return NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND;
      NORTHCAPE_RESTRICTIONS_SET_TASK_ID: return NORTHCAPE_RESTRICTIONS_SET_TASK_ID;
      default: return NORTHCAPE_RESTRICTIONS_NONE;
    endcase
  endfunction

  assign parent_offset = aux1_reg_q[31:0];
  assign parent_offset_isr = aux1_reg_isr_q[31:0];

  // FFs for MMIO inputs
  // the last one we latch is what we will end up using
  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : mmioInFFs
    if (rst_ni == 1'b0) begin
      input_capability_token_q <= '0;

      restriction_register_q <= '0;

      direction_q <= '0;
      new_segment_length_q <= '0;

      intended_capability_type_q <= OFFSET_32_BIT;

      restriction_enabled_q <= '0;

      read_perm_q <= '0;
      write_perm_q <= '0;
      x_perm_q <= '0;
      lockable_perm_q <= '0;
      irq_accessible_perm_q <= '0;
      cacheable_tlb_perm_q <= '0;
      cacheable_access_perm_q <= '0;

      requested_operation_q <= NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE;

      restriction_type_q <= NORTHCAPE_RESTRICTIONS_NONE;

      aux1_reg_q <= '0;


      input_capability_token_isr_q <= '0;

      restriction_register_isr_q <= '0;

      direction_isr_q <= '0;
      new_segment_length_isr_q <= '0;

      intended_capability_type_isr_q <= OFFSET_32_BIT;

      restriction_enabled_isr_q <= '0;

      read_perm_isr_q <= '0;
      write_perm_isr_q <= '0;
      x_perm_isr_q <= '0;
      lockable_perm_isr_q <= '0;
      irq_accessible_perm_isr_q <= '0;
      cacheable_tlb_perm_isr_q <= '0;
      cacheable_access_perm_isr_q <= '0;

      requested_operation_isr_q <= NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE;

      restriction_type_isr_q <= NORTHCAPE_RESTRICTIONS_NONE;

      aux1_reg_isr_q <= '0;
    end else begin
      input_capability_token_q <= input_capability_token_d;

      restriction_register_q <= restriction_register_d;

      direction_q <= direction_d;
      new_segment_length_q <= new_segment_length_d;

      intended_capability_type_q <= intended_capability_type_d;

      restriction_enabled_q <= restriction_enabled_d;

      read_perm_q <= read_perm_d;
      write_perm_q <= write_perm_d;
      x_perm_q <= x_perm_d;
      lockable_perm_q <= lockable_perm_d;
      irq_accessible_perm_q <= irq_accessible_perm_d;
      cacheable_tlb_perm_q <= cacheable_tlb_perm_d;
      cacheable_access_perm_q <= cacheable_access_perm_d;

      requested_operation_q <= requested_operation_d;

      restriction_type_q <= restriction_type_d;

      aux1_reg_q <= aux1_reg_d;

      input_capability_token_isr_q <= input_capability_token_isr_d;

      restriction_register_isr_q <= restriction_register_isr_d;

      direction_isr_q <= direction_isr_d;
      new_segment_length_isr_q <= new_segment_length_isr_d;

      intended_capability_type_isr_q <= intended_capability_type_isr_d;

      restriction_enabled_isr_q <= restriction_enabled_isr_d;

      read_perm_isr_q <= read_perm_isr_d;
      write_perm_isr_q <= write_perm_isr_d;
      x_perm_isr_q <= x_perm_isr_d;
      lockable_perm_isr_q <= lockable_perm_isr_d;
      irq_accessible_perm_isr_q <= irq_accessible_perm_isr_d;
      cacheable_tlb_perm_isr_q <= cacheable_tlb_perm_isr_d;
      cacheable_access_perm_isr_q <= cacheable_access_perm_isr_d;

      requested_operation_isr_q <= requested_operation_isr_d;

      restriction_type_isr_q <= restriction_type_isr_d;

      aux1_reg_isr_q <= aux1_reg_isr_d;
    end
  end : mmioInFFs

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : isrOutputBufRegs
    if (rst_ni == 1'b0) begin
      create_cap_output_token_buf_q <= '0;
      create_cap_inspect_restrictions_buf_q <= '0;
      create_cap_inspect_length_buf_q <= '0;
      create_cap_inspect_base_buf_q <= '0;
      create_cap_inspect_permissions_buf_q <= '0;
      create_cap_inspect_refcount_buf_q <= '0;

      output_capability_token_mmio_isr_q <= '0;
    end else begin
      create_cap_output_token_buf_q <= create_cap_output_token_buf_d;
      create_cap_inspect_restrictions_buf_q <= create_cap_inspect_restrictions_buf_d;
      create_cap_inspect_length_buf_q <= create_cap_inspect_length_buf_d;
      create_cap_inspect_base_buf_q <= create_cap_inspect_base_buf_d;
      create_cap_inspect_permissions_buf_q <= create_cap_inspect_permissions_buf_d;
      create_cap_inspect_refcount_buf_q <= create_cap_inspect_refcount_buf_d;

      output_capability_token_mmio_isr_q <= output_capability_token_mmio_isr_d;
    end
  end : isrOutputBufRegs


  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : statCountRegs
    if (rst_ni == 1'b0) begin
      idle_check_count_q <= '0;
      idle_check_count_isr_q <= '0;

      create_cycles_q <= '0;
      create_cycles_isr_q <= '0;
    end else begin
      idle_check_count_q <= idle_check_count_d;
      idle_check_count_isr_q <= idle_check_count_isr_d;

      create_cycles_q <= create_cycles_d;
      create_cycles_isr_q <= create_cycles_isr_d;
    end
  end : statCountRegs

  assign zero_segment_phys_addr_cmt = INITIAL_CMT_BASE;
  assign zero_segment_length_cmt = (1 << INITIAL_CMT_SIZE_CLOG2) * $bits(northcape_cmt_entry_t) / 8;

  always_comb begin : zeroSegmentInputLogic
    zero_segment_phys_addr = (state_q == ZERO_CMT) ? zero_segment_phys_addr_cmt : zero_segment_phys_addr_create;
    zero_segment_length = (state_q == ZERO_CMT) ? zero_segment_length_cmt : zero_segment_length_create;
  end : zeroSegmentInputLogic

  always_comb begin : ISRinspectRestrictionsLogic
    // maintain
    inspect_base_isr_d1 = inspect_base_isr_q;
    inspect_length_isr_d1 = inspect_length_isr_q;
    inspect_restrictions_isr_d1 = inspect_restrictions_isr_q;
    inspect_permissions_isr_d1 = inspect_permissions_isr_q;
    inspect_refcount_isr_d1 = inspect_refcount_isr_q;

    unique case (isr_state_q)
      IDLE: begin
        // consumed - reset
        inspect_base_isr_d1 = '0;
        inspect_length_isr_d1 = '0;
        inspect_restrictions_isr_d1 = '0;
        inspect_permissions_isr_d1 = '0;
        inspect_refcount_isr_d1 = '0;
      end
      CREATE_CAP: begin
        // latch
        inspect_base_isr_d1 = inspect_base_isr_d;
        inspect_length_isr_d1 = inspect_length_isr_d;
        inspect_restrictions_isr_d1 = inspect_restrictions_isr_d;
        inspect_permissions_isr_d1 = inspect_permissions_isr_d;
        inspect_refcount_isr_d1 = inspect_refcount_isr_d;
      end
      default: begin
        // default assignment above
      end
    endcase
  end : ISRinspectRestrictionsLogic

  always_comb begin : outputTokenLogicISR
    output_capability_token_mmio_isr_d = output_capability_token_mmio_isr_q;

    unique case (isr_state_q)
      IDLE: begin
        output_capability_token_mmio_isr_d = '0;
      end
      CREATE_CAP: begin
        // do not leak non-ISR tokens here
        if (create_cap_done && current_operation_is_isr) begin
          output_capability_token_mmio_isr_d = output_capability_token_d1;
        end
      end
      REPORT_ERROR: begin
        output_capability_token_mmio_isr_d = '0;
      end
      default: begin
        // default assignment above
      end
    endcase
  end : outputTokenLogicISR

  always_comb begin : addrLatchLogic
    if (MMIO_INTERFACE_SUPPORTED) begin
      if (axi_slave.arvalid && !axi_slave.arready) begin
        last_araddr_d = axi_slave.araddr;
      end else begin
        last_araddr_d = last_araddr_q;
      end
    end
  end : addrLatchLogic

  always_comb begin : deviceTaskIdLatchLogic
    unique case (state_q)
      IDLE: begin
        if (arbiter_grant == MMIO_GRANT) begin
          current_device_id_d = current_device_task_interface.active_device;
          current_task_id_d   = current_device_task_interface.active_task;
        end else begin
          if (csr_req_i.req_valid && !csr_req_i.is_irq) begin
            current_device_id_d = csr_req_i.device_id;
            current_task_id_d   = csr_req_i.task_id;
          end else begin
            current_device_id_d = current_device_id_q;
            current_task_id_d   = current_task_id_q;
          end
        end
      end
      default: begin
        // hold on to last value
        // last value was read on operation start
        current_device_id_d = current_device_id_q;
        current_task_id_d   = current_task_id_q;
      end
    endcase
  end : deviceTaskIdLatchLogic


  always_comb begin : deviceTaskIdLatchLogicISR
    unique case (isr_state_q)
      IDLE: begin
        if (arbiter_grant == MMIO_GRANT) begin
          current_device_id_isr_d = current_device_task_interface.active_device;
          current_task_id_isr_d   = current_device_task_interface.active_task;
        end else begin
          if (csr_req_i.req_valid && csr_req_i.is_irq) begin
            current_device_id_isr_d = csr_req_i.device_id;
            current_task_id_isr_d   = csr_req_i.task_id;
          end else begin
            current_device_id_isr_d = current_device_id_isr_q;
            current_task_id_isr_d   = current_task_id_isr_q;
          end
        end
      end
      default: begin
        // hold on to last value
        // last value was read on operation start
        current_device_id_isr_d = current_device_id_isr_q;
        current_task_id_isr_d   = current_task_id_isr_q;
      end
    endcase
  end : deviceTaskIdLatchLogicISR

  always_comb begin : mmioParsingLogic
    input_capability_token_d = input_capability_token_q;
    input_capability_token_isr_d = input_capability_token_isr_q;
    restriction_register_d = restriction_register_q;
    restriction_register_isr_d = restriction_register_isr_q;
    aux1_reg_d = aux1_reg_q;
    aux1_reg_isr_d = aux1_reg_isr_q;
    restriction_type_d = restriction_type_q;
    restriction_type_isr_d = restriction_type_isr_q;
    intended_capability_type_d = intended_capability_type_q;
    intended_capability_type_isr_d = intended_capability_type_isr_q;
    direction_d = direction_q;
    direction_isr_d = direction_isr_q;
    new_segment_length_d = new_segment_length_q;
    new_segment_length_isr_d = new_segment_length_isr_q;
    restriction_enabled_d = restriction_enabled_q;
    restriction_enabled_isr_d = restriction_enabled_isr_q;

    read_perm_d = read_perm_q;
    read_perm_isr_d = read_perm_isr_q;
    write_perm_d = write_perm_q;
    write_perm_isr_d = write_perm_isr_q;
    x_perm_d = x_perm_q;
    x_perm_isr_d = x_perm_isr_q;
    lockable_perm_d = lockable_perm_q;
    lockable_perm_isr_d = lockable_perm_isr_q;
    irq_accessible_perm_d = irq_accessible_perm_q;
    irq_accessible_perm_isr_d = irq_accessible_perm_isr_q;
    cacheable_tlb_perm_d = cacheable_tlb_perm_q;
    cacheable_tlb_perm_isr_d = cacheable_tlb_perm_isr_q;
    cacheable_access_perm_d = cacheable_access_perm_q;
    cacheable_access_perm_isr_d = cacheable_access_perm_isr_q;
    requested_operation_d = requested_operation_q;
    requested_operation_isr_d = requested_operation_isr_q;

    csr_addr = csr_req_i.reg_num * AXI_LITE_DATA_WIDTH / 8;
    csr_addr[6] = csr_req_i.is_irq;


    unique case (arbiter_grant)
      MMIO_GRANT: begin
        data_in = axi_slave.wdata;
        data_in_valid = axi_slave.wvalid && axi_slave.wready;
        comp_addr_wr = last_awaddr_q;
      end
      default: begin
        data_in = csr_req_i.reg_new_val;
        data_in_valid = csr_req_i.req_valid && csr_req_i.req_type == CSR_WRITE;
        comp_addr_wr = csr_addr;
      end
    endcase

    unique case (isr_state_q)
      IDLE, MMIO_LOCKED: begin
        automatic logic task_device_match;

        if (isr_state_q == IDLE) begin
          task_device_match = 1'b1;
        end else begin
          unique case (arbiter_grant)
            MMIO_GRANT: begin
              task_device_match = current_device_task_interface.active_device == current_device_id_isr_q && current_device_task_interface.active_task == current_task_id_isr_q;
            end
            default: begin
              task_device_match = csr_req_i.device_id == current_device_id_isr_q && csr_req_i.task_id == current_task_id_isr_q;
            end
          endcase
        end

        if (isr_state_q == IDLE) begin
          // make sure that values go back to their default before next invocation
          // otherwise, if a register is not explicitly set, the last value might be copied
          input_capability_token_isr_d = '0;

          restriction_register_isr_d = '0;

          direction_isr_d = '0;
          new_segment_length_isr_d = '0;

          intended_capability_type_isr_d = OFFSET_32_BIT;

          restriction_enabled_isr_d = '0;

          read_perm_isr_d = '0;
          write_perm_isr_d = '0;
          x_perm_isr_d = '0;
          lockable_perm_isr_d = '0;
          irq_accessible_perm_isr_d = '0;
          // added later, hence in a different spot...
          cacheable_tlb_perm_isr_d = '0;
          cacheable_access_perm_isr_d = '0;

          requested_operation_isr_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE;

          aux1_reg_isr_d = '0;
        end

        if (comp_addr_wr == REG_INTERFACE_TOKEN_CTRL_STATUS_REG_ISR && data_in_valid && task_device_match) begin

          restriction_type_isr_d = decode_restriction_type(data_in[48:46]);

          intended_capability_type_isr_d = decode_capability_type(data_in[45:44]);

          direction_isr_d = data_in[43];
          new_segment_length_isr_d = data_in[42:11];

          restriction_enabled_isr_d = data_in[10];

          read_perm_isr_d = data_in[9];
          write_perm_isr_d = data_in[8];
          x_perm_isr_d = data_in[7];
          lockable_perm_isr_d = data_in[6];
          irq_accessible_perm_isr_d = data_in[5];
          // added later, hence in a different spot...
          cacheable_tlb_perm_isr_d = data_in[50];
          cacheable_access_perm_isr_d = data_in[49];


          unique case (data_in[4:0])
            NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE: begin
              requested_operation_isr_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE: begin
              requested_operation_isr_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
              requested_operation_isr_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE: begin
              requested_operation_isr_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE: begin
              requested_operation_isr_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE: begin
              requested_operation_isr_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
              requested_operation_isr_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT: begin
              requested_operation_isr_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
              requested_operation_isr_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP: begin
              requested_operation_isr_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP;
            end
            default: begin
              requested_operation_isr_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_UNKNOWN;
            end
          endcase
        end

        if (comp_addr_wr == REG_INTERFACE_TOKEN_INPUT_REG_ISR && data_in_valid && task_device_match) begin
          input_capability_token_isr_d = data_in;
        end

        if (comp_addr_wr == REG_INTERFACE_RESTRICTION_REG_ISR && data_in_valid && task_device_match) begin
          restriction_register_isr_d = data_in;
        end

        if (comp_addr_wr == REG_INTERFACE_AUX1_REG_ISR && data_in_valid && task_device_match) begin
          aux1_reg_isr_d = data_in;
        end

      end

      default: begin
        // latch values
      end
    endcase


    unique case (state_q)
      // input capability token, restriction register accepted in any order during IDLE
      // ignored afterwards
      IDLE, MMIO_LOCKED: begin
        automatic logic task_device_match;
        if (isr_state_q == IDLE) begin
          task_device_match = 1'b1;
        end else begin
          unique case (arbiter_grant)
            MMIO_GRANT: begin
              task_device_match = current_device_task_interface.active_device == current_device_id_q && current_device_task_interface.active_task == current_task_id_q;
            end
            default: begin
              task_device_match = csr_req_i.device_id == current_device_id_q && csr_req_i.task_id == current_task_id_q;
            end
          endcase
        end

        if (state_q == IDLE) begin
          // make sure that values go back to their default before next invocation
          // otherwise, if a register is not explicitly set, the last value might be copied
          input_capability_token_d = '0;

          restriction_register_d = '0;

          direction_d = '0;
          new_segment_length_d = '0;

          intended_capability_type_d = OFFSET_32_BIT;

          restriction_enabled_d = '0;

          read_perm_d = '0;
          write_perm_d = '0;
          x_perm_d = '0;
          lockable_perm_d = '0;
          irq_accessible_perm_d = '0;
          cacheable_tlb_perm_d = '0;
          cacheable_access_perm_d = '0;

          requested_operation_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE;

          aux1_reg_d = '0;
        end

        // inputs from MMIO
        if (comp_addr_wr == REG_INTERFACE_TOKEN_INPUT_REG && data_in_valid && task_device_match) begin
          input_capability_token_d = data_in;
        end

        if (comp_addr_wr == REG_INTERFACE_RESTRICTION_REG && data_in_valid && task_device_match) begin
          restriction_register_d = data_in;
        end

        if (comp_addr_wr == REG_INTERFACE_AUX1_REG && data_in_valid && task_device_match) begin
          aux1_reg_d = data_in;
        end


        if (comp_addr_wr == REG_INTERFACE_TOKEN_CTRL_STATUS_REG && data_in_valid && task_device_match) begin

          restriction_type_d = decode_restriction_type(data_in[48:46]);

          intended_capability_type_d = decode_capability_type(data_in[45:44]);

          direction_d = data_in[43];
          new_segment_length_d = data_in[42:11];

          restriction_enabled_d = data_in[10];

          read_perm_d = data_in[9];
          write_perm_d = data_in[8];
          x_perm_d = data_in[7];
          lockable_perm_d = data_in[6];
          irq_accessible_perm_d = data_in[5];
          // added later, hence in a different spot...
          cacheable_tlb_perm_d = data_in[50];
          cacheable_access_perm_d = data_in[49];

          unique case (data_in[4:0])
            NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE: begin
              requested_operation_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE: begin
              requested_operation_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
              requested_operation_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE: begin
              requested_operation_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE: begin
              requested_operation_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE: begin
              requested_operation_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
              requested_operation_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT: begin
              requested_operation_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
              requested_operation_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP: begin
              requested_operation_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP;
            end
            default: begin
              requested_operation_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_UNKNOWN;
            end
          endcase
        end
      end
      RESET: begin
        // next operation is creation of root capability
        requested_operation_d = NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE;
      end
      default: begin
        // latch last values
      end
    endcase
  end : mmioParsingLogic

  always_comb begin : restrictionRegParser
    restriction_device_id_d = restriction_register_q[47:32];
    restriction_task_id_d = restriction_register_q[31:0];
    restriction_device_interpreted_restriction_d = restriction_register_q;

    restriction_device_id_isr_d = restriction_register_isr_q[47:32];
    restriction_task_id_isr_d = restriction_register_isr_q[31:0];
    restriction_device_interpreted_restriction_isr_d = restriction_register_isr_q;
  end : restrictionRegParser


  always_comb begin : isrOutputBufLogic
    create_cap_output_token_buf_d = create_cap_output_token_buf_q;
    create_cap_inspect_restrictions_buf_d = create_cap_inspect_restrictions_buf_q;
    create_cap_inspect_length_buf_d = create_cap_inspect_length_buf_q;
    create_cap_inspect_base_buf_d = create_cap_inspect_base_buf_q;
    create_cap_inspect_permissions_buf_d = create_cap_inspect_permissions_buf_q;
    create_cap_inspect_refcount_buf_d = create_cap_inspect_refcount_buf_q;

    if (create_cap_done && !current_operation_is_isr) begin
      // latch non-ISR values for later output, in case ISR is handled before non-ISR values are retrieved
      create_cap_output_token_buf_d = output_capability_token_d1;
      create_cap_inspect_restrictions_buf_d = inspect_restrictions_d;
      create_cap_inspect_length_buf_d = inspect_length_d;
      create_cap_inspect_base_buf_d = inspect_base_d;
      create_cap_inspect_permissions_buf_d = inspect_permissions_d;
      create_cap_inspect_refcount_buf_d = inspect_refcount_d;
    end


  end : isrOutputBufLogic

  always_comb begin : MMIOOutput
    // default outputs to MMIO
    // reg 0,2 are w-only
    for (int i = 0; i < NUM_REGS; i++) begin
      regs_in[i] = '0;
    end

    cap_ops_initialized = !(state_q inside {RESET, ZERO_CMT, CREATE_ROOT_CAP});

    // especially for revoke, there is a race condition between revocation done and the user receiving the token
    // we force the user to wait for revocation to complete here
    if(state_q == CREATE_CAP_RETURN_RESULT || state_q == CREATE_CAP_RETURN_RESULT_WAIT_READ_COMPLETE)
    begin
      regs_in[1] = create_cap_output_token_buf_q;
    end else begin
      regs_in[1] = '0;
    end

    if(requested_operation_q == NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT && (state_q == CREATE_CAP_RETURN_RESULT || state_q == CREATE_CAP_RETURN_RESULT_WAIT_READ_COMPLETE))
    begin
      // restrictions out
      regs_in[2] = create_cap_inspect_restrictions_buf_q.body;
      regs_in[3] = {
        (state_q == CREATE_CAP_RETURN_RESULT || state_q == REPORT_ERROR),
        (state_q == CREATE_CAP || state_q == CREATE_CAP_REVOKE),
        (state_q == REPORT_ERROR || arbiter_grant != MMIO_GRANT),
        13'd0,
        create_cap_inspect_restrictions_buf_q.restriction_type,
        2'd0,
        1'b0,
        create_cap_inspect_length_buf_q,
        1'b0,
        create_cap_inspect_permissions_buf_q,
        2'd0
      };
      if (state_q == REPORT_ERROR && PROVIDE_ERROR_CODES) begin
        regs_in[3][31:0] = error_code_q;
      end
      regs_in[4] = {16'h0, create_cap_inspect_refcount_buf_q, create_cap_inspect_base_buf_q};
    end else begin
      regs_in[2] = '0;
      regs_in[3] = '0;
      regs_in[3] = {
        (state_q == CREATE_CAP_RETURN_RESULT || state_q == REPORT_ERROR),
        (state_q == CREATE_CAP || state_q == CREATE_CAP_REVOKE),
        (state_q == REPORT_ERROR || arbiter_grant != MMIO_GRANT),
        61'h0
      };
      if (state_q == REPORT_ERROR && PROVIDE_ERROR_CODES) begin
        regs_in[3][31:0] = error_code_q;
      end
      regs_in[4] = '0;

      regs_in[5] = {cap_ops_initialized, 1'b0, capability_count};
    end

    regs_in[7] = {create_cycles_q, idle_check_count_q};


    // registers for the ISR state machine
    if(isr_state_q == CREATE_CAP_RETURN_RESULT || isr_state_q == CREATE_CAP_RETURN_RESULT_WAIT_READ_COMPLETE)
    begin
      regs_in[9] = output_capability_token_mmio_isr_q;
    end else begin
      regs_in[9] = '0;
    end

    if(requested_operation_isr_q == NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT && (isr_state_q == CREATE_CAP_RETURN_RESULT || isr_state_q == CREATE_CAP_RETURN_RESULT_WAIT_READ_COMPLETE))
    begin
      // restrictions out
      regs_in[10] = inspect_restrictions_isr_q.body;
      regs_in[11] = {
        (isr_state_q == CREATE_CAP_RETURN_RESULT || isr_state_q == REPORT_ERROR),
        (isr_state_q == CREATE_CAP || isr_state_q == CREATE_CAP_REVOKE),
        isr_state_q == REPORT_ERROR || arbiter_grant != MMIO_GRANT,
        13'd0,
        inspect_restrictions_isr_q.restriction_type,
        2'd0,
        1'b0,
        inspect_length_isr_q,
        1'b0,
        inspect_permissions_isr_q,
        2'd0
      };
      if (isr_state_q == REPORT_ERROR && PROVIDE_ERROR_CODES) begin
        regs_in[11][31:0] = error_code_isr_q;
      end
      regs_in[12] = {16'h0, inspect_refcount_isr_q, inspect_base_isr_q};
    end else begin
      regs_in[10] = '0;
      regs_in[11] = '0;
      regs_in[11] = {
        (isr_state_q == CREATE_CAP_RETURN_RESULT || isr_state_q == REPORT_ERROR),
        (isr_state_q == CREATE_CAP || isr_state_q == CREATE_CAP_REVOKE),
        isr_state_q == REPORT_ERROR || arbiter_grant != MMIO_GRANT,
        61'h0
      };
      if (isr_state_q == REPORT_ERROR && PROVIDE_ERROR_CODES) begin
        regs_in[11][31:0] = error_code_isr_q;
      end
      regs_in[12] = '0;
      regs_in[13] = {cap_ops_initialized, 1'b0, capability_count};
    end

    regs_in[6]  = trng_reg;
    regs_in[15] = {create_cycles_isr_q, idle_check_count_isr_q};
    regs_in[14] = trng_reg;

    // locking check - non-ISR half
    if(MMIO_INTERFACE_SUPPORTED && arbiter_grant == MMIO_GRANT && (state_q == IDLE || (current_device_id_q == current_device_task_interface.active_device && current_task_id_q == current_device_task_interface.active_task)))
    begin
      for (int i = 0; i < NUM_REGS / 2; i++) begin
        // all registers are read as "error"
        regs_in_mmio[i] = regs_in[i];
      end
    end else begin
      for (int i = 0; i < NUM_REGS / 2; i++) begin
        // all registers are read as "error"
        regs_in_mmio[i] = {1'b1, 1'b0, 1'b1, 61'h0};
      end
    end

    // locking check - non-ISR half
    if(MMIO_INTERFACE_SUPPORTED && arbiter_grant == MMIO_GRANT && (isr_state_q == IDLE || (current_device_id_isr_q == current_device_task_interface.active_device && current_task_id_isr_q == current_device_task_interface.active_task)))
    begin
      for (int i = NUM_REGS / 2; i < NUM_REGS; i++) begin
        // all registers are read as "error"
        regs_in_mmio[i] = regs_in[i];
      end
    end else begin
      for (int i = NUM_REGS / 2; i < NUM_REGS; i++) begin
        // all registers are read as "error"
        regs_in_mmio[i] = {1'b1, 1'b0, 1'b1, 61'h0};
      end
    end

  end : MMIOOutput

  always_comb begin : CSROutput

    if (CSR_INTERFACE_SUPPORTED && arbiter_grant == CSR_GRANT) begin
      if (csr_req_i.is_irq) begin
        // grant is valid or ignored
        csr_rsp_o.ok = arbiter_grant == CSR_GRANT && csr_req_i.reg_num <= REG_INTERFACE_COUNT_STATS_REG/(AXI_LITE_DATA_WIDTH/8) && (isr_state_q == IDLE || (csr_req_i.task_id == current_task_id_isr_q && csr_req_i.device_id == current_device_id_isr_q));
        csr_rsp_o.reg_old_val = regs_in[csr_req_i.reg_num+8];
        if (csr_req_i.reg_num == 3) begin
          // clear error bit intended for MMIO
          csr_rsp_o.reg_old_val[61] = isr_state_q == REPORT_ERROR;
          if (~csr_rsp_o.ok) begin
            csr_rsp_o.reg_old_val[31:0] = NORTHCAPE_ERR_MMIO_LOCKED;
          end
        end else if (~csr_rsp_o.ok) begin
          csr_rsp_o.reg_old_val = '0;
        end
      end else begin
        // grant is valid or ignored
        csr_rsp_o.ok = arbiter_grant == CSR_GRANT && csr_req_i.reg_num <= REG_INTERFACE_COUNT_STATS_REG/(AXI_LITE_DATA_WIDTH/8) && (state_q == IDLE || (csr_req_i.task_id == current_task_id_q && csr_req_i.device_id == current_device_id_q));
        csr_rsp_o.reg_old_val = regs_in[csr_req_i.reg_num];
        if (csr_req_i.reg_num == 3) begin
          // clear error bit intended for MMIO
          csr_rsp_o.reg_old_val[61] = state_q == REPORT_ERROR;
          if (~csr_rsp_o.ok) begin
            csr_rsp_o.reg_old_val[31:0] = NORTHCAPE_ERR_MMIO_LOCKED;
          end
        end else if (~csr_rsp_o.ok) begin
          csr_rsp_o.reg_old_val = '0;
        end
      end
    end else begin
      csr_rsp_o = '0;
    end

  end : CSROutput
  always_comb begin : interfaceArbiter
    unique case ({
      MMIO_INTERFACE_SUPPORTED, CSR_INTERFACE_SUPPORTED
    })
      2'b01:   arbiter_grant = CSR_GRANT;
      2'b10:   arbiter_grant = MMIO_GRANT;
      2'b11: begin
        // CPU is the most important user, so it is always given precedence
        // however, we default to MMIO, as the CSR 
        unique case ({
          axi_slave.arvalid | axi_slave.awvalid, csr_req_i.req_valid
        })
          2'b01, 2'b11: arbiter_grant = CSR_GRANT;
          default: arbiter_grant = MMIO_GRANT;
        endcase
      end
      default: arbiter_grant = NO_GRANT;

    endcase
  end : interfaceArbiter

  // TODO this tracking assumes no concurrent reads, which is something the current FSMs do not do anyway
  always_comb begin : interfaceStateLogic
    interface_state_d = interface_state_q;

    unique case (interface_state_q)
      INTERFACE_IDLE: begin
        if (axi_master.arvalid) begin
          // ARVALID commences read - need to finish the read
          interface_state_d = INTERFACE_BUSY_READ;
        end
      end
      default: begin
        if (axi_master.rvalid && axi_master.rready && axi_master.rlast && !axi_master.arvalid) begin
          // last read beat accepted and no new read started - interface is idle
          interface_state_d = INTERFACE_IDLE;
        end
      end

    endcase

  end : interfaceStateLogic


  // FFs for AXI master interface
  always_comb begin : axiArbiterLogic
    // static/default values
    axi_master.atop_type = ATOMIC_NONE;
    axi_master.atop_subtype = '0;

    axi_master.awid = '0;
    axi_master.awaddr = '0;
    axi_master.awlen = '0;
    axi_master.awsize = $clog2(AXI_DATA_WIDTH / 8);
    axi_master.awburst = INCR;
    axi_master.awlock = 0;
    axi_master.awcache = '0;
    axi_master.awprot = '0;
    axi_master.awqos = '0;
    axi_master.awregion = '0;
    axi_master.awuser = '0;
    axi_master.awvalid = 0;


    axi_master.wid = '0;
    axi_master.wdata = '0;
    axi_master.wstrb = '1;
    axi_master.wlast = 0;
    axi_master.wuser = '0;
    axi_master.wvalid = 0;

    axi_master.arid = '0;
    axi_master.araddr = '0;
    axi_master.arlen = '0;
    axi_master.arsize = '0;
    axi_master.arburst = BURST_RESERVED;
    axi_master.arlock = '0;
    axi_master.arcache = '0;
    axi_master.arprot = '0;
    axi_master.arqos = '0;
    axi_master.arregion = '0;
    axi_master.aruser = '0;
    axi_master.arvalid = '0;

    axi_master.rready = 0;

    axi_master.bready = 0;

    revocation_intf.awready = 0;

    revocation_intf.wready = 0;

    revocation_intf.bid = '0;
    revocation_intf.bresp = SLVERR;
    revocation_intf.buser = '0;
    revocation_intf.bvalid = 0;

    cap_creation_intf.arready = 0;

    cap_creation_intf.awready = 0;

    cap_creation_intf.wready = 0;

    cap_creation_intf.rid = '0;
    cap_creation_intf.rdata = '0;
    cap_creation_intf.rresp = SLVERR;
    cap_creation_intf.rlast = 0;
    cap_creation_intf.ruser = '0;
    cap_creation_intf.rvalid = 0;

    cap_creation_intf.bid = '0;
    cap_creation_intf.bresp = SLVERR;
    cap_creation_intf.buser = '0;
    cap_creation_intf.bvalid = 0;

    cap_creation_intf_isr.arready = 0;

    cap_creation_intf_isr.awready = 0;

    cap_creation_intf_isr.wready = 0;

    cap_creation_intf_isr.rid = '0;
    cap_creation_intf_isr.rdata = '0;
    cap_creation_intf_isr.rresp = SLVERR;
    cap_creation_intf_isr.rlast = 0;
    cap_creation_intf_isr.ruser = '0;
    cap_creation_intf_isr.rvalid = 0;

    cap_creation_intf_isr.bid = '0;
    cap_creation_intf_isr.bresp = SLVERR;
    cap_creation_intf_isr.buser = '0;
    cap_creation_intf_isr.bvalid = 0;

    debug_is_revoke_o = 1'b0;


    unique case (state_q)
      CREATE_CAP, CREATE_ROOT_CAP: begin
        if (interface_state_q == INTERFACE_IDLE && cap_creation_intf_isr.arvalid == 1'b1) begin
          // interface is not currently doing a read and the ISR FSM wants to read
          // it is RT-critical, so we give it the interface
          `NORTHCAPE_MAP_INTERFACES_READ(, axi_master, =, cap_creation_intf_isr);
        end else begin
          // non-ISR FSM may use the interface
          `NORTHCAPE_MAP_INTERFACES_READ(, axi_master, =, cap_creation_intf);
        end
        // ISR FSM not expected to write, so we can always map the write part of the interface to the non-ISR FSM
        `NORTHCAPE_MAP_INTERFACES_WRITE(, axi_master, =, cap_creation_intf);
      end
      ZERO_CMT, CREATE_CAP_REVOKE: begin
        debug_is_revoke_o = state_q == CREATE_CAP_REVOKE;
        // ISR FSM can use the read part of the interface during the operation
        `NORTHCAPE_MAP_INTERFACES_READ(, axi_master, =, cap_creation_intf_isr);
        // cannot read, has write-only interface
        `NORTHCAPE_MAP_INTERFACES_WRITE(, axi_master, =, revocation_intf);
      end
      default: begin
        if (isr_state_q == CREATE_CAP) begin
          if (requested_operation_isr_d == NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT) begin
            // inspect - special ISR FSM
            `NORTHCAPE_MAP_INTERFACES_READ(, axi_master, =, cap_creation_intf_isr);
          end else begin
            // non-inspect - normal FSM
            `NORTHCAPE_MAP_INTERFACES_READ(, axi_master, =, cap_creation_intf);
          end

          // ISR FSM not expected to write, so we can always map the write part of the interface to the non-ISR FSM
          `NORTHCAPE_MAP_INTERFACES_WRITE(, axi_master, =, cap_creation_intf);
        end else begin
          // does not really matter
          `NORTHCAPE_MAP_INTERFACES_READ(, axi_master, =, cap_creation_intf);
          // FSM is idle or in revoke
          `NORTHCAPE_MAP_INTERFACES_WRITE(, axi_master, =, revocation_intf);
        end

      end
    endcase
  end : axiArbiterLogic

  // start/stop signals for hierarchical FSMs
  always_comb begin : startStopLogic
    create_cap_start = (state_q == CREATE_ROOT_CAP || state_q == CREATE_CAP || (isr_state_q == CREATE_CAP && requested_operation_isr_d != NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT)) && !create_cap_done;
    // non-inspect shares the full FSM with non-ISR logic
    create_cap_start_isr = isr_state_q == CREATE_CAP && requested_operation_isr_d == NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT && !create_cap_done_isr;
    zero_segment_start = (state_q == CREATE_CAP_REVOKE && !zero_segment_done) || (state_q == ZERO_CMT && !zero_segment_done);
    zero_segment_start |= (isr_state_q == CREATE_CAP_REVOKE && !zero_segment_done) || (isr_state_q == ZERO_CMT && !zero_segment_done);
  end : startStopLogic

  // FSM next state logic for capability ops module
  always_comb begin : capOpsStateMachine
    state_d = state_q;

    error_code_d = error_code_q;

    unique case (state_q)
      RESET: begin
        if (!WAIT_FOR_MEMORY_READY || memory_ready_i) begin
          if(data_in_valid && comp_addr_wr == REG_INTERFACE_COUNT_CTRL_STATUS_REG && ((axi_slave.wstrb & {1'b1, 7'h0} != 0) || arbiter_grant != MMIO_GRANT))
          begin
`ifdef VERILATOR
            // this is to help judge whether to keep waiting for CMT reset when debugging interactively
            $display("[Cap ops] reset start!");
`endif
            // enable write
            state_d = ZERO_CMT;
          end
        end
      end
      ZERO_CMT: begin
        if (zero_segment_done) begin
          state_d = CREATE_ROOT_CAP;
        end
      end
      CREATE_ROOT_CAP: begin
        if (create_cap_done) begin
`ifdef VERILATOR
          // this is to help judge whether to keep waiting for CMT reset when debugging interactively
          $display("[Cap ops] reset done!");
`endif
          state_d = IDLE;
        end
      end
      IDLE, MMIO_LOCKED: begin
        // in case of concurrent R/W, we migth get the wrong device
        // in this case, we do not do anything
        if(data_in_valid && comp_addr_wr == REG_INTERFACE_TOKEN_CTRL_STATUS_REG && ((axi_slave.wstrb & 1 != 0) ||  arbiter_grant != MMIO_GRANT) && (current_device_task_interface.parsing_error == 1'b0 || arbiter_grant != MMIO_GRANT))
        begin
          // write to (lowest byte of) operations register
          // wait one cycle for regs to update then check what we need to do
          state_d = MMIO_PARSE_OPERATION;
        end  // careful not to lock on ISR access here!
        else if(data_in_valid && comp_addr_wr inside {REG_INTERFACE_TOKEN_INPUT_REG, REG_INTERFACE_TOKEN_OUTPUT_REG, REG_INTERFACE_RESTRICTION_REG, REG_INTERFACE_TOKEN_CTRL_STATUS_REG, REG_INTERFACE_AUX1_REG})
        begin
          // this was the first write of a sequence - lock the device
          // from now on, writes with mismatching task ID are ignored
          state_d = MMIO_LOCKED;
        end
        error_code_d = NORTHCAPE_NO_ERROR;
      end
      MMIO_PARSE_OPERATION: begin
        // have to wait for non-ISR's operation to complete
        // exception: inspect - can always proceed immediately
        if(requested_operation_isr_d == NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT || state_q != CREATE_CAP)
        begin
          state_d = CREATE_CAP;
        end
        if (requested_operation_q != NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP && requested_operation_q != NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT) begin
          if (restriction_enabled_q && restriction_type_q == NORTHCAPE_RESTRICTIONS_SET_TASK_ID) begin
            // in order to prevent arbitrary impersonation attacks, only the (semi) trusted loader task can create set-task-id capabilities with identities different from its own
            if(!((restriction_task_id_d == current_task_id_q && restriction_device_id_d == current_device_id_q) || (current_task_id_q == NORTHCAPE_LOADER_TASK_TASK_ID && current_device_id_q == NORTHCAPE_LOADER_TASK_DEVICE_ID)))
            begin
              state_d = REPORT_ERROR;
              error_code_d = NORTHCAPE_ERR_CANNOT_HIJACK_TASK_ID;
            end
          end
        end
        // need to delay one cycle for my own regs to catch up
        unique case (requested_operation_d)
          NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE,NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE: begin
            if (new_segment_length_d <= max_length_for_capability_type(
                    intended_capability_type_d
                )) begin
              state_d = state_d;
            end else begin
              // not possible
              state_d = REPORT_ERROR;
              error_code_d = NORTHCAPE_ERR_LENGTH_EXCEEDS_CAP_TYPE;
            end
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
            // no immediate error cases
            state_d = state_d;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE: begin
            // no immediate error cases
            state_d = state_d;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE: begin
            // no immediate error cases
            state_d = state_d;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE: begin
            // no immediate error cases
            state_d = state_d;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
            // no immediate error cases
            state_d = state_d;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT: begin
            // no immediate error cases
            state_d = state_d;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
            // no immediate error cases
            state_d = state_d;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP: begin
            // no immediate error cases
            state_d = state_d;
          end
          default: begin
            // unknown / invalid / ...
            state_d = REPORT_ERROR;
            error_code_d = NORTHCAPE_ERR_UNKNOWN_OPERATION;
          end
        endcase
      end
      CREATE_CAP: begin
        if (create_cap_done) begin
          if (create_cap_error) begin
            state_d = REPORT_ERROR;
            error_code_d = error_code_create_caps;
          end else if (requested_operation_q inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE}) begin
            state_d = CREATE_CAP_REVOKE;
          end else begin
            state_d = CREATE_CAP_RETURN_RESULT;
          end
        end
      end
      CREATE_CAP_RETURN_RESULT: begin
        if (arbiter_grant == MMIO_GRANT && axi_slave.arvalid && axi_slave.arready && axi_slave.araddr[AXI_LITE_COMPARE_WIDTH-1:0] == REG_INTERFACE_TOKEN_OUTPUT_REG) begin
          // read into output register
          state_d = CREATE_CAP_RETURN_RESULT_WAIT_READ_COMPLETE;
        end
        else if(arbiter_grant == CSR_GRANT && csr_req_i.req_valid && csr_req_i.req_type == CSR_READ && csr_addr == REG_INTERFACE_TOKEN_OUTPUT_REG)
        begin
          // read completes instantaneously
          state_d = IDLE;
        end
      end
      CREATE_CAP_RETURN_RESULT_WAIT_READ_COMPLETE: begin
        if (arbiter_grant == MMIO_GRANT && axi_slave.rvalid && axi_slave.rready) begin
          state_d = IDLE;
        end
      end
      CREATE_CAP_REVOKE: begin
        if (zero_segment_done) begin
          state_d = CREATE_CAP_RETURN_RESULT;
        end
      end
      REPORT_ERROR: begin
        if (arbiter_grant == MMIO_GRANT && axi_slave.rvalid && axi_slave.rready && last_araddr_q[AXI_LITE_COMPARE_WIDTH-1:0] == REG_INTERFACE_TOKEN_CTRL_STATUS_REG) begin
          // error was read by SW driver
          state_d = IDLE;
        end
        else if(arbiter_grant == CSR_GRANT && csr_req_i.req_valid && csr_req_i.req_type == CSR_READ && csr_addr == REG_INTERFACE_TOKEN_CTRL_STATUS_REG)
        begin
          state_d = IDLE;
        end
      end
      default: begin
        state_d = state_q;
      end
    endcase

  end : capOpsStateMachine

  /* clear the TRNG reg after every successful read to prevent someone else stealing (some of) the bits */
  always_comb begin : trngRegClearLogic

    unique case (arbiter_grant)
      MMIO_GRANT: begin
        trng_reg_clear = last_araddr_d == REG_INTERFACE_COUNT_TRNG_REG && axi_slave.rvalid && axi_slave.rready;
      end
      CSR_GRANT: begin
        trng_reg_clear = csr_req_i.req_valid && csr_req_i.req_type == CSR_READ && csr_req_i.reg_num == REG_INTERFACE_COUNT_TRNG_REG/(AXI_LITE_DATA_WIDTH/8);
      end
      default: begin
        trng_reg_clear = 1'b0;
      end
    endcase


  end : trngRegClearLogic

  always_comb begin : statCountLogic
    // default assignments
    idle_check_count_d = idle_check_count_q;
    idle_check_count_isr_d = idle_check_count_isr_q;

    create_cycles_d = create_cycles_q;
    create_cycles_isr_d = create_cycles_isr_q;

    unique case (state_q)
      IDLE: begin
        // new operation
        idle_check_count_d = '0;
        create_cycles_d = '0;
      end
      CREATE_CAP: begin
        idle_check_count_d += idle_check_occupied_event;
        create_cycles_d++;
      end
      CREATE_CAP_REVOKE: begin
        // still busy with the operation
        create_cycles_d++;
      end
      default: begin
        // default assignments above
      end
    endcase

    unique case (isr_state_q)
      IDLE: begin
        // new operation
        idle_check_count_isr_d = '0;
        create_cycles_isr_d = '0;
      end
      CREATE_CAP: begin
        idle_check_count_isr_d += idle_check_occupied_event;
        create_cycles_isr_d++;
      end
      CREATE_CAP_REVOKE: begin
        // still busy with the operation
        create_cycles_isr_d++;
      end
      default: begin
        // default assignments above
      end
    endcase
  end : statCountLogic

  // FSM ISR next state logic for capability ops module
  always_comb begin : capOpsStateMachineISR
    isr_state_d = isr_state_q;

    error_code_isr_d = error_code_isr_q;

    unique case (isr_state_q)
      IDLE, MMIO_LOCKED: begin
        // in case of concurrent R/W, we migth get the wrong device
        // in this case, we do not do anything
        if(data_in_valid && comp_addr_wr == REG_INTERFACE_TOKEN_CTRL_STATUS_REG_ISR && (axi_slave.wstrb & 1 != 0 || arbiter_grant != MMIO_GRANT) && (current_device_task_interface.parsing_error == 1'b0 || arbiter_grant != MMIO_GRANT))
        begin
          // write to (lowest byte of) operations register
          // wait one cycle for regs to update then check what we need to do
          isr_state_d = MMIO_PARSE_OPERATION;
        end  // careful not to conflate IRQ, non-IRQ accesses here!
        else if(data_in_valid && comp_addr_wr inside {REG_INTERFACE_TOKEN_INPUT_REG_ISR, REG_INTERFACE_TOKEN_OUTPUT_REG_ISR, REG_INTERFACE_RESTRICTION_REG_ISR, REG_INTERFACE_TOKEN_CTRL_STATUS_REG_ISR, REG_INTERFACE_AUX1_REG_ISR})
        begin
          // begin of a sequence
          // device is now locked
          isr_state_d = MMIO_LOCKED;
        end
        error_code_isr_d = NORTHCAPE_NO_ERROR;
      end
      MMIO_PARSE_OPERATION: begin
        isr_state_d = CREATE_CAP;
        if (requested_operation_isr_q != NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP && requested_operation_isr_q != NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT) begin
          if (restriction_enabled_isr_q && restriction_type_isr_q == NORTHCAPE_RESTRICTIONS_SET_TASK_ID) begin
            // in order to prevent arbitrary impersonation attacks, only the (semi) trusted loader task can create set-task-id capabilities with identities different from its own
            if(!((restriction_task_id_isr_d == current_task_id_isr_q && restriction_device_id_isr_d == current_device_id_isr_q) || (current_task_id_isr_q == NORTHCAPE_LOADER_TASK_TASK_ID && current_device_id_isr_q == NORTHCAPE_LOADER_TASK_DEVICE_ID)))
            begin
              isr_state_d = REPORT_ERROR;
              error_code_isr_d = NORTHCAPE_ERR_CANNOT_HIJACK_TASK_ID;
            end
          end
        end
        // need to delay one cycle for my own regs to catch up
        unique case (requested_operation_isr_d)
          NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE,NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE: begin
            if (new_segment_length_isr_d <= max_length_for_capability_type(
                    intended_capability_type_isr_d
                )) begin
              isr_state_d = isr_state_d;
            end else begin
              // not possible
              isr_state_d = REPORT_ERROR;
              error_code_isr_d = NORTHCAPE_ERR_LENGTH_EXCEEDS_CAP_TYPE;
            end
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
            // no immediate error cases
            isr_state_d = isr_state_d;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE: begin
            // no immediate error cases
            isr_state_d = isr_state_d;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE: begin
            // no immediate error cases
            isr_state_d = isr_state_d;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE: begin
            // no immediate error cases
            isr_state_d = isr_state_d;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
            // no immediate error cases
            isr_state_d = isr_state_d;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT: begin
            // no immediate error cases
            isr_state_d = isr_state_d;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
            // no immediate error cases
            isr_state_d = isr_state_d;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP: begin
            // no immediate error cases
            isr_state_d = isr_state_d;
          end
          default: begin
            // unknown / invalid / ...
            isr_state_d = REPORT_ERROR;
            error_code_isr_d = NORTHCAPE_ERR_UNKNOWN_OPERATION;
          end
        endcase
      end
      CREATE_CAP: begin
        if (requested_operation_isr_d == NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT) begin
          // inspect - use special inspect ISR to ensure timing
          if (create_cap_done_isr) begin
            if (create_cap_error_isr) begin
              isr_state_d = REPORT_ERROR;
              error_code_isr_d = error_code_isr_create_caps;
            end else begin
              isr_state_d = CREATE_CAP_RETURN_RESULT;
            end
          end
        end else begin
          // non-inspect - use "normal" ISR
          if (state_q != CREATE_CAP) begin
            // have to wait for non-ISR operation (if any) to finish before mine triggers
            if (create_cap_done) begin
              if (create_cap_error) begin
                isr_state_d = REPORT_ERROR;
                error_code_isr_d = error_code_create_caps;
              end else if (requested_operation_isr_q inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE}) begin
                isr_state_d = CREATE_CAP_REVOKE;
              end else begin
                isr_state_d = CREATE_CAP_RETURN_RESULT;
              end
            end
          end
        end
      end
      CREATE_CAP_RETURN_RESULT: begin
        if (axi_slave.arvalid && axi_slave.arready && axi_slave.araddr[AXI_LITE_COMPARE_WIDTH-1:0] == REG_INTERFACE_TOKEN_OUTPUT_REG_ISR) begin
          // read into output register
          isr_state_d = CREATE_CAP_RETURN_RESULT_WAIT_READ_COMPLETE;
        end
        else if(arbiter_grant == CSR_GRANT && csr_req_i.req_valid && csr_req_i.req_type == CSR_READ && csr_addr == REG_INTERFACE_TOKEN_OUTPUT_REG_ISR)
        begin
          // 1-cycle read
          isr_state_d = IDLE;
        end
      end
      CREATE_CAP_RETURN_RESULT_WAIT_READ_COMPLETE: begin
        if (axi_slave.rvalid && axi_slave.rready) begin
          isr_state_d = IDLE;
        end
      end
      CREATE_CAP_REVOKE: begin
        if (state_q != CREATE_CAP_REVOKE) begin
          // have to wait for the non-ISR FSM to complete first, it it is running
          if (zero_segment_done) begin
            isr_state_d = CREATE_CAP_RETURN_RESULT;
          end
        end
      end
      REPORT_ERROR: begin
        if (axi_slave.rvalid && axi_slave.rready && last_araddr_q[AXI_LITE_COMPARE_WIDTH-1:0] == REG_INTERFACE_TOKEN_CTRL_STATUS_REG_ISR) begin
          // error was read by SW driver
          isr_state_d = IDLE;
        end
        else if(arbiter_grant == CSR_GRANT && csr_req_i.req_valid && csr_req_i.req_type == CSR_READ && csr_addr == REG_INTERFACE_TOKEN_CTRL_STATUS_REG_ISR)
        begin
          isr_state_d = IDLE;
        end
      end
      default: begin
        isr_state_d = isr_state_q;
      end
    endcase

    current_operation_is_isr = isr_state_q != IDLE;

  end : capOpsStateMachineISR

  // IRQ must be raised when completed and lowered when the result has been acknowledged/read
  assign irq_out.irqs[0] = (state_q == REPORT_ERROR || state_q == CREATE_CAP_RETURN_RESULT || isr_state_q == REPORT_ERROR || isr_state_q == CREATE_CAP_RETURN_RESULT);

  always_comb begin : debugStateLogic
    debug_top_state_o = '0;

    unique case (state_q)
      RESET: debug_top_state_o = 4'd0;
      ZERO_CMT: debug_top_state_o = 4'd1;
      CREATE_ROOT_CAP: debug_top_state_o = 4'd2;
      MMIO_PARSE_OPERATION: debug_top_state_o = 4'd3;
      CREATE_CAP: debug_top_state_o = 4'd4;
      CREATE_CAP_RETURN_RESULT: debug_top_state_o = 4'd5;
      CREATE_CAP_RETURN_RESULT_WAIT_READ_COMPLETE: debug_top_state_o = 4'd6;
      CREATE_CAP_REVOKE: debug_top_state_o = 4'd7;
      IDLE: debug_top_state_o = 4'd8;
      REPORT_ERROR: debug_top_state_o = 4'd9;
      MMIO_LOCKED: debug_top_state_o = 4'd10;
      default: debug_top_state_o = '1;
    endcase

    debug_top_state_isr_o = '0;

    unique case (isr_state_q)
      RESET: debug_top_state_isr_o = 4'd0;
      ZERO_CMT: debug_top_state_isr_o = 4'd1;
      CREATE_ROOT_CAP: debug_top_state_isr_o = 4'd2;
      MMIO_PARSE_OPERATION: debug_top_state_isr_o = 4'd3;
      CREATE_CAP: debug_top_state_isr_o = 4'd4;
      CREATE_CAP_RETURN_RESULT: debug_top_state_isr_o = 4'd5;
      CREATE_CAP_RETURN_RESULT_WAIT_READ_COMPLETE: debug_top_state_isr_o = 4'd6;
      CREATE_CAP_REVOKE: debug_top_state_isr_o = 4'd7;
      IDLE: debug_top_state_isr_o = 4'd8;
      REPORT_ERROR: debug_top_state_isr_o = 4'd9;
      MMIO_LOCKED: debug_top_state_isr_o = 4'd10;
      default: debug_top_state_isr_o = '1;
    endcase
  end : debugStateLogic

`ifdef NORTHCAPE_TEST_COVERAGE
  covergroup capability_ops_top_level_coverage_group @(posedge clk_i);
    coverpoint state_q;
    coverpoint isr_state_q;
    coverpoint input_capability_token_q iff state_q == CREATE_CAP {
      bins special_root = {64'h00000000????????}; bins non_root = default;
    }
    coverpoint input_capability_token_isr_q iff isr_state_q == CREATE_CAP {
      bins special_root = {64'h00000000????????}; bins non_root = default;
    }
    coverpoint requested_operation_q iff state_q == CREATE_CAP;
    coverpoint create_cap_error iff state_q == CREATE_CAP;
    coverpoint create_cap_error_isr iff state_q == CREATE_CAP;
    coverpoint restriction_enabled_q iff state_q == CREATE_CAP;
    coverpoint restriction_device_id_d iff state_q == CREATE_CAP;
    coverpoint restriction_task_id_d iff state_q == CREATE_CAP;
    coverpoint current_device_task_interface.active_device iff state_q == CREATE_CAP;
    coverpoint current_device_task_interface.active_task iff state_q == CREATE_CAP;
    coverpoint read_perm_q iff state_q == CREATE_CAP;
    coverpoint write_perm_q iff state_q == CREATE_CAP;
    coverpoint x_perm_q iff state_q == CREATE_CAP;
    coverpoint irq_accessible_perm_q iff state_q == CREATE_CAP;
    coverpoint cacheable_tlb_perm_q iff state_q == CREATE_CAP;
    coverpoint cacheable_access_perm_q iff state_q == CREATE_CAP;
    coverpoint direction_q iff state_q == CREATE_CAP;
    coverpoint intended_capability_type_q iff state_q == CREATE_CAP;
    coverpoint new_segment_length_q iff state_q == CREATE_CAP {
      bins special_zero = {32'h0};
      bins mod_zero = {32'h???????0};
      bins mod_one = {32'h???????1};
      bins mod_two = {32'h???????2};
      bins mod_three = {32'h???????3};
      bins mod_four = {32'h???????4};
      bins mod_five = {32'h???????5};
      bins mod_six = {32'h???????6};
      bins mod_seven = {32'h???????7};
      bins mod_eight = {32'h???????8};
      bins mod_nine = {32'h???????9};
      bins mod_ten = {32'h???????a};
      bins mod_eleven = {32'h???????b};
      bins mod_twelve = {32'h???????c};
      bins mod_thirteen = {32'h???????d};
      bins mod_fourteen = {32'h???????e};
      bins mod_fifteen = {32'h???????f};
      bins others = default;
    }
  endgroup

  capability_ops_top_level_coverage_group cov_group;
  initial begin
    cov_group = new;
  end

`endif

  `NORTHCAPE_UNREAD(axi_master.clk_i);
  `NORTHCAPE_UNREAD(axi_master.rst_ni);
  `NORTHCAPE_UNREAD(cmt_interface.clk_i);
  `NORTHCAPE_UNREAD(current_device_task_interface.clk_i);
  `NORTHCAPE_UNREAD(irq_out.clk_i);
  `NORTHCAPE_UNREAD(rng_interface.clk_i);
  `NORTHCAPE_UNREAD(rng_interface.rst_ni);

  `NORTHCAPE_UNREAD(current_device_task_interface.device_specific_restriction);

  `NORTHCAPE_UNREAD(cache_interface.clk_i);


endmodule
