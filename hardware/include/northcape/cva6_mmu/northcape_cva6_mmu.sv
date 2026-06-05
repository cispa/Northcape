import northcape_types::*;
import northcape_mmu_common::NorthcapeMMUCommon;

module northcape_cva6_mmu #(
    parameter int XLEN = 64,
    parameter type access_size_t = logic [$clog2(8)-1:0],
    parameter bit IS_EXECUTE = 1'b0,
    parameter device_id_t DEVICE_ID = 32'h0,
    parameter bit CAN_HANDLE_MISPREDICT = 1'b1,
    parameter bit HAS_CACHE = 1'b0,
    parameter bit CACHE_IS_FULLY_ASSOCIATIVE = 1'b0,
    parameter CACHE_SIZE = -1,
    parameter CBO_CACHELINE_WIDTH = 16
) (
    input logic clk_i,
    input logic rst_ni,

    // cva6 -> northcape: translate this token please
    input logic [XLEN-1:0] data_address_i,
    input logic data_is_store_i,
    input access_size_t data_access_size_i,
    // precondition to translation_immediate_o
    input logic data_is_immediate_i,
    // read + write
    input logic data_is_atomic_i,
    // are we in IRQ context?
    input logic data_is_irq_i,
    input logic data_is_valid_i,
    // branch predict - capture task ID to undo subsystem call if needed
    input logic data_is_branch_predict_i,
    // mispredict - undo changes to task ID if any
    input logic data_is_mispredict_i,
    // CPU flush - abort the request
    input logic data_abort_i,
    // correct predict - reset locked task ID
    input logic data_is_correct_predict_i,

    // northcape -> cva6: translated token, error if any
    output logic [XLEN-1:0] translated_address_o,
    output logic translation_error_o,
    output logic translation_valid_o,
    // response in same cycle
    output logic translation_immediate_o,
    // is non-cacheable?
    output logic translation_requires_non_cacheable_o,
    // device-specific restriction
    output northcape_device_interpreted_restriction_t translation_device_specific_restriction_o,
    // was this a subsystem call?
    output logic translation_is_subsystem_call_o,
    // was this a subsystem call to ourselves?
    output logic translation_is_subsystem_call_self_o,
    // was this a cache miss? - raised only once per translation
    output logic translation_cache_miss_event_o,
    // cache block operation would leave capability bounds
    output logic translation_cbo_misaligned_o,

    // second port for mtvec / translation of auxilliary capability
    // cva6 -> northcape: aux address, (hard coded) metadata
    input logic [XLEN-1:0] aux_addr_i,
    input logic [XLEN-1:0] aux_expected_length_i,
    input axis_validate_request_perm_t aux_access_type_i,
    input task_id_t aux_check_task_id_i,
    input logic [XLEN-1:0] aux_access_length_i,
    input logic aux_addr_valid_i,

    // northcape->cva6: translated address (valid for 1 cycle only)
    output logic [XLEN-1:0] aux_translated_addr_o,
    output logic aux_translated_addr_valid_o,
    output logic aux_translated_addr_err_o,

    // conveys task ID
    input northcape_types::task_id_t current_task_id_irq_i,
    input northcape_types::task_id_t current_task_id_non_irq_i,
    input logic is_subsystem_call_i,

    output northcape_types::task_id_t current_task_id_irq_o,
    output northcape_types::task_id_t current_task_id_non_irq_o,

    // overwrite task ID with old task ID, e.g., on speculation error
    input northcape_types::task_id_t task_id_overwrite_i,
    logic task_id_overwrite_active_i,

    // interface to capability resolver
    Axis5.TRANSMITTER axis_validate_request,
    Axis5.RECEIVER axis_validate_response,

    // cache flush needed?
    input logic northcape_cache_flush_i,

    // current CMT metadata from operations module
    NorthcapeCMTInterface.CONSUMER cmt_interface,

    output northcape_resolve_error_t final_error_o,

    output logic dbg_cache_write_o,
    output northcape_types::northcape_physical_address_t dbg_cache_write_phys_addr_o,
    output northcape_types::segment_length_t dbg_cache_write_segment_length_o,
    output logic [2:0] dbg_state_o,
    output northcape_types::northcape_physical_address_t dbg_cache_read_phys_addr_o,
    output northcape_types::segment_length_t dbg_cache_read_segment_length_o
);


  `include "northcape_unread.vh"

  typedef enum logic [2:0] {
    IDLE,
    WAIT_REQUEST,
    WAIT_RESPONSE,
    HOLD_RESPONSE,
    ABORT_REQUEST,
    ABORT_WAIT_RESPONSE,
    TRANSLATE_AUX_DO_REQUEST,
    TRANSLATE_AUX_WAIT_RESPONSE
  } mmu_state_t;

  typedef NorthcapeMMUCommon#(
      .AXI_ADDR_WIDTH(XLEN),
      .AXI_DATA_WIDTH(XLEN),
      .AXI_ID_WIDTH(1),
      .AXI_USER_WIDTH(1),
      .ACCEPT_AXI_WRAP_BURSTS(1'b0),
      .IS_WRITE_CHAN(1'b0)
  ) northcape_mmu_common_t;

  mmu_state_t state_q, state_d;

  axis_validate_request_tdata_t  request_data;
  axis_validate_response_tdata_t response_data;
  // bounds_check_ok_miss only does checks needed for resolver response - shorter combinatorical path
  logic bounds_check_ok, bounds_check_ok_miss;

  logic is_subsystem_call;

  task_id_t task_id_d;

  logic [XLEN-1:0] capability_offset;

  int bytes_in_burst;

  northcape_resolve_error_t final_error_d, final_error_d1, final_error_q;


  // buffer for last request, used to hold output while LSU keeps requesting it
  logic [XLEN-1:0] data_address_q, data_address_d;
  logic data_is_store_q, data_is_store_d;
  access_size_t data_access_size_q, data_access_size_d;
  logic data_is_atomic_q, data_is_atomic_d;
  logic data_is_irq_q, data_is_irq_d;

  // buffer for last response - tdata gone after tready
  logic [XLEN-1:0] translated_address_q, translated_address_d;
  logic translation_error_q, translation_error_d;
  logic translation_requires_non_cacheable_q, translation_requires_non_cacheable_d;
  logic translation_is_subsystem_call_q, translation_is_subsystem_call_d;
  logic translation_is_subsystem_call_self_q, translation_is_subsystem_call_self_d;

  northcape_device_interpreted_restriction_t
      translation_device_specific_restriction_q, translation_device_specific_restriction_d;

  logic request_is_helt;

  logic cache_miss;
  axis_validate_response_tdata_t cache_response;
  northcape_permissions_t requested_permissions;
  logic [$bits(northcape_permissions_t)-1:0] requested_permissions_raw, given_permissions_raw;

  //===================================
  // Default assignments
  //===================================
  assign axis_validate_request.tstrb   = '1;
  assign axis_validate_request.tkeep   = '1;
  assign axis_validate_request.tid     = 1'b0;
  assign axis_validate_request.tdest   = 1'b0;
  assign axis_validate_request.tuser   = 1'b0;
  assign axis_validate_request.twakeup = 1'b1;
  assign axis_validate_request.tlast   = 1'b1;
  //===================================
  // Components
  //===================================

  generate
    if (HAS_CACHE) begin : gen_cache

      if (CACHE_IS_FULLY_ASSOCIATIVE) begin : gen_cache_fully_assoc
        logic cache_write;
        northcape_cva6_mmu_cache_full_assoc #(
            .CACHE_SIZE(CACHE_SIZE)
        ) i_mmu_cache (
            .clk_i(clk_i),
            .rst_ni(rst_ni),
            .lookup_capability_i(request_data.address),
            .lookup_tag_i(request_data.tag),
            .lookup_valid_i(data_is_valid_i),
            .lookup_response_o(cache_response),
            .cache_miss_o(cache_miss),
            .missunit_response_i(axis_validate_response.tdata),
            .missunit_response_valid_i(cache_write),
            .cache_flush_i(northcape_cache_flush_i),
            .cmt_interface(cmt_interface)
        );
        // we only admit entries that are cacheable for both the TLB and data cache -- otherwise, logic for setting cacheable below does not work
        // not too bad performance-wise, as the entry will likely still be in the L2 TLB
        assign cache_write = axis_validate_response.tvalid && !data_abort_i && !(state_q inside {ABORT_REQUEST, ABORT_WAIT_RESPONSE, TRANSLATE_AUX_WAIT_RESPONSE}) && response_data.permissions.indirect_capability_permissions.cacheable_tlb && response_data.permissions.indirect_capability_permissions.cacheable_access && bounds_check_ok_miss;
        assign dbg_cache_write_phys_addr_o = response_data.address;
        assign dbg_cache_write_segment_length_o = response_data.segment_length;
        assign dbg_cache_read_phys_addr_o = cache_response.address;
        assign dbg_cache_read_segment_length_o = cache_response.segment_length;
        assign dbg_cache_write_o = cache_write;
      end : gen_cache_fully_assoc
      else begin : gen_cache_direct
        logic cache_write;
        northcape_cva6_mmu_cache #(
            .CACHE_SIZE(CACHE_SIZE)
        ) i_mmu_cache (
            .clk_i(clk_i),
            .rst_ni(rst_ni),
            .lookup_capability_i(request_data.address),
            .lookup_tag_i(request_data.tag),
            .lookup_response_o(cache_response),
            .cache_miss_o(cache_miss),
            .missunit_response_i(axis_validate_response.tdata),
            .missunit_response_valid_i(cache_write),
            .cache_flush_i(northcape_cache_flush_i),
            .cmt_interface(cmt_interface)
        );
        // we only admit entries that are cacheable for both the TLB and data cache -- otherwise, logic for setting cacheable below does not work
        // not too bad performance-wise, as the entry will likely still be in the L2 TLB
        assign cache_write = axis_validate_response.tvalid && !data_abort_i && !(state_q inside {ABORT_REQUEST, ABORT_WAIT_RESPONSE, TRANSLATE_AUX_WAIT_RESPONSE}) && response_data.permissions.indirect_capability_permissions.cacheable_tlb && response_data.permissions.indirect_capability_permissions.cacheable_access && bounds_check_ok_miss;
        assign dbg_cache_write_phys_addr_o = response_data.address;
        assign dbg_cache_write_segment_length_o = response_data.segment_length;
        assign dbg_cache_read_phys_addr_o = cache_response.address;
        assign dbg_cache_read_segment_length_o = cache_response.segment_length;
        assign dbg_cache_write_o = cache_write;
      end : gen_cache_direct
    end : gen_cache
    else begin : gen_no_cache
      assign cache_miss = 1'b1;
      assign cache_response = '0;
      assign dbg_cache_write_phys_addr_o = '0;
      assign dbg_cache_write_segment_length_o = '0;
      assign dbg_cache_read_phys_addr_o = '0;
      assign dbg_cache_read_segment_length_o = '0;
      assign dbg_cache_write_o = 1'b0;
    end : gen_no_cache
  endgenerate


  //===================================
  // Registers
  //===================================

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : stateReg
    if (!rst_ni) begin
      state_q <= IDLE;
    end else begin
      state_q <= state_d;
    end
  end : stateReg

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : inputLatch
    if (!rst_ni) begin
      {data_address_q, data_is_store_q, data_access_size_q, data_is_atomic_q, data_is_irq_q} <= '0;
    end else begin
      {data_address_q, data_is_store_q, data_access_size_q, data_is_atomic_q, data_is_irq_q} <= {
        data_address_d, data_is_store_d, data_access_size_d, data_is_atomic_d, data_is_irq_d
      };
    end
  end : inputLatch


  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : outputLatch
    if (!rst_ni) begin
      translated_address_q <= '0;
      translation_error_q <= 1'b0;
      translation_requires_non_cacheable_q <= 1'b0;
      translation_device_specific_restriction_q <= '0;
      translation_is_subsystem_call_q <= 1'b0;
      translation_is_subsystem_call_self_q <= 1'b0;
      final_error_q <= NORTHCAPE_RESOLVE_NO_ERROR;
    end else begin
      translated_address_q <= translated_address_d;
      translation_error_q <= translation_error_d;
      translation_requires_non_cacheable_q <= translation_requires_non_cacheable_d;
      translation_device_specific_restriction_q <= translation_device_specific_restriction_d;
      translation_is_subsystem_call_q <= translation_is_subsystem_call_d;
      translation_is_subsystem_call_self_q <= translation_is_subsystem_call_self_d;
      final_error_q <= final_error_d;
    end
  end : outputLatch

  //===================================
  // Combinatorical logic
  //===================================

  // CANNOT stall
  assign axis_validate_response.tready = 1'b1;

  assign capability_offset = capability_accessors#(XLEN)::capability_get_offset(data_address_i);

  assign bytes_in_burst = 1 << data_access_size_i;

  always_comb begin : boundsCheckLogic
    final_error_d1 = NORTHCAPE_RESOLVE_NO_ERROR;
    if (response_data.error_code != NORTHCAPE_RESOLVE_NO_ERROR) begin
      final_error_d1 = response_data.error_code;
    end
    // subsystem calls only allowed to first byte of segment to prevent jumping over parts of the trampoline
    bounds_check_ok = !northcape_mmu_common_t::resolved_address_overlaps_cmt(
        cmt_interface.cmt_base, cmt_interface.table_size_clog2, response_data.address,
            bytes_in_burst);
    if (~bounds_check_ok && final_error_d1 == NORTHCAPE_RESOLVE_NO_ERROR) begin
      final_error_d1 = NORTHCAPE_RESOLVE_ERROR_CMT_OVERLAP;
    end
    bounds_check_ok &= 64'(bytes_in_burst) + 64'(capability_offset) <= 64'(response_data.segment_length);
    if (~bounds_check_ok && final_error_d1 == NORTHCAPE_RESOLVE_NO_ERROR) begin
      final_error_d1 = NORTHCAPE_RESOLVE_ERROR_BOUNDS;
    end
    bounds_check_ok &= (!is_subsystem_call || capability_offset == '0);
    if (~bounds_check_ok && final_error_d1 == NORTHCAPE_RESOLVE_NO_ERROR) begin
      final_error_d1 = NORTHCAPE_RESOLVE_ERROR_SUBSYS_CALL_OFFSET;
    end
    // checks below are ONLY needed for cache hits, as they are offloaded to resolver on miss
    bounds_check_ok_miss = bounds_check_ok;

    translation_cbo_misaligned_o = translated_address_o - translated_address_o % (CBO_CACHELINE_WIDTH/8) < response_data.address;
    translation_cbo_misaligned_o |= translated_address_o + CBO_CACHELINE_WIDTH/8 - (translated_address_o % (CBO_CACHELINE_WIDTH/8)) >= response_data.address + response_data.segment_length;

    requested_permissions = '0;
    requested_permissions.indirect_capability_permissions.read_permission = IS_EXECUTE ? 1'b0 : (!data_is_store_i || data_is_atomic_i);
    requested_permissions.indirect_capability_permissions.write_permission = IS_EXECUTE ? 1'b0 : (data_is_store_i || data_is_atomic_i);
    requested_permissions.indirect_capability_permissions.execute_permission = IS_EXECUTE;
    requested_permissions.indirect_capability_permissions.irq_accessible_permission = data_is_irq_i;
    // lockable, cacheable not checked here
    requested_permissions_raw = requested_permissions;
    given_permissions_raw = response_data.permissions;


    if (HAS_CACHE && !cache_miss) begin
      // normally, the resolver checks the permissions and task ID
      // however, in case of a cache hit, the parameters of the current request might have changed
      // so we have to check here again

      // permissions check
      bounds_check_ok &= (requested_permissions_raw & given_permissions_raw) == requested_permissions_raw;
      if (~bounds_check_ok && final_error_d1 == NORTHCAPE_RESOLVE_NO_ERROR) begin
        final_error_d1 = NORTHCAPE_RESOLVE_ERROR_PERMISSIONS;
      end
      if (!is_subsystem_call) begin
        unique case (response_data.restriction_type)
          // nothing to check
          NORTHCAPE_RESTRICTIONS_NONE, NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED: ;
          NORTHCAPE_RESTRICTIONS_SET_TASK_ID: begin
            bounds_check_ok &= capability_offset == '0 || task_id_d == response_data.restriction.task_restriction.task_id;
            if (~bounds_check_ok && final_error_d1 == NORTHCAPE_RESOLVE_NO_ERROR) begin
              final_error_d1 = NORTHCAPE_RESOLVE_ERROR_SUBSYS_CALL_OFFSET;
            end
          end
          NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND: begin
            bounds_check_ok &= task_id_d == response_data.restriction.task_restriction.task_id;
            if (~bounds_check_ok && final_error_d1 == NORTHCAPE_RESOLVE_NO_ERROR) begin
              final_error_d1 = NORTHCAPE_RESOLVE_ERROR_RESTRICTIONS;
            end
          end
          default: begin
            // undefined - reject
            bounds_check_ok = 1'b0;
            if (~bounds_check_ok && final_error_d1 == NORTHCAPE_RESOLVE_NO_ERROR) begin
              final_error_d1 = NORTHCAPE_RESOLVE_ERROR_RESTRICTIONS;
            end
          end
        endcase

      end

    end
  end : boundsCheckLogic

  always_comb begin : immediateOutLogic
    translation_immediate_o = data_is_immediate_i;
    translation_immediate_o             &= ((state_q == IDLE && ((HAS_CACHE && !cache_miss))) || !cmt_interface.reset_done);
    // load/store units expect us to signal TLB hit as soon as data are valid
    translation_immediate_o |= translation_valid_o;
  end : immediateOutLogic

  always_comb begin : responseDataLogic
    response_data = axis_validate_response.tdata;
    if (HAS_CACHE) begin
      response_data = cache_response;
    end
    /* validate response trumps cache response; cache response might be invalid on miss */
    if (axis_validate_response.tvalid) begin
      response_data = axis_validate_response.tdata;
    end
  end : responseDataLogic


  always_comb begin : requestHoldLogic
    // hold by default
    {data_address_d, data_is_store_d, data_access_size_d, data_is_atomic_d, data_is_irq_d} = {
      data_address_q, data_is_store_q, data_access_size_q, data_is_atomic_q, data_is_irq_q
    };
    if (!data_abort_i && !(state_q inside {ABORT_REQUEST, ABORT_WAIT_RESPONSE}) && data_is_valid_i) begin
      // this is an input set for which we have a valid translation - hold it until next request
      // in case a cache exists, this doubles as the replacement input
      {data_address_d, data_is_store_d, data_access_size_d, data_is_atomic_d, data_is_irq_d} = {
        data_address_i, data_is_store_i, data_access_size_i, data_is_atomic_i, data_is_irq_i
      };
    end
    // signal starts being valid as soon as response arrives, so check against "new" value, not register
    request_is_helt = {data_address_i, data_is_store_i, data_access_size_i, data_is_atomic_i, data_is_irq_i} == {data_address_q, data_is_store_q, data_access_size_q, data_is_atomic_q, data_is_irq_q};
    // need to indicate 0 as soon as no request 
    request_is_helt &= data_is_valid_i;
  end : requestHoldLogic

  always_comb begin : responseHoldLogic
    translated_address_d = translated_address_o;
    translation_error_d = translation_error_o;
    final_error_d = final_error_o;
    translation_requires_non_cacheable_d = translation_requires_non_cacheable_o;
    translation_device_specific_restriction_d = translation_device_specific_restriction_o;
    translation_is_subsystem_call_d = translation_is_subsystem_call_o;
    translation_is_subsystem_call_self_d = translation_is_subsystem_call_self_o;

    if (state_q == HOLD_RESPONSE && request_is_helt) begin
      translated_address_d = translated_address_q;
      translation_error_d = translation_error_q;
      final_error_d = final_error_q;
      translation_requires_non_cacheable_d = translation_requires_non_cacheable_q;
      translation_device_specific_restriction_d = translation_device_specific_restriction_q;
      translation_is_subsystem_call_d = translation_is_subsystem_call_q;
      translation_is_subsystem_call_self_d = translation_is_subsystem_call_self_q;
    end
  end : responseHoldLogic


  always_comb begin : validateRequestLogic
    request_data = '0;
    if (state_q inside {WAIT_REQUEST, WAIT_RESPONSE, ABORT_REQUEST}) begin
      // use registered value to prevent LSU from changing the input address before we do cache replacement
      request_data.address = capability_accessors#(XLEN)::capability_get_id(data_address_q);
      request_data.tag     = capability_accessors#(XLEN)::capability_get_tag(data_address_q);
    end else begin
      request_data.address = capability_accessors#(XLEN)::capability_get_id(data_address_i);
      request_data.tag     = capability_accessors#(XLEN)::capability_get_tag(data_address_i);
    end

    axis_validate_request.tvalid = 1'b0;

    /* parameters only become valid on second cycle of the request onwards */
    if (IS_EXECUTE) begin
      request_data.access_type = data_is_irq_q ? EXECUTE_IRQ : EXECUTE;
    end else begin
      if (data_is_store_i) begin
        if (data_is_atomic_i) begin
          request_data.access_type = data_is_irq_q ? READ_WRITE_IRQ : READ_WRITE;
        end else begin
          request_data.access_type = data_is_irq_q ? WRITE_IRQ : WRITE;
        end
      end else begin
        request_data.access_type = data_is_irq_q ? READ_IRQ : READ;
      end
    end

    request_data.task_id        = task_id_d;
    request_data.device_id      = DEVICE_ID;

    axis_validate_request.tdata = request_data;
    unique case (state_q)
      IDLE: begin
        // timing: use FSM to figure out when to set this, do not wait for cache_miss here
        axis_validate_request.tvalid = 1'b0;
      end
      WAIT_REQUEST, ABORT_REQUEST: begin
        // only get here when preconditions are met
        axis_validate_request.tvalid = 1'b1;
      end
      HOLD_RESPONSE: begin
        if (!request_is_helt) begin
          // new request
          // need not check CMT interface - do not get here unless reset done
          axis_validate_request.tvalid = data_is_valid_i & cache_miss & !data_abort_i;
        end
      end
      TRANSLATE_AUX_DO_REQUEST: begin
        /* never check L1 cache -> interrupts are infrequent, do not want to pollute the precious L1; also, would increase timing */
        request_data.address         = capability_accessors#(XLEN)::capability_get_id(aux_addr_i);
        request_data.tag             = capability_accessors#(XLEN)::capability_get_tag(aux_addr_i);
        request_data.access_type     = aux_access_type_i;
        request_data.task_id         = aux_check_task_id_i;

        axis_validate_request.tdata  = request_data;

        axis_validate_request.tvalid = 1'b1;
      end
      default: begin
        // nothing to do
        axis_validate_request.tvalid = 1'b0;
      end
    endcase
  end : validateRequestLogic

  always_comb begin : outputLogic
    // default assignments
    translated_address_o = 1'b0;
    translation_error_o = 1'b0;
    final_error_o = NORTHCAPE_RESOLVE_NO_ERROR;
    translation_valid_o = 1'b0;
    // L1 hit -> cannot have been uncacheable
    // or still in the process of resolving -> value does not matter
    translation_requires_non_cacheable_o = 1'b0;
    translation_device_specific_restriction_o = '0;
    translation_is_subsystem_call_o = 1'b0;
    translation_is_subsystem_call_self_o = 1'b0;

    if (axis_validate_response.tvalid || (HAS_CACHE && !cache_miss)) begin
      // response is here
      translation_valid_o = (state_q != TRANSLATE_AUX_WAIT_RESPONSE);
      translated_address_o = capability_offset + response_data.address;
      translation_error_o = !bounds_check_ok;
      final_error_o = final_error_d1;
      if (response_data.restriction_type == NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED) begin
        translation_device_specific_restriction_o = response_data.restriction.device_interpreted_bits;
      end
      if (axis_validate_response.tvalid) begin
        // we have to break the combinatorical path here
        automatic axis_validate_response_tdata_t response_resolver = axis_validate_response.tdata;
        translation_requires_non_cacheable_o = !response_resolver.permissions.indirect_capability_permissions.cacheable_access;
      end
      /* 
       * necessary preconditions for subsystem call: 
       * - valid capability (tag etc.)
       * - set-task-id restriction
       * - offset of 0
       */
      translation_is_subsystem_call_o = bounds_check_ok && capability_offset == '0 && response_data.restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID;
      translation_is_subsystem_call_self_o = translation_is_subsystem_call_o;
      // do we actually CHANGE the task ID?
      translation_is_subsystem_call_o &= task_id_d != response_data.restriction.task_restriction.task_id;
    end else begin

      if (state_q == HOLD_RESPONSE && request_is_helt) begin
        translation_valid_o = 1'b1;
        translated_address_o = translated_address_q;
        translation_error_o = translation_error_q;
        final_error_o = final_error_d;
        translation_requires_non_cacheable_o = translation_requires_non_cacheable_q;
        translation_device_specific_restriction_o = translation_device_specific_restriction_q;
        translation_is_subsystem_call_o = translation_is_subsystem_call_q;
        translation_is_subsystem_call_self_o = translation_is_subsystem_call_self_q;
      end
    end

    if (!cmt_interface.reset_done) begin
      // forward
      translation_valid_o = data_is_valid_i;
      translation_error_o = 1'b0;
      final_error_o = NORTHCAPE_RESOLVE_NO_ERROR;
      translated_address_o = data_address_i;
    end
  end : outputLogic

  always_comb begin : cacheMissLogic
    translation_cache_miss_event_o = 1'b0;

    if (state_q inside {IDLE, HOLD_RESPONSE} && !data_abort_i) begin
      // only count the miss once
      // use the transition into resolver request as trigger
      translation_cache_miss_event_o = data_is_valid_i && cache_miss;
    end
  end : cacheMissLogic

  always_comb begin : auxAddrResponseLogic
    aux_translated_addr_o = response_data.address + capability_accessors#(XLEN)::capability_get_offset(
        aux_addr_i);
    aux_translated_addr_valid_o = (state_q == TRANSLATE_AUX_WAIT_RESPONSE) && axis_validate_response.tvalid;

    aux_translated_addr_err_o = 1'b0;

    if (response_data.segment_length != aux_expected_length_i) begin
      aux_translated_addr_err_o = 1'b1;
    end
    if (response_data.error_code != NORTHCAPE_RESOLVE_NO_ERROR) begin
      aux_translated_addr_err_o = 1'b1;
    end
    // bounds checks: outside of lenght, inside non-allowed region 
    if (capability_accessors#(XLEN)::capability_get_offset(
            aux_addr_i
        ) + aux_access_length_i > aux_expected_length_i) begin
      aux_translated_addr_err_o = 1'b1;
    end
    if (northcape_mmu_common_t::resolved_address_overlaps_cmt(
            cmt_interface.cmt_base,
            cmt_interface.table_size_clog2,
            aux_translated_addr_o,
            aux_access_length_i
        )) begin
      aux_translated_addr_err_o = 1'b1;
    end
  end : auxAddrResponseLogic

  always_comb begin : stateLogic
    state_d = state_q;

    unique case (state_q)
      IDLE: begin
        if ((HAS_CACHE && !cache_miss)) begin
          // zero-cycle
          state_d = HOLD_RESPONSE;
        end else begin
          // need to go missed
          state_d = WAIT_REQUEST;
        end

        if (!cmt_interface.reset_done || !data_is_valid_i || data_abort_i) begin
          // not active
          state_d = IDLE;
          if (aux_addr_valid_i) begin
            state_d = TRANSLATE_AUX_DO_REQUEST;
          end
        end
      end
      WAIT_REQUEST: begin
        if (axis_validate_request.tready) begin
          if (axis_validate_response.tvalid) begin
            if (data_abort_i) begin
              state_d = IDLE;
            end else begin
              // transaction accepted and response in one cycle - done
              state_d = HOLD_RESPONSE;
            end
          end else begin
            if (data_abort_i) begin
              state_d = ABORT_WAIT_RESPONSE;
            end else begin
              state_d = WAIT_RESPONSE;
            end
          end
        end else begin
          if (data_abort_i) begin
            state_d = ABORT_REQUEST;
          end
        end
      end
      WAIT_RESPONSE: begin
        if (axis_validate_response.tvalid) begin
          if (data_abort_i) begin
            state_d = IDLE;
          end else begin
            // transaction accepted and response in one cycle - done
            state_d = HOLD_RESPONSE;
          end
        end else begin
          if (data_abort_i) begin
            state_d = ABORT_WAIT_RESPONSE;
          end
        end
      end
      HOLD_RESPONSE: begin
        if (!request_is_helt) begin
          // check for new request
          state_d = IDLE;
          if (HAS_CACHE) begin
            if (data_is_valid_i && cache_miss) begin
              // miss - have to lookup the capability in second-level cache
              state_d = axis_validate_request.tready ? WAIT_RESPONSE : WAIT_REQUEST;
            end else if (data_is_valid_i) begin
              // 0-cycle transaction - stay here
              state_d = HOLD_RESPONSE;
            end
          end else begin
            if (data_is_valid_i & axis_validate_request.tready) begin
              if (axis_validate_response.tvalid) begin
                // 1-cycle transaction - stay here
                state_d = HOLD_RESPONSE;
              end else begin
                // resolver accepted the transaction immediately - only need to wait for response
                state_d = WAIT_RESPONSE;
              end
            end else if (data_is_valid_i) begin
              // resolver did not accept transaction
              state_d = WAIT_REQUEST;
            end
          end
        end
        if (data_abort_i) begin
          // abort - have to go back to idle unconditionally
          // especially: do not request data
          state_d = IDLE;
        end
      end
      ABORT_REQUEST: begin
        if (axis_validate_request.tready) begin
          // request accepted - have to eat the response
          state_d = ABORT_WAIT_RESPONSE;
        end
      end
      ABORT_WAIT_RESPONSE: begin
        if (axis_validate_response.tvalid) begin
          // got the validate response - can proceed normally
          state_d = IDLE;
        end
      end
      TRANSLATE_AUX_DO_REQUEST: begin
        if (axis_validate_request.tready) begin
          state_d = TRANSLATE_AUX_WAIT_RESPONSE;
        end
      end
      TRANSLATE_AUX_WAIT_RESPONSE: begin
        if (axis_validate_response.tvalid) begin
          state_d = IDLE;
        end
      end
      default: begin
        // nothing to do
      end
    endcase

  end : stateLogic

  always_comb begin : stateDebugEncoder
    unique case (state_q)
      IDLE: dbg_state_o = 3'h0;
      WAIT_REQUEST: dbg_state_o = 3'h1;
      WAIT_RESPONSE: dbg_state_o = 3'h2;
      HOLD_RESPONSE: dbg_state_o = 3'h3;
      ABORT_REQUEST: dbg_state_o = 3'h4;
      ABORT_WAIT_RESPONSE: dbg_state_o = 3'h5;
      default: dbg_state_o = '1;
    endcase
  end : stateDebugEncoder

  generate
    if (IS_EXECUTE == 1'b1) begin : genTaskIdGeneration
      task_id_t task_id_irq_q, task_id_non_irq_q;
      // to undo/redo after branch predict/ before mispredict
      task_id_t task_id_locked_q, task_id_locked_d;
      task_id_t task_id_locked_irq_q, task_id_locked_irq_d;
      task_id_t task_id_irq_d1, task_id_non_irq_d1;
      logic mispredict_seen_d, mispredict_seen_d1, mispredict_seen_q;

      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : taskIdFFs
        if (!rst_ni) begin
          task_id_irq_q <= '0;
          task_id_non_irq_q <= '0;
          if (CAN_HANDLE_MISPREDICT == 1'b1) begin
            task_id_locked_q <= '0;
            task_id_locked_irq_q <= '0;
            mispredict_seen_q <= 1'b0;
          end
        end else begin
          task_id_irq_q <= task_id_irq_d1;
          task_id_non_irq_q <= task_id_non_irq_d1;
          if (CAN_HANDLE_MISPREDICT == 1'b1) begin
            task_id_locked_q <= task_id_locked_d;
            task_id_locked_irq_q <= task_id_locked_irq_d;
            mispredict_seen_q <= mispredict_seen_d1;
          end
        end
      end : taskIdFFs

      assign current_task_id_irq_o = task_id_irq_d1;
      assign current_task_id_non_irq_o = task_id_non_irq_d1;
      `NORTHCAPE_UNREAD(current_task_id_irq_i);
      `NORTHCAPE_UNREAD(current_task_id_non_irq_i);

      // uses "old" values to avoid timing loop
      // exception: overwrite - use overwritten task ID immediately
      assign task_id_d = task_id_overwrite_active_i ? task_id_overwrite_i : (data_is_irq_i ? task_id_irq_q : task_id_non_irq_q);

      assign is_subsystem_call = response_data.restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID && task_id_d != response_data.restriction.task_restriction.task_id;

      always_comb begin : nextTaskIdLogic
        // hold by default
        task_id_irq_d1 = task_id_irq_q;
        task_id_non_irq_d1 = task_id_non_irq_q;

        if (CAN_HANDLE_MISPREDICT == 1'b1) begin
          task_id_locked_d = task_id_locked_q;
          task_id_locked_irq_d = task_id_locked_irq_q;
        end else begin
          task_id_locked_d = '0;
          task_id_locked_irq_d = '0;
        end


        if (data_is_irq_i & task_id_overwrite_active_i) begin
          task_id_irq_d1 = task_id_overwrite_i;
        end else if (task_id_overwrite_active_i) begin
          task_id_non_irq_d1 = task_id_overwrite_i;
        end

        if (CAN_HANDLE_MISPREDICT == 1'b1) begin
          mispredict_seen_d = mispredict_seen_q;
        end else begin
          mispredict_seen_d = 1'b0;
        end

        // this can happen before the resolver response is complete
        // in this case, we re-set to the (still correct) value before we took the branch
        // the resolver request is ignored in this case
        if (CAN_HANDLE_MISPREDICT == 1'b1 && data_is_mispredict_i) begin
          task_id_irq_d1 = task_id_locked_irq_q;
          task_id_non_irq_d1 = task_id_locked_q;
          mispredict_seen_d = 1'b1;
        end

        if(!mispredict_seen_d && bounds_check_ok && (axis_validate_response.tvalid || (!cache_miss && data_is_valid_i)) && !(state_q inside {ABORT_REQUEST, ABORT_WAIT_RESPONSE, TRANSLATE_AUX_WAIT_RESPONSE}) && !data_abort_i && response_data.restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID)
        begin
          if (data_is_irq_i) begin
            // update IRQ task id
            task_id_irq_d1 = response_data.restriction.task_restriction.task_id;
            if (CAN_HANDLE_MISPREDICT == 1'b1 && data_is_branch_predict_i) begin
              // capture old value for rollback if needed
              task_id_locked_irq_d = task_id_irq_q;
            end else if (CAN_HANDLE_MISPREDICT == 1'b1) begin
              // non-speculative - update to new task ID
              task_id_locked_irq_d = response_data.restriction.task_restriction.task_id;
            end
          end else begin
            // update non-IRQ task id
            task_id_non_irq_d1 = response_data.restriction.task_restriction.task_id;
            if (CAN_HANDLE_MISPREDICT == 1'b1 && data_is_branch_predict_i) begin
              // capture old value for rollback if needed
              task_id_locked_d = task_id_non_irq_q;
            end else if (CAN_HANDLE_MISPREDICT == 1'b1) begin
              // non-speculative - update to new task ID
              task_id_locked_d = response_data.restriction.task_restriction.task_id;
            end
          end
        end
        // disambiguate to prevent loop
        mispredict_seen_d1 = mispredict_seen_d;

        if ((axis_validate_response.tvalid && state_q != TRANSLATE_AUX_WAIT_RESPONSE) || (!cache_miss && data_is_valid_i)) begin
          mispredict_seen_d1 = 1'b0;
        end

        if (CAN_HANDLE_MISPREDICT == 1'b1 && data_is_correct_predict_i) begin
          // predict was correct - discard locked value
          task_id_locked_d = task_id_non_irq_d1;
          task_id_locked_irq_d = task_id_irq_d1;
        end

      end : nextTaskIdLogic
      `NORTHCAPE_UNREAD(is_subsystem_call_i);
    end : genTaskIdGeneration
    else begin : genTaskIdUse
      assign task_id_d = data_is_irq_i ? current_task_id_irq_i : current_task_id_non_irq_i;
      assign current_task_id_irq_o = current_task_id_irq_i;
      assign current_task_id_non_irq_o = current_task_id_non_irq_i;
      // non applicable
      assign is_subsystem_call = 1'b0;
      `NORTHCAPE_UNREAD(data_is_branch_predict_i);
      `NORTHCAPE_UNREAD(data_is_mispredict_i);
    end : genTaskIdUse
  endgenerate
endmodule
