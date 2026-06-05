/**
  * Parser functionality for CMT entries
  */

package northcape_cmt_parser_pkg;
  import northcape_types::*;

  typedef enum {
    CMT_ENTRY_FAIL_TAG,
    CMT_ENTRY_FAIL_PERMISSIONS,
    CMT_ENTRY_FAIL_RESTRICTIONS,
    CMT_ENTRY_FAIL_CAP_TYPE,
    CMT_ENTRY_FAIL_LOCKED,
    CMT_ENTRY_RECURSE,
    CMT_ENTRY_MATCH
  } cmt_parser_verdict_t;

  class automatic northcape_cmt_parser;

    static function logic entry_permission_allows_access(
        input northcape_cmt_entry_t cmt_entry, input axis_validate_request_perm_t access_type);

      if(cmt_entry.capability_type == NORTHCAPE_CMT_REVOCATION && !(access_type inside {ACCESS_NONE, ACCESS_DERIVE_RECURSION}))
      begin
        // NEVER allows read/write/execute
        return 1'b0;
      end

      // read-write-execute contained in all union versions
      unique case (access_type)
        READ: begin
          return cmt_entry.permissions.direct_capability_permissions.read_permission;
        end
        READ_IRQ: begin
          return cmt_entry.permissions.direct_capability_permissions.read_permission && cmt_entry.permissions.direct_capability_permissions.irq_accessible_permission;
        end
        WRITE: begin
          return cmt_entry.permissions.direct_capability_permissions.write_permission;
        end
        WRITE_IRQ: begin
          return cmt_entry.permissions.direct_capability_permissions.write_permission && cmt_entry.permissions.direct_capability_permissions.irq_accessible_permission;
        end
        READ_WRITE: begin
          return cmt_entry.permissions.direct_capability_permissions.read_permission && cmt_entry.permissions.direct_capability_permissions.write_permission;
        end
        READ_WRITE_IRQ: begin
          return cmt_entry.permissions.direct_capability_permissions.read_permission && cmt_entry.permissions.direct_capability_permissions.write_permission && cmt_entry.permissions.direct_capability_permissions.irq_accessible_permission;
        end
        EXECUTE: begin
          return cmt_entry.permissions.direct_capability_permissions.execute_permission;
        end
        EXECUTE_IRQ: begin
          return cmt_entry.permissions.direct_capability_permissions.execute_permission && cmt_entry.permissions.direct_capability_permissions.irq_accessible_permission;
        end
        ACCESS_NONE, ACCESS_DERIVE_RECURSION: return 1;
        default: begin
          return 0;
        end
      endcase
    endfunction

    protected static function cmt_parser_verdict_t entry_matches_root_capability(
        input northcape_cmt_entry_t cmt_entry);
      if (cmt_entry.capability_type != NORTHCAPE_CMT_DIRECT) begin
`ifdef DEBUG
        $display("Capability invalidated!");
`endif
        // perhaps invalidated?
        return CMT_ENTRY_FAIL_CAP_TYPE;
      end
      // OK
      return CMT_ENTRY_MATCH;
    endfunction

    static function cmt_parser_verdict_t entry_restriction_matches(
        input northcape_cmt_entry_t cmt_entry, input device_id_t device_id, input task_id_t task_id,
        input axis_validate_request_perm_t access_type);
      /* ACCESS_NONE is called on first capability in the chain - need to check restrictions */
      if (access_type == ACCESS_DERIVE_RECURSION || access_type == PERM_RESERVED) begin
`ifdef DEBUG
        $display("Restriction compare skip for access type %d (%s)!", access_type,
                 access_type.name());
`endif
        // for lookups, we can accept anything
        return CMT_ENTRY_MATCH;
      end
      unique case (cmt_entry.restrictions.restriction_type)
        NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED, NORTHCAPE_RESTRICTIONS_NONE: begin
`ifdef DEBUG
          $display("No restrictions to compare!");
`endif
          // nothing to check
          return CMT_ENTRY_MATCH;
        end
        NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND: begin
          device_id_t corrected_cmt_device_id = cmt_entry.restrictions.body.task_restriction.device_id >> NORTHCAPE_DEVICE_ID_COMP_IGNORED_BITS;
          device_id_t corrected_input_device_id = device_id >> NORTHCAPE_DEVICE_ID_COMP_IGNORED_BITS;
          // MMUs have two "devices": read and write channel "device"
          // thus, ignore least significant bit in comparison

`ifdef DEBUG
          $display(
              "For TASK_ID_BOUND restriction comparing device %x against device %x and task %x against task %x",
              corrected_cmt_device_id, corrected_input_device_id,
              cmt_entry.restrictions.body.task_restriction.task_id, task_id);
`endif
          if(corrected_cmt_device_id != corrected_input_device_id || cmt_entry.restrictions.body.task_restriction.task_id != task_id)
          begin
`ifdef DEBUG
            $display("Restriction mismatch!");
`endif
            return CMT_ENTRY_FAIL_RESTRICTIONS;
          end
          return CMT_ENTRY_MATCH;
        end
        NORTHCAPE_RESTRICTIONS_SET_TASK_ID: begin
          device_id_t corrected_cmt_device_id = cmt_entry.restrictions.body.task_restriction.device_id >> NORTHCAPE_DEVICE_ID_COMP_IGNORED_BITS;
          device_id_t corrected_input_device_id = device_id >> NORTHCAPE_DEVICE_ID_COMP_IGNORED_BITS;

          if (access_type inside {EXECUTE, EXECUTE_IRQ}) begin
            // we can execute any task ID
            return CMT_ENTRY_MATCH;
          end

          // for other (R/W) access, only the task with the same task/device is allowed
          // this prevents subsystem caller from reading/writing context pointer
          if(corrected_cmt_device_id != corrected_input_device_id || cmt_entry.restrictions.body.task_restriction.task_id != task_id)
          begin
`ifdef DEBUG
            $display("Restriction mismatch!");
`endif
            return CMT_ENTRY_FAIL_RESTRICTIONS;
          end

          return CMT_ENTRY_MATCH;

        end
        default: begin
`ifdef DEBUG
          $display("Unknown restriction type %x!", cmt_entry.restrictions.restriction_type);
`endif
          return CMT_ENTRY_FAIL_RESTRICTIONS;
        end
      endcase

      return CMT_ENTRY_FAIL_RESTRICTIONS;
    endfunction

    protected static function cmt_parser_verdict_t entry_matches_direct_capability(
        input northcape_cmt_entry_t cmt_entry, northcape_lock_key_t lock_key);

      // locking also needs to be check during derive - cannot derive while capability is locked
      if (cmt_entry.location.physical_location.locked_key != lock_key) begin
        // can only access via lock holder capability
`ifdef DEBUG
        $display("Capability locked with key %x but got %x!",
                 cmt_entry.location.physical_location.locked_key, lock_key);
`endif
        return CMT_ENTRY_FAIL_LOCKED;
      end

      // no other direct-capability-specific restrictions
      // OK
      return CMT_ENTRY_MATCH;
    endfunction

    protected static function cmt_parser_verdict_t entry_matches_indirect_capability(
        input northcape_cmt_entry_t cmt_entry);

`ifdef DEBUG
      $display("Capability recurse");
`endif

      // currently no indirect-capability-specific restrictions
      // but we have to check the parent capabilities
      return CMT_ENTRY_RECURSE;
    endfunction

    protected static function cmt_parser_verdict_t entry_matches_lock_holder(
        input northcape_cmt_entry_t cmt_entry);
`ifdef DEBUG
      $display("Capability lock-holder recurse!");
`endif

      // currently no lock-holder-specific restrictions
      // but we have to check the parent capabilities
      return CMT_ENTRY_RECURSE;
    endfunction

    protected static function cmt_parser_verdict_t entry_matches_revocation(
        input northcape_cmt_entry_t cmt_entry);

`ifdef DEBUG
      $display("Capability lock-holder recurse!");
`endif

      // currently no revocation-specific restrictions
      // but we have to check the parent capabilities
      return CMT_ENTRY_RECURSE;

    endfunction

    static function cmt_parser_verdict_t entry_matches_validate_request(
        input northcape_cmt_entry_t cmt_entry, input capability_id_t given_capability_id,
        input capability_tag_t given_capability_tag, input axis_validate_request_perm_t access_type,
        input device_id_t device_id, input task_id_t task_id, input northcape_lock_key_t lock_key);
      if (cmt_entry.tag != given_capability_tag) begin
        // forgery!
`ifdef DEBUG
        $display("Capability tag error!");
`endif
        return CMT_ENTRY_FAIL_TAG;
      end

      if (!entry_permission_allows_access(cmt_entry, access_type)) begin
        // access type not allowed
`ifdef DEBUG
        $display("Capability invalid access!");
`endif
        return CMT_ENTRY_FAIL_PERMISSIONS;
      end

      // if we are recursing in derive, we do not need to check restrictions
      // the user only needs to be able to use the first capability that it provided
      if (entry_restriction_matches(
              cmt_entry, device_id, task_id, access_type
          ) != CMT_ENTRY_MATCH) begin
`ifdef DEBUG
        $display("Capability restriction fail!");
`endif
        return CMT_ENTRY_FAIL_RESTRICTIONS;
      end

      unique case (cmt_entry.capability_type)
        NORTHCAPE_CMT_DIRECT: begin
          return entry_matches_direct_capability(cmt_entry, lock_key);
        end
        NORTHCAPE_CMT_INDIRECT: begin
          return entry_matches_indirect_capability(cmt_entry);
        end
        NORTHCAPE_CMT_LOCK_HOLDER: begin
          return entry_matches_lock_holder(cmt_entry);
        end
        NORTHCAPE_CMT_REVOCATION: begin
          return entry_matches_revocation(cmt_entry);
        end
        default: begin
          return CMT_ENTRY_FAIL_CAP_TYPE;
        end
      endcase

    endfunction

    static function northcape_physical_address_t entry_get_phys_addr(
        input northcape_cmt_entry_t cmt_entry);
      unique case (cmt_entry.capability_type)
        NORTHCAPE_CMT_DIRECT: begin
          return cmt_entry.location.physical_location.base;
        end
        NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_REVOCATION: begin
          return cmt_entry.location.indirect_location.effective_base;
        end
        // none
        NORTHCAPE_CMT_LOCK_HOLDER: begin
          return '0;
        end
        default: begin
          // TODO not implemented
          return '1;
        end
      endcase
    endfunction

    static function segment_length_t entry_get_phys_length(input northcape_cmt_entry_t cmt_entry);
      unique case (cmt_entry.capability_type)
        NORTHCAPE_CMT_DIRECT: begin
          return cmt_entry.location.physical_location.length;
        end
        NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_REVOCATION: begin
          return cmt_entry.location.indirect_location.length;
        end
        // none
        NORTHCAPE_CMT_LOCK_HOLDER: begin
          return '0;
        end
        default: begin
          // TODO not implemented
          return '0;
        end
      endcase
    endfunction

    static function logic [63:0] entry_get_parent_token(input northcape_cmt_entry_t cmt_entry);
      unique case (cmt_entry.capability_type)
        NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_REVOCATION: begin
          return cmt_entry.location.indirect_location.parent;
        end
        // none
        NORTHCAPE_CMT_LOCK_HOLDER: begin
          return cmt_entry.location.lock_holder_location.parent;
        end
        default: begin
          // TODO not implemented
          return '1;
        end
      endcase
    endfunction

    static function northcape_lock_key_t entry_get_lock_key(input northcape_cmt_entry_t cmt_entry);
      unique case (cmt_entry.capability_type)
        NORTHCAPE_CMT_DIRECT: begin
          return cmt_entry.location.physical_location.locked_key;
        end
        NORTHCAPE_CMT_LOCK_HOLDER: begin
          return cmt_entry.location.lock_holder_location.lock_key;
        end
        default: begin
          // not lockable
          return '0;
        end
      endcase
    endfunction

  endclass

endpackage
