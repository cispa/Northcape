import northcape_capability_ops_common::*;
import northcape_types::*;
import northcape_cmt_parser_pkg::*;

/**
  * Part of the northcape capability resolver operations module.
  * Contains an FSM that can be used for creating (and deriving) capabilities.
  */
module northcape_capability_ops_create_caps #(
    parameter HASH_TYPE = -1,
    parameter HAS_CACHE_INTERFACE = 1'b0,

    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_ID_WIDTH   = -1,
    parameter AXI_USER_WIDTH = -1,

    parameter CAPABILITY_COUNTER_WIDTH = -1,
    parameter bit CAPABILITY_COUNTER_ACTIVE = 1'b1,

    parameter AXI_LITE_DATA_WIDTH = -1,

    parameter logic [AXI_ADDR_WIDTH-1:0] INITIAL_CMT_BASE = -1,
    parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1,
    parameter bit IS_ISR_ONLY = 1'b0,
    parameter northcape_capability_ops_common::northcape_capability_ops_tag_method_t OPS_TAG_METHOD = northcape_capability_ops_common::NORTHCAPE_CAPABILITY_OPS_CBC,
    parameter bit USE_TEST_ONLY_BRAM = 1'b0,
    parameter int BITMAP_BRAM_DATA_WIDTH = 64
) (
    Axi5.FROM axi_master,

    NorthcapeCMTInterface.CONSUMER cmt_interface,

    // capability token FROM WHICH to create a capability
    input logic [AXI_ADDR_WIDTH-1:0] capability_token_i,
    // merge has a second input
    input logic [AXI_ADDR_WIDTH-1:0] capability_token_right_i,
    // the device and requesting the create operation
    input device_id_t device_id_i,
    input task_id_t task_id_i,
    input northcape_capability_operation_t operation_i,

    input logic is_irq_i,

    // restriction for new capability
    input logic restriction_enabled_i,
    input device_id_t restriction_device_id_i,
    input task_id_t restriction_task_id_i,
    input northcape_device_interpreted_restriction_t device_interpreted_restriction_i,
    northcape_restriction_type_t restriction_type_i,

    // permissions for new capability
    input logic read_perm_i,
    input logic write_perm_i,
    input logic x_perm_i,
    input logic lockable_perm_i,
    input logic irq_accessible_perm_i,
    input logic cacheable_tlb_perm_i,
    input logic cacheable_access_perm_i,

    // new length and where to add it
    input logic direction_i,
    input segment_length_t segment_length_i,
    input segment_length_t parent_offset_i,

    // type of capability (ID) that we are supposed to create
    input capability_type_t capability_type_i,

    input  logic start_i,
    output logic done_o,

    output logic error_o,
    // capability token that we have created
    output logic [AXI_ADDR_WIDTH-1:0] capability_token_o,

    // determines whether this is the root capability - behavior is slightly different
    input logic is_root_capability_i,

    // used for revocation
    // indicate start / end of segment to be overwritten
    output northcape_physical_address_t zero_segment_phys_addr_o,
    output segment_length_t zero_segment_length_o,

    // for random values
    input logic rng_interface_rng_valid,
    input logic [NORTHCAPE_CAPABILITY_OPS_RNG_INTERFACE_BITS-1:0] rng_interface_rng_out,
    output logic rng_interface_rng_consumer_ready,

    output northcape_restrictions_t inspect_restrictions_o,
    output segment_length_t inspect_length_o,
    output segment_base_addr_t inspect_base_o,
    output northcape_direct_capability_permissions_t inspect_permissions_o,
    output northcape_reference_count_t inspect_refcount_o,

    output logic [CAPABILITY_COUNTER_WIDTH-1:0] capability_count_o,

    NorthcapeCapabilityCacheInterfaceOps.OPS_INTERFACE cache_interface,

    output logic wrote_any_capability_o,
    output northcape_types::capability_id_t written_capability_o,

    // to idle check counter
    output logic idle_check_occupied_event_o,

    output northcape_capability_ops_common::northcape_error_code_t error_code_o,


    output logic [4:0] debug_state_o,
    output logic debug_is_unlock_o,
    output logic debug_input_capability_valid_o,
    output logic [1:0] debug_update_complete_o,
    output logic [2:0] debug_capabilities_valid_o,
    /* INPUT capability token that we see */
    output logic [AXI_ADDR_WIDTH-1:0] debug_capability_token_o,
    output northcape_capability_operation_t debug_capability_operation_o
);
  import axi5::*;
  import northcape_capability_ops_common::*;
  `include "northcape_unread.vh"

  typedef NorthcapeCapabilityOpsGenerator#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .HASH_TYPE(HASH_TYPE)
  ) gen_t;

  typedef enum {
    CREATE_CAP_COMPLETE_RESET,
    CREATE_CAP_PREPARE_RESET_BITMAP,
    CREATE_CAP_RESET_BITMAP,
    CREATE_CAP_COLLECT_ENTROPY_HIGH,
    CREATE_CAP_COLLECT_ENTROPY_LOW,
    CREATE_CAP_CREATE_QARMA_KEY_HIGH,
    CREATE_CAP_WAIT_QARMA_KEY_HIGH,
    CREATE_CAP_CREATE_QARMA_KEY_LOW,
    CREATE_CAP_WAIT_QARMA_KEY_LOW,
    CREATE_CAP_CREATE_INITIAL_NONCE,
    CREATE_CAP_WAIT_INITIAL_NONCE,
    CREATE_CAP_IDLE,
    CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY,
    CREATE_CAP_GET_INPUT_CAPABILITY,
    CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY_RIGHT,
    CREATE_CAP_GET_INPUT_CAPABILITY_RIGHT,
    CREATE_CAP_PREPARE_RECURSE_INPUT_CAPABILITY,
    CREATE_CAP_RECURSE_INPUT_CAPABILITY,
    CREATE_CAP_PREPARE_CHECK_IDLE,
    CREATE_CAP_CHECK_IDLE,
    CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY,
    CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY,
    CREATE_CAP_SETUP_WRITE_UPDATE_PARENT_CAPABILITY,
    CREATE_CAP_SETUP_WRITE_UPDATE_SECOND_INPUT_CAPABILITY,
    CREATE_CAP_WAIT_WRITE_COMPLETE,
    CREATE_CAP_WAIT_RESPONSE,
    CREATE_CAP_CBC_MAC,
    CREATE_CAP_SWEEP_GETROW,
    CREATE_CAP_SWEEP,
    CREATE_CAP_DONE,
    CREATE_CAP_ERROR
  } northcape_capability_ops_create_cap_state_t;

  // CTR has exactly one round
  localparam NUMBER_CBC_ROUNDS = OPS_TAG_METHOD == NORTHCAPE_CAPABILITY_OPS_CBC ? $bits(
      northcape_cmt_entry_t
  ) / 64 : 1;

  // CTR needs full 64 bits of width to ensure the sequence does not repeat too early
  localparam type nonce_t = logic [(OPS_TAG_METHOD == NORTHCAPE_CAPABILITY_OPS_CTR ? 64 : 16) -1 : 0];


  logic clk_i;
  logic rst_ni;

  // hierarchical state machine for creating a capability
  northcape_capability_ops_create_cap_state_t create_state_q, create_state_d;

  // FSM for creating capabilities private state
  northcape_cmt_entry_t
      capability_to_create_d,
      capability_to_create_q,
      input_capability_d,
      // input capability that actually gets persisted in the register
      input_capability_d1,
      input_capability_q,
      base_direct_capability_q,
      base_direct_capability_d,
      response_cmt_entry_q,
      response_cmt_entry_d;

  northcape_lock_key_t
      last_lock_key_q,
      last_lock_key_d,
      retrieved_lock_key_q,
      retrieved_lock_key_d,
      unlock_key_d,
      unlock_key_q;

  // bits of the capability to be created
  // as input for qarma
  logic [$bits(northcape_cmt_entry_t)-1:0] capability_to_create_raw;

  logic [AXI_ADDR_WIDTH-1:0] capability_insert_addr, input_capability_addr, recurse_capability_addr;
  capability_id_t output_capability_id_d, output_capability_id_q;
  capability_id_t sweep_capability_id_d, sweep_capability_id_q;

  // 1 when valid slot and we can use it for capability creation
  logic slot_unoccupied;

  // I circled the ID space once
  // this means we cannot insert
  logic slot_overflow_q, slot_overflow_d;

  // I can use the input capability to perform the intended operation
  northcape_error_code_t input_capability_valid;

  northcape_error_code_t error_code_q, error_code_d;

  // ID of the last capability that we used
  // starts with 0 for root capability
  // which one we use depends on the intended capability type
  capability_id_t [3:0] last_capability_id_q, last_capability_id_d;

  // starts after the last 32-bit offset id
  // capability we started searching at
  capability_id_t capability_search_start_q, capability_search_start_d;

  // the parent's capability ID
  capability_id_t create_parent_capability_id_q, create_parent_capability_id_d;

  // the ID of the base direct capability from whose tree we attempt to lock
  capability_id_t base_direct_capability_id_q, base_direct_capability_id_d;

  logic signed [CAPABILITY_COUNTER_WIDTH-1:0] capability_count_q, capability_count_d;
  logic signed [CAPABILITY_COUNTER_WIDTH-1:0] capability_count_addend;
  // 1 when this is a create where the new segment length is equal to the parent's length, i.e., the parent is destroyed in the process
  // 0 otherwise
  logic
      capability_count_create_added_new_capability_d,
      capability_count_create_added_new_capability_q;

  // have written updated capability
  logic
      update_complete_q,
      update_complete_d,
      update_complete_second_parent_q,
      update_complete_second_parent_d;

  // used to ensure we always use THE FIRST parent
  logic create_have_parent_capability_q, create_have_parent_capability_d;
  // used to ensure we have the LAST parent and that it is valid
  logic create_have_base_capability_q, create_have_base_capability_d;

  // whether we are actually unlocking a lock holder token
  logic create_drop_is_unlock_q, create_drop_is_unlock_d;

  // used to ensure we are not attempting to modify a capability that is not actually our parent
  // useful if drop is called on a capability whose parent was revoked
  logic parent_capability_is_valid_q, parent_capability_is_valid_d;

  logic [$clog2(NUMBER_CBC_ROUNDS):0] remaining_rounds_qarma_q, remaining_rounds_qarma_d;

  nonce_t current_nonce_q, current_nonce_d;

  northcape_capability_ops_mac_key_t
      collected_random_entropy_q, collected_random_entropy_d, qarma_key_q, qarma_key_d;

  logic rng_consumer_ready_d;

  northcape_mac_tag_t last_tag_q, last_tag_d;

  // input capability recursion
  cmt_parser_verdict_t recursed_capability_verdict;

  capability_id_t recurse_capability_id_d, recurse_capability_id_q;
  northcape_mac_tag_t recurse_capability_tag_q, recurse_capability_tag_d;

  // for merge
  // base and length for first input
  northcape_physical_address_t base_left_d, base_left_q;
  segment_length_t segment_length_left_d, segment_length_left_q;

  // next handshaking signals
  logic arvalid_d, rready_d;
  logic awvalid_d, wvalid_d, bready_d;
  logic [AXI_ADDR_WIDTH-1:0] araddr_d, awaddr_d;
  logic [AXI_DATA_WIDTH-1:0] wdata_d;

  // next values for phys addr / segment length
  northcape_physical_address_t zero_segment_phys_addr_d;
  segment_length_t zero_segment_length_d;

  // next values for inspect base
  segment_length_t inspect_length_d;
  segment_base_addr_t inspect_base_d;
  northcape_reference_count_t inspect_refcount_d;

  logic inspect_is_partial_reveal_d;

  // next output capability token
  logic [AXI_ADDR_WIDTH-1:0] capability_token_d;

  // CBC signalling
  logic cbc_start_d;
  logic [63:0] cbc_block_in_d;
  logic [127:0] cbc_key_d;

  // bchan-before-wchan-signalling
  logic b_chan_complete_d, b_chan_complete_q;
  axi5::axi_resp_t bresp_d, bresp_q;

  logic cache_interface_response_err_q, cache_interface_response_err_d;

  // module scope for debugging
  capability_id_t input_cap_id;
  capability_tag_t input_tag;
  capability_off_t input_offset;
  axis_validate_request_perm_t cmt_check_type;

  logic is_lock_holder_d, is_lock_holder_q;
  logic have_checked_bounds_d, have_checked_bounds_q;

  assign clk_i = axi_master.clk_i;
  assign rst_ni = axi_master.rst_ni;

  assign response_cmt_entry_d = (cache_interface.response_valid) ? cache_interface.response_cmt_entry : response_cmt_entry_q;
  assign cache_interface_response_err_d = (cache_interface.response_valid) ? cache_interface.response_err : cache_interface_response_err_q;

  localparam BITMAP_BRAM_DATA_DEPTH = (2 ** INITIAL_CMT_SIZE_CLOG2) / BITMAP_BRAM_DATA_WIDTH;
  logic [$clog2(BITMAP_BRAM_DATA_DEPTH)-1:0]
      bram_addr,
      bram_addr_initializer,
      bram_addr_deferred_d,
      bram_addr_deferred_q,
      bram_addr_deferred_q1;

  logic bram_addr_deferred_q1_valid_d, bram_addr_deferred_q1_valid_q;
  logic [BITMAP_BRAM_DATA_WIDTH-1:0]
      bram_in, bram_out, bram_out_initializer, bram_in_deferred_d, bram_in_deferred_q;
  logic
      bram_enable,
      bram_wenable,
      bram_wenable_initializer,
      bram_wenable_deferred_d,
      bram_wenable_deferred_q;

  logic bram_init_start, bram_init_busy;

  logic [$clog2(BITMAP_BRAM_DATA_WIDTH):0] bram_leading_zeros_out;
  logic [$clog2(BITMAP_BRAM_DATA_WIDTH):0] bram_leading_zeros;


  Qarma64CBCInterface qarma_intf (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  // ISR state machines does not support the operations - no need to generate quarma
  generate
    if (IS_ISR_ONLY == 1'b0) begin : genQarma
      if (OPS_TAG_METHOD == NORTHCAPE_CAPABILITY_OPS_CBC) begin : gen_cbc
        qarma64CBC i_cbc_mac (.intf(qarma_intf));
      end : gen_cbc
      else if (OPS_TAG_METHOD == NORTHCAPE_CAPABILITY_OPS_CTR) begin : gen_ctr
        qarma64Wrapper i_qarma (.intf(qarma_intf));
      end : gen_ctr
      else begin
        $error("Unknown tag method!");
      end
    end : genQarma
    else begin : genQarmaCBCDefaults
      assign qarma_intf.cbc_done = 1'b0;
      assign qarma_intf.cbc_tag  = '0;
    end : genQarmaCBCDefaults
  endgenerate

  generate
    if (IS_ISR_ONLY == 1'b0) begin : genBitmap
      if (USE_TEST_ONLY_BRAM == 1'b1) begin : gen_test_bram
        northcape_bram_driver_mod #(
            .DATA_WIDTH  (BITMAP_BRAM_DATA_WIDTH),
            .DATA_DEPTH  (BITMAP_BRAM_DATA_DEPTH),
            .INIT_TO_ZERO(1'b1),
            .WRITE_FIRST (1'b1)
        ) i_bram_driver (
            .clk_i(clk_i),

            .a_wdata_i(bram_in),
            .a_wenable_i(bram_wenable),
            .a_rdata_o(bram_out),
            .a_addr_i(bram_addr),
            .a_enable_i(bram_enable),

            .b_wdata_i(bram_in_deferred_d),
            .b_wenable_i(bram_wenable_deferred_q),
            .b_rdata_o(  /*not used */),
            .b_addr_i(bram_addr_deferred_q),
            .b_enable_i(bram_wenable_deferred_q)

        );
      end : gen_test_bram
      else begin : gen_real_bram
        northcape_sram_dport #(
            .DATA_WIDTH  (BITMAP_BRAM_DATA_WIDTH),
            .DATA_DEPTH  (BITMAP_BRAM_DATA_DEPTH),
            .INIT_TO_ZERO(1'b1),
            .WRITE_FIRST (1'b1)
        ) i_bram (
            .clk_i(clk_i),

            .a_wdata_i(bram_in),
            .a_wenable_i(bram_wenable),
            .a_rdata_o(bram_out),
            .a_addr_i(bram_addr),
            .a_enable_i(bram_enable),

            .b_wdata_i(bram_in_deferred_d),
            .b_wenable_i(bram_wenable_deferred_q),
            .b_rdata_o(  /*not used */),
            .b_addr_i(bram_addr_deferred_q),
            .b_enable_i(bram_wenable_deferred_q)
        );
      end : gen_real_bram
      // BRAM starts out in unknown state - need to zero it out after reset!
      northcape_sram_initializer #(
          .DATA_WIDTH(BITMAP_BRAM_DATA_WIDTH),
          .DATA_DEPTH(BITMAP_BRAM_DATA_DEPTH),
          .START_BUSY(1'b0)
      ) i_sram_initializer (
          .clk_i (clk_i),
          .rst_ni(rst_ni),

          .wdata_o  (bram_out_initializer),
          .waddr_o  (bram_addr_initializer),
          .wenable_o(bram_wenable_initializer),

          .start_i(bram_init_start),
          .busy_o (bram_init_busy)
      );

      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : bram_ffs
        if (!rst_ni) begin
          bram_wenable_deferred_q <= 1'b0;
          bram_addr_deferred_q <= '0;
          bram_addr_deferred_q1 <= '0;
          bram_addr_deferred_q1_valid_q <= 1'b0;
          bram_in_deferred_q <= '0;
          output_capability_id_q <= '0;
          sweep_capability_id_q <= '0;
        end else begin
          bram_wenable_deferred_q <= bram_wenable_deferred_d;
          bram_addr_deferred_q <= bram_addr_deferred_d;
          bram_addr_deferred_q1 <= bram_addr_deferred_q;
          bram_addr_deferred_q1_valid_q <= bram_addr_deferred_q1_valid_d;
          bram_in_deferred_q <= bram_in_deferred_d;
          output_capability_id_q <= output_capability_id_d;
          sweep_capability_id_q <= sweep_capability_id_d;
        end
      end : bram_ffs
    end : genBitmap
    else begin : gen_no_bitmap
      assign bram_out = '0;
      assign bram_init_busy = 1'b0;
      assign sweep_capability_id_q = '0;
    end : gen_no_bitmap
  endgenerate

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : stateQFF
    if (rst_ni == 0) begin
      // non-ISR FSM is responsible for initialization
      create_state_q <= IS_ISR_ONLY ? CREATE_CAP_IDLE : CREATE_CAP_COMPLETE_RESET;
      error_code_q <= NORTHCAPE_NO_ERROR;
    end else begin
      create_state_q <= create_state_d;
      error_code_q <= error_code_d;
    end
  end : stateQFF

  assign error_code_o = error_code_q;


  // static/default values
  assign axi_master.atop_type = ATOMIC_NONE;
  assign axi_master.atop_subtype = '0;

  assign axi_master.awburst = INCR;
  assign axi_master.awlock = 0;
  assign axi_master.awcache = '0;
  assign axi_master.awprot = '0;
  assign axi_master.awqos = '0;
  assign axi_master.awregion = '0;
  assign axi_master.awuser = '0;
  assign axi_master.awid = '0;

  assign axi_master.wid = '0;
  assign axi_master.wuser = '0;

  assign axi_master.arid = '0;
  assign axi_master.arsize = $clog2(AXI_DATA_WIDTH / 8);
  assign axi_master.arburst = INCR;
  assign axi_master.arlock = '0;
  assign axi_master.arcache = '0;
  assign axi_master.arprot = '0;
  assign axi_master.arqos = '0;
  assign axi_master.arregion = '0;
  assign axi_master.aruser = '0;


  generate
    if (HAS_CACHE_INTERFACE) begin : gen_tieoffs_axi
    end : gen_tieoffs_axi
    else begin : gen_regs_axi
      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : axiReadFF
        if (rst_ni == 0) begin
          axi_master.araddr  <= '0;
          axi_master.arvalid <= '0;
          axi_master.rready  <= 0;
        end else begin
          axi_master.araddr  <= araddr_d;
          axi_master.arvalid <= arvalid_d;
          axi_master.rready  <= rready_d;
        end
      end : axiReadFF
    end : gen_regs_axi
  endgenerate

  generate
    if (HAS_CACHE_INTERFACE) begin : gen_cache_interface_regs
      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : stateQFF
        if (rst_ni == 0) begin
          response_cmt_entry_q <= '0;
          cache_interface_response_err_q <= 1'b0;
        end else begin
          response_cmt_entry_q <= response_cmt_entry_d;
          cache_interface_response_err_q <= cache_interface_response_err_d;
        end
      end : stateQFF
    end : gen_cache_interface_regs
    else begin : gen_cache_interface_regs_tieoff
      assign response_cmt_entry_q = '0;
      assign cache_interface_response_err_q = 1'b0;
    end : gen_cache_interface_regs_tieoff
  endgenerate

  generate
    if (IS_ISR_ONLY == 1'b0 && HAS_CACHE_INTERFACE == 1'b0) begin : genWriteFFs
      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : axiWriteFF
        if (rst_ni == 0) begin
          axi_master.awvalid <= 0;
          axi_master.awlen   <= 0;
          axi_master.awsize  <= $clog2(AXI_DATA_WIDTH / 8);

          axi_master.wvalid  <= 0;
          axi_master.wstrb   <= '1;
          axi_master.bready  <= 0;

          axi_master.awaddr  <= '0;

          axi_master.wdata   <= '0;
          axi_master.wlast   <= 1'b1;

          b_chan_complete_q  <= 1'b0;
          bresp_q            <= SLVERR;
        end else begin
          axi_master.awvalid <= wvalid_d;
          axi_master.awlen <= '0;
          axi_master.wvalid  <= wvalid_d;
          axi_master.wstrb <= '1;
          axi_master.bready  <= bready_d;

          axi_master.awaddr  <= awaddr_d;
          axi_master.awsize  <= $clog2(
              AXI_DATA_WIDTH / 8
          );
          axi_master.wlast <= 1'b1;

          axi_master.wdata   <= wdata_d;

          b_chan_complete_q <= b_chan_complete_d;
          bresp_q <= bresp_d;
        end

        assign axi_master.bready = 1'b1;
      end : axiWriteFF
    end : genWriteFFs
    else begin : genWriteDefaults

      assign axi_master.bready  = 1'b1;

      assign b_chan_complete_q  = 1'b0;
      assign bresp_q            = SLVERR;
    end : genWriteDefaults
  endgenerate

  function capability_id_t get_search_end();
    unique case (capability_type_i)
      OFFSET_8_BIT: return NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_8;
      OFFSET_16_BIT: return NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_16;
      OFFSET_24_BIT: return NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_24;
      default: return NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_32;
    endcase
  endfunction

  generate
    if (IS_ISR_ONLY == 1'b0) begin : genCapabilityIdFFs
      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : lastCapabilityIdFF
        if (rst_ni == 0) begin

          last_capability_id_q[OFFSET_32_BIT] <= NORTHCAPE_ROOT_CAPABILITY_ID + 1;
          last_capability_id_q[OFFSET_24_BIT] <= NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_32 + 1;
          last_capability_id_q[OFFSET_16_BIT] <= NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_24 + 1;
          last_capability_id_q[OFFSET_8_BIT] <= NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_16 + 1;

          capability_search_start_q <= NORTHCAPE_ROOT_CAPABILITY_ID + 1;
          slot_overflow_q <= 0;

          // all-zeros is special
          last_lock_key_q <= 64'd1;
        end else begin
          last_capability_id_q <= last_capability_id_d;
          capability_search_start_q <= capability_search_start_d;
          slot_overflow_q <= slot_overflow_d;
          last_lock_key_q <= last_lock_key_d;
        end
      end : lastCapabilityIdFF
    end : genCapabilityIdFFs
    else begin : genCapabilityIdDefaults
      assign last_capability_id_q[OFFSET_32_BIT] = NORTHCAPE_ROOT_CAPABILITY_ID + 1;
      assign last_capability_id_q[OFFSET_24_BIT] = NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_32 + 1;
      assign last_capability_id_q[OFFSET_16_BIT] = NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_24 + 1;
      assign last_capability_id_q[OFFSET_8_BIT] = NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_16 + 1;

      assign capability_search_start_q = NORTHCAPE_ROOT_CAPABILITY_ID + 1;
      assign slot_overflow_q = 0;

      // all-zeros is special
      assign last_lock_key_q = 64'd1;
    end : genCapabilityIdDefaults
  endgenerate

  generate
    if (IS_ISR_ONLY == 1'b0) begin : gencapabilityCountFF
      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : capabilityCountFF
        if (rst_ni == 0) begin
          capability_count_q <= '0;
          capability_count_create_added_new_capability_q <= 1'b0;
        end else begin
          capability_count_q <= capability_count_d;
          capability_count_create_added_new_capability_q <= capability_count_create_added_new_capability_d;
        end
      end : capabilityCountFF
    end : gencapabilityCountFF
    else begin : genCapabilityCountDefaults
      assign capability_count_q = '0;
      assign capability_count_create_added_new_capability_q = 1'b0;
    end : genCapabilityCountDefaults
  endgenerate

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : inputCapabilityRegFF
    if (rst_ni == 0) begin
      input_capability_q <= '0;
      recurse_capability_id_q <= '0;
      recurse_capability_tag_q <= '0;
      base_left_q <= '0;
      segment_length_left_q <= '0;
      zero_segment_phys_addr_o <= '0;
      zero_segment_length_o <= '0;
      create_have_parent_capability_q <= 0;
      parent_capability_is_valid_q <= 0;
      base_direct_capability_q <= '0;
      create_drop_is_unlock_q <= 0;
      create_have_base_capability_q <= 0;

      create_parent_capability_id_q <= '0;
      base_direct_capability_id_q <= '0;
      retrieved_lock_key_q <= '0;

      inspect_length_o <= '0;
      inspect_base_o <= '0;
      inspect_refcount_o <= '0;

      is_lock_holder_q <= 1'b0;
      have_checked_bounds_q <= 1'b0;
      unlock_key_q <= '0;
    end else begin
      input_capability_q <= input_capability_d1;
      recurse_capability_id_q <= recurse_capability_id_d;
      recurse_capability_tag_q <= recurse_capability_tag_d;
      base_left_q <= base_left_d;
      segment_length_left_q <= segment_length_left_d;
      zero_segment_phys_addr_o <= zero_segment_phys_addr_d;
      zero_segment_length_o <= zero_segment_length_d;
      create_have_parent_capability_q <= create_have_parent_capability_d;
      parent_capability_is_valid_q <= parent_capability_is_valid_d;
      base_direct_capability_q <= base_direct_capability_d;
      create_drop_is_unlock_q <= create_drop_is_unlock_d;
      create_have_base_capability_q <= create_have_base_capability_d;

      create_parent_capability_id_q <= create_parent_capability_id_d;
      base_direct_capability_id_q <= base_direct_capability_id_d;
      retrieved_lock_key_q <= retrieved_lock_key_d;

      inspect_length_o <= inspect_length_d;
      inspect_base_o <= inspect_base_d;
      inspect_refcount_o <= inspect_refcount_d;

      is_lock_holder_q <= is_lock_holder_d;
      have_checked_bounds_q <= have_checked_bounds_d;
      unlock_key_q <= unlock_key_d;
    end
  end : inputCapabilityRegFF

  function logic [AXI_ADDR_WIDTH-1:0] create_output_token();
    logic [AXI_ADDR_WIDTH-1:0] ret;

    ret = '0;
    ret = capability_accessors#(AXI_ADDR_WIDTH)::capability_set_type(ret, capability_type_i);
    ret = capability_accessors#(AXI_ADDR_WIDTH)::capability_set_id(
        ret, last_capability_id_q[capability_type_i]);
    ret =
        capability_accessors#(AXI_ADDR_WIDTH)::capability_set_tag(ret, capability_to_create_d.tag);

    return ret;
  endfunction

  generate
    if (IS_ISR_ONLY == 1'b0) begin : genOutputCapabilityTokenFFs
      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : createOutputCapabilityTokenFF
        if (rst_ni == 0) begin
          capability_token_o <= '0;
        end else begin
          capability_token_o <= capability_token_d;
        end
      end : createOutputCapabilityTokenFF
    end : genOutputCapabilityTokenFFs
    else begin : genOutputCapabilityTokenDefaults
      assign capability_token_o = '0;
    end : genOutputCapabilityTokenDefaults
  endgenerate

  generate
    if (IS_ISR_ONLY == 1'b0) begin : genUpdateCompleteFFs
      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : updateCompleteFF
        if (rst_ni == 0) begin
          update_complete_q <= 0;
          update_complete_second_parent_q <= 0;
        end else begin
          update_complete_q <= update_complete_d;
          update_complete_second_parent_q <= update_complete_second_parent_d;
        end
      end : updateCompleteFF
    end : genUpdateCompleteFFs
    else begin : genUpdateCompleteDefaults
      assign update_complete_q = 0;
      assign update_complete_second_parent_q = 0;
    end : genUpdateCompleteDefaults
  endgenerate

  // TODO needed?
  assign qarma_intf.cbc_tweak = '0;


  assign capability_to_create_raw = capability_to_create_q;

  generate
    if (IS_ISR_ONLY == 1'b0) begin : genQarmaFFs
      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : qarmaFFs
        if (rst_ni == 0) begin
          remaining_rounds_qarma_q <= NUMBER_CBC_ROUNDS;
          qarma_intf.cbc_start <= 0;
          capability_to_create_q <= '0;
          qarma_intf.cbc_block_in <= 0;
          qarma_intf.cbc_key <= '0;
          qarma_key_q <= '0;
          last_tag_q <= 0;
          current_nonce_q <= '0;
        end else begin
          remaining_rounds_qarma_q <= remaining_rounds_qarma_d;
          qarma_intf.cbc_start <= cbc_start_d;
          capability_to_create_q <= capability_to_create_d;
          qarma_intf.cbc_block_in <= cbc_block_in_d;
          qarma_intf.cbc_key <= cbc_key_d;
          qarma_key_q <= qarma_key_d;
          last_tag_q <= last_tag_d;
          current_nonce_q <= current_nonce_d;
        end
      end : qarmaFFs
    end : genQarmaFFs
    else begin : genQarmaDefaults
      assign remaining_rounds_qarma_q = NUMBER_CBC_ROUNDS;
      assign qarma_intf.cbc_start = 0;
      assign capability_to_create_q = '0;
      assign qarma_intf.cbc_block_in = 0;
      assign qarma_intf.cbc_key = '0;
      assign qarma_key_q = '0;
      assign last_tag_q = 0;
      assign current_nonce_q = '0;
    end : genQarmaDefaults
  endgenerate

  generate
    if (IS_ISR_ONLY == 1'b0) begin : genRngInterfaceFFs
      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : rngInterfaceFFs
        if (rst_ni == 0) begin
          collected_random_entropy_q <= '0;
          rng_interface_rng_consumer_ready <= 0;
        end else begin
          collected_random_entropy_q <= collected_random_entropy_d;
          rng_interface_rng_consumer_ready <= rng_consumer_ready_d;
        end
      end : rngInterfaceFFs
    end : genRngInterfaceFFs
    else begin : genRngInterfaceDefaults
      assign collected_random_entropy_q = '0;
      assign rng_interface_rng_consumer_ready = 0;
    end : genRngInterfaceDefaults
  endgenerate

  // handshake logic for AXI interface, read side
  always_comb begin : axiReadHandshakeLogic
    araddr_d  = '0;
    arvalid_d = 0;
    rready_d  = 0;

    if (HAS_CACHE_INTERFACE == 1'b0) begin
      unique case (create_state_q)
        CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY, CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY_RIGHT: begin
          araddr_d  = input_capability_addr;
          arvalid_d = !(axi_master.arvalid && axi_master.arready);
          rready_d  = 0;
        end
        CREATE_CAP_PREPARE_RECURSE_INPUT_CAPABILITY: begin
          araddr_d  = recurse_capability_addr;
          arvalid_d = !(axi_master.arvalid && axi_master.arready);
          rready_d  = 0;
        end
        CREATE_CAP_GET_INPUT_CAPABILITY, CREATE_CAP_GET_INPUT_CAPABILITY_RIGHT, CREATE_CAP_RECURSE_INPUT_CAPABILITY: begin
          araddr_d  = '0;
          arvalid_d = 0;
          rready_d  = !(axi_master.rvalid && axi_master.rready);
        end
        default: begin
          // default assignment is above
        end
      endcase
    end
  end : axiReadHandshakeLogic

  always_comb begin : cacheRequestLogic
    cache_interface.request_valid = 1'b0;
    cache_interface.request_capability_id = '0;
    cache_interface.request_capability_tag = '0;
    cache_interface.is_write = 1'b0;
    cache_interface.write_request_capability = '0;
    cache_interface.write_request_flush = 1'b0;
    cache_interface.request_is_uncacheable = 1'b0;

    wrote_any_capability_o = 1'b0;
    written_capability_o = '0;

    if (HAS_CACHE_INTERFACE == 1'b1) begin
      unique case (create_state_q)
        CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY, CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY_RIGHT: begin
          cache_interface.request_valid = 1'b1;
          cache_interface.request_capability_id = input_cap_id;
          cache_interface.request_capability_tag = input_tag;
        end
        CREATE_CAP_PREPARE_RECURSE_INPUT_CAPABILITY: begin
          cache_interface.request_valid = 1'b1;
          cache_interface.request_capability_id = recurse_capability_id_q;
          cache_interface.request_capability_tag = recurse_capability_tag_q;
        end
        CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY, CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY, CREATE_CAP_SETUP_WRITE_UPDATE_SECOND_INPUT_CAPABILITY, CREATE_CAP_SETUP_WRITE_UPDATE_PARENT_CAPABILITY: begin
          cache_interface.request_valid = 1'b1;
          cache_interface.is_write = 1'b1;
          cache_interface.request_capability_id = output_capability_id_d;
          cache_interface.request_capability_tag = capability_to_create_d.tag;
          cache_interface.write_request_capability = capability_to_create_d;
          // writes are cacheable if the corresponding capability permits it
          cache_interface.request_is_uncacheable = capability_to_create_d.capability_type == NORTHCAPE_CMT_DIRECT ? !capability_to_create_d.permissions.direct_capability_permissions.cacheable_tlb : !capability_to_create_d.permissions.indirect_capability_permissions.cacheable_tlb;
        end
        CREATE_CAP_DONE: begin
          // flush for EXACTLY one cycle to prevent degrading cache performance
          // we do this after the operation is completed - by the cache invariant, the resolver/MMUs could have concurrently loaded capabilities that are no longer valid
          cache_interface.write_request_flush = (operation_i inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK, NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE}) || create_drop_is_unlock_q || is_root_capability_i;
        end

        default: begin
          // default assignment is above
        end
      endcase
      // only for write capabilities, and only for one cycle
      wrote_any_capability_o = cache_interface.request_valid && cache_interface.is_write && cache_interface.response_valid;
      written_capability_o = cache_interface.request_capability_id;
    end
  end : cacheRequestLogic

  generate
    if (IS_ISR_ONLY == 1'b0 && HAS_CACHE_INTERFACE == 1'b0) begin : genWriteHandshakeLogic
      // handshake logic for AXI interface, write side
      always_comb begin : axiWriteHandshakeLogic
        awaddr_d = axi_master.awaddr;
        awvalid_d = 0;
        wvalid_d = 0;
        wdata_d = axi_master.wdata;
        bready_d = 0;
        b_chan_complete_d = b_chan_complete_q;
        bresp_d = bresp_q;

        // only once per transaction - state does not matter
        if (axi_master.bvalid == 1'b1) begin
          bresp_d = axi_master.bresp;
        end

        unique case (create_state_q)
          CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY, CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY, CREATE_CAP_SETUP_WRITE_UPDATE_SECOND_INPUT_CAPABILITY, CREATE_CAP_SETUP_WRITE_UPDATE_PARENT_CAPABILITY: begin
            // theoretically, the entire transaction can complete in 1 cycle - need to make sure we are not starting a second transaction
            awaddr_d = capability_insert_addr;
            awvalid_d = !(axi_master.awvalid && axi_master.awready);

            wvalid_d = !(axi_master.wvalid && axi_master.wready);
            wdata_d = capability_to_create_d;

            bready_d = 1'b1;
            // at the earliest, bvalid can go up when the transaction has been accepted
            b_chan_complete_d = axi_master.bvalid;
          end
          CREATE_CAP_WAIT_WRITE_COMPLETE: begin
            wvalid_d = !(axi_master.wvalid && axi_master.wready);
            bready_d = 1'b1;
            b_chan_complete_d = b_chan_complete_q | axi_master.bvalid;
          end
          CREATE_CAP_WAIT_RESPONSE: begin
            bready_d = 1'b1;
            b_chan_complete_d = b_chan_complete_q | axi_master.bvalid;
          end
          default: begin
            // default assignment is above
          end
        endcase
      end : axiWriteHandshakeLogic
    end : genWriteHandshakeLogic
    else begin : genWriteHandshakeDefaults
      assign awaddr_d = '0;
      assign awvalid_d = 0;
      assign wvalid_d = 0;
      assign wdata_d = '0;
      assign bready_d = 0;
      assign bresp_d = SLVERR;
      assign b_chan_complete_d = 0;
    end : genWriteHandshakeDefaults
  endgenerate

  generate
    if (IS_ISR_ONLY == 1'b0) begin : genOutputCapabilityTokenLogic
      // output capability token logic
      always_comb begin : outputCapabilityTokenLogic
        // maintain
        // output is reset in top level module as soon as read by consumer
        capability_token_d = capability_token_o;

        unique case (create_state_q)
          CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY: begin
            unique case (operation_i)
              NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE,NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE,NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE,NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE,NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE,NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK:
            begin
                // there is an output
                // entry must also be valid
                capability_token_d = create_output_token();
              end
              default: begin
                // no output
                capability_token_d = '0;
              end
            endcase
          end
          CREATE_CAP_IDLE: begin
            // reset such that on output-less operations like DROP, INSPECT nothing is leaked
            capability_token_d = '0;
          end
          default: begin
            // default assignment above
          end
        endcase
      end : outputCapabilityTokenLogic
    end : genOutputCapabilityTokenLogic
    else begin : genOutputCapabilityTokenLogicDefaults
      assign capability_token_d = '0;
    end : genOutputCapabilityTokenLogicDefaults
  endgenerate

  generate
    if (IS_ISR_ONLY == 1'b0) begin : genUpdatecompleteLogic
      // logic that checks whether parent capabilities were updated
      always_comb begin : updateCompleteLogic
        update_complete_d = update_complete_q;
        update_complete_second_parent_d = update_complete_second_parent_q;

        unique case (create_state_q)
          CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY,CREATE_CAP_SETUP_WRITE_UPDATE_PARENT_CAPABILITY: begin
            update_complete_d = 1;
            if (operation_i != NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE && (operation_i != NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK || input_capability_q.capability_type == NORTHCAPE_CMT_DIRECT) && (operation_i != NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP || !create_drop_is_unlock_q || !create_have_parent_capability_q || !create_have_base_capability_q)) begin
              update_complete_second_parent_d = 1;
            end
          end
          CREATE_CAP_SETUP_WRITE_UPDATE_SECOND_INPUT_CAPABILITY: begin
            update_complete_d = 1;
            update_complete_second_parent_d = 1;
          end
          CREATE_CAP_WAIT_WRITE_COMPLETE, CREATE_CAP_WAIT_RESPONSE: begin
            update_complete_d = update_complete_q;
            update_complete_second_parent_d = update_complete_second_parent_d;
          end
          default: begin
            update_complete_d = 0;
            update_complete_second_parent_d = 0;
          end
        endcase
      end : updateCompleteLogic
    end : genUpdatecompleteLogic
    else begin : genUpdateCompleteLogicDefaults
      assign update_complete_d = 1'b0;
      assign update_complete_second_parent_d = 1'b0;
    end : genUpdateCompleteLogicDefaults
  endgenerate


  generate
    if (IS_ISR_ONLY == 1'b0) begin : genCapabilityIdLogic
      // logic associated with tracking the next capability ID and related metadata
      always_comb begin : lastCapabilityIdLogic

        last_capability_id_d = last_capability_id_q;
        slot_overflow_d = slot_overflow_q;
        last_lock_key_d = last_lock_key_q;
        capability_search_start_d = capability_search_start_q;

        unique case (create_state_q)
          CREATE_CAP_COMPLETE_RESET: begin
            // initialization for initial capability write, which (as the only capability) never goes through PREPARE_GET_INPUT_CAPABILITY below
            capability_search_start_d = last_capability_id_q[OFFSET_32_BIT];
            slot_overflow_d = 0;
          end
          CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY: begin
            // do this here instead of idle to break a combinatorical path from MMIO registers
            capability_search_start_d = last_capability_id_q[capability_type_i];
            slot_overflow_d = 0;
          end
          CREATE_CAP_CHECK_IDLE: begin

            if (slot_unoccupied) begin
              // clear the index into the slot - must come from leading zero count!
              last_capability_id_d[capability_type_i] = last_capability_id_q[capability_type_i];
              last_capability_id_d[capability_type_i][$clog2(BITMAP_BRAM_DATA_WIDTH)-1:0] =
                  bram_leading_zeros;
            end else begin
              if (gen_t::get_next_capability_id(
                      last_capability_id_q[capability_type_i],
                      BITMAP_BRAM_DATA_WIDTH,
                      capability_type_i
                  ) == capability_search_start_q) begin
                slot_overflow_d = 1;
              end
              // keep searching
              last_capability_id_d[capability_type_i] = gen_t::get_next_capability_id(
                  BITMAP_BRAM_DATA_WIDTH, last_capability_id_q[capability_type_i],
                      capability_type_i);
            end

          end
          CREATE_CAP_DONE: begin
            if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK) begin
              last_lock_key_d = last_lock_key_q + (last_lock_key_q == '1 ? 2 : 1);
            end
          end
          default: begin
            // default assignment above
          end
        endcase
      end : lastCapabilityIdLogic
    end : genCapabilityIdLogic
    else begin : genCapabilityIdLogicDefaults
      assign last_capability_id_d = '0;
      assign slot_overflow_d = '0;
      assign last_lock_key_d = '0;
      assign capability_search_start_d = '0;
    end : genCapabilityIdLogicDefaults
  endgenerate

  generate
    if (IS_ISR_ONLY == 1'b0) begin : genQarmaLogic
      // logic that controls the quarma core
      always_comb begin : QarmaControlLogic
        remaining_rounds_qarma_d = remaining_rounds_qarma_q;
        cbc_start_d = qarma_intf.cbc_start;
        cbc_block_in_d = qarma_intf.cbc_block_in;
        cbc_key_d = qarma_intf.cbc_key;
        qarma_key_d = qarma_key_q;
        last_tag_d = last_tag_q;
        current_nonce_d = current_nonce_q;

        unique case (create_state_q)
          CREATE_CAP_CREATE_QARMA_KEY_HIGH: begin
            cbc_key_d = collected_random_entropy_q;
            cbc_start_d = 1;
            cbc_block_in_d = NORTHCAPE_CAPABILITY_OPS_QARMA_INPUT_KEY_HIGH;
          end
          CREATE_CAP_WAIT_QARMA_KEY_HIGH: begin
            cbc_start_d = 0;
            if (qarma_intf.cbc_done) begin
              qarma_key_d[127:64] = qarma_intf.cbc_tag;
            end
          end
          CREATE_CAP_CREATE_QARMA_KEY_LOW: begin
            cbc_key_d = collected_random_entropy_q;
            cbc_start_d = 1;
            cbc_block_in_d = NORTHCAPE_CAPABILITY_OPS_QARMA_INPUT_KEY_LOW;
          end
          CREATE_CAP_WAIT_QARMA_KEY_LOW: begin
            cbc_start_d = 0;
            if (qarma_intf.cbc_done) begin
              qarma_key_d[63:0] = qarma_intf.cbc_tag;
            end
          end
          CREATE_CAP_CREATE_INITIAL_NONCE: begin
            cbc_key_d = collected_random_entropy_q;
            cbc_start_d = 1;
            cbc_block_in_d = NORTHCAPE_CAPABILITY_OPS_QARMA_INPUT_NONCE;
          end
          CREATE_CAP_WAIT_INITIAL_NONCE: begin
            cbc_start_d = 0;
            if (qarma_intf.cbc_done) begin
              current_nonce_d = qarma_intf.cbc_tag;
            end
          end
          CREATE_CAP_DONE: begin
            // this is held for exactly 1 cycle, after successful update
            current_nonce_d = current_nonce_q + 1;
            unique case (OPS_TAG_METHOD)
              NORTHCAPE_CAPABILITY_OPS_CTR: begin
                cbc_start_d = 1'b1;
                cbc_block_in_d = current_nonce_d;
                remaining_rounds_qarma_d = 1'b1;
                cbc_key_d = qarma_key_q;
              end
              default: ;
            endcase
          end
          CREATE_CAP_CBC_MAC: begin
            unique case (OPS_TAG_METHOD)
              NORTHCAPE_CAPABILITY_OPS_CBC: begin
                if (remaining_rounds_qarma_q == NUMBER_CBC_ROUNDS || qarma_intf.cbc_done) begin
`ifdef DEBUG
                  $display(
                      "Remaining rounds qarma %d full capability %x current capability block %x",
                      remaining_rounds_qarma_q, capability_to_create_raw,
                      capability_to_create_raw[remaining_rounds_qarma_q*64-1-:64]);
`endif
                  // first iteration or qarma has completed a block - need to provided new data immediately
                  if (remaining_rounds_qarma_q) begin
                    cbc_block_in_d = capability_to_create_raw[remaining_rounds_qarma_q*64-1-:64];
                  end else begin
                    // last round - assignment would be out of bounds
                    cbc_block_in_d = '0;
                    last_tag_d = qarma_intf.cbc_tag;
                  end
                  if (remaining_rounds_qarma_q != NUMBER_CBC_ROUNDS) begin
`ifdef DEBUG
                    $display("Completed QARMA round %d input key %x input tag %x output tag %x",
                             NUMBER_CBC_ROUNDS - remaining_rounds_qarma_q, qarma_key_q,
                             cbc_block_in_d, qarma_intf.cbc_tag);
`endif
                  end
                  cbc_start_d = (remaining_rounds_qarma_q == NUMBER_CBC_ROUNDS);
                  remaining_rounds_qarma_d = remaining_rounds_qarma_q - 1;
                  cbc_key_d = qarma_key_q;
                end else begin
                  cbc_start_d = 0;
                end
              end
              // nothing to do - just waiting for the ready flag in the FSM
              NORTHCAPE_CAPABILITY_OPS_CTR: ;
              default: ;
            endcase
          end
          default: begin
            if (OPS_TAG_METHOD == NORTHCAPE_CAPABILITY_OPS_CBC) begin
              remaining_rounds_qarma_d = NUMBER_CBC_ROUNDS;
            end
            cbc_start_d = 0;
          end
        endcase

        if (OPS_TAG_METHOD == NORTHCAPE_CAPABILITY_OPS_CTR && qarma_intf.cbc_done) begin
          // irregardless of state machine, 
          remaining_rounds_qarma_d = 1'b0;
          // register in the value - qarma will be reset
          last_tag_d = qarma_intf.cbc_tag;
        end
      end : QarmaControlLogic
    end : genQarmaLogic
    else begin : genQarmaLogicDefaults
      assign remaining_rounds_qarma_d = '0;
      assign cbc_start_d = '0;
      assign cbc_block_in_d = '0;
      assign cbc_key_d = '0;
      assign qarma_key_d = '0;
      assign last_tag_d = '0;
      assign current_nonce_d = '0;
    end : genQarmaLogicDefaults
  endgenerate

  generate
    if (IS_ISR_ONLY == 1'b0) begin : genRngLogic
      // logic that controls RNG interface signalling
      always_comb begin : rngLogic
        rng_consumer_ready_d = rng_interface_rng_consumer_ready;
        collected_random_entropy_d = collected_random_entropy_q;

        unique case (create_state_q)
          CREATE_CAP_COLLECT_ENTROPY_LOW: begin
            rng_consumer_ready_d = !rng_interface_rng_valid;
            if (rng_interface_rng_valid) begin
              collected_random_entropy_d[63:0] = rng_interface_rng_out;
            end
          end
          CREATE_CAP_COLLECT_ENTROPY_HIGH: begin
            rng_consumer_ready_d = !rng_interface_rng_valid;
            if (rng_interface_rng_valid) begin
              collected_random_entropy_d[127:64] = rng_interface_rng_out;
            end
          end
          default: begin
            rng_consumer_ready_d = 0;
          end
        endcase
      end : rngLogic
    end : genRngLogic
    else begin : genRngLogicDefaults
      assign rng_consumer_ready_d = '0;
      assign collected_random_entropy_d = '0;
    end : genRngLogicDefaults
  endgenerate

  generate
    if (HAS_CACHE_INTERFACE == 1'b1) begin
      // state machine buffers one cycle - useful to meet timing
      assign input_capability_d = response_cmt_entry_q;
    end else begin
      assign input_capability_d = axi_master.rdata;
    end
  endgenerate

  // lookup logic
  always_comb begin : capLookupLogic
    /* for the (initial) input capability, we need to check task ID; otherwise, task ID need not match */
    cmt_check_type = create_state_q == CREATE_CAP_GET_INPUT_CAPABILITY ? ACCESS_NONE : ACCESS_DERIVE_RECURSION;

    slot_unoccupied = bram_out != '1;

    input_offset = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(capability_token_i);

    unique case (create_state_q)
      CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY_RIGHT, CREATE_CAP_GET_INPUT_CAPABILITY_RIGHT: begin
        input_cap_id =
            capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(capability_token_right_i);
        input_tag =
            capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(capability_token_right_i);
      end
      default: begin
        input_cap_id = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(capability_token_i);
        input_tag = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(capability_token_i);
      end
    endcase

    if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP) begin
      // invariant: always 1 ahead
      input_cap_id = (sweep_capability_id_q - 1);
    end

    input_capability_addr =
        gen_t::get_capability_addr(INITIAL_CMT_BASE, INITIAL_CMT_SIZE_CLOG2, input_cap_id);

    recurse_capability_addr = gen_t::get_capability_addr(INITIAL_CMT_BASE, INITIAL_CMT_SIZE_CLOG2,
                                                         recurse_capability_id_q);

    if (((HAS_CACHE_INTERFACE == 1'b0 && axi_master.rvalid && axi_master.rready) || (HAS_CACHE_INTERFACE == 1'b1))) begin
`ifdef DEBUG
      $display("Checking recursed capability with check type %d (%s)!", cmt_check_type,
               cmt_check_type.name());
`endif
    end

    // this checks if we are able to use the capability for derivation
    // skips some of the checks (e.g., can be restricted to someone else)
    recursed_capability_verdict = northcape_cmt_parser::entry_matches_validate_request(
      input_capability_d,
      recurse_capability_id_q,
      recurse_capability_tag_q,
      cmt_check_type,
      device_id_i,
      task_id_i,
      operation_i inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE, NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP} ? input_capability_d.location.physical_location.locked_key : retrieved_lock_key_q  // either 0 if no lock holder or key from lock holder; for revoke, check, sweep is skipped (should always succeed)
    );

    if (((HAS_CACHE_INTERFACE == 1'b0 && axi_master.rvalid && axi_master.rready) || (HAS_CACHE_INTERFACE == 1'b1))) begin
`ifdef DEBUG
      $display("Checking input capability!");
`endif
    end

    unique case (operation_i)
      NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE: begin
        input_capability_valid = NorthcapeCapabilityOpsInputParser::input_capability_allows_create(
          input_cap_id,
          input_tag,
          input_capability_d,
          device_id_i,
          task_id_i,
          read_perm_i,
          write_perm_i,
          x_perm_i,
          lockable_perm_i,
          irq_accessible_perm_i,
          cacheable_tlb_perm_i,
          cacheable_access_perm_i,
          segment_length_i
        );
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE: begin
        input_capability_valid = NorthcapeCapabilityOpsInputParser::input_capability_allows_derive(
          input_cap_id,
          input_tag,
          input_capability_d,
          device_id_i,
          task_id_i,
          read_perm_i,
          write_perm_i,
          x_perm_i,
          irq_accessible_perm_i,
          cacheable_tlb_perm_i,
          cacheable_access_perm_i,
          segment_length_i,
          parent_offset_i
        );
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
        input_capability_valid = NorthcapeCapabilityOpsInputParser::input_capability_allows_drop(
            input_cap_id, input_tag, input_capability_d, device_id_i, task_id_i);
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE: begin
        input_capability_valid = NorthcapeCapabilityOpsInputParser::input_capability_allows_merge(
            input_cap_id, input_tag, input_capability_d, device_id_i, task_id_i);
        if (create_state_q == CREATE_CAP_GET_INPUT_CAPABILITY_RIGHT) begin
          // capabilities need to also be adjacent
          if(input_capability_valid == NORTHCAPE_NO_ERROR)
          begin
            if(input_capability_d.location.physical_location.base != base_left_q + segment_length_left_q)
            begin
              input_capability_valid = NORTHCAPE_ERR_NOT_ADJACENT;
            end
          end
        end
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE: begin
        input_capability_valid = NorthcapeCapabilityOpsInputParser::input_capability_allows_clone(
          input_cap_id,
          input_tag,
          input_capability_d,
          device_id_i,
          task_id_i,
          read_perm_i,
          write_perm_i,
          x_perm_i,
          irq_accessible_perm_i,
          cacheable_tlb_perm_i,
          cacheable_access_perm_i
        );
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE: begin
        input_capability_valid = NorthcapeCapabilityOpsInputParser::input_capability_allows_revoke(
            input_cap_id, input_tag, input_capability_d, device_id_i, task_id_i);
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
        input_capability_valid = NorthcapeCapabilityOpsInputParser::input_capability_allows_lock(
          input_cap_id,
          input_tag,
          input_capability_d,
          device_id_i,
          task_id_i,
          read_perm_i,
          write_perm_i,
          x_perm_i,
          irq_accessible_perm_i,
          cacheable_tlb_perm_i,
          cacheable_access_perm_i
        );

        if (input_capability_d.capability_type == NORTHCAPE_CMT_DIRECT) begin
          if(input_capability_valid == NORTHCAPE_NO_ERROR)
          begin
            if(input_capability_d.location.physical_location.locked_key != '0)
            begin
              input_capability_valid = NORTHCAPE_ERR_ALREADY_LOCKED;
            end else if(input_capability_d.permissions.direct_capability_permissions.lockable_permission == 1'b0)
            begin
              input_capability_valid = NORTHCAPE_ERR_NOT_LOCKABLE;
            end
          end
          ;
        end
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT: begin
        input_capability_valid = NorthcapeCapabilityOpsInputParser::input_capability_allows_inspect(
            input_cap_id, input_tag, input_capability_d, device_id_i, task_id_i);
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
        // no special conditions
        input_capability_valid = NorthcapeCapabilityOpsInputParser::input_capability_allows_restrict(
          input_cap_id,
          input_tag,
          input_capability_d,
          device_id_i,
          task_id_i,
          segment_length_i,
          parent_offset_i,
          restriction_enabled_i
        );
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP: begin
        input_capability_valid = (input_capability_d.capability_type != NORTHCAPE_CMT_INVALID) ? NORTHCAPE_NO_ERROR : NORTHCAPE_ERR_PARSER_FAIL_CAP_TYPE;
      end
      default: begin
        input_capability_valid = NORTHCAPE_ERR_INVALID_OPERATION;
      end
    endcase
  end : capLookupLogic

  function automatic northcape_cmt_entry_t set_cmt_entry_restrictions(
      input northcape_cmt_entry_t entry);
    northcape_cmt_entry_t ret;
    ret = entry;
    if (restriction_enabled_i) begin
      unique case (restriction_type_i)
        NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED: begin
          ret.restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED;
          ret.restrictions.body.device_interpreted_bits = device_interpreted_restriction_i;
        end
        NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND, NORTHCAPE_RESTRICTIONS_SET_TASK_ID: begin
          ret.restrictions.restriction_type = restriction_type_i;
          // need to be able to do the operation
          ret.restrictions.body.task_restriction.task_id = restriction_task_id_i;
          ret.restrictions.body.task_restriction.device_id = restriction_device_id_i;
        end
        default: begin
          ret.restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
          ret.restrictions.body = '0;
        end
      endcase
    end
    return ret;
  endfunction

  function northcape_cmt_entry_t create_cmt_entry();
    northcape_cmt_entry_t ret;

    ret = '0;

    unique case (operation_i)
      NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE: begin
        ret.capability_type = NORTHCAPE_CMT_DIRECT;
        if (direction_i == 0) begin
          // create new segment at the start
          ret.location.physical_location.base = input_capability_d.location.physical_location.base;
          ret.location.physical_location.length = segment_length_i;
        end else begin
          // create new segment at the end
          ret.location.physical_location.base = input_capability_d.location.physical_location.base + (input_capability_d.location.physical_location.length - segment_length_i);
          ret.location.physical_location.length = segment_length_i;
        end

        ret = set_cmt_entry_restrictions(ret);

        ret.permissions.direct_capability_permissions.read_permission = read_perm_i;
        ret.permissions.direct_capability_permissions.write_permission = write_perm_i;
        ret.permissions.direct_capability_permissions.execute_permission = x_perm_i;
        ret.permissions.direct_capability_permissions.lockable_permission = lockable_perm_i;
        ret.permissions.direct_capability_permissions.irq_accessible_permission = irq_accessible_perm_i;
        ret.permissions.direct_capability_permissions.cacheable_tlb = cacheable_tlb_perm_i;
        ret.permissions.direct_capability_permissions.cacheable_access = cacheable_access_perm_i;

        ret.nonce = current_nonce_q;


        return ret;
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE: begin
        ret.capability_type = NORTHCAPE_CMT_INDIRECT;
        ret.location.indirect_location.parent = capability_token_i;

        // 0 is always possible
`ifndef ASIC
        void'(capability_accessors#(AXI_ADDR_WIDTH)::capability_set_offset(
              ret.location.indirect_location.parent, 0));
`endif

        /* in case of lock-holder, direct parent does not have this information */
        ret.location.indirect_location.effective_base = parent_offset_i;
        ret.location.indirect_location.length = segment_length_i;

        ret = set_cmt_entry_restrictions(ret);

        ret.permissions.indirect_capability_permissions.read_permission = read_perm_i;
        ret.permissions.indirect_capability_permissions.write_permission = write_perm_i;
        ret.permissions.indirect_capability_permissions.execute_permission = x_perm_i;
        ret.permissions.indirect_capability_permissions.irq_accessible_permission = irq_accessible_perm_i;
        ret.permissions.indirect_capability_permissions.cacheable_tlb = cacheable_tlb_perm_i;
        ret.permissions.indirect_capability_permissions.cacheable_access = cacheable_access_perm_i;
        // rest of the permissions not defined

        ret.nonce = current_nonce_q;

        return ret;
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE: begin
        ret.capability_type = NORTHCAPE_CMT_INDIRECT;
        ret.location.indirect_location.parent = capability_token_i;
`ifndef ASIC
        // 0 is always possible
        void'(capability_accessors#(AXI_ADDR_WIDTH)::capability_set_offset(
            ret.location.indirect_location.parent, 0
        ));
`endif
        /* in case of lock-holder, direct parent does not have this information - will be added later */
        ret.location.indirect_location.effective_base = '0;
        ret.location.indirect_location.length = '0;


        ret = set_cmt_entry_restrictions(ret);

        
        ret.permissions.indirect_capability_permissions.read_permission = read_perm_i;
        ret.permissions.indirect_capability_permissions.write_permission = write_perm_i;
        ret.permissions.indirect_capability_permissions.execute_permission = x_perm_i;
        ret.permissions.indirect_capability_permissions.irq_accessible_permission = irq_accessible_perm_i;
        ret.permissions.indirect_capability_permissions.cacheable_tlb = cacheable_tlb_perm_i;
        ret.permissions.indirect_capability_permissions.cacheable_access = cacheable_access_perm_i;
        // rest of the permissions not defined

        ret.nonce = current_nonce_q;

        return ret;
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
        return '0;
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE: begin
        ret.capability_type = NORTHCAPE_CMT_DIRECT;

        ret.location.physical_location.base = base_left_q;
        ret.location.physical_location.length = segment_length_left_q + input_capability_d.location.physical_location.length;

        ret = set_cmt_entry_restrictions(ret);

        ret.permissions.direct_capability_permissions.read_permission = read_perm_i;
        ret.permissions.direct_capability_permissions.write_permission = write_perm_i;
        ret.permissions.direct_capability_permissions.execute_permission = x_perm_i;
        ret.permissions.direct_capability_permissions.lockable_permission = lockable_perm_i;
        ret.permissions.direct_capability_permissions.irq_accessible_permission = irq_accessible_perm_i;
        ret.permissions.direct_capability_permissions.cacheable_tlb = cacheable_tlb_perm_i;
        ret.permissions.direct_capability_permissions.cacheable_access = cacheable_access_perm_i;

        ret.nonce = current_nonce_q;

        return ret;
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE: begin
        ret.capability_type = NORTHCAPE_CMT_DIRECT;

        ret.location.physical_location.base = input_capability_d.location.physical_location.base;
        ret.location.physical_location.length = input_capability_d.location.physical_location.length;

        ret = set_cmt_entry_restrictions(ret);

        ret.permissions.direct_capability_permissions.read_permission = read_perm_i;
        ret.permissions.direct_capability_permissions.write_permission = write_perm_i;
        ret.permissions.direct_capability_permissions.execute_permission = x_perm_i;
        ret.permissions.direct_capability_permissions.lockable_permission = lockable_perm_i;
        ret.permissions.direct_capability_permissions.irq_accessible_permission = irq_accessible_perm_i;
        ret.permissions.direct_capability_permissions.cacheable_tlb = cacheable_tlb_perm_i;
        ret.permissions.direct_capability_permissions.cacheable_access = cacheable_access_perm_i;

        ret.nonce = current_nonce_q;


        return ret;
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
        ret.capability_type = NORTHCAPE_CMT_LOCK_HOLDER;
        ret.location.lock_holder_location.parent = capability_token_i;
`ifndef ASIC
        // 0 is always possible
        void'(capability_accessors#(AXI_ADDR_WIDTH)::capability_set_offset(
            ret.location.lock_holder_location.parent, 0
        ));
`endif

        ret.location.lock_holder_location.lock_key = last_lock_key_q;
        ret.location.lock_holder_location.prev_key = '0;


        ret = set_cmt_entry_restrictions(ret);

        ret.permissions.indirect_capability_permissions.read_permission = read_perm_i;
        ret.permissions.indirect_capability_permissions.write_permission = write_perm_i;
        ret.permissions.indirect_capability_permissions.execute_permission = x_perm_i;
        ret.permissions.indirect_capability_permissions.irq_accessible_permission = irq_accessible_perm_i;
        ret.permissions.indirect_capability_permissions.cacheable_tlb = cacheable_tlb_perm_i;
        ret.permissions.indirect_capability_permissions.cacheable_access = cacheable_access_perm_i;
        // rest of the permissions not defined

        ret.nonce = current_nonce_q;

        return ret;
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
        // the value is used in the last cycle of CREATE_CAP_GET_INPUT_CAPABILITY, when this value is valid and the register still has an old value
        ret = input_capability_d;

        if (ret.capability_type == NORTHCAPE_CMT_INDIRECT) begin
          // for direct capability, no modification
          ret.location.indirect_location.length -= segment_length_i;
          ret.location.indirect_location.effective_base += parent_offset_i;
        end

        ret = set_cmt_entry_restrictions(ret);

        // these are in the same place for direct and indirect capabilities
        ret.permissions.indirect_capability_permissions.read_permission &= read_perm_i;
        ret.permissions.indirect_capability_permissions.write_permission &= write_perm_i;
        ret.permissions.indirect_capability_permissions.execute_permission &= x_perm_i;
        ret.permissions.indirect_capability_permissions.irq_accessible_permission &= irq_accessible_perm_i;
        ret.permissions.indirect_capability_permissions.cacheable_tlb &= cacheable_tlb_perm_i;
        ret.permissions.indirect_capability_permissions.cacheable_access &= cacheable_access_perm_i;

        if (ret.capability_type == NORTHCAPE_CMT_DIRECT) begin
          ret.permissions.direct_capability_permissions.lockable_permission &= lockable_perm_i;
        end
        // nothing else modified

        return ret;
      end

      default: begin
        return '0;
      end
    endcase
  endfunction

  function northcape_cmt_entry_t update_input_cmt_entry(northcape_cmt_entry_t entry_to_update);
    northcape_cmt_entry_t ret;

    ret = entry_to_update;

    unique case (operation_i)
      NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE: begin

        if (direction_i == 0) begin
          // created at start
          ret.location.physical_location.base += segment_length_i;
          ret.location.physical_location.length -= segment_length_i;
        end else begin
          ret.location.physical_location.length -= segment_length_i;
        end

        if (ret.location.physical_location.length == 0) begin
          //input capability was destroyed by create
          ret = '0;
          ret.capability_type = NORTHCAPE_CMT_INVALID;
        end

        return ret;
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE: begin
        // when we check whether the capability is valid, we also check that adding one here does not lead to overflow
        ret.refcount += 1;
        return ret;
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
        // the operations ensure that this cannot overflow
        ret.refcount -= 1;

        /*
         * If:
         * - we call drop on lock-holder
         * - we reach the grandparent
         * we update the locked key, either to '0 (last lock-holder) or previous lock-holder's key
         */
        if (ret.capability_type == NORTHCAPE_CMT_DIRECT && create_drop_is_unlock_q) begin
          ret.location.physical_location.locked_key = unlock_key_q;
        end

        return ret;
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE, NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE, NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP: begin
        // destroyed
        ret = '0;
        ret.capability_type = NORTHCAPE_CMT_INVALID;
        return ret;
      end
      NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
        ret.refcount += 1;
        if (ret.capability_type == NORTHCAPE_CMT_DIRECT) begin
          ret.location.physical_location.locked_key = last_lock_key_q;
        end
        return ret;
      end
      default: begin
        // no modification
        return ret;
      end
    endcase
  endfunction

  // logic responsible for input capability processing / storage
  always_comb begin : inputCapabilityProcessingLogic
    recurse_capability_id_d = recurse_capability_id_q;
    recurse_capability_tag_d = recurse_capability_tag_q;
    base_left_d = base_left_q;
    segment_length_left_d = segment_length_left_q;
    zero_segment_phys_addr_d = zero_segment_phys_addr_o;
    zero_segment_length_d = zero_segment_length_o;
    create_have_parent_capability_d = create_have_parent_capability_q;
    parent_capability_is_valid_d = parent_capability_is_valid_q;
    base_direct_capability_d = base_direct_capability_q;
    create_drop_is_unlock_d = create_drop_is_unlock_q;
    create_have_base_capability_d = create_have_base_capability_q;

    create_parent_capability_id_d = create_parent_capability_id_q;
    base_direct_capability_id_d = base_direct_capability_id_q;
    retrieved_lock_key_d = retrieved_lock_key_q;
    unlock_key_d = unlock_key_q;

    inspect_length_d = inspect_length_o;
    inspect_base_d = inspect_base_o;
    inspect_refcount_d = inspect_refcount_o;

    input_capability_d1 = input_capability_q;

    unique case (create_state_q)
      CREATE_CAP_GET_INPUT_CAPABILITY: begin
        if (((HAS_CACHE_INTERFACE == 1'b0 && axi_master.rvalid && axi_master.rready) || (HAS_CACHE_INTERFACE == 1'b1))) begin
          inspect_refcount_d = input_capability_d.refcount;
          if (input_capability_d.capability_type == NORTHCAPE_CMT_LOCK_HOLDER) begin
            // this is either valid or ignored
            recurse_capability_id_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                input_capability_d.location.lock_holder_location.parent);
            recurse_capability_tag_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(
                input_capability_d.location.lock_holder_location.parent);
            // valid or ignored
            create_parent_capability_id_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                input_capability_d.location.lock_holder_location.parent);
            base_direct_capability_id_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                input_capability_d.location.lock_holder_location.parent);
            // top lock key ALWAYS wins
            retrieved_lock_key_d = input_capability_d.location.lock_holder_location.lock_key;
            unlock_key_d = input_capability_d.location.lock_holder_location.prev_key;
          end else begin
            // this is either valid or ignored
            recurse_capability_id_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                input_capability_d.location.indirect_location.parent);
            recurse_capability_tag_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(
                input_capability_d.location.indirect_location.parent);
            if (input_capability_d.capability_type == NORTHCAPE_CMT_DIRECT) begin
              inspect_length_d = input_capability_d.location.physical_location.length;
              inspect_base_d   = input_capability_d.location.physical_location.base;
            end else begin
              // must be indirect then
              inspect_length_d = input_capability_d.location.indirect_location.length;
              inspect_base_d = input_capability_d.location.indirect_location.effective_base;

              // this might already be the base capability
              // scenario: one indirect capability on top of one direct capability
              create_parent_capability_id_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                  input_capability_d.location.indirect_location.parent);
              base_direct_capability_id_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                  input_capability_d.location.indirect_location.parent);
            end
          end

          input_capability_d1 = input_capability_d;

          // valid or ignored
          base_left_d = input_capability_d.location.physical_location.base;
          segment_length_left_d = input_capability_d.location.physical_location.length;
          zero_segment_phys_addr_d = input_capability_d.location.physical_location.base;
          zero_segment_length_d = input_capability_d.location.physical_location.length;
          create_drop_is_unlock_d = (input_capability_d.capability_type == NORTHCAPE_CMT_LOCK_HOLDER);
        end
      end
      CREATE_CAP_GET_INPUT_CAPABILITY_RIGHT: begin
        if (((HAS_CACHE_INTERFACE == 1'b0 && axi_master.rvalid && axi_master.rready) || (HAS_CACHE_INTERFACE == 1'b1))) begin
          // save input capability as soon as possible
          input_capability_d1 = input_capability_d;
        end
      end
      CREATE_CAP_RECURSE_INPUT_CAPABILITY: begin
        if ((HAS_CACHE_INTERFACE == 1'b0 && axi_master.rvalid && axi_master.rready) || (HAS_CACHE_INTERFACE == 1'b1)) begin
          if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP) begin
            if (!create_have_parent_capability_q) begin
              input_capability_d1 = input_capability_d;
              // need only update the first parent
              create_have_parent_capability_d = 1'b1;
              parent_capability_is_valid_d = (recursed_capability_verdict == CMT_ENTRY_MATCH || recursed_capability_verdict == CMT_ENTRY_RECURSE);
            end else begin
              // make sure this stays all-zeros when we do not have direct parent yet
              // otherwise, might doubly-write parent
              base_direct_capability_d = input_capability_d;
              // need not only have base capability, but it also needs to be valid
              create_have_base_capability_d = (recursed_capability_verdict == CMT_ENTRY_MATCH);
            end
            // last non-direct capability must have the base direct capability's ID
            if (input_capability_d.capability_type inside {NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_REVOCATION}) begin
              base_direct_capability_id_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                  input_capability_d.location.indirect_location.parent);
            end
            if (input_capability_d.capability_type == NORTHCAPE_CMT_LOCK_HOLDER) begin
              base_direct_capability_id_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                  input_capability_d.location.lock_holder_location.parent);
            end
          end else begin
            // have parent and are doing the next recursion
            base_direct_capability_d = input_capability_d;
            // we can retrieve this from the LAST indirect capability
            // if direct: do nothing and use last value
            if (input_capability_d.capability_type inside {NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_LOCK_HOLDER, NORTHCAPE_CMT_REVOCATION}) begin
              if (input_capability_d.capability_type inside {NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_REVOCATION}) begin
                base_direct_capability_id_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                    input_capability_d.location.indirect_location.parent);
                if (!inspect_base_d && !inspect_length_d) begin
                  // 0-length capabilities cannot exist - the first capability in the chain was a lock-holder
                  inspect_length_d = input_capability_d.location.indirect_location.length;
                  inspect_base_d   = input_capability_d.location.indirect_location.effective_base;
                end
              end else begin
                base_direct_capability_id_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                    input_capability_d.location.lock_holder_location.parent);
              end
            end
            if (input_capability_d.capability_type == NORTHCAPE_CMT_DIRECT) begin
              if (!inspect_base_d && !inspect_length_d) begin
                // 0-length capabilities cannot exist - the first capability in the chain was a lock-holder
                inspect_length_d = input_capability_d.location.physical_location.length;
                inspect_base_d   = input_capability_d.location.physical_location.base;
              end
            end
          end
          if (input_capability_d.capability_type inside {NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_REVOCATION}) begin
            // this is either valid or ignored
            recurse_capability_id_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                input_capability_d.location.indirect_location.parent);
            recurse_capability_tag_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(
                input_capability_d.location.indirect_location.parent);
          end else begin
            // this is either valid or ignored
            recurse_capability_id_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                input_capability_d.location.lock_holder_location.parent);
            recurse_capability_tag_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(
                input_capability_d.location.lock_holder_location.parent);
          end

          if (input_capability_d.capability_type == NORTHCAPE_CMT_LOCK_HOLDER) begin
            if (retrieved_lock_key_q == '0) begin
              // this is the first lock holder in the tree -> must be the valid one
              retrieved_lock_key_d = input_capability_d.location.lock_holder_location.lock_key;
            end
          end
        end
      end
      CREATE_CAP_IDLE: begin
        create_have_parent_capability_d = 1'b0;
        parent_capability_is_valid_d = 1'b0;
        base_left_d = '0;
        segment_length_left_d = '0;
        base_direct_capability_d = '0;
        create_have_base_capability_d = 0;
        create_drop_is_unlock_d = 0;
        inspect_length_d = '0;
        inspect_base_d = '0;
        inspect_refcount_d = '0;
        // in inspect, we re-use the recursed capability logic to check whether the capability is valid
        recurse_capability_id_d =
            capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(capability_token_i);
        recurse_capability_tag_d =
            capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(capability_token_i);
        create_parent_capability_id_d = '0;
        base_direct_capability_id_d = '0;
        retrieved_lock_key_d = '0;
      end
      default: begin
        // default assignment above
      end
    endcase

    if (inspect_is_partial_reveal_d == 1'b1) begin
      // not needed / allowed in case of partial reveal
      inspect_length_d = '0;
      inspect_base_d = '0;
      inspect_refcount_d = '0;
    end
  end : inputCapabilityProcessingLogic


  capability_id_t new_capability_id;

  generate
    if (IS_ISR_ONLY == 1'b0) begin : genCapabilityCreationLogic
      // combinational logic for creating capabilities
      always_comb begin : capCreateLogic
        northcape_cmt_entry_t new_capability_entry;

        unique case (operation_i)
          NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE, NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE, NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE, NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
            new_capability_id = last_capability_id_q[capability_type_i];
            new_capability_entry = capability_to_create_q;
            new_capability_entry.tag = is_root_capability_i ? '0 : last_tag_q;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
            // drop, restrict always overwrites the input cap
            new_capability_id =
                capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(capability_token_i);
            new_capability_entry = '0;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
            new_capability_id =
                capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(capability_token_i);
            new_capability_entry = capability_to_create_q;  // tag not modified
          end
          default: begin
            new_capability_id = '0;
            new_capability_entry = '0;
          end
        endcase

        /* new bounds have not been known until now in case of input being a lock-holder */
        unique case (operation_i)
          NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE: begin
            new_capability_entry.location.indirect_location.effective_base = inspect_base_o + parent_offset_i;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE: begin
            new_capability_entry.location.indirect_location.effective_base = inspect_base_o;
            new_capability_entry.location.indirect_location.length = inspect_length_o;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
            /* not valid previously */
            new_capability_entry.location.lock_holder_location.prev_key = base_direct_capability_q.location.physical_location.locked_key;
          end
          default: ;
        endcase

        output_capability_id_d = '0;

        capability_count_create_added_new_capability_d = capability_count_create_added_new_capability_q;

        unique case (is_root_capability_i)
          1'b1: begin
            capability_to_create_d = gen_t::generate_root_capability();
            output_capability_id_d = NORTHCAPE_ROOT_CAPABILITY_ID;
          end
          default: begin
            unique case (create_state_q)
              CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY: begin
                capability_to_create_d = update_input_cmt_entry(input_capability_q);
                if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP) begin
                  // invariant: always 1 ahead
                  output_capability_id_d = sweep_capability_id_q - 1;
                end else begin
                  output_capability_id_d =
                      capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(capability_token_i);
                end
                if(operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE && capability_to_create_d.capability_type == NORTHCAPE_CMT_INVALID)
                begin
                  // need to maintain the capability count - parent was destroyed in the process
                  capability_count_create_added_new_capability_d = 1'b0;
                end else begin
                  capability_count_create_added_new_capability_d = 1'b1;
                end
              end
              CREATE_CAP_SETUP_WRITE_UPDATE_PARENT_CAPABILITY: begin
                capability_to_create_d = update_input_cmt_entry(input_capability_q);
                output_capability_id_d = create_parent_capability_id_q;
              end
              CREATE_CAP_SETUP_WRITE_UPDATE_SECOND_INPUT_CAPABILITY: begin
                unique case (operation_i)
                  NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE: begin
                    // merge does not need the input
                    capability_to_create_d = update_input_cmt_entry('0);
                    output_capability_id_d = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                        capability_token_right_i);
                  end
                  NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
                    capability_to_create_d = base_direct_capability_q;
                    capability_to_create_d.location.physical_location.locked_key = last_lock_key_q;
                    output_capability_id_d = base_direct_capability_id_q;
                  end
                  NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
                    // DROP 
                    capability_to_create_d = base_direct_capability_q;
                    capability_to_create_d.location.physical_location.locked_key = unlock_key_q;
                    output_capability_id_d = base_direct_capability_id_q;
                  end
                  default: begin
`ifdef DEBUG
                    $display("Invalid state!");
                    $stop();
`endif
                    capability_to_create_d = '0;
                    output_capability_id_d = '0;
                  end
                endcase
              end
              CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY: begin
                capability_to_create_d = new_capability_entry;
                output_capability_id_d = new_capability_id;
              end
              CREATE_CAP_GET_INPUT_CAPABILITY, CREATE_CAP_GET_INPUT_CAPABILITY_RIGHT: begin
                capability_to_create_d = create_cmt_entry();
                output_capability_id_d = new_capability_id;
              end
              default: begin
                output_capability_id_d = new_capability_id;
                // hold until next update
                capability_to_create_d = capability_to_create_q;
              end
            endcase
          end
        endcase

        capability_insert_addr = gen_t::get_capability_addr(
            INITIAL_CMT_BASE, INITIAL_CMT_SIZE_CLOG2, output_capability_id_d);
      end : capCreateLogic
    end : genCapabilityCreationLogic
    else begin : genCapabilityCreationDefaults
      assign output_capability_id_d = '0;
      assign capability_to_create_d = '0;
      assign capability_insert_addr = '0;
    end : genCapabilityCreationDefaults
  endgenerate

  generate
    if (CAPABILITY_COUNTER_ACTIVE == 1'b1) begin : genCapabilityCountLogic
      always_comb begin : capabilityCountLogic


        capability_count_addend = 0;

        capability_count_d = capability_count_q;

        // we stay in the DONE state for exactly one cycle, and only arrive there after a successful operation
        // operation_i should still be maintained at this point
        if (create_state_q == CREATE_CAP_DONE) begin
          unique case (operation_i)
            NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE: begin
              // if parent was destroyed, maintain the count
              // exception to the exception is the root capability, for which there is no parent
              capability_count_addend = (capability_count_create_added_new_capability_d || is_root_capability_i) ? 1 : 0;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK:
            begin
              capability_count_addend = 1;
            end
            NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE: begin
              capability_count_addend = -1;
            end
            default: begin
              capability_count_addend = 0;
            end
          endcase
        end

        if(create_state_q == CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY && operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP && cache_interface.response_valid)
        begin
          // one capability was kicked in sweep
          capability_count_addend = -1;
        end

        capability_count_d = capability_count_d + capability_count_addend;

        capability_count_o = capability_count_q;
      end : capabilityCountLogic
    end : genCapabilityCountLogic
    else begin : genCapabilityCountDummyLogic
      assign capability_count_addend = '0;
      assign capability_count_d = '0;
      assign capability_count_o = '0;
    end : genCapabilityCountDummyLogic
  endgenerate

  generate
    if (IS_ISR_ONLY == 1'b0) begin : gen_bram_logic

      assign bram_leading_zeros = BITMAP_BRAM_DATA_WIDTH - bram_leading_zeros_out[$clog2(
          BITMAP_BRAM_DATA_WIDTH
      )-1:0] - 1;

      always_comb begin : bramLogic
        bram_in = '0;
        bram_wenable = 1'b0;
        bram_addr = '0;
        bram_enable = 1'b0;
        bram_init_start = 1'b0;

        bram_addr_deferred_q1_valid_d = bram_addr_deferred_q1_valid_q;

        // in case of an address conflict (i.e., two writes to the same BRAM address in subsequent cycles), face risk of missed update
        // cannot rely on write-first logic of the block RAM, as we use different ports for reading and writing
        // could use the same port at expense of more complicated logic; also, write-first not always available
        // solution: if we are writing the same address in two subsequent cycles, use the data from the last cycle as initial source

        // we always write JUST after the read command - can do this with the output data based on combinatorical logic
        bram_in_deferred_d = bram_out;

        bram_addr_deferred_d = bram_addr_deferred_q;

        if (create_state_q != CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY) begin
          // for the first write (CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY), ALWAYS need to use BRAM output
          // otherwise, check
          if (bram_addr_deferred_q == bram_addr_deferred_q1 && bram_addr_deferred_q1_valid_q) begin
            bram_in_deferred_d = bram_in_deferred_q;
          end
        end
        // have to use "last" cycle's capability and ID to create here, otherwise, might already refer to the next capability
        bram_in_deferred_d[output_capability_id_q % BITMAP_BRAM_DATA_WIDTH] = capability_to_create_q.capability_type != NORTHCAPE_CMT_INVALID;

        bram_wenable_deferred_d = 1'b0;

        if (bram_wenable_deferred_q) begin
          // WILL be valid in the next cycle
          bram_addr_deferred_q1_valid_d = 1'b1;
        end

        unique case (create_state_q)
          CREATE_CAP_IDLE: begin
            bram_addr_deferred_q1_valid_d = 1'b0;
          end
          // busy is set 1 cycle AFTER start - need to start the reset before we go into CREATE_CAP_RESET_BITMAP, where the FSM waits for busy to go low
          CREATE_CAP_PREPARE_RESET_BITMAP, CREATE_CAP_RESET_BITMAP: begin
            bram_in = bram_out_initializer;
            bram_addr = bram_addr_initializer;
            bram_wenable = bram_wenable_initializer;
            bram_enable = bram_wenable_initializer;
            bram_init_start = 1'b1;
          end
          CREATE_CAP_PREPARE_CHECK_IDLE: begin
            bram_enable = 1'b1;
            bram_addr = (new_capability_id % (2 ** INITIAL_CMT_SIZE_CLOG2)) / BITMAP_BRAM_DATA_WIDTH;
          end
          CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY, CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY, CREATE_CAP_SETUP_WRITE_UPDATE_PARENT_CAPABILITY, CREATE_CAP_SETUP_WRITE_UPDATE_SECOND_INPUT_CAPABILITY, CREATE_CAP_WAIT_WRITE_COMPLETE:
          begin
            // we only read the old mask here - write is handled with the "deferred" signals based on our address and capability and the mask to be read back in the next cycle
            // FSM / system design ensures we never read/write conflicting addresses using this mechanism
            bram_addr = (output_capability_id_d % (2 ** INITIAL_CMT_SIZE_CLOG2)) / BITMAP_BRAM_DATA_WIDTH;

            // write back the changed value in the next cycle
            // will be reset as soon as we leave the last setup write state
            // also, only to be triggered once on last cycle to avoid doing this multiple times - costs energy
            if (HAS_CACHE_INTERFACE) begin
              bram_wenable_deferred_d = cache_interface.response_valid;
            end else begin
              bram_wenable_deferred_d = axi_master.awvalid && axi_master.awready;
            end
            // only need to read for once cycle too
            bram_enable = bram_wenable_deferred_d;
          end
          CREATE_CAP_SWEEP_GETROW, CREATE_CAP_SWEEP: begin
            bram_addr = (sweep_capability_id_q % (2 ** INITIAL_CMT_SIZE_CLOG2)) / BITMAP_BRAM_DATA_WIDTH;
            bram_enable = (create_state_q == CREATE_CAP_SWEEP_GETROW);
          end
          default: ;
        endcase
        if (bram_wenable_deferred_d) begin
          // always have to finish the write in the next cycle
          // hold this stable until we are ready to write to prevent this signal from propagating into bram_addr_deferred_q1_valid_q
          bram_addr_deferred_d = bram_addr;
        end
      end : bramLogic

      northcape_leading_zero_count #(
          .SIZE(BITMAP_BRAM_DATA_WIDTH)
      ) i_bram_alloc (
          .one_hot_i(~bram_out),
          .leading_zero_count_o(bram_leading_zeros_out)
      );

    end : gen_bram_logic
  endgenerate

  // sizing of CMT ensures that the counter cannot overflow
  assert property (@(posedge(clk_i))
    (rst_ni && capability_count_addend > 0) |-> capability_count_q < {CAPABILITY_COUNTER_WIDTH{1'b1}}
  );

  assert property (@(posedge(clk_i))
    (rst_ni && capability_count_addend < 0) |-> capability_count_q > {CAPABILITY_COUNTER_WIDTH{1'b0}}
  );

  // FSM next state logic for capability creation FSM
  always_comb begin : createCapStateMachine
    create_state_d = create_state_q;

    have_checked_bounds_d = have_checked_bounds_q;
    is_lock_holder_d = is_lock_holder_q;

    sweep_capability_id_d = sweep_capability_id_q;

    error_code_d = error_code_q;

    unique case (create_state_q)
      CREATE_CAP_COMPLETE_RESET: begin
        create_state_d = CREATE_CAP_COLLECT_ENTROPY_LOW;
      end
      CREATE_CAP_COLLECT_ENTROPY_LOW: begin
        if (rng_interface_rng_valid) begin
          create_state_d = CREATE_CAP_COLLECT_ENTROPY_HIGH;
        end
      end
      CREATE_CAP_COLLECT_ENTROPY_HIGH: begin
        if (rng_interface_rng_valid) begin
          create_state_d = CREATE_CAP_CREATE_QARMA_KEY_HIGH;
        end
      end
      CREATE_CAP_CREATE_QARMA_KEY_HIGH: begin
        create_state_d = CREATE_CAP_WAIT_QARMA_KEY_HIGH;
      end
      CREATE_CAP_WAIT_QARMA_KEY_HIGH: begin
        if (!qarma_intf.cbc_start && qarma_intf.cbc_done) begin
          create_state_d = CREATE_CAP_CREATE_QARMA_KEY_LOW;
        end
      end
      CREATE_CAP_CREATE_QARMA_KEY_LOW: begin
        create_state_d = CREATE_CAP_WAIT_QARMA_KEY_LOW;
      end
      CREATE_CAP_WAIT_QARMA_KEY_LOW: begin
        if (!qarma_intf.cbc_start && qarma_intf.cbc_done) begin
          create_state_d = CREATE_CAP_CREATE_INITIAL_NONCE;
        end
      end
      CREATE_CAP_CREATE_INITIAL_NONCE: begin
        create_state_d = CREATE_CAP_WAIT_INITIAL_NONCE;
      end
      CREATE_CAP_WAIT_INITIAL_NONCE: begin
        if (!qarma_intf.cbc_start && qarma_intf.cbc_done) begin
          create_state_d = CREATE_CAP_PREPARE_RESET_BITMAP;
        end
      end
      CREATE_CAP_PREPARE_RESET_BITMAP: begin
        // need to wait one cycle for the busy signal to appear in the SRAM initializer
        create_state_d = CREATE_CAP_RESET_BITMAP;
      end
      CREATE_CAP_RESET_BITMAP: begin
        if (!bram_init_busy) begin
          create_state_d = CREATE_CAP_IDLE;
        end
      end
      CREATE_CAP_IDLE: begin
        error_code_d = NORTHCAPE_NO_ERROR;
        if (start_i) begin
          if (is_root_capability_i) begin
            // CMT was zeroed out
            // can immediately write the capability
            create_state_d = CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY;
          end else begin
            if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP) begin
              create_state_d = CREATE_CAP_SWEEP_GETROW;
            end else begin
              // need to search for an insert slot
              create_state_d = CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY;
            end
          end
          have_checked_bounds_d = 1'b0;
          is_lock_holder_d = 1'b0;
        end
      end
      CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY: begin
        if ((HAS_CACHE_INTERFACE == 1'b0 && axi_master.arvalid && axi_master.arready) || (HAS_CACHE_INTERFACE == 1'b1 && cache_interface.response_valid)) begin
          // read accepted
          create_state_d = CREATE_CAP_GET_INPUT_CAPABILITY;
        end
      end
      CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY_RIGHT: begin
        if (((HAS_CACHE_INTERFACE == 1'b0 && axi_master.arvalid && axi_master.arready) || (HAS_CACHE_INTERFACE == 1'b1 && cache_interface.response_valid))) begin
          // read accepted
          create_state_d = CREATE_CAP_GET_INPUT_CAPABILITY_RIGHT;
        end
      end
      CREATE_CAP_GET_INPUT_CAPABILITY: begin
        if (((HAS_CACHE_INTERFACE == 1'b0 && axi_master.rvalid && axi_master.rready) || (HAS_CACHE_INTERFACE == 1'b1))) begin
          if (HAS_CACHE_INTERFACE == 1'b0 && (!axi_master.rlast || axi_master.rresp != OKAY)) begin
            create_state_d = CREATE_CAP_ERROR;
            error_code_d = NORTHCAPE_ERR_BUS;
          end else if (HAS_CACHE_INTERFACE == 1'b1 && cache_interface_response_err_q) begin
            create_state_d = CREATE_CAP_ERROR;
            error_code_d = NORTHCAPE_ERR_BUS;
          end else if (input_capability_valid == NORTHCAPE_NO_ERROR) begin
            if (input_capability_d.capability_type == NORTHCAPE_CMT_DIRECT) begin
              if (operation_i inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE}) begin
                // need to get second input capability as well
                create_state_d = CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY_RIGHT;
              end else if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT) begin
                // nothing to write
                create_state_d = CREATE_CAP_DONE;
              end else if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT) begin
                // no new capability created, so new idle check
                create_state_d = CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY;
              end else if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP) begin
                // checks out - next
                create_state_d = CREATE_CAP_SWEEP_GETROW;
              end else begin
                create_state_d = CREATE_CAP_PREPARE_CHECK_IDLE;
              end
            end else begin
              // must be indirect
              create_state_d = CREATE_CAP_PREPARE_RECURSE_INPUT_CAPABILITY;

              if (input_capability_d.capability_type == NORTHCAPE_CMT_LOCK_HOLDER) begin
                is_lock_holder_d = 1'b1;
              end
            end
          end else begin
            // cannot use the capability for create
            create_state_d = CREATE_CAP_ERROR;
            error_code_d = input_capability_valid;
          end
        end
      end
      CREATE_CAP_GET_INPUT_CAPABILITY_RIGHT: begin
        if ((HAS_CACHE_INTERFACE == 1'b0 && axi_master.rvalid && axi_master.rready) || (HAS_CACHE_INTERFACE == 1'b1)) begin
          if (HAS_CACHE_INTERFACE == 1'b0 && (!axi_master.rlast || axi_master.rresp != OKAY)) begin
            error_code_d = NORTHCAPE_ERR_BUS;
            create_state_d = CREATE_CAP_ERROR;
          end else if (HAS_CACHE_INTERFACE == 1'b1 && cache_interface_response_err_q) begin
            error_code_d = NORTHCAPE_ERR_BUS;
            create_state_d = CREATE_CAP_ERROR;
          end else if (input_capability_valid == NORTHCAPE_NO_ERROR) begin
            unique case (operation_i)
              NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE:
              create_state_d = CREATE_CAP_PREPARE_CHECK_IDLE;
              default:
              begin
                create_state_d = CREATE_CAP_ERROR;
                error_code_d = NORTHCAPE_ERR_UNKNOWN_OPERATION;
              end
            endcase

          end else begin
            // either second capability invalid or not adjacent
            create_state_d = CREATE_CAP_ERROR;
            error_code_d = input_capability_valid;
          end
        end
      end
      CREATE_CAP_PREPARE_RECURSE_INPUT_CAPABILITY: begin
        if (((HAS_CACHE_INTERFACE == 1'b0 && axi_master.arvalid && axi_master.arready) || (HAS_CACHE_INTERFACE == 1'b1 && cache_interface.response_valid))) begin
          // read accepted
          create_state_d = CREATE_CAP_RECURSE_INPUT_CAPABILITY;
        end
      end
      CREATE_CAP_RECURSE_INPUT_CAPABILITY: begin
        if (((HAS_CACHE_INTERFACE == 1'b0 && axi_master.rvalid && axi_master.rready) || (HAS_CACHE_INTERFACE == 1'b1))) begin
          unique case (recursed_capability_verdict)
            CMT_ENTRY_MATCH: begin
              unique case (operation_i)
                NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE,NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE,NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE: begin
                  create_state_d = CREATE_CAP_PREPARE_CHECK_IDLE;
                end
                NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
                  // no new entry created - go straight to update of parent
                  create_state_d = CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY;
                end
                NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
                  /* correctness of locking key is checked by CMT parser above */
                  if(input_capability_d.permissions.direct_capability_permissions.lockable_permission == 1'b1)
                  begin
                    create_state_d = CREATE_CAP_PREPARE_CHECK_IDLE;
                  end else begin
                    // cannot lock
                    error_code_d = NORTHCAPE_ERR_NOT_LOCKABLE;
                    create_state_d = CREATE_CAP_ERROR;
                  end
                end
                NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT: begin
                  create_state_d = CREATE_CAP_DONE;
                end
                NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP: begin
                  // checks out
                  create_state_d = CREATE_CAP_SWEEP_GETROW;
                end
                NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE:
                begin
                  // need to get second input capability as well
                  create_state_d = CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY_RIGHT;
                end
                default: begin
                  error_code_d = NORTHCAPE_ERR_UNKNOWN_OPERATION;
                  create_state_d = CREATE_CAP_ERROR;
                end
              endcase
              // end of recursion
              // check bounds - deferred
              if (is_lock_holder_q && ~have_checked_bounds_q) begin
                if(operation_i inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT})
                begin
                  if((segment_length_i + parent_offset_i) > input_capability_d.location.physical_location.length)
                  begin
                    create_state_d = CREATE_CAP_ERROR;
                    error_code_d = NORTHCAPE_ERR_OUT_OT_BOUNDS;
                  end else begin
                    have_checked_bounds_d = 1'b1;
                  end
                end
              end
            end
            CMT_ENTRY_RECURSE: begin
              if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP && !create_drop_is_unlock_q) begin
                // drop only cares about the direct parent
                create_state_d = CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY;
              end else begin
                // recurse to next capability
                create_state_d = CREATE_CAP_PREPARE_RECURSE_INPUT_CAPABILITY;
              end

              // check bounds - deferred
              if(is_lock_holder_q && ~have_checked_bounds_q && input_capability_d.capability_type == NORTHCAPE_CMT_INDIRECT)
              begin
                if(operation_i inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT})
                begin
                  if((segment_length_i + parent_offset_i) > input_capability_d.location.indirect_location.length)
                  begin
                    create_state_d = CREATE_CAP_ERROR;
                    error_code_d = NORTHCAPE_ERR_OUT_OT_BOUNDS;
                  end else begin
                    have_checked_bounds_d = 1'b1;
                  end
                end
              end
            end
            // failure cases
            default: begin
              if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP) begin
                // direct parent was revoked
                // we stop recursion and modify input capability only
                create_state_d = CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY;
              end else if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP) begin
                create_state_d = CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY;
              end else begin
                create_state_d = CREATE_CAP_ERROR;
                error_code_d = NORTHCAPE_ERR_RECURSE;
              end
            end
          endcase

          if (HAS_CACHE_INTERFACE == 1'b0 && (!axi_master.rlast || axi_master.rresp != OKAY)) begin
            create_state_d = CREATE_CAP_ERROR;
            error_code_d = NORTHCAPE_ERR_BUS;
          end

          if (HAS_CACHE_INTERFACE == 1'b1 && cache_interface_response_err_q) begin
            create_state_d = CREATE_CAP_ERROR;
            error_code_d = NORTHCAPE_ERR_BUS;
          end

        end
      end
      CREATE_CAP_PREPARE_CHECK_IDLE: begin
        // block RAM has 1-cycle access delay
        create_state_d = CREATE_CAP_CHECK_IDLE;
      end
      CREATE_CAP_CHECK_IDLE: begin
        if (slot_unoccupied) begin
          // found an empty slot
          // can proceed to compute tag and write capability
          if (OPS_TAG_METHOD == NORTHCAPE_CAPABILITY_OPS_CTR && !remaining_rounds_qarma_d) begin
            // tag will be ready in the next cycle - can skip this state entirely
            create_state_d = CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY;
          end else begin
            create_state_d = CREATE_CAP_CBC_MAC;
          end
        end else if (!slot_overflow_d) begin
          // need to check next slot
          create_state_d = CREATE_CAP_PREPARE_CHECK_IDLE;
        end else if (slot_overflow_d) begin
          // error out
          create_state_d = CREATE_CAP_ERROR;
          error_code_d = NORTHCAPE_ERR_UNKNOWN_OPERATION;
        end
      end
      CREATE_CAP_CBC_MAC: begin
        if (remaining_rounds_qarma_q == '0 && qarma_intf.cbc_done) begin
          create_state_d = CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY;
        end else begin
          create_state_d = CREATE_CAP_CBC_MAC;
        end
      end
      CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY, CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY, CREATE_CAP_SETUP_WRITE_UPDATE_PARENT_CAPABILITY, CREATE_CAP_SETUP_WRITE_UPDATE_SECOND_INPUT_CAPABILITY: begin
        if ((HAS_CACHE_INTERFACE == 1'b0 && axi_master.awvalid && axi_master.awready) || (HAS_CACHE_INTERFACE == 1'b1 && cache_interface.response_valid == 1'b1)) begin
          // aw channel complete
          if (HAS_CACHE_INTERFACE == 1'b1 || (HAS_CACHE_INTERFACE == 1'b0 && axi_master.wvalid && axi_master.wready && axi_master.wlast)) begin
            // w chan complete
            if (HAS_CACHE_INTERFACE == 1'b1 || (HAS_CACHE_INTERFACE == 1'b0 && b_chan_complete_d)) begin
              if ((HAS_CACHE_INTERFACE == 1'b1 && cache_interface_response_err_q) || (HAS_CACHE_INTERFACE == 1'b0 && bresp_d != OKAY)) begin
                create_state_d = CREATE_CAP_ERROR;
                error_code_d = NORTHCAPE_ERR_BUS;
              end  // b chan complete
              else if (is_root_capability_i || (update_complete_d && update_complete_second_parent_d)) begin
                // no update to input capability needed
                create_state_d = (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP) ? CREATE_CAP_SWEEP_GETROW : CREATE_CAP_DONE;
              end else begin
                if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP) begin
                  if (parent_capability_is_valid_q) begin
                    // parent has been written in this cycle
                    if (update_complete_d) begin
                      if (create_have_base_capability_q) begin
                        // have yet-to-update the base direct capability
                        create_state_d = CREATE_CAP_SETUP_WRITE_UPDATE_SECOND_INPUT_CAPABILITY;
                      end else begin
                        // hierarchie incomplete, direct parent was updated
                        create_state_d = CREATE_CAP_DONE;
                      end
                    end else begin
                      // yet-to-update the parent
                      create_state_d = CREATE_CAP_SETUP_WRITE_UPDATE_PARENT_CAPABILITY;
                    end
                  end else begin
                    // drop after parent was revoked
                    // modification of parent would be logic error
                    create_state_d = CREATE_CAP_DONE;
                  end
                end else if (operation_i inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK}) begin
                  // no need to hold for 2 cycles
                  create_state_d = update_complete_d ? CREATE_CAP_SETUP_WRITE_UPDATE_SECOND_INPUT_CAPABILITY : CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY;
                end else if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT) begin
                  // only input is updated
                  create_state_d = CREATE_CAP_DONE;
                end else begin
                  create_state_d = CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY;
                end
              end
            end else begin
              // wait B chan
              create_state_d = CREATE_CAP_WAIT_RESPONSE;
            end
          end else begin
            // wait W chan
            create_state_d = CREATE_CAP_WAIT_WRITE_COMPLETE;
          end
        end
      end
      CREATE_CAP_WAIT_WRITE_COMPLETE: begin
        // not used / reachable if HAS_CACHE_INTERFACE
        if (HAS_CACHE_INTERFACE == 1'b0 && axi_master.wvalid && axi_master.wready && axi_master.wlast) begin
          if (b_chan_complete_d) begin
            // b chan complete - request done
            if (is_root_capability_i || (update_complete_q && update_complete_second_parent_q)) begin
              // no update to input capability needed
              create_state_d = CREATE_CAP_DONE;
            end else begin
              if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP) begin
                if (parent_capability_is_valid_q) begin
                  if (update_complete_q) begin
                    if (create_have_base_capability_q) begin
                      // have yet-to-update the base direct capability
                      create_state_d = CREATE_CAP_SETUP_WRITE_UPDATE_SECOND_INPUT_CAPABILITY;
                    end else begin
                      // hierarchie incomplete, direct parent was updated
                      create_state_d = CREATE_CAP_DONE;
                    end
                  end else begin
                    // yet-to-update the parent
                    create_state_d = CREATE_CAP_SETUP_WRITE_UPDATE_PARENT_CAPABILITY;
                  end
                end else begin
                  // drop after parent was revoked
                  // modification of parent would be logic error
                  create_state_d = CREATE_CAP_DONE;
                end
              end else if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE || operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK) begin
                create_state_d = update_complete_q ? CREATE_CAP_SETUP_WRITE_UPDATE_SECOND_INPUT_CAPABILITY : CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY;
              end else if (operation_i inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT}) begin
                // only input is updated
                create_state_d = CREATE_CAP_DONE;
              end else begin
                create_state_d = CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY;
              end
            end
            if (bresp_d != OKAY) begin
              create_state_d = CREATE_CAP_ERROR;
              error_code_d = NORTHCAPE_ERR_BUS;
            end
          end else begin
            // wait B chan
            create_state_d = CREATE_CAP_WAIT_RESPONSE;
          end
        end
      end
      CREATE_CAP_WAIT_RESPONSE: begin
        // not used / reachable if HAS_CACHE_INTERFACE
        if (HAS_CACHE_INTERFACE == 1'b0 && b_chan_complete_d) begin
          // b chan complete - request done
          if (is_root_capability_i || (update_complete_q && update_complete_second_parent_q)) begin
            // no update to input capability needed
            create_state_d = CREATE_CAP_DONE;
          end else begin
            if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP) begin
              if (parent_capability_is_valid_q) begin
                if (update_complete_q) begin
                  if (create_have_base_capability_q) begin
                    // have yet-to-update the base direct capability
                    create_state_d = CREATE_CAP_SETUP_WRITE_UPDATE_SECOND_INPUT_CAPABILITY;
                  end else begin
                    // hierarchie incomplete, direct parent was updated
                    create_state_d = CREATE_CAP_DONE;
                  end
                end else begin
                  // yet-to-update the parent
                  create_state_d = CREATE_CAP_SETUP_WRITE_UPDATE_PARENT_CAPABILITY;
                end
              end else begin
                // drop after parent was revoked
                // modification of parent would be logic error
                create_state_d = CREATE_CAP_DONE;
              end
            end else if (operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE || operation_i == NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK) begin
              create_state_d = update_complete_q ? CREATE_CAP_SETUP_WRITE_UPDATE_SECOND_INPUT_CAPABILITY : CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY;
            end else if (operation_i inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT}) begin
              // only input is updated
              create_state_d = CREATE_CAP_DONE;
            end else begin
              create_state_d = CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY;
            end
          end

          if (bresp_d != OKAY) begin
            create_state_d = CREATE_CAP_ERROR;
            error_code_d = NORTHCAPE_ERR_BUS;
          end
        end
      end
      CREATE_CAP_SWEEP_GETROW: begin
        // 1 cycle latency for BRAM
        create_state_d = CREATE_CAP_SWEEP;
      end
      CREATE_CAP_SWEEP: begin
        if (bram_out == '0) begin
          // complete row can be skipped
          if (sweep_capability_id_q / BITMAP_BRAM_DATA_WIDTH == BITMAP_BRAM_DATA_DEPTH - 1) begin
            // last row
            sweep_capability_id_d = '0;
            create_state_d = CREATE_CAP_DONE;
          end else begin
            // try again with next row
            // could have just kicked the last member of the row -> ensure that the offset into the row gets reset too
            sweep_capability_id_d -= sweep_capability_id_d % BITMAP_BRAM_DATA_WIDTH;
            sweep_capability_id_d += BITMAP_BRAM_DATA_WIDTH;
            create_state_d = CREATE_CAP_SWEEP_GETROW;
          end
        end else begin
          // have to go one-by-one
          sweep_capability_id_d = sweep_capability_id_q + 1;
          if (bram_out[sweep_capability_id_q%BITMAP_BRAM_DATA_WIDTH]) begin
            // valid - check
            create_state_d = CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY;
          end
          else if(sweep_capability_id_q % BITMAP_BRAM_DATA_WIDTH == BITMAP_BRAM_DATA_WIDTH - 1)
          begin
            // next row
            create_state_d = CREATE_CAP_SWEEP_GETROW;
          end

          if (sweep_capability_id_q == BITMAP_BRAM_DATA_WIDTH * BITMAP_BRAM_DATA_DEPTH - 1) begin
            // completed the entire CMT -> wrap-around to 1 in next cycle, signal completion
            create_state_d = CREATE_CAP_DONE;
          end
        end
      end
      CREATE_CAP_ERROR, CREATE_CAP_DONE: begin
        create_state_d = CREATE_CAP_IDLE;
      end
      default: begin
        create_state_d = create_state_q;
      end
    endcase
  end : createCapStateMachine

  assign done_o  = (create_state_q == CREATE_CAP_DONE || create_state_q == CREATE_CAP_ERROR);
  assign error_o = (create_state_q == CREATE_CAP_ERROR);

  always_comb begin : debugOutputGen
    unique case (create_state_q)
      CREATE_CAP_COMPLETE_RESET: begin
        debug_state_o = 0;
      end
      CREATE_CAP_COLLECT_ENTROPY_HIGH: begin
        debug_state_o = 1;
      end
      CREATE_CAP_COLLECT_ENTROPY_LOW: begin
        debug_state_o = 2;
      end
      CREATE_CAP_CREATE_QARMA_KEY_HIGH: begin
        debug_state_o = 3;
      end
      CREATE_CAP_WAIT_QARMA_KEY_HIGH: begin
        debug_state_o = 4;
      end
      CREATE_CAP_CREATE_QARMA_KEY_LOW: begin
        debug_state_o = 5;
      end
      CREATE_CAP_WAIT_QARMA_KEY_LOW: begin
        debug_state_o = 6;
      end
      CREATE_CAP_CREATE_INITIAL_NONCE: begin
        debug_state_o = 7;
      end
      CREATE_CAP_WAIT_INITIAL_NONCE: begin
        debug_state_o = 8;
      end
      CREATE_CAP_IDLE: begin
        debug_state_o = 9;
      end
      CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY: begin
        debug_state_o = 10;
      end
      CREATE_CAP_GET_INPUT_CAPABILITY: begin
        debug_state_o = 11;
      end
      CREATE_CAP_PREPARE_GET_INPUT_CAPABILITY_RIGHT: begin
        debug_state_o = 12;
      end
      CREATE_CAP_GET_INPUT_CAPABILITY_RIGHT: begin
        debug_state_o = 13;
      end
      CREATE_CAP_PREPARE_RECURSE_INPUT_CAPABILITY: begin
        debug_state_o = 14;
      end
      CREATE_CAP_RECURSE_INPUT_CAPABILITY: begin
        debug_state_o = 15;
      end
      CREATE_CAP_PREPARE_CHECK_IDLE: begin
        debug_state_o = 16;
      end
      CREATE_CAP_CHECK_IDLE: begin
        debug_state_o = 17;
      end
      CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY: begin
        debug_state_o = 18;
      end
      CREATE_CAP_SETUP_WRITE_UPDATE_INPUT_CAPABILITY: begin
        debug_state_o = 19;
      end
      CREATE_CAP_SETUP_WRITE_UPDATE_PARENT_CAPABILITY: begin
        debug_state_o = 20;
      end
      CREATE_CAP_SETUP_WRITE_UPDATE_SECOND_INPUT_CAPABILITY: begin
        debug_state_o = 21;
      end
      CREATE_CAP_WAIT_WRITE_COMPLETE: begin
        debug_state_o = 22;
      end
      CREATE_CAP_WAIT_RESPONSE: begin
        debug_state_o = 23;
      end
      CREATE_CAP_CBC_MAC: begin
        debug_state_o = 24;
      end
      CREATE_CAP_DONE: begin
        debug_state_o = 25;
      end
      CREATE_CAP_ERROR: begin
        debug_state_o = 26;
      end
      CREATE_CAP_SWEEP_GETROW: begin
        debug_state_o = 27;
      end
      CREATE_CAP_SWEEP: begin
        debug_state_o = 28;
      end
      CREATE_CAP_PREPARE_RESET_BITMAP: begin
        debug_state_o = 30;
      end
      default: begin
        debug_state_o = '1;
      end
    endcase

    debug_is_unlock_o = create_drop_is_unlock_q;
    debug_input_capability_valid_o = input_capability_valid == NORTHCAPE_NO_ERROR;
    debug_update_complete_o = {update_complete_q, update_complete_second_parent_q};
    debug_capabilities_valid_o = {
      create_have_parent_capability_q, create_have_base_capability_q, parent_capability_is_valid_q
    };
    debug_capability_token_o = capability_token_i;
    debug_capability_operation_o = operation_i;
  end : debugOutputGen

  // base and length are directly registered in, as they are not contained in, e.g., a lock-holder's entry
  always_comb begin : inspectOutputGen
    inspect_restrictions_o = input_capability_q.restrictions;

    // valid or ignored
    inspect_is_partial_reveal_d = (input_capability_d1.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID && (input_capability_d1.restrictions.body.task_restriction.device_id != device_id_i || input_capability_d1.restrictions.body.task_restriction.task_id != task_id_i));

    if (input_capability_q.capability_type == NORTHCAPE_CMT_DIRECT) begin
      inspect_permissions_o = input_capability_q.permissions.direct_capability_permissions;
    end else begin
      inspect_permissions_o.read_permission = input_capability_q.permissions.indirect_capability_permissions.read_permission;
      inspect_permissions_o.write_permission = input_capability_q.permissions.indirect_capability_permissions.write_permission;
      inspect_permissions_o.execute_permission = input_capability_q.permissions.indirect_capability_permissions.execute_permission;
      inspect_permissions_o.lockable_permission = base_direct_capability_q.permissions.direct_capability_permissions.lockable_permission;
      inspect_permissions_o.irq_accessible_permission = base_direct_capability_q.permissions.direct_capability_permissions.irq_accessible_permission;
      inspect_permissions_o.cacheable_tlb = input_capability_q.permissions.indirect_capability_permissions.cacheable_tlb;
      inspect_permissions_o.cacheable_access = input_capability_q.permissions.indirect_capability_permissions.cacheable_access;
    end

    if (inspect_is_partial_reveal_d == 1'b1) begin
      // only execute and IRQ accessible are needed to determine if this is callable
      inspect_permissions_o.read_permission = 1'b0;
      inspect_permissions_o.write_permission = 1'b0;
      inspect_permissions_o.lockable_permission = 1'b0;
      inspect_permissions_o.cacheable_tlb = 1'b0;
      inspect_permissions_o.cacheable_access = 1'b0;
    end
  end : inspectOutputGen

  `NORTHCAPE_UNREAD(axi_master.rid);
  `NORTHCAPE_UNREAD(axi_master.ruser);
  `NORTHCAPE_UNREAD(axi_master.bid);
  `NORTHCAPE_UNREAD(axi_master.buser);
  `NORTHCAPE_UNREAD(cmt_interface.cmt_base);
  `NORTHCAPE_UNREAD(cmt_interface.table_size_clog2);
  `NORTHCAPE_UNREAD(cmt_interface.reset_done);
  `NORTHCAPE_UNREAD(cmt_interface.clk_i);
  `NORTHCAPE_UNREAD(cmt_interface.need_flush_data_caches);
  `NORTHCAPE_UNREAD(cmt_interface.wrote_any_capability);
  `NORTHCAPE_UNREAD(cmt_interface.written_capability);

  // some bits are never read
  `NORTHCAPE_UNREAD(input_cap_id);

  // TODO Vivado complains about this for some reason
  `NORTHCAPE_UNREAD(device_id_i);
  `NORTHCAPE_UNREAD(task_id_i);

  // ISR FSM does not implement most operations, which is why many inputs and locals are never read
  generate
    if (IS_ISR_ONLY == 1'b1) begin

      `NORTHCAPE_UNREAD(input_capability_q.location);
      `NORTHCAPE_UNREAD(input_capability_q.refcount);
      `NORTHCAPE_UNREAD(input_capability_q.tag);
      `NORTHCAPE_UNREAD(input_capability_q.nonce);
      `NORTHCAPE_UNREAD(input_capability_q.reserved);

      `NORTHCAPE_UNREAD(base_direct_capability_q);

      `NORTHCAPE_UNREAD(create_parent_capability_id_q);

      `NORTHCAPE_UNREAD(axi_master.awready);
      `NORTHCAPE_UNREAD(axi_master.wready);
      `NORTHCAPE_UNREAD(axi_master.bresp);
      `NORTHCAPE_UNREAD(axi_master.bvalid);

      `NORTHCAPE_UNREAD(rng_interface_rng_out);

      `NORTHCAPE_UNREAD(capability_token_right_i);

      `NORTHCAPE_UNREAD(base_direct_capability_id_q);

      `NORTHCAPE_UNREAD(restriction_device_id_i);
      `NORTHCAPE_UNREAD(device_interpreted_restriction_i);
      `NORTHCAPE_UNREAD(restriction_type_i);
      `NORTHCAPE_UNREAD(direction_i);
      `NORTHCAPE_UNREAD(capability_type_i);

      `NORTHCAPE_UNREAD(restriction_task_id_i);


    end

    if (HAS_CACHE_INTERFACE == 1'b1) begin
      `NORTHCAPE_UNREAD(axi_master.arready);

      `NORTHCAPE_UNREAD(axi_master.awready);

      `NORTHCAPE_UNREAD(axi_master.wready);

      `NORTHCAPE_UNREAD(axi_master.rvalid);
      `NORTHCAPE_UNREAD(axi_master.rdata);
      `NORTHCAPE_UNREAD(axi_master.rid);
      `NORTHCAPE_UNREAD(axi_master.ruser);
      `NORTHCAPE_UNREAD(axi_master.rresp);
      `NORTHCAPE_UNREAD(axi_master.rlast);

      `NORTHCAPE_UNREAD(axi_master.bvalid);
      `NORTHCAPE_UNREAD(axi_master.bid);
      `NORTHCAPE_UNREAD(axi_master.buser);
      `NORTHCAPE_UNREAD(axi_master.bresp);
      `NORTHCAPE_UNREAD(is_irq_i);
    end
  endgenerate
  /* the offset is at least 8 bits and always ignored */
  `NORTHCAPE_UNREAD(capability_token_right_i[7:0]);

  `NORTHCAPE_UNREAD(cache_interface.clk_i);

  `NORTHCAPE_UNREAD(unlock_key_q);


  assign idle_check_occupied_event_o = (create_state_q == CREATE_CAP_CHECK_IDLE) && !slot_unoccupied;

`ifdef NORTHCAPE_TEST_COVERAGE
  covergroup capability_ops_create_cap_coverage_group @(posedge clk_i);
    coverpoint create_state_q;
    coverpoint slot_overflow_q iff create_state_q == CREATE_CAP_CHECK_IDLE;
    coverpoint slot_unoccupied iff create_state_q == CREATE_CAP_CHECK_IDLE;
    coverpoint capability_token_o[63:62] iff create_state_q == CREATE_CAP_SETUP_WRITE_NEW_CAPABILITY{
      bins offset_32 = {2'b00};
      bins offset_16 = {2'b11};
      bins offset_24 = {2'b10};
      bins offset_0 = {2'b01};
      bins others = default;
    }
    coverpoint input_capability_valid iff create_state_q == CREATE_CAP_GET_INPUT_CAPABILITY;
  endgroup

  capability_ops_create_cap_coverage_group cov_group;
  initial begin
    cov_group = new;
  end

`endif
endmodule
