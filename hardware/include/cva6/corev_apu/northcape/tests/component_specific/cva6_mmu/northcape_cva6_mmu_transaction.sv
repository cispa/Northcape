/**
 * Transaction via the Northcape CVA6 MMU.
 */
package northcape_cva6_mmu_transaction;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import northcape_types::*;
  import northcape_test::*;
  import northcape_mmu_common::NorthcapeMMUCommon;


  localparam MAX_CMT_SIZE_CLOG2 = $clog2(16384);

  /**
     * Sequence item that holds all data needed for an MMU transaction.
     */
  class automatic NorthcapeCVA6MMUTransaction #(
      parameter device_id_t INSTR_CHAN_DEVICE_ID = -1,
      parameter device_id_t DATA_CHAN_DEVICE_ID = -1,
      parameter AXI_ADDR_WIDTH = 64
  ) extends uvm_sequence_item implements INorthcapeCapabilityResolverTransaction;

    localparam COMPONENT_NAME = "Northcape CVA6 MMU Transaction";

    typedef NorthcapeMMUCommon#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH(1),
        .AXI_USER_WIDTH(1),
        .ACCEPT_AXI_WRAP_BURSTS(1'b0),
        .IS_WRITE_CHAN(1'b0)
    ) northcape_mmu_common_t;


    randc bit valid_test;
    randc bit is_execute;
    rand bit data_is_atomic;
    // input parameters to the CVA6 MMU
    rand logic [AXI_ADDR_WIDTH-1:0] data_address;
    rand capability_off_t capability_offset;
    rand logic data_is_store;
    rand logic [$clog2(AXI_ADDR_WIDTH/8)-1:0] data_access_size;
    rand logic data_is_immediate;
    rand logic data_is_irq;

    // for response generation
    rand segment_base_addr_t segment_base;
    rand segment_length_t segment_length;

    // to be set by agent
    task_id_t task_id_irq;
    task_id_t task_id_non_irq;

    // bounds of capability metadata table
    rand northcape_physical_address_t cmt_base_addr;
    rand int unsigned cmt_size_clog2;


    // for restrictions
    // will be adapted by agent to global state if needed
    rand northcape_restriction_body_t restriction_body;
    rand northcape_restriction_type_t restriction_type;

    // cacheability
    rand bit is_cacheable_data;

    // is this a branch predict?
    rand bit branch_predict;
    // is this a branch-MISpredict?
    rand bit branch_mispredict;
    localparam MAX_PREDICT_CYCLES_CLOG2 = 8;
    // how long until we confirm correct predict / mispredict?
    rand bit [MAX_PREDICT_CYCLES_CLOG2-1:0] predict_cycles;

    // MMU has "self preservation mode": it refuses all accesses that resolve into the CMT
    function bit call_overlaps_cmt();
      bit [AXI_ADDR_WIDTH-1:0] request_start_addr;
      int bytes_in_burst;

      request_start_addr =
          capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(data_address) + segment_base;
      bytes_in_burst = 1 << data_access_size;


      return northcape_mmu_common_t::resolved_address_overlaps_cmt(
          cmt_base_addr, cmt_size_clog2, request_start_addr, bytes_in_burst
      );

    endfunction

    function bit [AXI_ADDR_WIDTH-1:0] get_cmt_end();
      return 64'(cmt_base_addr) + (1 << 64'(cmt_size_clog2)) * ($bits(northcape_cmt_entry_t) / 8);
    endfunction

    constraint cmt_is_not_too_big {cmt_size_clog2 <= MAX_CMT_SIZE_CLOG2;}


    constraint cmt_fits_in_addr_space {get_cmt_end() <= 64'h00000000ffffffff;}

    constraint segment_fits_in_addr_space {
      64'(segment_base) + 64'(segment_length) <= 64'h00000000ffffffff;
    }

    constraint access_into_cmt_is_invalid {valid_test -> call_overlaps_cmt() == 0;}

    constraint valid_test_implies_valid_restriction_type {
      valid_test ->
      restriction_type inside {NORTHCAPE_RESTRICTIONS_NONE, NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED, NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND, NORTHCAPE_RESTRICTIONS_SET_TASK_ID};
    }

    constraint task_id_restriction_implies_matching_device_id {
      (valid_test && restriction_type inside {NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND, NORTHCAPE_RESTRICTIONS_SET_TASK_ID}) ->
      restriction_body.task_restriction.device_id == INSTR_CHAN_DEVICE_ID >> 1;
      // task ID to be set by agent
    }

    constraint addresses_are_aligned {
      data_address & ((1 << data_access_size) - 1) == 0;
      segment_base & ((1 << data_access_size) - 1) == 0;
    }

    constraint segment_length_is_possible {
      valid_test -> 64'(capability_offset) + 64'(1 << data_access_size) <= 64'(segment_length);
    }

    constraint store_or_execute {data_is_store -> !is_execute;}



    function new(string name = "");
      super.new(name);
    endfunction

    typedef NorthcapeCVA6MMUTransaction#(
        .INSTR_CHAN_DEVICE_ID(INSTR_CHAN_DEVICE_ID),
        .DATA_CHAN_DEVICE_ID(DATA_CHAN_DEVICE_ID),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) my_type_t;

    function void do_copy(uvm_object rhs);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      valid_test = other_transaction.valid_test;
      is_execute = other_transaction.is_execute;
      data_address = other_transaction.data_address;
      capability_offset = other_transaction.capability_offset;
      data_is_store = other_transaction.data_is_store;
      data_access_size = other_transaction.data_access_size;
      data_is_immediate = other_transaction.data_is_immediate;
      data_is_irq = other_transaction.data_is_irq;

      segment_base = other_transaction.segment_base;
      segment_length = other_transaction.segment_length;

      task_id_irq = other_transaction.task_id_irq;
      task_id_non_irq = other_transaction.task_id_non_irq;

      cmt_base_addr = other_transaction.cmt_base_addr;
      cmt_size_clog2 = other_transaction.cmt_size_clog2;

      restriction_body = other_transaction.restriction_body;
      restriction_type = other_transaction.restriction_type;
      is_cacheable_data = other_transaction.is_cacheable_data;
      branch_predict = other_transaction.branch_predict;
      branch_mispredict = other_transaction.branch_mispredict;
      predict_cycles = other_transaction.predict_cycles;
    endfunction : do_copy



    function string convert2string();
      string s;
      northcape_restrictions_t restrictions;
      restrictions.body = restriction_body;
      restrictions.restriction_type = restriction_type;

      s = $sformatf(
          "valid %b execute %b address %x store %b size %d immediate %b IRQ %b segment base %x segment length %d task id irq %d task id non irq %d CMT base %x cmt size log2 %d restriction %s is cacheable data %b branch predict %b branch mispredict %b predict cycles %d",
          valid_test,
          is_execute,
          data_address,
          data_is_store,
          data_access_size,
          data_is_immediate,
          data_is_irq,

          segment_base,
          segment_length,

          task_id_irq,
          task_id_non_irq,

          cmt_base_addr,
          cmt_size_clog2,
          print_restriction(
              restrictions
          ),
          is_cacheable_data,
          branch_predict,
          branch_mispredict,
          predict_cycles
      );

      return s;
    endfunction : convert2string


    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      return  valid_test == other_transaction.valid_test &&
              is_execute == other_transaction.is_execute &&
              data_address == other_transaction.data_address &&
              capability_offset == other_transaction.capability_offset &&
              data_is_store == other_transaction.data_is_store &&
              data_access_size == other_transaction.data_access_size &&
              data_is_immediate == other_transaction.data_is_immediate &&
              data_is_irq == other_transaction.data_is_irq &&

              segment_base == other_transaction.segment_base &&
              segment_length == other_transaction.segment_length &&
              task_id_irq == other_transaction.task_id_irq &&
              task_id_non_irq == other_transaction.task_id_non_irq &&
              cmt_base_addr == other_transaction.cmt_base_addr &&
              cmt_size_clog2 == other_transaction.cmt_size_clog2 && 
              restriction_body == other_transaction.restriction_body &&
              restriction_type == other_transaction.restriction_type && 
              is_cacheable_data == other_transaction.is_cacheable_data &&
              branch_predict == other_transaction.branch_predict &&
              branch_mispredict == other_transaction.branch_mispredict &&
              predict_cycles == other_transaction.predict_cycles;
    endfunction : do_compare

    function void post_randomize();
      bit offset_ok;
      capability_type_t needed_type = OFFSET_8_BIT;

      if (capability_offset > max_length_for_capability_type(needed_type)) begin
        needed_type = OFFSET_16_BIT;
      end

      if (capability_offset > max_length_for_capability_type(needed_type)) begin
        needed_type = OFFSET_24_BIT;
      end

      if (capability_offset > max_length_for_capability_type(needed_type)) begin
        needed_type = OFFSET_32_BIT;
      end

      data_address =
          capability_accessors#(AXI_ADDR_WIDTH)::capability_set_type(data_address, needed_type);

      offset_ok = capability_accessors#(AXI_ADDR_WIDTH)::capability_set_offset(data_address,
                                                                               capability_offset);

      if (!offset_ok) begin
        `uvm_fatal(COMPONENT_NAME, "Could not set capability offset!");
      end
      if (!valid_test) begin
        // in case test is valid on accident, make sure it is not flagged
        int bytes_in_burst = 1 << data_access_size;
        bit is_actually_ok;
        bit subsystem_call;

        is_actually_ok = !northcape_mmu_common_t::resolved_address_overlaps_cmt(
            cmt_base_addr, cmt_size_clog2, segment_base, bytes_in_burst);

        subsystem_call = restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID && restriction_body.task_restriction.task_id != (data_is_irq ? task_id_irq : task_id_non_irq);

        is_actually_ok &= 64'(bytes_in_burst) + 64'(capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(
            data_address
        )) <= 64'(segment_length);
        is_actually_ok &= capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(
            data_address
        ) == 0 || !subsystem_call;

        if (is_actually_ok) begin
          valid_test = 1'b1;
          `uvm_info(COMPONENT_NAME, "Found restriction that is actually OK!", UVM_HIGH);
        end
      end else begin
        bit [63:0] offset = 64'(capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(
            data_address
        ));
        if (offset + 64'(1 << data_access_size) >= 64'(segment_length)) begin
          `uvm_fatal(COMPONENT_NAME, $sformatf(
                     "Data generation error: offset %d access size 1<<%d segment length %d",
                     offset,
                     data_access_size,
                     segment_length
                     ));
        end
      end
    endfunction


    virtual function axis_validate_request_perm_t get_axi_request_type();
      if (data_is_irq) begin
        if (is_execute) begin
          return EXECUTE_IRQ;
        end
        if (data_is_atomic && data_is_store) begin
          return READ_WRITE_IRQ;
        end
        if (data_is_store) begin
          return WRITE_IRQ;
        end
        return READ_IRQ;
      end else begin
        if (is_execute) begin
          return EXECUTE;
        end
        if (data_is_atomic && data_is_store) begin
          return READ_WRITE;
        end
        if (data_is_store) begin
          return WRITE;
        end
        return READ;
      end
    endfunction

    virtual function axis_validate_request_tdata_t get_resolver_expected_request();
      axis_validate_request_tdata_t ret;

      ret = '0;

      ret.address = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(data_address);
      ret.tag = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(data_address);
      ret.access_type = get_axi_request_type();
      ret.device_id = is_execute ? INSTR_CHAN_DEVICE_ID : DATA_CHAN_DEVICE_ID;
      ret.task_id = data_is_irq ? task_id_irq : task_id_non_irq;

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Parsed address %x into ID %x tag %x!", data_address, ret.address, ret.tag),
                UVM_DEBUG);

      // only used for recursion
      ret.flags = '0;
      ret.original_address = '0;
      ret.original_segment_length = '0;
      ret.original_permission_tid_match = 1'b0;
      ret.original_permissions = '0;
      ret.lock_key = '0;

      ret.restriction = '0;
      ret.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
      ret.error_code = NORTHCAPE_RESOLVE_NO_ERROR;

      return ret;
    endfunction

    virtual function axis_validate_response_tdata_t get_resolver_response();
      axis_validate_response_tdata_t ret;

      ret = '0;

      ret.address = segment_base;
      ret.segment_length = segment_length;
      ret.restriction_type = restriction_type;
      ret.restriction = restriction_body;
      ret.error_code = NORTHCAPE_RESOLVE_NO_ERROR;
      ret.permissions = '0;
      ret.permissions.indirect_capability_permissions.cacheable_access = is_cacheable_data;
      // would break test assumptions...
      ret.permissions.indirect_capability_permissions.cacheable_tlb = 1'b0;
      // other permissions do not matter - CVA6 MMU should rely on resolver for checking on miss

      return ret;
    endfunction

  endclass

  class NorthcapeCVA6MMUInterfaceTransaction #(
      parameter device_id_t INSTR_CHAN_DEVICE_ID = -1,
      parameter device_id_t DATA_CHAN_DEVICE_ID = -1,
      parameter AXI_ADDR_WIDTH = -1
  ) extends NorthcapeCVA6MMUTransaction #(
      .INSTR_CHAN_DEVICE_ID(INSTR_CHAN_DEVICE_ID),
      .DATA_CHAN_DEVICE_ID(DATA_CHAN_DEVICE_ID),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
  );
    function new(string name = "");
      super.new(name);
    endfunction

    // currently no special behavior

  endclass

  class NorthcapeCVA6MMUInterfaceResultTransaction #(
      parameter AXI_ADDR_WIDTH = -1
  ) extends uvm_sequence_item;

    function new(string name = "");
      super.new(name);
    endfunction

    localparam COMPONENT_NAME = "Northcape CVA6 MMU Result Transaction";

    logic [AXI_ADDR_WIDTH-1:0] translated_address;
    logic translation_error;
    logic translation_valid;
    logic translation_hit;
    logic translation_requires_non_cacheable;
    northcape_device_interpreted_restriction_t translation_device_interpreted;
    // were the resuls collected BEFORE predict/mispredict was given?
    bit is_before_predict_end;

    task_id_t task_id_irq;
    task_id_t task_id_non_irq;

    logic is_subsystem_call;
    logic is_subsystem_call_self;

    typedef NorthcapeCVA6MMUInterfaceResultTransaction#(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) my_type_t;

    function void do_copy(uvm_object rhs);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      translated_address = other_transaction.translated_address;
      translation_error = other_transaction.translation_error;
      translation_valid = other_transaction.translation_error;
      translation_hit = other_transaction.translation_hit;
      translation_requires_non_cacheable = other_transaction.translation_requires_non_cacheable;
      translation_device_interpreted = other_transaction.translation_device_interpreted;

      task_id_irq = other_transaction.task_id_irq;
      task_id_non_irq = other_transaction.task_id_non_irq;
      is_before_predict_end = other_transaction.is_before_predict_end;
      is_subsystem_call = other_transaction.is_subsystem_call;
      is_subsystem_call_self = other_transaction.is_subsystem_call_self;
    endfunction

    function string convert2string();
      string s;

      s = $sformatf(
          "Address %x error %b valid %b immediate %b non cacheable %b task ID IRQ %d task ID non IRQ %d device interpreted restr %x results were before mispredict? %b subsys call? %b subsys call self? %b",
          translated_address,
          translation_error,
          translation_valid,
          translation_hit,
          translation_requires_non_cacheable,
          task_id_irq,
          task_id_non_irq,
          translation_device_interpreted,
          is_before_predict_end,
          is_subsystem_call,
          is_subsystem_call_self
      );
      return s;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Comparing result %s with %s", convert2string(), rhs.convert2string()), UVM_HIGH);

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      if (translated_address !== other_transaction.translated_address) begin
        `uvm_error(COMPONENT_NAME, "Address does not match!");
        return 1'b0;
      end

      if (translation_error !== other_transaction.translation_error) begin
        `uvm_error(COMPONENT_NAME, "Translation error does match!");
        return 1'b0;
      end

      if (translation_valid !== other_transaction.translation_valid) begin
        `uvm_error(COMPONENT_NAME, "Translation valid does match!");
        return 1'b0;
      end

      if (translation_hit !== other_transaction.translation_hit) begin
        `uvm_error(COMPONENT_NAME, "Translation immediate does match!");
        return 1'b0;
      end

      if(translation_requires_non_cacheable !== other_transaction.translation_requires_non_cacheable)
      begin
        `uvm_error(COMPONENT_NAME, "Translation non cacheable does match!");
        return 1'b0;
      end

      if (task_id_irq !== other_transaction.task_id_irq) begin
        `uvm_error(COMPONENT_NAME, "IRQ task ID does match!");
        return 1'b0;
      end

      if (task_id_non_irq !== other_transaction.task_id_non_irq) begin
        `uvm_error(COMPONENT_NAME, "Non-IRQ task ID does match!");
        return 1'b0;
      end

      if (translation_device_interpreted !== other_transaction.translation_device_interpreted) begin
        `uvm_error(COMPONENT_NAME, "Device-interpreted restriction does not match!");
        return 1'b0;
      end

      if (is_subsystem_call !== other_transaction.is_subsystem_call) begin
        `uvm_error(COMPONENT_NAME, "Subsystem call does not match!");
        return 1'b0;
      end

      if (is_subsystem_call_self !== other_transaction.is_subsystem_call_self) begin
        `uvm_error(COMPONENT_NAME, "Subsystem call self does not match!");
        return 1'b0;
      end

      return 1'b1;
    endfunction
  endclass
endpackage
