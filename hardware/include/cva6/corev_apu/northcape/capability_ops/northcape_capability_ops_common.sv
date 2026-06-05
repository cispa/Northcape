/**
  * Definitions and utility functions for Northcape Operations module.
  */
package northcape_capability_ops_common;

  import northcape_types::*;
  import northcape_capability_resolver_common::NorthcapeCapabilityResolverHash;
  import northcape_cmt_parser_pkg::*;


  typedef enum logic [4:0] {
    NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE         = 5'h0,
    NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE         = 5'h1,
    NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP           = 5'h2,
    NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE          = 5'h3,
    NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE          = 5'h4,
    NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE         = 5'h5,
    NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK           = 5'h6,
    NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT        = 5'h7,
    NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT       = 5'h8,
    NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP          = 5'hb,
    NORTHCAPE_CAPABILITY_OPS_OPERATION_UNKNOWN        = '1
  } northcape_capability_operation_t;

  typedef enum logic {
    NORTHCAPE_CAPABILITY_OPS_CBC,
    NORTHCAPE_CAPABILITY_OPS_CTR
  } northcape_capability_ops_tag_method_t;

  typedef enum logic [31:0] {
    /* none */
    NORTHCAPE_NO_ERROR = 32'd0,
    /* vanilla Northcape */
    NORTHCAPE_ERR_NEW_SEGMENT_LENGTH_TOO_SHORT = 32'd1,
    NORTHCAPE_ERR_PARSER_FAIL_TAG = 32'd2,
    NORTHCAPE_ERR_PARSER_FAIL_PERMISSIONS = 32'd3,
    NORTHCAPE_ERR_PARSER_FAIL_RESTRICTIONS = 32'd4,
    NORTHCAPE_ERR_PARSER_FAIL_CAP_TYPE = 32'd5,
    NORTHCAPE_ERR_PARSER_FAIL_LOCKED = 32'd6,
    NORTHCAPE_ERR_WRONG_CAP_TYPE = 32'd7,
    NORTHCAPE_ERR_INSUFFICIENT_PERMS = 32'd8,
    NORTHCAPE_ERR_INSUFFICIENT_LENGTH = 32'd9,
    NORTHCAPE_ERR_TOO_MANY_REFERENCES = 32'd10,
    NORTHCAPE_ERR_CANNOT_ADD_RESTRICTIONS = 32'd11,
    NORTHCAPE_ERR_WRONG_RESTRICTIONS = 32'd12,
    NORTHCAPE_ERR_NOT_ADJACENT = 32'd13,
    NORTHCAPE_ERR_ALREADY_LOCKED = 32'd14,
    NORTHCAPE_ERR_NOT_LOCKABLE = 32'd15,
    NORTHCAPE_ERR_INVALID_OPERATION = 32'd16,
    NORTHCAPE_ERR_BUS = 32'd17,
    NORTHCAPE_ERR_UNKNOWN_OPERATION = 32'd18,
    NORTHCAPE_ERR_RECURSE = 32'd19,
    NORTHCAPE_ERR_CANNOT_HIJACK_TASK_ID = 32'd20,
    NORTHCAPE_ERR_LENGTH_EXCEEDS_CAP_TYPE = 32'd21,
    NORTHCAPE_ERR_MMIO_LOCKED = 32'd22,
    NORTHCAPE_ERR_OUT_OT_BOUNDS = 32'd23
  } northcape_error_code_t;

  typedef bit [127:0] northcape_capability_ops_mac_key_t;

  localparam NORTHCAPE_CAPABILITY_OPS_RNG_INTERFACE_BITS = 64;

  localparam NORTHCAPE_CAPABILITY_OPS_QARMA_INPUT_KEY_HIGH = 64'hfeedbeefdeadbeef;
  localparam NORTHCAPE_CAPABILITY_OPS_QARMA_INPUT_KEY_LOW = 64'hfeeddeadbeefbeef;
  localparam NORTHCAPE_CAPABILITY_OPS_QARMA_INPUT_NONCE = 64'hfeeddeaddeadfeed;

  // one interrupt for complete
  localparam NORTHCAPE_CAPABILITY_OPS_NUM_IRQS = 1;

  class automatic NorthcapeCapabilityOpsGenerator #(
      parameter AXI_ADDR_WIDTH = -1,
      parameter HASH_TYPE = -1
  );

    typedef NorthcapeCapabilityResolverHash#(.HASH_TYPE(HASH_TYPE)) hash_t;

    static function capability_id_t get_next_capability_id(capability_id_t last_id, int increment,
                                                           capability_type_t capability_type);
      capability_id_t ret;

      ret = last_id + increment;

      ret = ret & get_id_mask_for_capability_type(capability_type);

      return ret;
    endfunction

    static function northcape_cmt_entry_t generate_root_capability();
      northcape_cmt_entry_t root;

      root = '0;

      root.capability_type = NORTHCAPE_CMT_DIRECT;

      root.location.physical_location.base = '0;
      root.location.physical_location.length = '1;
      root.location.physical_location.locked_key = '0;
      root.refcount = 0;
      root.restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
      // restriction body needs not be set

      root.permissions.direct_capability_permissions.read_permission = 1'b1;
      root.permissions.direct_capability_permissions.write_permission = 1'b1;
      root.permissions.direct_capability_permissions.execute_permission = 1'b1;
      root.permissions.direct_capability_permissions.lockable_permission = 1'b1;
      root.permissions.direct_capability_permissions.irq_accessible_permission = 1'b1;
      root.permissions.direct_capability_permissions.cacheable_tlb = 1'b1;
      root.permissions.direct_capability_permissions.cacheable_access = 1'b1;

      root.tag = '0;

      root.nonce = '0;

      return root;
    endfunction

    static function bit [AXI_ADDR_WIDTH - 1 : 0] get_capability_addr(
        bit [AXI_ADDR_WIDTH-1:0] cmt_base, int unsigned table_size_clog2, capability_id_t id);

      bit [AXI_ADDR_WIDTH -1 : 0] ret;

      capability_id_t hashed_id;

      hashed_id = hash_t::compute_hash(id, table_size_clog2);

      ret = cmt_base + 64'(hashed_id) * $bits(northcape_cmt_entry_t) / 8;

      return ret;
    endfunction
  endclass

  class automatic NorthcapeCapabilityOpsInputParser;
    static function northcape_error_code_t cmt_parser_error_to_northcape_error(
        input cmt_parser_verdict_t verdict);
      unique case (verdict)
        CMT_ENTRY_FAIL_TAG: return NORTHCAPE_ERR_PARSER_FAIL_TAG;
        CMT_ENTRY_FAIL_PERMISSIONS: return NORTHCAPE_ERR_PARSER_FAIL_PERMISSIONS;
        CMT_ENTRY_FAIL_RESTRICTIONS: return NORTHCAPE_ERR_PARSER_FAIL_RESTRICTIONS;
        CMT_ENTRY_FAIL_CAP_TYPE: return NORTHCAPE_ERR_PARSER_FAIL_CAP_TYPE;
        CMT_ENTRY_FAIL_LOCKED: return NORTHCAPE_ERR_PARSER_FAIL_LOCKED;
        /* e.g., got RECURSE when expecting MATCH */
        default: return NORTHCAPE_ERR_WRONG_CAP_TYPE;
      endcase
    endfunction

    static function northcape_error_code_t input_capability_allows_create(
        input capability_id_t input_cap_id, input capability_tag_t input_tag,
        northcape_cmt_entry_t input_capability, device_id_t create_input_device_id,
        task_id_t create_input_task_id,
        // requested permissions
        input logic read_perm, write_perm, x_perm, lockable_perm, irq_accessible_perm,
        cacheable_tlb_perm,
        cacheable_access_perm,
        // requested segment length
        input segment_length_t new_segment_length);
      bit input_capability_valid;
      northcape_direct_capability_permissions_t requested_perm, given_perm;
      cmt_parser_verdict_t verdict;

      if (new_segment_length == 0) begin
        // a 0-length direct capability is useless - refuse to create it
        return NORTHCAPE_ERR_NEW_SEGMENT_LENGTH_TOO_SHORT;
      end


      verdict = northcape_cmt_parser::entry_matches_validate_request(
          input_capability,
          input_cap_id,
          input_tag,
          ACCESS_NONE,
          create_input_device_id,
          create_input_task_id,
          '0
      );
      input_capability_valid = (verdict == CMT_ENTRY_MATCH);

      if (~input_capability_valid) begin
        return cmt_parser_error_to_northcape_error(verdict);
      end

      // create assumes direct capability with zero refcount
      // exception: root capability --> required for initializing MMIO while still being able to nuke the Skadi loader
      input_capability_valid = (input_capability.capability_type == NORTHCAPE_CMT_DIRECT) && (input_cap_id == 0 || input_capability.refcount == 0);

      if (~input_capability_valid) begin
        return NORTHCAPE_ERR_WRONG_CAP_TYPE;
      end


      requested_perm = {
        read_perm,
        write_perm,
        x_perm,
        lockable_perm,
        irq_accessible_perm,
        cacheable_tlb_perm,
        cacheable_access_perm
      };
      given_perm = {
        input_capability.permissions.direct_capability_permissions.read_permission,
        input_capability.permissions.direct_capability_permissions.write_permission,
        input_capability.permissions.direct_capability_permissions.execute_permission,
        input_capability.permissions.direct_capability_permissions.lockable_permission,
        input_capability.permissions.direct_capability_permissions.irq_accessible_permission,
        input_capability.permissions.direct_capability_permissions.cacheable_tlb,
        input_capability.permissions.direct_capability_permissions.cacheable_access
      };

      // if requested permissions have bits set that given permissions do not, this evaluates to false
      input_capability_valid = (requested_perm | given_perm) == given_perm;

      if (~input_capability_valid) begin
        return NORTHCAPE_ERR_INSUFFICIENT_PERMS;
      end



      input_capability_valid = (new_segment_length <= input_capability.location.physical_location.length);

      if (~input_capability_valid) begin
        return NORTHCAPE_ERR_INSUFFICIENT_LENGTH;
      end

      return NORTHCAPE_NO_ERROR;
    endfunction

    static function northcape_error_code_t input_capability_allows_derive(
        input capability_id_t input_cap_id, input capability_tag_t input_tag,
        northcape_cmt_entry_t input_capability, device_id_t create_input_device_id,
        task_id_t create_input_task_id,
        // requested permissions
        input logic read_perm, write_perm, x_perm, irq_accessible_perm, cacheable_tlb_perm,
        cacheable_access_perm,
        // requested segment length
        input segment_length_t new_segment_length, input segment_length_t parent_offset);
      bit input_capability_valid_parser;
      bit input_capability_valid_type;
      bit input_capability_valid_perm;
      bit input_capability_valid_len;
      bit input_capability_valid_refcount;

      northcape_indirect_capability_permissions_t requested_perm, given_perm;
      cmt_parser_verdict_t verdict;

      if (new_segment_length == 0) begin
        // a 0-length direct capability is useless - refuse to create it
        return NORTHCAPE_ERR_NEW_SEGMENT_LENGTH_TOO_SHORT;
      end

      verdict = (northcape_cmt_parser::entry_matches_validate_request(
          input_capability,
          input_cap_id,
          input_tag,
          ACCESS_NONE,
          create_input_device_id,
          create_input_task_id,
          '0
      ));

      input_capability_valid_parser = (verdict == CMT_ENTRY_MATCH || verdict == CMT_ENTRY_RECURSE);

      if (input_capability_valid_parser == 1'b0) begin
        return cmt_parser_error_to_northcape_error(verdict);
      end

      if(! (input_capability.capability_type inside {NORTHCAPE_CMT_DIRECT, NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_LOCK_HOLDER}))
      begin
        input_capability_valid_type = 0;
        return NORTHCAPE_ERR_WRONG_CAP_TYPE;
      end else begin
        input_capability_valid_type = 1;
      end

      // for derive, permissions must not become stronger

      requested_perm = {
        read_perm,
        write_perm,
        x_perm,
        irq_accessible_perm,
        cacheable_tlb_perm,
        cacheable_access_perm
      };
      if (input_capability.capability_type == NORTHCAPE_CMT_DIRECT) begin
        given_perm = {
          input_capability.permissions.direct_capability_permissions.read_permission,
          input_capability.permissions.direct_capability_permissions.write_permission,
          input_capability.permissions.direct_capability_permissions.execute_permission,
          input_capability.permissions.direct_capability_permissions.irq_accessible_permission,
          input_capability.permissions.direct_capability_permissions.cacheable_tlb,
          input_capability.permissions.direct_capability_permissions.cacheable_access
        };
      end else begin
        given_perm = {
          input_capability.permissions.indirect_capability_permissions.read_permission,
          input_capability.permissions.indirect_capability_permissions.write_permission,
          input_capability.permissions.indirect_capability_permissions.execute_permission,
          input_capability.permissions.indirect_capability_permissions.irq_accessible_permission,
          input_capability.permissions.indirect_capability_permissions.cacheable_tlb,
          input_capability.permissions.indirect_capability_permissions.cacheable_access
        };
      end

      // if requested permissions have bits set that given permissions do not, this evaluates to false
      input_capability_valid_perm = (requested_perm | given_perm) == given_perm;

      if (input_capability_valid_perm == 1'b0) begin
        return NORTHCAPE_ERR_INSUFFICIENT_PERMS;
      end


      if (input_capability.capability_type == NORTHCAPE_CMT_DIRECT) begin
        input_capability_valid_len = (new_segment_length + parent_offset <= input_capability.location.physical_location.length);
      end else if (input_capability.capability_type == NORTHCAPE_CMT_INDIRECT) begin
        input_capability_valid_len = (new_segment_length + parent_offset <= input_capability.location.indirect_location.length);
      end else if (input_capability.capability_type == NORTHCAPE_CMT_LOCK_HOLDER) begin
        /* TODO have to check again when first capability with length is encountered */
        input_capability_valid_len = 1'b1;
      end else begin
        // revocation
        input_capability_valid_len = 1'b0;
      end

      if (input_capability_valid_len == 1'b0) begin
        return NORTHCAPE_ERR_INSUFFICIENT_LENGTH;
      end


      input_capability_valid_refcount = input_capability.refcount != '1;

      if (input_capability_valid_refcount == 1'b0) begin
        return NORTHCAPE_ERR_TOO_MANY_REFERENCES;
      end


      return NORTHCAPE_NO_ERROR;
    endfunction


    static function northcape_error_code_t input_capability_allows_drop(
        input capability_id_t input_cap_id, input capability_tag_t input_tag,
        northcape_cmt_entry_t input_capability, device_id_t create_input_device_id,
        task_id_t create_input_task_id);
      bit input_capability_valid;
      cmt_parser_verdict_t verdict;

      verdict = (northcape_cmt_parser::entry_matches_validate_request(
          input_capability,
          input_cap_id,
          input_tag,
          ACCESS_NONE,
          create_input_device_id,
          create_input_task_id,
          '0
      ));

      input_capability_valid = (verdict == CMT_ENTRY_MATCH || verdict == CMT_ENTRY_RECURSE);

      if (~input_capability_valid) begin
        return cmt_parser_error_to_northcape_error(verdict);
      end

      if (input_capability.capability_type != NORTHCAPE_CMT_INDIRECT && input_capability.capability_type != NORTHCAPE_CMT_LOCK_HOLDER) begin
        return NORTHCAPE_ERR_WRONG_CAP_TYPE;
      end



      input_capability_valid = (input_capability.refcount == 0);

      if (~input_capability_valid) begin
        return NORTHCAPE_ERR_WRONG_CAP_TYPE;
      end

      return NORTHCAPE_NO_ERROR;
    endfunction

    // this needs to be called for both input capabilities individually
    // application logic needs to check that capabilities are indeed adjacent!
    static function northcape_error_code_t input_capability_allows_merge(
        input capability_id_t input_cap_id, input capability_tag_t input_tag,
        northcape_cmt_entry_t input_capability, device_id_t create_input_device_id,
        task_id_t create_input_task_id);
      bit input_capability_valid;
      cmt_parser_verdict_t verdict;

      verdict = (northcape_cmt_parser::entry_matches_validate_request(
          input_capability,
          input_cap_id,
          input_tag,
          ACCESS_NONE,
          create_input_device_id,
          create_input_task_id,
          '0
      ));

      input_capability_valid = (verdict == CMT_ENTRY_MATCH);

      if (~input_capability_valid) begin
        return cmt_parser_error_to_northcape_error(verdict);
      end

      if (input_capability.capability_type != NORTHCAPE_CMT_DIRECT) begin
        input_capability_valid = 0;
        return NORTHCAPE_ERR_WRONG_CAP_TYPE;
      end

      input_capability_valid = (input_capability.refcount == 0);
      if (~input_capability_valid) begin
        return NORTHCAPE_ERR_TOO_MANY_REFERENCES;
      end

      return NORTHCAPE_NO_ERROR;
    endfunction

    static function northcape_error_code_t input_capability_allows_clone(
        input capability_id_t input_cap_id, input capability_tag_t input_tag,
        northcape_cmt_entry_t input_capability, device_id_t create_input_device_id,
        task_id_t create_input_task_id,
        // requested permissions
        input logic read_perm, write_perm, x_perm, irq_accessible_perm, cacheable_tlb_perm,
        cacheable_access_perm);
      bit input_capability_valid;
      northcape_indirect_capability_permissions_t requested_perm, given_perm;
      cmt_parser_verdict_t verdict;

      verdict = (northcape_cmt_parser::entry_matches_validate_request(
          input_capability,
          input_cap_id,
          input_tag,
          ACCESS_NONE,
          create_input_device_id,
          create_input_task_id,
          '0
      ));

      input_capability_valid = (verdict == CMT_ENTRY_MATCH || verdict == CMT_ENTRY_RECURSE);

      if (~input_capability_valid) begin
        return cmt_parser_error_to_northcape_error(verdict);
      end

      if(!(input_capability.capability_type inside{NORTHCAPE_CMT_DIRECT, NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_LOCK_HOLDER}))
      begin
        input_capability_valid = 0;
        return NORTHCAPE_ERR_WRONG_CAP_TYPE;
      end



      requested_perm = {
        read_perm,
        write_perm,
        x_perm,
        irq_accessible_perm,
        cacheable_tlb_perm,
        cacheable_access_perm
      };
      if (input_capability.capability_type == NORTHCAPE_CMT_DIRECT) begin
        given_perm = {
          input_capability.permissions.direct_capability_permissions.read_permission,
          input_capability.permissions.direct_capability_permissions.write_permission,
          input_capability.permissions.direct_capability_permissions.execute_permission,
          input_capability.permissions.direct_capability_permissions.irq_accessible_permission,
          input_capability.permissions.direct_capability_permissions.cacheable_tlb,
          input_capability.permissions.direct_capability_permissions.cacheable_access
        };
      end else begin
        given_perm = {
          input_capability.permissions.indirect_capability_permissions.read_permission,
          input_capability.permissions.indirect_capability_permissions.write_permission,
          input_capability.permissions.indirect_capability_permissions.execute_permission,
          input_capability.permissions.indirect_capability_permissions.irq_accessible_permission,
          input_capability.permissions.indirect_capability_permissions.cacheable_tlb,
          input_capability.permissions.indirect_capability_permissions.cacheable_access
        };
      end

      // if requested permissions have bits set that given permissions do not, this evaluates to false
      input_capability_valid = (requested_perm | given_perm) == given_perm;

      if (~input_capability_valid) begin
        return NORTHCAPE_ERR_INSUFFICIENT_PERMS;
      end



      input_capability_valid = input_capability.refcount != '1;
      if (~input_capability_valid) begin
        return NORTHCAPE_ERR_TOO_MANY_REFERENCES;
      end

      return NORTHCAPE_NO_ERROR;
    endfunction

    static function northcape_error_code_t input_capability_allows_revoke(
        input capability_id_t input_cap_id, input capability_tag_t input_tag,
        northcape_cmt_entry_t input_capability, device_id_t create_input_device_id,
        task_id_t create_input_task_id);
      bit input_capability_valid_parser;
      bit input_capability_valid_type;
      cmt_parser_verdict_t verdict;
      
      verdict = (northcape_cmt_parser::entry_matches_validate_request(
          input_capability,
          input_cap_id,
          input_tag,
          ACCESS_NONE,
          create_input_device_id,
          create_input_task_id,
          input_capability.location.physical_location.locked_key  // valid or ignored
      ));

      input_capability_valid_parser = (verdict == CMT_ENTRY_MATCH);

      if (~input_capability_valid_parser) begin
        return cmt_parser_error_to_northcape_error(verdict);
      end

      input_capability_valid_type = (input_capability.capability_type == NORTHCAPE_CMT_DIRECT);

      if (~input_capability_valid_type) begin
        return NORTHCAPE_ERR_WRONG_CAP_TYPE;
      end

      return NORTHCAPE_NO_ERROR;

    endfunction


    static function northcape_error_code_t input_capability_allows_lock(
        input capability_id_t input_cap_id, input capability_tag_t input_tag,
        northcape_cmt_entry_t input_capability, device_id_t create_input_device_id,
        task_id_t create_input_task_id,
        // requested permissions
        input logic read_perm, write_perm, x_perm, irq_accessible_perm, cacheable_tlb_perm,
        cacheable_access_perm);
      bit input_capability_valid;
      northcape_indirect_capability_permissions_t requested_perm, given_perm;
      cmt_parser_verdict_t verdict;

      verdict = (northcape_cmt_parser::entry_matches_validate_request(
          input_capability,
          input_cap_id,
          input_tag,
          ACCESS_NONE,
          create_input_device_id,
          create_input_task_id,
          '0
      ));

      input_capability_valid = (verdict == CMT_ENTRY_MATCH || verdict == CMT_ENTRY_RECURSE);

      if (~input_capability_valid) begin
        return cmt_parser_error_to_northcape_error(verdict);
      end

      if(!(input_capability.capability_type inside {NORTHCAPE_CMT_DIRECT, NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_LOCK_HOLDER}))
      begin
        input_capability_valid = 0;
        return NORTHCAPE_ERR_WRONG_CAP_TYPE;
      end

      // for clone, permissions must not become stronger

      requested_perm = {
        read_perm,
        write_perm,
        x_perm,
        irq_accessible_perm,
        cacheable_tlb_perm,
        cacheable_access_perm
      };
      if (input_capability.capability_type == NORTHCAPE_CMT_DIRECT) begin
        given_perm = {
          input_capability.permissions.direct_capability_permissions.read_permission,
          input_capability.permissions.direct_capability_permissions.write_permission,
          input_capability.permissions.direct_capability_permissions.execute_permission,
          input_capability.permissions.direct_capability_permissions.irq_accessible_permission,
          input_capability.permissions.direct_capability_permissions.cacheable_tlb,
          input_capability.permissions.direct_capability_permissions.cacheable_access
        };
      end else begin
        given_perm = {
          input_capability.permissions.indirect_capability_permissions.read_permission,
          input_capability.permissions.indirect_capability_permissions.write_permission,
          input_capability.permissions.indirect_capability_permissions.execute_permission,
          input_capability.permissions.indirect_capability_permissions.irq_accessible_permission,
          input_capability.permissions.indirect_capability_permissions.cacheable_tlb,
          input_capability.permissions.indirect_capability_permissions.cacheable_access
        };
      end

      // if requested permissions have bits set that given permissions do not, this evaluates to false
      input_capability_valid = (requested_perm | given_perm) == given_perm;



      input_capability_valid = input_capability.refcount != '1;
      if (~input_capability_valid) begin
        return NORTHCAPE_ERR_INSUFFICIENT_PERMS;
      end

      return NORTHCAPE_NO_ERROR;
    endfunction

    static function northcape_error_code_t input_capability_allows_restrict(
        input capability_id_t input_cap_id, input capability_tag_t input_tag,
        northcape_cmt_entry_t input_capability, device_id_t create_input_device_id,
        task_id_t create_input_task_id,
        // permissions are NOT checked
        // in case we request to set a permission that was not set, we silently do not set it
        // requested segment length
        input segment_length_t new_segment_length, input segment_length_t parent_offset,
        bit restriction_requested);
      bit input_capability_valid_parser;
      bit input_capability_valid_type;
      bit input_capability_valid_len;
      bit input_restrictions_valid;

      cmt_parser_verdict_t verdict;

      verdict = (northcape_cmt_parser::entry_matches_validate_request(
          input_capability,
          input_cap_id,
          input_tag,
          ACCESS_NONE,
          create_input_device_id,
          create_input_task_id,
          '0
      ));

      input_capability_valid_parser = (verdict == CMT_ENTRY_MATCH || verdict == CMT_ENTRY_RECURSE);


      if (input_capability_valid_parser == 1'b0) begin
        return cmt_parser_error_to_northcape_error(verdict);
      end


      if(!(input_capability.capability_type inside{NORTHCAPE_CMT_DIRECT, NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_LOCK_HOLDER, NORTHCAPE_CMT_REVOCATION}))
      begin
        input_capability_valid_type = 0;
        return NORTHCAPE_ERR_WRONG_CAP_TYPE;
      end

      if (input_capability.capability_type inside {NORTHCAPE_CMT_DIRECT, NORTHCAPE_CMT_LOCK_HOLDER, NORTHCAPE_CMT_REVOCATION}) begin
        // length is never changed for direct capability, lock-holder capability
        input_capability_valid_len = 1'b1;
      end else if (input_capability.capability_type == NORTHCAPE_CMT_INDIRECT) begin
        // new_segment_length, parent_offset are subtrahend and addend, respectively
        input_capability_valid_len = (parent_offset <= input_capability.location.indirect_location.length - new_segment_length);
        // no overflow, no 0-length capability
        input_capability_valid_len &= (input_capability.location.indirect_location.length > new_segment_length);
      end else begin
        input_capability_valid_len = 1'b0;
      end

      if (input_capability_valid_len == 1'b0) begin
        return NORTHCAPE_ERR_INSUFFICIENT_LENGTH;
      end


      if (restriction_requested) begin
        input_restrictions_valid = (input_capability.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_NONE);
      end else begin
        // no restriction to be added - ok
        input_restrictions_valid = 1'b1;
      end


      if (input_restrictions_valid == 1'b0) begin
        return NORTHCAPE_ERR_CANNOT_ADD_RESTRICTIONS;
      end

      return NORTHCAPE_NO_ERROR;

      // no need to check reference count, as this operation does not create any new references
    endfunction

    static function northcape_error_code_t input_capability_allows_inspect(
        input capability_id_t input_cap_id, input capability_tag_t input_tag,
        northcape_cmt_entry_t input_capability, device_id_t create_input_device_id,
        task_id_t create_input_task_id);
      bit input_capability_valid_parser, input_capability_valid_restrictions;
      cmt_parser_verdict_t verdict;

      verdict = (northcape_cmt_parser::entry_matches_validate_request(
          input_capability,
          input_cap_id,
          input_tag,
          ACCESS_DERIVE_RECURSION,  /* we do NOT want restriction check - we will do this below */
          create_input_device_id,
          create_input_task_id,
          '0
      ));

      input_capability_valid_parser = (verdict == CMT_ENTRY_MATCH || verdict == CMT_ENTRY_RECURSE);

      if (~input_capability_valid_parser) begin
        return cmt_parser_error_to_northcape_error(verdict);
      end

      unique case (input_capability.restrictions.restriction_type)
        NORTHCAPE_RESTRICTIONS_NONE: input_capability_valid_restrictions = 1'b1;
        NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND:
        input_capability_valid_restrictions = (input_capability.restrictions.body.task_restriction.device_id == create_input_device_id && input_capability.restrictions.body.task_restriction.task_id == create_input_task_id);
        NORTHCAPE_RESTRICTIONS_SET_TASK_ID:
        // we will check separately if we need to do a partial reveal
        input_capability_valid_restrictions = 1'b1;
        NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED: input_capability_valid_restrictions = 1'b1;
        default: input_capability_valid_restrictions = 1'b0;
      endcase

      if (input_capability_valid_restrictions == 1'b0) begin
        return NORTHCAPE_ERR_WRONG_RESTRICTIONS;
      end

      return NORTHCAPE_NO_ERROR;
    endfunction

  endclass

endpackage
