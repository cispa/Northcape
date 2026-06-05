/**
  * Test class that holds all state and expected responses for a Capability Operations Test.
  */
package northcape_capability_ops_transaction;



  import axi5::*;
  import northcape_types::*;
  import northcape_test::*;
  import northcape_capability_ops_common::*;
  import northcape_capability_resolver_transaction::NorthcapeCapabilityResolverTransactionCMTEntry;
  import northcape_capability_resolver_transaction::MAX_INDIRECT_CAPABILITIES;
  import northcape_capability_resolver_transaction::NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE_CHILD;
  import northcape_capability_resolver_transaction::NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_DIRECT_CAPABILITY;
  import northcape_capability_resolver_common::*;
  import northcape_cmt_parser_pkg::northcape_cmt_parser;

  import uvm_pkg::*;
  `include "uvm_macros.svh"



  /**
    * Main scoreboard for capability operations module test
    */
  class NorthcapeCapabilityOpsTransaction #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      // parameters for AXI LITE (slave) interface

      parameter AXI_LITE_DATA_WIDTH = -1,
      parameter AXI_LITE_ADDR_WIDTH = -1,

      parameter HASH_TYPE = -1,

      parameter bit [AXI_ADDR_WIDTH-1:0] INITIAL_CMT_BASE = -1,
      parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1
  ) extends uvm_sequence_item;


    typedef NorthcapeCapabilityOpsTransaction#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),

        .HASH_TYPE(HASH_TYPE),

        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) my_type_t;

    typedef NorthcapeCapabilityResolverTransactionCMTEntry#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .HASH_TYPE(HASH_TYPE_IDENTITY)
    ) cmt_entry_t;

    localparam string COMPONENT_NAME = "Northcape Capability Ops Transaction";

    // for sake of time, only test for the smallest number of capabilities
    localparam UNSUCCESSFULL_LOOKUP_WIDTH = $clog2(NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_32 + 1);
    // number of attempts for which the capability slot is blocked
    // for this transaction only
    rand bit [UNSUCCESSFULL_LOOKUP_WIDTH:0] unsuccessful_lookups;


    constraint unsuccessful_lookup_number_does_not_overflow {
      if (valid_test) {
        // otherwise, would not create an OK lookup
        unsuccessful_lookups <= NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_32;
      }
    }

    bit [AXI_ADDR_WIDTH-1:0] cmt_base;
    int unsigned cmt_size_clog2;

    // 1 for valid access --> OK output
    // randc --> cycles through valid and invalid
    rand bit valid_test;

    rand capability_type_t intended_capability_type;

    constraint valid_capability_types_only_on_valid_test {
      if (valid_test) {
        intended_capability_type == OFFSET_32_BIT ||
        intended_capability_type == OFFSET_24_BIT ||
        intended_capability_type == OFFSET_16_BIT ||
        intended_capability_type == OFFSET_8_BIT;
      }
    }

    rand bit [AXI_DATA_WIDTH-1:0] input_token, input_token_right;

    // for restriction of new capability
    rand device_id_t device_id_restriction;
    rand task_id_t task_id_restriction;
    rand bit [AXI_DATA_WIDTH-1:0] device_interpreted_restriction;
    rand northcape_restriction_type_t restriction_type;
    rand bit restriction_enabled;

    // current device
    // the one performing the operation
    rand device_id_t device_id_current;
    rand task_id_t task_id_current;

    // permissions for newly created segment
    rand bit read_perm;
    rand bit write_perm;
    rand bit x_perm;
    rand bit lockable_perm;
    rand bit irq_accessible_perm;
    rand bit cacheable_tlb_perm;
    rand bit cacheable_access_perm;

    rand northcape_capability_operation_t operation;

    rand northcape_cmt_entry_t input_cmt_entry;
    // for merge operation
    // second / right capability to merge the first one with
    rand northcape_cmt_entry_t input_cmt_entry_right;

    constraint operation_must_be_valid_supported {
      if (valid_test) {
        operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE ||
        operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE ||
        operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP   ||
        operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE  ||
        operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE  || 
        operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE ||
        operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK   || 
        operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT||
        operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT;
        
      }
    }


    // slow and not many interesting edge cases
    constraint perform_unseal_infrequently {
      operation dist {
        NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE := 1000,
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE := 1000,
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP := 1000,
        NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE := 1000,
        NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE := 1000,
        NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE := 1000,
        NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK := 1000,
        NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT := 1000,
        NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT := 1000
      };
    }

    rand axi_resp_t read_resp;
    rand axi_resp_t write_resp;

    constraint responses_must_be_valid_on_valid_test {
      if (valid_test) {
        read_resp == OKAY;
        write_resp == OKAY;
      }
    }

    // discriminates whether the new segment starts at beginning or end of input segment
    rand bit direction;
    rand segment_length_t new_segment_length;
    // how many bytes into the parent the new segment is supposed to start
    rand segment_length_t parent_offset;



    // in case of derive, the cap ops module needs to lookup the hierarchie of capabilities
    // this is this very list
    cmt_entry_t recursion_cmt_entries[$];

    // nonce for newly created entry
    rand northcape_nonce_t nonce;

    // ID for newly created transaction
    capability_id_t output_capability_id;

    rand int rng_seed;

    // RCSR or MMIO interface? -> test multiplexer
    rand bit use_rcsr_interface;



    constraint input_capability_must_be_possible {
      if (valid_test) {
        if(operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE || operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE || operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE || operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE || operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT){
          if (input_cmt_entry.capability_type == NORTHCAPE_CMT_DIRECT) {
            64'(input_cmt_entry.location.physical_location.base) + 64'(input_cmt_entry.location.physical_location.length) <= 64'hffffffff;
          }
          if (input_cmt_entry.capability_type == NORTHCAPE_CMT_INDIRECT) {
            64'(input_cmt_entry.location.indirect_location.effective_base) + 64'(input_cmt_entry.location.indirect_location.length) <= 64'hffffffff;
          }
        }
        // right capability must not cause address overrun
        if (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE) {
          64'(input_cmt_entry_right.location.physical_location.base) + 64'(input_cmt_entry_right.location.physical_location.length) <= 64'hffffffff;
          64'(input_cmt_entry.location.physical_location.base) + 64'(input_cmt_entry.location.physical_location.length) + 64'(input_cmt_entry_right.location.physical_location.length) <= 64'hffffffff;
        }
      }
    }

    constraint new_segment_length_must_be_smaller_than_old_segment {
      if (valid_test) {
        if (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE) {
          new_segment_length <= input_cmt_entry.location.physical_location.length;
        } else
        if (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE) {
          parent_offset + new_segment_length <= input_cmt_entry.location.indirect_location.length;
        }
        // offset is addend, new_segment_length is subtrahend
        // only indirect capabilities are modified, though
        if (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT) {
          if (input_cmt_entry.capability_type == NORTHCAPE_CMT_INDIRECT) {
            64'(parent_offset) < 64'(input_cmt_entry.location.indirect_location.length)  - 64'(new_segment_length);
            // no overflow
            input_cmt_entry.location.indirect_location.length > new_segment_length;
          }

        }
        // others: not used, no restrictions necessary
      }
    }

    constraint new_segment_length_must_be_possible_with_offset {
      if (valid_test) {
        // not used for these operations
        if (!(operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE, NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT})) {
          new_segment_length <= max_length_for_capability_type(intended_capability_type);
        }
      }
    }

    constraint new_segment_length_cannot_be_0_for_valid_test {
      if (valid_test) {
        // not used for some operations
        if (!(operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE, NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT})) {
          new_segment_length > 0;
        }
      }
    }

    constraint restriction_type_must_be_valid_when_successful_test {
      if (valid_test) {
        input_cmt_entry.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_NONE ||
        input_cmt_entry.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED ||
        input_cmt_entry.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND ||
        input_cmt_entry.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID;

        input_cmt_entry_right.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_NONE ||
        input_cmt_entry_right.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED ||
        input_cmt_entry_right.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND ||
        input_cmt_entry_right.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID;
      }
    }

    constraint input_capability_is_direct_or_indirect_for_derive {
      if (valid_test) {
        if(operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE || operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE || operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK){
          input_cmt_entry.capability_type inside {NORTHCAPE_CMT_DIRECT, NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_LOCK_HOLDER};
        }
      }
    }

    constraint input_capability_is_direct_indirect_or_lock_holder_for_restrict {
      if (valid_test && operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT) {
        // lock_holder is added later
        input_cmt_entry.capability_type inside {NORTHCAPE_CMT_DIRECT, NORTHCAPE_CMT_INDIRECT};
      }
    }

    constraint refcount_is_not_full {
      if (valid_test) {
        input_cmt_entry.refcount != '1;
      }
    }

    constraint input_capability_has_valid_type_for_valid_test {
      if (valid_test) {
        input_cmt_entry.capability_type inside {NORTHCAPE_CMT_DIRECT, NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_LOCK_HOLDER};
      }
    }

    rand int unsigned number_indirect_caps;

    rand bit drop_make_one_capability_invalid;

    rand bit drop_flip_type;

    rand northcape_mac_tag_t drop_flip_tag;

    rand bit restrict_input_is_lock_holder;

    constraint suitable_number_indirect_caps {
      // we add an input CMT entry on top
      number_indirect_caps <= MAX_INDIRECT_CAPABILITIES - 1;
    }

    constraint derive_input_capability_must_match_number_indirect_caps {
      if (valid_test && (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE || operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE || operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK || operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT)) {
        if (number_indirect_caps == 0) {
          input_cmt_entry.capability_type == NORTHCAPE_CMT_DIRECT;
        } else {
          input_cmt_entry.capability_type inside {NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_LOCK_HOLDER};
        }
      }
    }

    // nothing is stopping us from revoking any segment of any size
    // however, we impose a size limit to limit the test duration
    // note that interesting edge cases are probably all of the remainders of MAX_BYTES_PER_TRANSFER, not the length on its own
    localparam MAX_SEGMENT_LENGTH_REVOKE = MAX_BYTES_PER_TRANSFER * 32;


    // used for recursion
    rand bit [AXI_ADDR_WIDTH -1 : 0] capability_tokens[MAX_INDIRECT_CAPABILITIES+1];

    // for drop(), capability might either be indirect or lock holder
    // TODO direct constraint does not work for some reason
    rand bit drop_capability_is_lock_holder;

    // there is a second FSM with separate MMIO interface that is used in subsystem calls in IRQ regime
    // it currently only supports inspect() operations
    rand bit use_isr_fsm;

    // used for any lock-holders in the input sequence
    rand northcape_lock_key_t ref_lock_key;

    // number of orphans to be kicked in sweep - from integration agent
    int orphans;

    // 0 is special (unlocked)
    constraint ref_lock_key_is_nonzero {ref_lock_key != 0;}

    static task_id_t unseal_global_tid = 0;

    function void post_randomize();
      if (valid_test) begin

        // we will NOT be generating the lock-holder
        if (number_indirect_caps == 0) begin
          ref_lock_key = '0;
        end else begin
          // TODO not sure how this is possible - suspect xsim bug
          while (ref_lock_key == 0) begin
            ref_lock_key = $urandom();
          end
          `uvm_warning(COMPONENT_NAME, "ref_lock_key should not be 0!");
        end

        if (new_segment_length > max_length_for_capability_type(intended_capability_type)) begin
          // TODO I am not sure why the constraint above does not catch this!
          `uvm_warning(COMPONENT_NAME, $sformatf(
                       "New segment length %d is too big for capability type %s",
                       new_segment_length,
                       intended_capability_type.name()
                       ));
          new_segment_length = max_length_for_capability_type(intended_capability_type);
        end

        if(operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT && restriction_enabled == 1'b1) begin
          // can only add restriction if no restriction exists yet
          input_cmt_entry.restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
        end

        input_cmt_entry.tag =
            capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(input_token);
        input_cmt_entry_right.tag =
            capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(input_token_right);

        if(input_cmt_entry.restrictions.restriction_type inside {NORTHCAPE_RESTRICTIONS_SET_TASK_ID, NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND} && operation != NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT)
        begin
          // need to be able to do the operation
          input_cmt_entry.restrictions.body.task_restriction.task_id   = task_id_current;
          input_cmt_entry.restrictions.body.task_restriction.device_id = device_id_current;
        end

        if(operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT && input_cmt_entry.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND)
        begin
          // set-task-id can have any body (scoreboard checks if we need to do a partial or full reveal)
          // device-interpreted does not matter at all
          input_cmt_entry.restrictions.body.task_restriction.task_id   = task_id_current;
          input_cmt_entry.restrictions.body.task_restriction.device_id = device_id_current;
        end

        if(input_cmt_entry_right.restrictions.restriction_type inside {NORTHCAPE_RESTRICTIONS_SET_TASK_ID, NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND})
        begin
          input_cmt_entry_right.restrictions.body.task_restriction.task_id   = task_id_current;
          input_cmt_entry_right.restrictions.body.task_restriction.device_id = device_id_current;
        end

        if(operation != NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT && operation != NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP && restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID && device_id_current != NORTHCAPE_LOADER_TASK_DEVICE_ID && task_id_current != NORTHCAPE_LOADER_TASK_TASK_ID)
        begin
          // cannot impersonate other task
          task_id_restriction   = task_id_current;
          device_id_restriction = device_id_current;
        end

        unique case (operation)
          NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE: begin

            input_cmt_entry.location.physical_location.locked_key = '0;

            // must be given a valid direct capability
            input_cmt_entry.capability_type = NORTHCAPE_CMT_DIRECT;

            // fails on references exist
            // exception: root capability --> needed to bootstrap MMIO
            if (capability_accessors#(64)::capability_get_id(input_token) != 0) begin
              input_cmt_entry.refcount = '0;
            end

            // new permissions must be as or more restrictive as the current ones
            if (read_perm) begin
              input_cmt_entry.permissions.direct_capability_permissions.read_permission = 1;
            end
            if (write_perm) begin
              input_cmt_entry.permissions.direct_capability_permissions.write_permission = 1;
            end
            if (x_perm) begin
              input_cmt_entry.permissions.direct_capability_permissions.execute_permission = 1;
            end
            if (lockable_perm) begin
              input_cmt_entry.permissions.direct_capability_permissions.lockable_permission = 1;
            end
            if (irq_accessible_perm) begin
              input_cmt_entry.permissions.direct_capability_permissions.irq_accessible_permission = 1;
            end
            if (cacheable_tlb_perm) begin
              input_cmt_entry.permissions.direct_capability_permissions.cacheable_tlb = 1'b1;
            end
            if (cacheable_access_perm) begin
              input_cmt_entry.permissions.direct_capability_permissions.cacheable_access = 1'b1;
            end

          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
            // new permissions must be as or more restrictive as the current ones
            if (read_perm) begin
              input_cmt_entry.permissions.indirect_capability_permissions.read_permission = 1;
            end
            if (write_perm) begin
              input_cmt_entry.permissions.indirect_capability_permissions.write_permission = 1;
            end
            if (x_perm) begin
              input_cmt_entry.permissions.indirect_capability_permissions.execute_permission = 1;
            end
            if (irq_accessible_perm) begin
              input_cmt_entry.permissions.direct_capability_permissions.irq_accessible_permission = 1;
            end
            if (cacheable_tlb_perm) begin
              input_cmt_entry.permissions.indirect_capability_permissions.cacheable_tlb = 1'b1;
            end
            if (cacheable_access_perm) begin
              input_cmt_entry.permissions.indirect_capability_permissions.cacheable_access = 1'b1;
            end
            if (lockable_perm && input_cmt_entry.capability_type == NORTHCAPE_CMT_DIRECT) begin
              input_cmt_entry.permissions.direct_capability_permissions.lockable_permission = 1;
            end

            // we need to provide a list of CMT entries up to the direct capability in case the input capability is indirect
            // for direct input capabilities, nothing to do - can derive directly
            if (input_cmt_entry.capability_type inside {NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_LOCK_HOLDER}) begin

              if (input_cmt_entry.capability_type == NORTHCAPE_CMT_LOCK_HOLDER) begin
                input_cmt_entry.location.lock_holder_location.lock_key = ref_lock_key;
              end

              recursion_cmt_entries = cmt_entry_t::generate_test_entries(
                  NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE_CHILD,
                  ACCESS_NONE,
                  0,
                  // for restrict, these are addend and subtrahend
                  parent_offset + new_segment_length,
                  capability_tokens,
                  cmt_base,
                  device_id_current,
                  task_id_current,
                  ref_lock_key,
                  number_indirect_caps,
                  restriction_type
              );

              if (input_cmt_entry.capability_type == NORTHCAPE_CMT_INDIRECT) begin
                if(recursion_cmt_entries[0].get_entry().capability_type == NORTHCAPE_CMT_DIRECT)
                begin
                  input_cmt_entry.location.indirect_location.effective_base = recursion_cmt_entries[0].get_entry().location.physical_location.base;
                  input_cmt_entry.location.indirect_location.length = recursion_cmt_entries[0].get_entry().location.physical_location.length;
                end else begin
                  input_cmt_entry.location.indirect_location.effective_base = recursion_cmt_entries[0].get_entry().location.indirect_location.effective_base;
                  input_cmt_entry.location.indirect_location.length = recursion_cmt_entries[0].get_entry().location.indirect_location.length;
                end
                input_cmt_entry.location.indirect_location.parent = capability_tokens[0];
                if (new_segment_length > input_cmt_entry.location.indirect_location.length) begin
                  /* only possible in directed tests */
                  new_segment_length = input_cmt_entry.location.indirect_location.length - parent_offset;
                end
                while(parent_offset + new_segment_length >= input_cmt_entry.location.indirect_location.length)
                begin
                  /* only possible in directed tests -> reduce offset */
                  parent_offset = $urandom() % parent_offset;
                end
              end else begin
                input_cmt_entry.location.lock_holder_location.parent = capability_tokens[0];
              end

            end else if (input_cmt_entry.capability_type == NORTHCAPE_CMT_DIRECT) begin
              input_cmt_entry.location.physical_location.locked_key = '0;
            end

            if (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK) begin
              if (valid_test && operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK && input_cmt_entry.capability_type == NORTHCAPE_CMT_DIRECT)
              begin
                input_cmt_entry.permissions.direct_capability_permissions.lockable_permission = 1;
              end else if (valid_test) begin
                recursion_cmt_entries[recursion_cmt_entries.size()-1].randomized_permissions_direct.lockable_permission = 1;
              end

            end

            if (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT) begin
              // passed through directly to MMIO
              // hence, need to clean up the reserved bits
              unique case (input_cmt_entry.restrictions.restriction_type)
                NORTHCAPE_RESTRICTIONS_SET_TASK_ID, NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND: begin
                  input_cmt_entry.restrictions.body.task_restriction.reserved = '0;
                end
                NORTHCAPE_RESTRICTIONS_NONE: begin
                  input_cmt_entry.restrictions.body = '0;
                end
                default: begin
                  // nothing to do
                end
              endcase
            end

          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
            if (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP) begin
              input_cmt_entry.capability_type = drop_capability_is_lock_holder ? NORTHCAPE_CMT_LOCK_HOLDER : NORTHCAPE_CMT_INDIRECT;
              // fails on references exist
              input_cmt_entry.refcount = '0;
            end
            else if(operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT && input_cmt_entry.capability_type == NORTHCAPE_CMT_INDIRECT)
            begin
              input_cmt_entry.capability_type = restrict_input_is_lock_holder ? NORTHCAPE_CMT_LOCK_HOLDER : NORTHCAPE_CMT_INDIRECT;
            end

            if (input_cmt_entry.capability_type != NORTHCAPE_CMT_DIRECT) begin

              if (input_cmt_entry.capability_type == NORTHCAPE_CMT_LOCK_HOLDER) begin
                input_cmt_entry.location.lock_holder_location.lock_key = ref_lock_key;
              end

              recursion_cmt_entries = cmt_entry_t::generate_test_entries(
                  NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE_CHILD,
                  ACCESS_NONE,
                  0,
                  // constraints + layout make this work at this point
                  operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT ? input_cmt_entry.location.indirect_location.length : parent_offset + new_segment_length,
                  capability_tokens,
                  cmt_base,
                  device_id_current,
                  task_id_current,
                  ref_lock_key,
                  number_indirect_caps,
                  restriction_type
              );
            end

            if (input_cmt_entry.capability_type == NORTHCAPE_CMT_INDIRECT) begin
              input_cmt_entry.location.indirect_location.parent = capability_tokens[0];

              if(recursion_cmt_entries[0].get_entry().capability_type == NORTHCAPE_CMT_DIRECT)
              begin
                input_cmt_entry.location.indirect_location.effective_base = recursion_cmt_entries[0].get_entry().location.physical_location.base;
                input_cmt_entry.location.indirect_location.length = recursion_cmt_entries[0].get_entry().location.physical_location.length;
              end else begin
                input_cmt_entry.location.indirect_location.effective_base = recursion_cmt_entries[0].get_entry().location.indirect_location.effective_base;
                input_cmt_entry.location.indirect_location.length = recursion_cmt_entries[0].get_entry().location.indirect_location.length;
              end

            end else if (input_cmt_entry.capability_type == NORTHCAPE_CMT_LOCK_HOLDER) begin
              input_cmt_entry.location.lock_holder_location.parent = capability_tokens[0];
            end else if (input_cmt_entry.capability_type == NORTHCAPE_CMT_DIRECT) begin
              // restrict only
              input_cmt_entry.location.physical_location.locked_key = '0;
            end


            if (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP && drop_make_one_capability_invalid) begin
              cmt_entry_t entry_to_flip;
              // note that drop contradicts CMT_DIRECT, so recursion_cmt_entries always exist

              // to make the testbench simpler, we always flip the direct capability at the end of the chain
              // we do not lose generality, as the tree might have arbitrary heigth and it does not matter what the capability that we flip originall was
              entry_to_flip = recursion_cmt_entries[recursion_cmt_entries.size()-1];
              if (drop_flip_type) begin
                // fresh from revoke() - invalid entry
                entry_to_flip.entry_type = NORTHCAPE_CMT_INVALID;
              end else begin
                // newly allocated - tag does not match
                entry_to_flip.mac_tag_provided = drop_flip_tag;
              end
            end
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE: begin
            input_cmt_entry.location.physical_location.locked_key = '0;
            input_cmt_entry_right.location.physical_location.locked_key = '0;
            // TODO this fails as a constraint
            input_cmt_entry_right.location.physical_location.base = input_cmt_entry.location.physical_location.base + input_cmt_entry.location.physical_location.length;
            // must be given a valid direct capability
            input_cmt_entry.capability_type = NORTHCAPE_CMT_DIRECT;
            input_cmt_entry_right.capability_type = NORTHCAPE_CMT_DIRECT;

            // fails on references exist
            input_cmt_entry.refcount = '0;
            input_cmt_entry_right.refcount = '0;
            // restrictions, permissions always accepted
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE: begin
            // must be given a valid direct capability
            input_cmt_entry.capability_type = NORTHCAPE_CMT_DIRECT;
            // too large segment causes very high execution time
            input_cmt_entry.location.physical_location.length = input_cmt_entry.location.physical_location.length % MAX_SEGMENT_LENGTH_REVOKE;
          end
          default: begin
            // not supported
            `uvm_fatal(COMPONENT_NAME, $sformatf("Invalid operation generated: %x", operation));
          end

        endcase

        if (!operation_is_supported()) begin
          `uvm_fatal(COMPONENT_NAME, $sformatf(
                     "Operation not supported for valid test - transaction %s", convert2string()));
        end

        foreach (recursion_cmt_entries[i]) begin
          northcape_cmt_entry_t entry = recursion_cmt_entries[i].get_entry();
          if(entry.capability_type == NORTHCAPE_CMT_LOCK_HOLDER && entry.location.lock_holder_location.lock_key == '0)
          begin
            `uvm_fatal(COMPONENT_NAME, "Lock holder has lock key 0 - should not be possible!");
          end
        end
      end
    endfunction

    // checks whether the ops will immediately reject the operation or at least start retrieving the capabilities
    function bit operation_is_supported();
      bit ret;

      ret = 1'b1;

      if(!(operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT,NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP}) && restriction_enabled && restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID)
      begin
        ret = (task_id_restriction == task_id_current && device_id_restriction == device_id_current || task_id_current == NORTHCAPE_LOADER_TASK_TASK_ID && device_id_current == NORTHCAPE_LOADER_TASK_DEVICE_ID);
      end

      unique case (operation)
        NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE, NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE: begin
          `uvm_info(COMPONENT_NAME, $sformatf(
                    "Checking segment length %d vs max length %d: %b",
                    new_segment_length,
                    max_length_for_capability_type(
                        intended_capability_type
                    ),
                    new_segment_length <= max_length_for_capability_type(
                        intended_capability_type
                    )
                    ), UVM_DEBUG);
          if (new_segment_length <= max_length_for_capability_type(intended_capability_type)) begin
            return ret;
          end
          return 0;
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE, NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
          // no immediate sanity checks
          return ret;
        end
        default: begin
          return 0;
        end
      endcase

    endfunction

    function northcape_error_code_t input_capability_allows_operation(
        bit is_second_capability = 1'b0);
      unique case (operation)
        NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE:
        return NorthcapeCapabilityOpsInputParser::input_capability_allows_create(
            capability_accessors#(64)::capability_get_id(
                input_token
            ),
            capability_accessors#(64)::capability_get_tag(
                input_token
            ),
            input_cmt_entry,
            device_id_current,
            task_id_current,
            read_perm,
            write_perm,
            x_perm,
            lockable_perm,
            irq_accessible_perm,
            cacheable_tlb_perm,
            cacheable_access_perm,
            new_segment_length
        );
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE: begin
          return NorthcapeCapabilityOpsInputParser::input_capability_allows_derive(
              capability_accessors#(64)::capability_get_id(
                  input_token
              ),
              capability_accessors#(64)::capability_get_tag(
                  input_token
              ),
              input_cmt_entry,
              device_id_current,
              task_id_current,
              read_perm,
              write_perm,
              x_perm,
              irq_accessible_perm,
              cacheable_tlb_perm,
              cacheable_access_perm,
              new_segment_length,
              parent_offset
          );
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
          return NorthcapeCapabilityOpsInputParser::input_capability_allows_drop(
              capability_accessors#(64)::capability_get_id(
                  input_token
              ),
              capability_accessors#(64)::capability_get_tag(
                  input_token
              ),
              input_cmt_entry,
              device_id_current,
              task_id_current
          );
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE: begin
          northcape_error_code_t left_valid, right_valid;

          left_valid = NorthcapeCapabilityOpsInputParser::input_capability_allows_merge(
              capability_accessors#(64)::capability_get_id(
                  input_token
              ),
              capability_accessors#(64)::capability_get_tag(
                  input_token
              ),
              input_cmt_entry,
              device_id_current,
              task_id_current
          );
          right_valid = NorthcapeCapabilityOpsInputParser::input_capability_allows_merge(
              capability_accessors#(64)::capability_get_id(
                  input_token_right
              ),
              capability_accessors#(64)::capability_get_tag(
                  input_token_right
              ),
              input_cmt_entry_right,
              device_id_current,
              task_id_current
          );

          // no request for second capability if we error out in the first one

          if (is_second_capability == 1'b0) begin
            return left_valid;
          end

          if (left_valid != NORTHCAPE_NO_ERROR) begin
            return left_valid;
          end
          if (right_valid != NORTHCAPE_NO_ERROR) begin
            return right_valid;
          end

          if(64'(input_cmt_entry.location.physical_location.base) + 64'(input_cmt_entry.location.physical_location.length) == 64'(input_cmt_entry_right.location.physical_location.base))
          begin
            return NORTHCAPE_NO_ERROR;
          end else begin
            return NORTHCAPE_ERR_NOT_ADJACENT;
          end
        end

        NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE: begin
          return NorthcapeCapabilityOpsInputParser::input_capability_allows_clone(
              capability_accessors#(64)::capability_get_id(
                  input_token
              ),
              capability_accessors#(64)::capability_get_tag(
                  input_token
              ),
              input_cmt_entry,
              device_id_current,
              task_id_current,
              read_perm,
              write_perm,
              x_perm,
              irq_accessible_perm,
              cacheable_tlb_perm,
              cacheable_access_perm
          );
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE: begin
          return NorthcapeCapabilityOpsInputParser::input_capability_allows_revoke(
              capability_accessors#(64)::capability_get_id(
                  input_token
              ),
              capability_accessors#(64)::capability_get_tag(
                  input_token
              ),
              input_cmt_entry,
              device_id_current,
              task_id_current
          );
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
          northcape_error_code_t allows_lock;
          bit lock_key_matches = 1'b1;


          allows_lock = NorthcapeCapabilityOpsInputParser::input_capability_allows_lock(
              capability_accessors#(64)::capability_get_id(
                  input_token
              ),
              capability_accessors#(64)::capability_get_tag(
                  input_token
              ),
              input_cmt_entry,
              device_id_current,
              task_id_current,
              read_perm,
              write_perm,
              x_perm,
              irq_accessible_perm,
              cacheable_tlb_perm,
              cacheable_access_perm
          );

          if (allows_lock != NORTHCAPE_NO_ERROR) begin
            return allows_lock;
          end

          if (recursion_cmt_entries.size() != 0) begin
            // in case of valid (multi-locked) test, lock-holder token can be non-zero
            lock_key_matches = lock_key_matches && (recursion_cmt_entries[recursion_cmt_entries.size()-1].get_entry().location.physical_location.locked_key == '0 || valid_test);
            lock_key_matches = lock_key_matches && recursion_cmt_entries[recursion_cmt_entries.size()-1].get_entry().permissions.direct_capability_permissions.lockable_permission;
          end else begin
            lock_key_matches = lock_key_matches && input_cmt_entry.location.physical_location.locked_key == '0;
            lock_key_matches = lock_key_matches && input_cmt_entry.permissions.direct_capability_permissions.lockable_permission;
          end

          return lock_key_matches ? NORTHCAPE_NO_ERROR : NORTHCAPE_ERR_PARSER_FAIL_LOCKED;
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT: begin
          return NorthcapeCapabilityOpsInputParser::input_capability_allows_inspect(
              capability_accessors#(64)::capability_get_id(
                  input_token
              ),
              capability_accessors#(64)::capability_get_tag(
                  input_token
              ),
              input_cmt_entry,
              device_id_current,
              task_id_current
          );
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
          return NorthcapeCapabilityOpsInputParser::input_capability_allows_restrict(
              capability_accessors#(64)::capability_get_id(
                  input_token
              ),
              capability_accessors#(64)::capability_get_tag(
                  input_token
              ),
              input_cmt_entry,
              device_id_current,
              task_id_current,
              new_segment_length,
              parent_offset,
              restriction_enabled
          );
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP: begin
          // unconditionally supported
          return NORTHCAPE_NO_ERROR;
        end
        default: begin
          `uvm_fatal(COMPONENT_NAME, "Operation not known!");
        end
      endcase
    endfunction

    localparam int unsigned MAX_BYTES_PER_TRANSFER = (AXI_DATA_WIDTH / 8) * AXI5_MAX_BURST_LEN;

    function int unsigned get_number_revoke_writes();

      if (!(operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE})) begin
        `uvm_fatal(COMPONENT_NAME, "I am not a revoke transaction!");
      end

      if (valid_test == 1'b0) begin
        `uvm_info(COMPONENT_NAME, "I am invalid and expect 0 revoke writes!", UVM_DEBUG);
        return 0;
      end

      
      return northcape_cmt_parser::entry_get_phys_length(input_cmt_entry) /
          MAX_BYTES_PER_TRANSFER + (northcape_cmt_parser::entry_get_phys_length(input_cmt_entry) %
                                    MAX_BYTES_PER_TRANSFER ? 1 : 0);
    endfunction

    function int unsigned get_revocation_write_len(int unsigned transaction_num);

      if (!(operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE})) begin
        `uvm_fatal(COMPONENT_NAME, "I am not a revoke transaction!");
      end

      if (transaction_num == get_number_revoke_writes() - 1) begin
        // last transaction - might be shorter
        int unsigned bytes_last_burst = northcape_cmt_parser::entry_get_phys_length(
            input_cmt_entry
        ) % MAX_BYTES_PER_TRANSFER;
        // implicit -1 offset
        return bytes_last_burst / (AXI_DATA_WIDTH / 8) + (bytes_last_burst % (AXI_DATA_WIDTH / 8) ? 1 : 0 ) - 1;
      end
      // implicit -1 offset
      return AXI5_MAX_BURST_LEN - 1;
    endfunction

    function bit [AXI_DATA_WIDTH-1:0] get_encoded_restriction();
      unique case (restriction_type)
        NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND, NORTHCAPE_RESTRICTIONS_SET_TASK_ID: begin
          return {16'h0, device_id_restriction, task_id_restriction};
        end
        NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED: begin
          return this.device_interpreted_restriction;
        end
        NORTHCAPE_RESTRICTIONS_NONE: begin
          // random value
          // should be cleared / ignored by ops module
          return this.device_interpreted_restriction;
        end
        default: begin
          `uvm_fatal(COMPONENT_NAME, $sformatf(
                     "Unknown restriction type: %s (%d)",
                     this.restriction_type.name(),
                     this.restriction_type
                     ));
        end
      endcase
    endfunction

    function new(string name = "");
      super.new(name);
      this.cmt_base = INITIAL_CMT_BASE;
      this.cmt_size_clog2 = INITIAL_CMT_SIZE_CLOG2;
    endfunction

    function void do_copy(uvm_object rhs);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "Copy RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      cmt_base = other_transaction.cmt_base;
      cmt_size_clog2 = other_transaction.cmt_size_clog2;

      valid_test = other_transaction.valid_test;

      input_token = other_transaction.input_token;
      input_token_right = other_transaction.input_token_right;

      input_cmt_entry_right = other_transaction.input_cmt_entry_right;

      device_id_restriction = other_transaction.device_id_restriction;
      task_id_restriction = other_transaction.task_id_restriction;
      restriction_enabled = other_transaction.restriction_enabled;
      use_rcsr_interface = other_transaction.use_rcsr_interface;

      device_interpreted_restriction = other_transaction.device_interpreted_restriction;
      restriction_type = other_transaction.restriction_type;

      device_id_current = other_transaction.device_id_current;
      task_id_current = other_transaction.task_id_current;

      read_perm = other_transaction.read_perm;
      write_perm = other_transaction.write_perm;
      x_perm = other_transaction.x_perm;
      lockable_perm = other_transaction.lockable_perm;
      irq_accessible_perm = other_transaction.irq_accessible_perm;
      cacheable_tlb_perm = other_transaction.cacheable_tlb_perm;
      cacheable_access_perm = other_transaction.cacheable_access_perm;

      operation = other_transaction.operation;

      input_cmt_entry = other_transaction.input_cmt_entry;

      read_resp = other_transaction.read_resp;
      write_resp = other_transaction.write_resp;

      direction = other_transaction.direction;
      new_segment_length = other_transaction.new_segment_length;
      nonce = other_transaction.nonce;

      output_capability_id = other_transaction.output_capability_id;
      unsuccessful_lookups = other_transaction.unsuccessful_lookups;
      rng_seed = other_transaction.rng_seed;

      intended_capability_type = other_transaction.intended_capability_type;

      parent_offset = other_transaction.parent_offset;
      recursion_cmt_entries = other_transaction.recursion_cmt_entries;
      number_indirect_caps = other_transaction.number_indirect_caps;

      capability_tokens = other_transaction.capability_tokens;

      drop_make_one_capability_invalid = other_transaction.drop_make_one_capability_invalid;
      drop_flip_type = other_transaction.drop_flip_type;
      drop_flip_tag = other_transaction.drop_flip_type;
      use_isr_fsm = other_transaction.use_isr_fsm;
      orphans = other_transaction.orphans;
      ref_lock_key = other_transaction.ref_lock_key;
      tpm_quote = other_transaction.tpm_quote;
      tpm_quote_size = other_transaction.tpm_quote_size;
      tpm_quote_sig_r = other_transaction.tpm_quote_sig_r;
      tpm_quote_sig_s = other_transaction.tpm_quote_sig_s;
      attest_nonce = other_transaction.attest_nonce;

    endfunction

    function string convert2string();

      return $sformatf(
          "cmt base %x, cmt size log2 %d, valid test %b, input token %x, device id restr %x task id restr %x restriction_enabled %b device id current %x task id current %x read perm %b write perm %b x perm %b lockable %b IRQ perm %b cacheable TLB %b cacheable access %b operation %s input entry %s read resp %s write resp %s direction %b new length %d nonce %x output cap id %x unsuccessful lookups %d rng seed %x parent offset %d number indirect capabilities %d intended capability type %s capability tokens %x CMT entries %s input token right %x input CMT entry right %s make capability invalid %b flip type %b flip tag %x restriction type %s device interpreted bits %x use inspect in FIFO %b lock key %x use rcsr interface %b orphans %d PCr index %d attest nonce %x AES fast %b SHA256 fast",
          cmt_base,
          cmt_size_clog2,

          valid_test,

          input_token,

          device_id_restriction,
          task_id_restriction,
          restriction_enabled,

          device_id_current,
          task_id_current,

          read_perm,
          write_perm,
          x_perm,
          lockable_perm,
          irq_accessible_perm,
          cacheable_access_perm,
          cacheable_tlb_perm,

          operation.name(),

          print_cmt_entry(
              input_cmt_entry
          ),

          read_resp.name(),
          write_resp.name(),

          direction,
          new_segment_length,
          nonce,

          output_capability_id,

          unsuccessful_lookups,

          rng_seed,
          parent_offset,
          number_indirect_caps,
          intended_capability_type.name(),
          capability_tokens,
          cmt_entry_t::format_entry_list(
              recursion_cmt_entries
          ),
          input_token_right,
          operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE} ? print_cmt_entry(
              input_cmt_entry_right
          ) : "ignored",
          drop_make_one_capability_invalid,
          drop_flip_type,
          drop_flip_tag,
          restriction_type.name(),
          device_interpreted_restriction,
          use_isr_fsm,
          ref_lock_key,
          use_rcsr_interface,
          orphans,
          0,
          attest_nonce,
          0,
          0
      );

    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "Compare RHS is null!");
      end

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      return cmt_base == other_transaction.cmt_base &&
        cmt_size_clog2 == other_transaction.cmt_size_clog2 &&

        valid_test == other_transaction.valid_test &&

        input_token == other_transaction.input_token &&
        input_token_right == other_transaction.input_token_right &&

        device_id_restriction == other_transaction.device_id_restriction &&
        task_id_restriction == other_transaction.task_id_restriction &&
        restriction_enabled == other_transaction.restriction_enabled &&
        use_rcsr_interface == other_transaction.use_rcsr_interface &&

        device_id_current == other_transaction.device_id_current &&
        task_id_current == other_transaction.task_id_current &&

        read_perm == other_transaction.read_perm &&
        write_perm == other_transaction.write_perm &&
        x_perm == other_transaction.x_perm &&
        lockable_perm == other_transaction.lockable_perm &&
        irq_accessible_perm == other_transaction.irq_accessible_perm &&
        cacheable_tlb_perm == other_transaction.cacheable_tlb_perm &&
        cacheable_access_perm == other_transaction.cacheable_access_perm &&

        operation == other_transaction.operation &&

        input_cmt_entry == other_transaction.input_cmt_entry &&
        input_cmt_entry_right == other_transaction.input_cmt_entry_right &&
        
        read_resp == other_transaction.read_resp &&
        write_resp == other_transaction.write_resp &&

        direction == other_transaction.direction &&
        new_segment_length == other_transaction.new_segment_length &&
        nonce == other_transaction.nonce &&
        output_capability_id == other_transaction.output_capability_id &&
        unsuccessful_lookups == other_transaction.unsuccessful_lookups &&
        rng_seed == other_transaction.rng_seed &&
        parent_offset == other_transaction.parent_offset &&
        recursion_cmt_entries == other_transaction.recursion_cmt_entries &&
        intended_capability_type == other_transaction.intended_capability_type &&
        capability_tokens == other_transaction.capability_tokens &&
        number_indirect_caps == other_transaction.number_indirect_caps &&
        drop_make_one_capability_invalid == other_transaction.drop_make_one_capability_invalid &&
        drop_flip_type == other_transaction.drop_flip_type &&
        drop_flip_tag == other_transaction.drop_flip_tag &&
        restriction_type == other_transaction.restriction_type &&
        device_interpreted_restriction == other_transaction.device_interpreted_restriction && 
        use_isr_fsm == other_transaction.use_isr_fsm && 
        ref_lock_key == other_transaction.ref_lock_key &&
        orphans == other_transaction.orphans;
    endfunction

  endclass

  /**
 * Predictor for the transaction that zeros the CMT out
 * This might take several requests.
 * Each instance of this class represents one.
 */
  class automatic NorthcapeCapabilityOpsTransactionCMTZero #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      // parameters for AXI LITE (slave) interface

      parameter AXI_LITE_DATA_WIDTH = -1,
      parameter AXI_LITE_ADDR_WIDTH = -1,

      parameter HASH_TYPE = -1,

      parameter bit [AXI_ADDR_WIDTH-1:0] INITIAL_CMT_BASE = -1,
      parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1
  ) extends NorthcapeCapabilityOpsTransaction #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),

      .HASH_TYPE(HASH_TYPE),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
  ) implements INorthcapeAXITransactionMasterSide#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  );
    typedef bit [AXI_ADDR_WIDTH-1:0] cmt_base_t;
    typedef int unsigned cmt_size_t;

    localparam string COMPONENT_NAME = "Northcape Capability Ops Transaction CMT Zero";

    protected axi_len_t axi_length;

    protected Axi5DelayGenerator delay_gen;

    function new(string name = "", int unsigned cmt_size_clog2 = INITIAL_CMT_SIZE_CLOG2,
                 bit is_last = 1);
      cmt_size_t cmt_size;

      super.new(name);

      cmt_size = (1 << cmt_size_clog2) * $bits(northcape_cmt_entry_t) / 8;

      if (!is_last) begin
        axi_length = AXI5_MAX_BURST_LEN - 1;
      end else begin
        axi_length = cmt_size % AXI5_MAX_BURST_LEN;
        if (axi_length == 0) begin
          axi_length = AXI5_MAX_BURST_LEN - 1;
        end
      end

      delay_gen = new;
    endfunction

    virtual function axi_test_request_type_t get_axi_request_type();
      return AXI_TEST_WRITE;
    endfunction

    virtual function axi_len_t get_test_len();
      return axi_length;
    endfunction


    virtual function bit [AXI_ID_WIDTH-1:0] get_test_id();
      return '0;
    endfunction

    virtual function bit [AXI_USER_WIDTH-1:0] get_test_user();
      return '0;
    endfunction

    // (read only) provided response
    virtual function bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] get_response_data();
      `uvm_error(COMPONENT_NAME, "Capability ops module should NOT read during CMT setup!");
    endfunction

    // (write only) type of atomic transfer
    virtual function axi5_atop_t get_atomic_type();
      return ATOMIC_NONE;
    endfunction

    // read/write response
    virtual function axi_resp_t get_given_response();
      return OKAY;
    endfunction

    // regressions: specific scenarios that failed in hardware and are unlikely to appear in random testing
    // force ready high before valid
    virtual function bit get_regression_ready_before_valid();
      return 1;
    endfunction

    // keep arvalid/awvalid after a ready, accepting a second transaction
    virtual function bit get_regression_keep_valid_high();
      return 1;
    endfunction

    virtual function bit generate_random_delay(axi_test_delay_type delay_type);
      return delay_gen.generate_random_delay(delay_type);
    endfunction

    virtual function string to_string();
      return convert2string();
    endfunction

  endclass


  /**
 * Predictor for the transaction that zeros the CMT out
 * This might take several requests.
 * Each instance of this class represents one.
 */
  class automatic NorthcapeCapabilityOpsTransactionCreateCap #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      // parameters for AXI LITE (slave) interface

      parameter AXI_LITE_DATA_WIDTH = -1,
      parameter AXI_LITE_ADDR_WIDTH = -1,

      parameter HASH_TYPE = -1,

      parameter bit [AXI_ADDR_WIDTH-1:0] INITIAL_CMT_BASE = -1,
      parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1
  ) extends NorthcapeCapabilityOpsTransaction #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),

      .HASH_TYPE(HASH_TYPE),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
  ) implements INorthcapeAXITransactionMasterSide#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  );
    typedef bit [AXI_ADDR_WIDTH-1:0] cmt_base_t;
    typedef int unsigned cmt_size_t;

    typedef NorthcapeCapabilityOpsGenerator#(
        .HASH_TYPE(HASH_TYPE),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) gen_t;

    localparam string COMPONENT_NAME = "Northcape Capability Ops Transaction Create Capability";

    protected axi_size_t axi_size;

    protected Axi5DelayGenerator delay_gen;

    protected northcape_cmt_entry_t capability_entry;
    protected capability_id_t capability_id;

    function new(string name = "");

      super.new(name);

      delay_gen = new;
    endfunction

    virtual function axi_test_request_type_t get_axi_request_type();
      return AXI_TEST_WRITE;
    endfunction

    // for performance reason, we assume this is possible in 1 cycle
    virtual function axi_len_t get_test_len();
      return 0;
    endfunction

    virtual function bit [AXI_ID_WIDTH-1:0] get_test_id();
      return '0;
    endfunction

    virtual function bit [AXI_USER_WIDTH-1:0] get_test_user();
      return '0;
    endfunction
    // (read only) provided response
    virtual function bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] get_response_data();
      `uvm_fatal(COMPONENT_NAME, "Capability ops module should NOT read during CMT setup!");
    endfunction

    // (write only) type of atomic transfer
    virtual function axi5_atop_t get_atomic_type();
      return ATOMIC_NONE;
    endfunction

    // read/write response
    virtual function axi_resp_t get_given_response();
      return OKAY;
    endfunction

    // regressions: specific scenarios that failed in hardware and are unlikely to appear in random testing
    // force ready high before valid
    virtual function bit get_regression_ready_before_valid();
      return 1;
    endfunction

    // keep arvalid/awvalid after a ready, accepting a second transaction
    virtual function bit get_regression_keep_valid_high();
      return 1;
    endfunction

    virtual function bit generate_random_delay(axi_test_delay_type delay_type);
      return delay_gen.generate_random_delay(delay_type);
    endfunction

    virtual function string to_string();
      return convert2string();
    endfunction

  endclass


  /**
 * Predictor for the transaction that reads the input CMT entry or recurses for the underlying direct capability.
 */
  class automatic NorthcapeCapabilityOpsTransactionCMTReadInput #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      // parameters for AXI LITE (slave) interface

      parameter AXI_LITE_DATA_WIDTH = -1,
      parameter AXI_LITE_ADDR_WIDTH = -1,

      parameter HASH_TYPE = -1,

      parameter bit [AXI_ADDR_WIDTH-1:0] INITIAL_CMT_BASE = -1,
      parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1
  ) extends NorthcapeCapabilityOpsTransaction #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),

      .HASH_TYPE(HASH_TYPE),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
  ) implements INorthcapeAXITransactionMasterSide#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  );
    typedef bit [AXI_ADDR_WIDTH-1:0] cmt_base_t;
    typedef int unsigned cmt_size_t;

    typedef NorthcapeCapabilityOpsGenerator#(
        .HASH_TYPE(HASH_TYPE),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) gen_t;

    localparam string COMPONENT_NAME = "Northcape Capability Ops Transaction Create Capability";

    protected axi_size_t axi_size;

    protected Axi5DelayGenerator delay_gen;

    protected northcape_cmt_entry_t capability_entry;
    protected capability_id_t capability_id;

    int unsigned resolution_call_number;

    bit is_right_input;

    function new(string name = "", int unsigned resolution_call_number = 0, bit is_right_input = 0);

      super.new(name);

      delay_gen = new;

      this.resolution_call_number = resolution_call_number;
      this.is_right_input = is_right_input;
    endfunction

    virtual function axi_test_request_type_t get_axi_request_type();
      return AXI_TEST_READ;
    endfunction

    // for performance reason, we assume this is possible in 1 cycle
    virtual function axi_len_t get_test_len();
      return 0;
    endfunction

    virtual function bit [AXI_ID_WIDTH-1:0] get_test_id();
      return '0;
    endfunction

    virtual function bit [AXI_USER_WIDTH-1:0] get_test_user();
      return '0;
    endfunction
    // (read only) provided response
    virtual function bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] get_response_data();
      bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] resp;
      resp = '0;
      if (resolution_call_number == 0) begin
        if (is_right_input) begin
          // special: second CMT entry
          // used for merge op
          resp[0] = input_cmt_entry_right;
          `uvm_info(COMPONENT_NAME, $sformatf(
                    "Returning right input entry %s", print_cmt_entry(input_cmt_entry_right)),
                    UVM_DEBUG);
        end else begin
          // special: input CMT entry generated by us
          `uvm_info(COMPONENT_NAME, $sformatf(
                    "Returning left input entry %s", print_cmt_entry(input_cmt_entry)), UVM_DEBUG);
          resp[0] = input_cmt_entry;
        end
      end else begin
        resp[0] = recursion_cmt_entries[resolution_call_number-1].get_entry();
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Returning indirect entry %s",
                  print_cmt_entry(
                      recursion_cmt_entries[resolution_call_number-1].get_entry()
                  )
                  ), UVM_DEBUG);
      end

      return resp;
    endfunction

    // (write only) type of atomic transfer
    virtual function axi5_atop_t get_atomic_type();
      return ATOMIC_NONE;
    endfunction

    // read/write response
    virtual function axi_resp_t get_given_response();
      return read_resp;
    endfunction

    // regressions: specific scenarios that failed in hardware and are unlikely to appear in random testing
    // force ready high before valid
    virtual function bit get_regression_ready_before_valid();
      return 1;
    endfunction

    // keep arvalid/awvalid after a ready, accepting a second transaction
    virtual function bit get_regression_keep_valid_high();
      return 1;
    endfunction

    virtual function bit generate_random_delay(axi_test_delay_type delay_type);
      return delay_gen.generate_random_delay(delay_type);
    endfunction

    virtual function string to_string();
      return convert2string();
    endfunction

  endclass


  /**
 * Predictor for the transaction that writes the output CMT entry.
 */
  class automatic NorthcapeCapabilityOpsTransactionCMTWriteOutput #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      // parameters for AXI LITE (slave) interface

      parameter AXI_LITE_DATA_WIDTH = -1,
      parameter AXI_LITE_ADDR_WIDTH = -1,

      parameter HASH_TYPE = -1,

      parameter bit [AXI_ADDR_WIDTH-1:0] INITIAL_CMT_BASE = -1,
      parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1
  ) extends NorthcapeCapabilityOpsTransaction #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),

      .HASH_TYPE(HASH_TYPE),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
  ) implements INorthcapeAXITransactionMasterSide#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  );
    typedef bit [AXI_ADDR_WIDTH-1:0] cmt_base_t;
    typedef int unsigned cmt_size_t;

    typedef NorthcapeCapabilityOpsGenerator#(
        .HASH_TYPE(HASH_TYPE),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) gen_t;

    localparam string COMPONENT_NAME = "Northcape Capability Ops Transaction Create Capability";

    protected axi_size_t axi_size;

    protected Axi5DelayGenerator delay_gen;

    protected northcape_cmt_entry_t capability_entry;
    protected capability_id_t capability_id;

    function new(string name = "");

      super.new(name);

      delay_gen = new;
    endfunction

    virtual function axi_test_request_type_t get_axi_request_type();
      return AXI_TEST_WRITE;
    endfunction

    // for performance reason, we assume this is possible in 1 cycle
    virtual function axi_len_t get_test_len();
      return 0;
    endfunction

    virtual function bit [AXI_ID_WIDTH-1:0] get_test_id();
      return '0;
    endfunction

    virtual function bit [AXI_USER_WIDTH-1:0] get_test_user();
      return '0;
    endfunction
    // (read only) provided response
    virtual function bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] get_response_data();
      return '0;
    endfunction

    // (write only) type of atomic transfer
    virtual function axi5_atop_t get_atomic_type();
      return ATOMIC_NONE;
    endfunction

    // read/write response
    virtual function axi_resp_t get_given_response();
      return write_resp;
    endfunction

    // regressions: specific scenarios that failed in hardware and are unlikely to appear in random testing
    // force ready high before valid
    virtual function bit get_regression_ready_before_valid();
      return 1;
    endfunction

    // keep arvalid/awvalid after a ready, accepting a second transaction
    virtual function bit get_regression_keep_valid_high();
      return 1;
    endfunction

    virtual function bit generate_random_delay(axi_test_delay_type delay_type);
      return delay_gen.generate_random_delay(delay_type);
    endfunction

    virtual function string to_string();
      return convert2string();
    endfunction

  endclass


  /**
 * Predictor for the RNG outputs used DURING a transaction.
 */
  class automatic NorthcapeCapabilityOpsTransactionRNG #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      // parameters for AXI LITE (slave) interface

      parameter AXI_LITE_DATA_WIDTH = -1,
      parameter AXI_LITE_ADDR_WIDTH = -1,

      parameter HASH_TYPE = -1,

      parameter bit [AXI_ADDR_WIDTH-1:0] INITIAL_CMT_BASE = -1,
      parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1
  ) extends NorthcapeCapabilityOpsTransaction #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),

      .HASH_TYPE(HASH_TYPE),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
  ) implements IRNGSeedTransaction;


    function new(string name = "");
      super.new(name);
    endfunction

    virtual function int get_rng_seed();
      return rng_seed;
    endfunction
    virtual function int get_number_expected_rng_invocations();
      // TODO
      return 0;
    endfunction
  endclass

  /**
 * Predictor for the RNG outputs for initial reset
 */
  class automatic NorthcapeCapabilityOpsTransactionRNGInitial #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      // parameters for AXI LITE (slave) interface

      parameter AXI_LITE_DATA_WIDTH = -1,
      parameter AXI_LITE_ADDR_WIDTH = -1,

      parameter HASH_TYPE = -1,

      parameter bit [AXI_ADDR_WIDTH-1:0] INITIAL_CMT_BASE = -1,
      parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1
  ) extends NorthcapeCapabilityOpsTransactionRNG #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),

      .HASH_TYPE(HASH_TYPE),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
  );

    rand int initial_seed;

    function new(string name = "");
      super.new(name);
    endfunction

    virtual function int get_rng_seed();
      return initial_seed;
    endfunction
    virtual function int get_number_expected_rng_invocations();
      // qarma key = 128 bit
      return 2;
    endfunction
  endclass

  /**
 * Predictor for the transaction that reads the input CMT entry or recurses for the underlying direct capability.
 */
  class automatic NorthcapeCapabilityOpsTransactionRevoke #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      // parameters for AXI LITE (slave) interface

      parameter AXI_LITE_DATA_WIDTH = -1,
      parameter AXI_LITE_ADDR_WIDTH = -1,

      parameter HASH_TYPE = -1,

      parameter bit [AXI_ADDR_WIDTH-1:0] INITIAL_CMT_BASE = -1,
      parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1
  ) extends NorthcapeCapabilityOpsTransaction #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),

      .HASH_TYPE(HASH_TYPE),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
  ) implements INorthcapeAXITransactionMasterSide#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  );
    typedef bit [AXI_ADDR_WIDTH-1:0] cmt_base_t;
    typedef int unsigned cmt_size_t;


    localparam string COMPONENT_NAME = "Northcape Capability Ops Transaction Revoke";

    protected Axi5DelayGenerator delay_gen;

    protected int unsigned transaction_num;

    function new(string name = "", int unsigned transaction_num);

      super.new(name);

      delay_gen = new;

      this.transaction_num = transaction_num;
    endfunction

    virtual function axi_test_request_type_t get_axi_request_type();
      return AXI_TEST_WRITE;
    endfunction

    // for performance reason, we assume this is possible in 1 cycle
    virtual function axi_len_t get_test_len();
      return get_revocation_write_len(transaction_num);
    endfunction

    virtual function bit [AXI_ID_WIDTH-1:0] get_test_id();
      return '0;
    endfunction

    virtual function bit [AXI_USER_WIDTH-1:0] get_test_user();
      return '0;
    endfunction
    // (read only) provided response
    virtual function bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] get_response_data();
      return '0;
    endfunction

    // (write only) type of atomic transfer
    virtual function axi5_atop_t get_atomic_type();
      return ATOMIC_NONE;
    endfunction

    // read/write response
    virtual function axi_resp_t get_given_response();
      // should never fail
      // in case it does, the capability points outside of the physical address space
      // revocation is pointless then
      return OKAY;
    endfunction

    // regressions: specific scenarios that failed in hardware and are unlikely to appear in random testing
    // force ready high before valid
    virtual function bit get_regression_ready_before_valid();
      return 1;
    endfunction

    // keep arvalid/awvalid after a ready, accepting a second transaction
    virtual function bit get_regression_keep_valid_high();
      return 1;
    endfunction

    virtual function bit generate_random_delay(axi_test_delay_type delay_type);
      return delay_gen.generate_random_delay(delay_type);
    endfunction

    virtual function string to_string();
      return convert2string();
    endfunction

  endclass

endpackage
