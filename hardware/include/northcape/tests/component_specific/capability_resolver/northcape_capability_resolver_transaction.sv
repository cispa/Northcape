/**
  * Test class that holds all state for a Capability Resolver Test.
  */
package northcape_capability_resolver_transaction;



  import axi5::*;
  import northcape_types::*;
  import northcape_test::*;
  import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
  import northcape_capability_resolver_common::NorthcapeCapabilityResolverHash;
  import uvm_pkg::*;

  `include "uvm_macros.svh"

  /**
      * Basic control-flow-relevant types of test. Details such as exact capability type and parameters (e.g., restrictions) generated at random.
      */
  typedef enum {
    // preseented a capability token that directly resolves to the Root capability - no recursion, 0-fixed ID and tag, 32 bit offset
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_ROOT_CAPABILITY,
    // presented a capability token that directly resolves to a direct capability - no recursion, need to parse tag and id
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_DIRECT_CAPABILITY,
    // presented a capability token that resolves to an indirect capability - recursion needed
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_INDIRECT_CAPABILITY,
    // presented a capability token that resolves to an invalid entry
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_INVALID_ENTRY,
    // looked up a locked capability, successfully
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_OK,
    /*
     * Three test cases for multi-locking:
     * - child of lock-holder token presented (indirect non-lockholder)
     * - lock-holder presented, in tree with other lock-holder
     * - child of lock-hoder, one more lock-holder in the tree
     */
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_CHILD,
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE,
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE_CHILD,
    // looked up a locked capability that is owned by someone else
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_FAIL,
    // got a bus error when resolving the capability
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_BUS_ERROR,
    // unsupported permission type requested
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_VALIDATION_ERROR,
    // refuses any access irregardless of settings
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_REVOCATION_CAPABILITY,
    // bounds of the parent have shrunk and now the capability is OOB
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_FRONT,
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_BACK,
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_FRONT,
    NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_BACK
  } northcape_capability_resolver_transaction_type_t;

  localparam MAX_INDIRECT_CAPABILITIES = 5;

  class automatic NorthcapeCapabilityResolverTransactionCMTEntry #(
      parameter AXI_ADDR_WIDTH = -1,
      parameter HASH_TYPE = -1
  ) extends uvm_sequence_item;

    `uvm_object_param_utils(
        NorthcapeCapabilityResolverTransactionCMTEntry#(AXI_ADDR_WIDTH, HASH_TYPE));

    localparam COMPONENT_NAME = "Northcape Capability Resolver Transaction CMT Entry";

    typedef NorthcapeCapabilityResolverTransactionCMTEntry#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .HASH_TYPE(HASH_TYPE)
    ) my_type_t;

    northcape_cmt_entry_type_t entry_type;
    bit is_root_capability;
    northcape_cmt_entry_t parent;
    northcape_cmt_entry_type_t parent_capability_type;
    bit [AXI_ADDR_WIDTH - 1 : 0] parent_token;

    capability_id_t token_id;

    function bit [63:0] get_parent_segment_length();
      unique case (parent_capability_type)
        NORTHCAPE_CMT_DIRECT: return 64'(parent.location.physical_location.length);
        NORTHCAPE_CMT_INDIRECT: return 64'(parent.location.indirect_location.length);
        // lock holder has no length information
        NORTHCAPE_CMT_LOCK_HOLDER: return '0;
        default: return '0;
      endcase
    endfunction

    function segment_length_t get_parent_segment_base();
      unique case (parent_capability_type)
        NORTHCAPE_CMT_DIRECT: return parent.location.physical_location.base;
        NORTHCAPE_CMT_INDIRECT: return parent.location.indirect_location.effective_base;
        // lock holder has no base information
        NORTHCAPE_CMT_LOCK_HOLDER: return '0;
        default: return '1;
      endcase
    endfunction

    capability_off_t token_offset_provided;
    segment_length_t access_len_provided;

    // --- Randomized CMT entry metadata begin ---

    rand bit [AXI_ADDR_WIDTH - 1 : 0] parent_randomized;

    // random tag for failing test
    rand northcape_mac_tag_t mac_tag_randomized;
    // tag from the token for passing test
    northcape_mac_tag_t mac_tag_provided;

    // random nonce, pretend this is included in the tag
    rand northcape_nonce_t nonce;

    // random physical address, esp. for direct capability
    rand northcape_physical_address_t physical_address_randomized;

    // offset from parent segment start and length of this segment
    // must be smaller than the parent segment length
    rand northcape_segment_length_t segment_length;
    rand northcape_segment_length_t parent_offset;

    // lock key associated with the top-level lock-holder capability (if such a capability exists)
    northcape_lock_key_t lock_key_provided;

    // page file number for paged-out capability
    rand northcape_page_number_t pagefile_number;

    // random permissions for test
    rand northcape_direct_capability_permissions_t randomized_permissions_direct;
    rand northcape_indirect_capability_permissions_t randomized_permissions_indirect;

    // requested access type
    axis_validate_request_perm_t request_type_provided;

    // reference count not used by the resolver module
    rand northcape_reference_count_t refcount_randomized;


    northcape_restriction_type_t restriction_type;

    // raw data for different types of restrictions
    rand device_id_t device_id_randomized;
    task_id_t task_id_randomized;
    rand bit [63:0] restrictions_device_specific;

    // in case restriction type is NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND, the device ID and task ID need to match
    device_id_t device_id_provided;
    task_id_t task_id_provided;

    // --- Randomized CMT entry metadata end ---

    // base address of the capability metadata table in system memory
    bit [AXI_ADDR_WIDTH-1:0] cmt_base;

    // if 1, the resolver needs to accept the capability for the token presented.
    bit valid_test;

    constraint capability_segment_not_bigger_than_parent {
      if (valid_test) {
        if(parent_capability_type == NORTHCAPE_CMT_DIRECT || parent_capability_type == NORTHCAPE_CMT_INDIRECT){
          // we are an indirect capability - our own restrictions cannot make the access impossible
          // have not moved the segment outside of the parent
          // have to force this to a larger type to prevent overflow
          64'(parent_offset) + 64'(segment_length) <= get_parent_segment_length();
          // have enough space to satisfy the access
          64'(token_offset_provided) + 64'(access_len_provided) <= 64'(segment_length);
        } else
        if (parent_capability_type == NORTHCAPE_CMT_INVALID) {
          // we are a direct capability - segment needs to be large enough to satisfy the access
          64'(token_offset_provided) + 64'(access_len_provided) <= 64'(segment_length);
          // to prevent overflow
          64'(physical_address_randomized) + 64'(segment_length) < 64'h100000000;
        }
        // other types of parent do not lead to successful test
      }
    }

    function new(string name = "");

      super.new(name);
    endfunction

    function void set_attributes(
        northcape_cmt_entry_type_t entry_type, bit [AXI_ADDR_WIDTH-1:0] cmt_base, bit valid_test,
        bit is_root_capability, device_id_t device_id, task_id_t task_id, capability_id_t token_id,
        northcape_mac_tag_t token_tag, capability_off_t token_offset, segment_length_t access_len,
        // might be invalid; in this case, WE are the root/direct capability
        northcape_cmt_entry_t parent, northcape_lock_key_t lock_key,
        axis_validate_request_perm_t request_type, bit [AXI_ADDR_WIDTH - 1 : 0] parent_token,
        northcape_restriction_type_t restriction_type);
      this.entry_type = entry_type;
      this.cmt_base = cmt_base;

      this.valid_test = valid_test;
      this.device_id_provided = device_id;
      this.task_id_provided = task_id;

      this.mac_tag_provided = token_tag;
      this.parent = parent;

      this.parent_capability_type = parent.capability_type;

      this.lock_key_provided = lock_key;
      this.request_type_provided = request_type;

      this.is_root_capability = is_root_capability;

      this.token_offset_provided = token_offset;
      this.access_len_provided = access_len;

      this.parent_token = parent_token;
      this.token_id = token_id;
      this.restriction_type = restriction_type;
    endfunction

    function northcape_cmt_entry_t get_entry();
      northcape_cmt_entry_t ret;

      ret.capability_type = entry_type;

      if (valid_test) begin

        if (is_root_capability) begin
          // root capability has a number of well-known default values that we need to overwrite the randomly generated values with
          nonce = NORTHCAPE_ROOT_CAPABILITY_NONCE;
          restriction_type = NORTHCAPE_ROOT_CAPABILITY_RESTRICTION_TYPE;
          physical_address_randomized = NORTHCAPE_ROOT_CAPABILITY_RESTRICTION_BASE;
          segment_length = NORTHCAPE_ROOT_CAPABILITY_LENGTH;
          // root capability can be locked
          // in this case, resolver refuses
          this.lock_key_provided = '0;
        end

        // need to generate an entry that matches the request precisely
        unique case (entry_type)
          NORTHCAPE_CMT_DIRECT: begin
            ret.location.physical_location.base = physical_address_randomized;
            ret.location.physical_location.length = segment_length;
            ret.location.physical_location.locked_key = this.lock_key_provided;

            `uvm_info(COMPONENT_NAME, $sformatf(
                      "Used lock key %x for direct capability CMT entry generated!",
                      this.lock_key_provided
                      ), UVM_DEBUG);

            ret.permissions.direct_capability_permissions = randomized_permissions_direct;
          end
          NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_REVOCATION: begin
            ret.location.indirect_location.effective_base = get_parent_segment_base() + parent_offset;
            `uvm_info(COMPONENT_NAME, $sformatf(
                      "Computed effective base %x based on parent base %x offset %x",
                      ret.location.indirect_location.effective_base,
                      get_parent_segment_base(),
                      parent_offset
                      ), UVM_DEBUG);
            ret.location.indirect_location.parent = parent_token;
            ret.location.indirect_location.length = this.segment_length;

            ret.permissions.indirect_capability_permissions = randomized_permissions_indirect;
          end
          NORTHCAPE_CMT_LOCK_HOLDER: begin
            ret.location.lock_holder_location.parent = parent_token;
            ret.location.lock_holder_location.lock_key = this.lock_key_provided;

            ret.permissions.indirect_capability_permissions = randomized_permissions_indirect;
          end
          NORTHCAPE_CMT_INVALID: begin
            `uvm_warning(COMPONENT_NAME, "Requested valid test with invalid capability!");
          end
          NORTHCAPE_CMT_PAGED_OUT: begin
            `uvm_warning(COMPONENT_NAME, "Requested valid test with paged-out capability!");
          end
          default: begin
            `uvm_error(COMPONENT_NAME, $sformatf(
                       "Requested valid test with invalid capability type %s!", entry_type.name()));
          end
        endcase

        ret.refcount = refcount_randomized;

        unique case (restriction_type)
          NORTHCAPE_RESTRICTIONS_NONE: begin
            ret.restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
          end
          NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED: begin
            ret.restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED;
            ret.restrictions.body.device_interpreted_bits = restrictions_device_specific;
          end
          NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND: begin
            ret.restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND;
            ret.restrictions.body.task_restriction.task_id = task_id_provided;
            ret.restrictions.body.task_restriction.device_id = device_id_provided;
          end
          NORTHCAPE_RESTRICTIONS_SET_TASK_ID: begin
            ret.restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_SET_TASK_ID;
            if (request_type_provided inside {READ, READ_IRQ, WRITE, WRITE_IRQ, READ_WRITE, READ_WRITE_IRQ}) begin
              // can only read when I have the same task Id 
              ret.restrictions.body.task_restriction.task_id   = task_id_provided;
              ret.restrictions.body.task_restriction.device_id = device_id_provided;
            end
            else if (request_type_provided inside {EXECUTE, EXECUTE_IRQ, ACCESS_NONE, ACCESS_DERIVE_RECURSION, PERM_RESERVED})
            begin
              // for execute, I can change my task/device ID to anything I like!
              ret.restrictions.body.task_restriction.task_id   = task_id_randomized;
              ret.restrictions.body.task_restriction.device_id = device_id_randomized;
            end else begin
              `uvm_fatal(COMPONENT_NAME, $sformatf(
                         "Unknown access type: %x (%s)",
                         request_type_provided,
                         request_type_provided.name()
                         ));
            end
          end
          default: begin
            `uvm_error(COMPONENT_NAME, $sformatf("Unknown restriction type: %d", restriction_type));
            $fatal(1);
          end
        endcase

        case (request_type_provided)
          PERM_RESERVED, ACCESS_NONE, ACCESS_DERIVE_RECURSION: begin
            // no permissions requested, nothing to do
          end
          READ: begin
            `uvm_info(COMPONENT_NAME, $sformatf(
                      "Setting read permission for access type %x!", request_type_provided),
                      UVM_DEBUG);
            ret.permissions.indirect_capability_permissions.read_permission = 1;
          end
          READ_IRQ: begin
            `uvm_info(COMPONENT_NAME, $sformatf(
                      "Setting read_irq permission for access type %x!", request_type_provided),
                      UVM_DEBUG);
            ret.permissions.indirect_capability_permissions.read_permission = 1;
            ret.permissions.indirect_capability_permissions.irq_accessible_permission = 1;
          end
          WRITE: begin
            `uvm_info(COMPONENT_NAME, "Setting write permission", UVM_DEBUG);
            ret.permissions.indirect_capability_permissions.write_permission = 1;
          end
          WRITE_IRQ: begin
            `uvm_info(COMPONENT_NAME, "Setting write_irq permission", UVM_DEBUG);
            ret.permissions.indirect_capability_permissions.write_permission = 1;
            ret.permissions.indirect_capability_permissions.irq_accessible_permission = 1;
          end
          READ_WRITE: begin
            ret.permissions.indirect_capability_permissions.read_permission  = 1;
            ret.permissions.indirect_capability_permissions.write_permission = 1;
          end
          READ_WRITE_IRQ: begin
            ret.permissions.indirect_capability_permissions.read_permission = 1;
            ret.permissions.indirect_capability_permissions.write_permission = 1;
            ret.permissions.indirect_capability_permissions.irq_accessible_permission = 1;
          end
          EXECUTE: ret.permissions.indirect_capability_permissions.execute_permission = 1;
          EXECUTE_IRQ: begin
            ret.permissions.indirect_capability_permissions.execute_permission = 1;
            ret.permissions.indirect_capability_permissions.irq_accessible_permission = 1;
          end
          default: begin
            `uvm_error(COMPONENT_NAME, $sformatf(
                       "Invalid request type indicated: %x", request_type_provided));
          end
        endcase

        ret.tag   = mac_tag_provided;
        ret.nonce = nonce;
      end else begin
        // everything is randomized - virtually guaranteed to fail *somewhere* during parsing
        unique case (entry_type)
          NORTHCAPE_CMT_DIRECT: begin
            ret.location.physical_location.base = physical_address_randomized;
            ret.location.physical_location.length = segment_length;
            ret.location.physical_location.locked_key = lock_key_provided;

            ret.permissions.direct_capability_permissions = randomized_permissions_direct;
          end
          NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_REVOCATION: begin
            ret.location.indirect_location.effective_base = physical_address_randomized;
            ret.location.indirect_location.parent = parent_randomized;
            ret.location.indirect_location.length = this.segment_length;

            ret.permissions.indirect_capability_permissions = randomized_permissions_indirect;
          end
          NORTHCAPE_CMT_LOCK_HOLDER: begin
            ret.location.lock_holder_location.parent = parent_randomized;
            ret.location.lock_holder_location.lock_key = this.lock_key_provided;

            ret.permissions.indirect_capability_permissions = randomized_permissions_indirect;
          end
          NORTHCAPE_CMT_PAGED_OUT: begin
            ret.location.pagefile_location.pagefile_number = pagefile_number;
            ret.location.pagefile_location.length = segment_length;
          end
          default: begin
            // nothing to do - the invalid type alone should fault it
          end
        endcase

        ret.refcount = refcount_randomized;

        unique case (restriction_type)
          NORTHCAPE_RESTRICTIONS_NONE:
          ret.restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
          NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED: begin
            ret.restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED;
            ret.restrictions.body.device_interpreted_bits = restrictions_device_specific;
          end
          NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND, NORTHCAPE_RESTRICTIONS_SET_TASK_ID: begin
            ret.restrictions.restriction_type = restriction_type;
            ret.restrictions.body.task_restriction.task_id = task_id_randomized;
            ret.restrictions.body.task_restriction.device_id = device_id_randomized;
          end
          default: begin
            `uvm_error(COMPONENT_NAME, "Invalid restriction type!");
          end
        endcase

        // randomized permissions should suffice

        ret.tag   = mac_tag_provided;
        ret.nonce = nonce;
      end

      return ret;
    endfunction

    function bit [AXI_ADDR_WIDTH - 1 : 0] get_entry_addr(int table_size_clog_2);
      capability_id_t hash;
      hash = NorthcapeCapabilityResolverHash#(.HASH_TYPE(HASH_TYPE))::compute_hash(
          token_id, table_size_clog_2);
      `uvm_info(COMPONENT_NAME, $sformatf(
                "Getting entry addr based on cmt base %x table size %d hash %d",
                cmt_base,
                table_size_clog_2,
                hash
                ), UVM_DEBUG);
      return cmt_base + hash * $bits(northcape_cmt_entry_t) / 8;
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

      entry_type = other_transaction.entry_type;
      is_root_capability = other_transaction.is_root_capability;
      parent = other_transaction.parent;
      parent_capability_type = other_transaction.parent_capability_type;
      parent_token = other_transaction.parent_token;
      token_id = other_transaction.token_id;

      token_offset_provided = other_transaction.token_offset_provided;
      access_len_provided = other_transaction.access_len_provided;
      parent_randomized = other_transaction.parent_randomized;

      mac_tag_randomized = other_transaction.mac_tag_randomized;
      mac_tag_provided = other_transaction.mac_tag_provided;

      nonce = other_transaction.nonce;

      physical_address_randomized = other_transaction.physical_address_randomized;
      segment_length = other_transaction.segment_length;
      parent_offset = other_transaction.parent_offset;

      lock_key_provided = other_transaction.lock_key_provided;

      pagefile_number = other_transaction.pagefile_number;

      randomized_permissions_direct = other_transaction.randomized_permissions_direct;
      randomized_permissions_indirect = other_transaction.randomized_permissions_indirect;

      request_type_provided = other_transaction.request_type_provided;
      refcount_randomized = other_transaction.refcount_randomized;

      restriction_type = other_transaction.restriction_type;

      device_id_randomized = other_transaction.device_id_randomized;
      task_id_randomized = other_transaction.task_id_randomized;

      restrictions_device_specific = other_transaction.restrictions_device_specific;

      device_id_provided = other_transaction.device_id_provided;
      task_id_provided = other_transaction.task_id_provided;

      cmt_base = other_transaction.cmt_base;

      valid_test = other_transaction.valid_test;



    endfunction

    function string convert2string();
      return $sformatf(
          {
            "Entry type %s is root? %b parent %s parent_capability_type %s parent_token %x token id %x token offset provided %x access_len_provided %d parent_randomized %x mac_tag_randomized %x",
            "mac tag provided %x nonce %x physical address randomized %x segment length %d parent offset %x lock key provided %x pagefile number %d randomized permissions direct %b randomized permissions indirect %b",
            "request type provided %s refcount randomized %d restriction type %s device id %d task id %d restrictions device specific %x device id provided %d task id provided %d cmt base %x valid test %b"
          },
          entry_type.name(),
          is_root_capability,
          print_cmt_entry(
              parent
          ),
          parent_capability_type.name(),
          parent_token,
          token_id,
          token_offset_provided,
          access_len_provided,
          parent_randomized,
          mac_tag_randomized,
          mac_tag_provided,
          nonce,
          physical_address_randomized,
          segment_length,
          parent_offset,
          lock_key_provided,
          pagefile_number,
          randomized_permissions_direct,
          randomized_permissions_indirect,
          request_type_provided.name(),
          refcount_randomized,
          restriction_type.name(),
          device_id_randomized,
          task_id_randomized,
          restrictions_device_specific,
          device_id_provided,
          task_id_provided,
          cmt_base,
          valid_test
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

      return entry_type == other_transaction.entry_type &&
            is_root_capability == other_transaction.is_root_capability &&
            parent == other_transaction.parent &&
            parent_capability_type == other_transaction.parent_capability_type &&
            parent_token == other_transaction.parent_token &&
            token_id == other_transaction.token_id &&

            token_offset_provided == other_transaction.token_offset_provided &&
            access_len_provided == other_transaction.access_len_provided &&
            parent_randomized == other_transaction.parent_randomized &&

            mac_tag_randomized == other_transaction.mac_tag_randomized &&
            mac_tag_provided == other_transaction.mac_tag_provided &&
            
            nonce == other_transaction.nonce &&

            physical_address_randomized == other_transaction.physical_address_randomized &&
            segment_length == other_transaction.segment_length &&
            parent_offset == other_transaction.parent_offset &&
            
            lock_key_provided == other_transaction.lock_key_provided &&

            pagefile_number == other_transaction.pagefile_number &&

            randomized_permissions_direct == other_transaction.randomized_permissions_direct &&
            randomized_permissions_indirect == other_transaction.randomized_permissions_indirect &&

            request_type_provided == other_transaction.request_type_provided &&
            refcount_randomized == other_transaction.refcount_randomized &&

            restriction_type == other_transaction.restriction_type &&

            device_id_randomized == other_transaction.device_id_randomized &&
            task_id_randomized == other_transaction.task_id_randomized &&

            restrictions_device_specific == other_transaction.restrictions_device_specific &&

            device_id_provided == other_transaction.device_id_provided &&
            task_id_provided == other_transaction.task_id_provided &&

            cmt_base == other_transaction.cmt_base &&

            valid_test == other_transaction.valid_test;
    endfunction

    typedef my_type_t my_type_list[$];
    typedef capability_accessors#(AXI_ADDR_WIDTH) capability_accessors_t;

    static function my_type_list generate_test_entries(
        input northcape_capability_resolver_transaction_type_t test_type,
        axis_validate_request_perm_t access_type, axi_size_t access_size, axi_len_t access_len,
        ref bit [63 : 0] capability_tokens[MAX_INDIRECT_CAPABILITIES+1],
        input bit [AXI_ADDR_WIDTH-1:0] cmt_base_addr, device_id_t request_device_id,
        task_id_t request_task_id, northcape_lock_key_t lock_key, int unsigned number_indirect_caps,
        northcape_restriction_type_t restriction_type);
      segment_length_t resolved_access_len;
      northcape_cmt_entry_t dummy_parent;
      my_type_list entries;

      // TODO this does not work as a constraint
      if (test_type == NORTHCAPE_CAPABILITY_RESOLVER_TEST_VALIDATION_ERROR) begin
        access_type = PERM_RESERVED;
      end

      dummy_parent.capability_type = NORTHCAPE_CMT_INVALID;


      resolved_access_len = (1 << access_size) * (access_len + 1);

      unique case (test_type)
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_ROOT_CAPABILITY: begin
          my_type_t entry;
          bit [AXI_ADDR_WIDTH-1:0] parent_token;
          capability_off_t original_offset;

          original_offset = capability_accessors_t::capability_get_offset(capability_tokens[0]);

          // special encoding for backward compatibility
          for (int i = 0; i < MAX_INDIRECT_CAPABILITIES + 1; i++) begin
            capability_tokens[i] = '0;
          end

          if (!capability_accessors_t::capability_set_offset(
                  capability_tokens[0], original_offset
              )) begin
            `uvm_fatal_context(COMPONENT_NAME, "Error: Could not set root capability offset!",
                               uvm_root::get());

          end

          parent_token = '0;


          entry = new("CMT entry");
          entry.set_attributes(
              .entry_type(NORTHCAPE_CMT_DIRECT), .cmt_base(cmt_base_addr), .valid_test(1),
              .is_root_capability(1), .device_id(request_device_id), .task_id(request_task_id),
              .token_id(capability_accessors_t::capability_get_id(capability_tokens[0])),
              .token_tag(capability_accessors_t::capability_get_tag(capability_tokens[0])),
              .token_offset(capability_accessors_t::capability_get_offset(capability_tokens[0])),
              .access_len(resolved_access_len), .parent(dummy_parent), .lock_key(lock_key),
              .request_type(access_type), .parent_token(parent_token),
              .restriction_type(restriction_type));

          // populate all of the non-default structures
          if (entry.randomize() != 1) begin
            `uvm_fatal_context(COMPONENT_NAME, $sformatf("Could not randomize direct entry!"),
                               uvm_root::get());
          end

          entries.push_back(entry);
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_VALIDATION_ERROR,NORTHCAPE_CAPABILITY_RESOLVER_TEST_BUS_ERROR,NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_DIRECT_CAPABILITY: begin
          my_type_t entry;
          bit [AXI_ADDR_WIDTH-1:0] parent_token;

          parent_token = '0;

          entry = new("CMT entry");
          entry.set_attributes(.entry_type(NORTHCAPE_CMT_DIRECT), .cmt_base(cmt_base_addr),
                               .valid_test(test_type == NORTHCAPE_CAPABILITY_RESOLVER_TEST_VALIDATION_ERROR ? 1'b0 : 1'b1),
                               .is_root_capability(0), .device_id(request_device_id),
                               .task_id(request_task_id),
                               .token_id(capability_accessors_t::capability_get_id(
                                   capability_tokens[0]
                               )),
                               .token_tag(capability_accessors_t::capability_get_tag(
                                   capability_tokens[0]
                               )),
                               .token_offset(capability_accessors_t::capability_get_offset(
                                   capability_tokens[0]
                               )),
                               .access_len(resolved_access_len), .parent(dummy_parent),
                               .lock_key(lock_key), .request_type(access_type),
                               .parent_token(parent_token), .restriction_type(restriction_type));

          // populate all of the non-default structures
          if (entry.randomize() != 1) begin
            `uvm_fatal_context(COMPONENT_NAME, $sformatf("Could not randomize direct entry!"),
                               uvm_root::get());
          end

          entries.push_back(entry);
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_INDIRECT_CAPABILITY, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_FRONT, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_BACK, NORTHCAPE_CAPABILITY_RESOLVER_TEST_REVOCATION_CAPABILITY: begin
          my_type_t entry, first_entry;
          bit [AXI_ADDR_WIDTH-1:0] parent_token;

          parent_token = '0;

          entry = new("CMT entry");
          // only the top level indirect capability needs matching restriction
          // we make the other restrictions not matching deliberately
          entry.set_attributes(.entry_type(NORTHCAPE_CMT_DIRECT), .cmt_base(cmt_base_addr),
                               .valid_test(1), .is_root_capability(0),
                               .device_id(request_device_id + 1), .task_id(request_task_id - 1),
                               .token_id(capability_accessors_t::capability_get_id(
                                   capability_tokens[number_indirect_caps]
                               )),
                               .token_tag(capability_accessors_t::capability_get_tag(
                                   capability_tokens[number_indirect_caps]
                               )),
                               // dealing with the offset is the MMU's job
                               .token_offset('0), .access_len(resolved_access_len),
                               .parent(dummy_parent), .lock_key(lock_key),
                               .request_type(access_type), .parent_token(parent_token),
                               .restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND));

          `uvm_info_context(COMPONENT_NAME, $sformatf(
                            "Used lock key %x for direct capability!", lock_key), UVM_DEBUG,
                            uvm_root::get());

          // populate all of the non-default structures
          if (entry.randomize() != 1) begin
            `uvm_fatal_context(COMPONENT_NAME, $sformatf("Could not randomize direct entry!",),
                               uvm_root::get());
          end

          first_entry = entry;

          entries.push_front(entry);

          for (int i = number_indirect_caps - 1; i >= 0; i--) begin
            entry = new("CMT entry");
            entry.set_attributes(.entry_type(NORTHCAPE_CMT_INDIRECT), .cmt_base(cmt_base_addr),
                                 .valid_test(1), .is_root_capability(0),
                                 .device_id(i == 0 ? request_device_id : request_device_id + 1),
                                 .task_id(i == 0 ? request_task_id : request_task_id - 1),
                                 .token_id(capability_accessors_t::capability_get_id(
                                     capability_tokens[i]
                                 )),
                                 .token_tag(capability_accessors_t::capability_get_tag(
                                     capability_tokens[i]
                                 )),
                                 .token_offset('0), .access_len(resolved_access_len),
                                 .parent(entries[0].get_entry()), .lock_key(lock_key),
                                 .request_type(access_type), .parent_token(capability_tokens[i+1]),
                                 .restriction_type(i == 0 ? restriction_type : NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND));

            // populate all of the non-default structures
            if (entry.randomize() != 1) begin
              `uvm_fatal_context(COMPONENT_NAME, $sformatf(
                                 "Could not randomize indirect entry %d with parent_offset %d + segment_length %d + token_offset_provided %d + access_len_provided %d <= parent segment length %d for parent %s!",
                                 i,
                                 entry.parent_offset,
                                 entry.segment_length,
                                 entry.token_offset_provided,
                                 entry.access_len_provided,
                                 entry.get_parent_segment_length(),
                                 entries[0].convert2string()
                                 ), uvm_root::get());
            end

            entries.push_front(entry);
          end

          if (test_type == NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_FRONT) begin
            northcape_physical_address_t old_address = first_entry.physical_address_randomized;
            first_entry.physical_address_randomized = entries[0].get_entry().location.indirect_location.effective_base + 1;
            first_entry.segment_length = entries[0].get_entry().location.indirect_location.length - 1;
            `uvm_info_context(COMPONENT_NAME, $sformatf(
                              "Updated first entry physical address %x to %x and decremented segment length to %x!",
                              old_address,
                              first_entry.physical_address_randomized,
                              first_entry.segment_length
                              ), UVM_HIGH, uvm_root::get());
          end
          if (test_type == NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_BACK) begin
            first_entry.segment_length = entries[0].get_entry().location.indirect_location.length - 1;
          end
          if (test_type == NORTHCAPE_CAPABILITY_RESOLVER_TEST_REVOCATION_CAPABILITY) begin
            // rest does not matter - revocation capability should NEVER be accessed
            entries[0].entry_type = NORTHCAPE_CMT_REVOCATION;
          end
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_OK,NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_FAIL, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_FRONT, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_BACK: begin
          my_type_t entry, first_entry;
          bit [AXI_ADDR_WIDTH-1:0] parent_token;

          parent_token = '0;

          entry = new("CMT entry");
          first_entry = entry;
          // again, restrictions of everything but top capability need not match
          entry.set_attributes(.entry_type(NORTHCAPE_CMT_DIRECT), .cmt_base(cmt_base_addr),
                               .valid_test(1), .is_root_capability(0),
                               .device_id(request_device_id + 1), .task_id(request_task_id - 1),
                               .token_id(capability_accessors_t::capability_get_id(
                                   capability_tokens[number_indirect_caps]
                               )),
                               .token_tag(capability_accessors_t::capability_get_tag(
                                   capability_tokens[number_indirect_caps]
                               )),
                               // dealing with the offset is the MMU's job
                               .token_offset('0), .access_len(resolved_access_len),
                               .parent(dummy_parent),
                               .lock_key(test_type == NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_FAIL ? '0: lock_key),
                               .request_type(access_type), .parent_token(parent_token),
                               .restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND));

          if (test_type == NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_FAIL && lock_key == '0) begin
            `uvm_fatal_context(COMPONENT_NAME,
                               "Have same randomized key as given key on invalid lock test!",
                               uvm_root::get());
          end

          // populate all of the non-default structures
          if (entry.randomize() != 1) begin
            `uvm_fatal_context(COMPONENT_NAME, $sformatf("Could not randomize direct entry!",),
                               uvm_root::get());
          end

          entries.push_front(entry);

          for (int i = number_indirect_caps - 1; i >= 0; i--) begin
            entry = new("CMT entry");
            // lock holder token is at the front
            // everything else need not match restrictions
            entry.set_attributes(
                .entry_type(i == 0 ? NORTHCAPE_CMT_LOCK_HOLDER : NORTHCAPE_CMT_INDIRECT),
                .cmt_base(cmt_base_addr), .valid_test(1), .is_root_capability(0),
                .device_id(i == 0 ? request_device_id : request_device_id + 1),
                .task_id(i == 0 ? request_task_id : request_task_id - 1),
                .token_id(capability_accessors_t::capability_get_id(capability_tokens[i])),
                .token_tag(capability_accessors_t::capability_get_tag(capability_tokens[i])),
                .token_offset('0), .access_len(resolved_access_len),
                .parent(entries[0].get_entry()), .lock_key(lock_key), .request_type(access_type),
                .parent_token(capability_tokens[i+1]),
                .restriction_type(i == 0 ? restriction_type : NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND));

            // populate all of the non-default structures
            if (entry.randomize() != 1) begin
              `uvm_fatal_context(COMPONENT_NAME, $sformatf(
                                 "Could not randomize indirect entry %d with parent_offset %d + segment_length %d + token_offset_provided %d + access_len_provided %d <= parent segment length %d for parent %s!",
                                 i,
                                 entry.parent_offset,
                                 entry.segment_length,
                                 entry.token_offset_provided,
                                 entry.access_len_provided,
                                 entry.get_parent_segment_length(),
                                 entries[0].convert2string()
                                 ), uvm_root::get());
            end

            entries.push_front(entry);
          end

          if(test_type == NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_FRONT)
          begin
            northcape_physical_address_t old_address = first_entry.physical_address_randomized;
            first_entry.physical_address_randomized = entries[1].get_entry().location.indirect_location.effective_base + 1;
            first_entry.segment_length = entries[1].get_entry().location.indirect_location.length - 1;
            `uvm_info_context(COMPONENT_NAME, $sformatf(
                              "Updated first entry physical address %x to %x and decremented segment length to %x!",
                              old_address,
                              first_entry.physical_address_randomized,
                              first_entry.segment_length
                              ), UVM_HIGH, uvm_root::get());
          end
          if(test_type == NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_BACK)
          begin
            first_entry.segment_length = entries[1].get_entry().location.indirect_location.length - 1;
          end
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_CHILD, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE_CHILD: begin
          my_type_t entry, first_entry;
          bit [AXI_ADDR_WIDTH-1:0] parent_token;

          parent_token = '0;

          entry = new("CMT entry");
          first_entry = entry;
          // again, restrictions of everything but top capability need not match
          entry.set_attributes(.entry_type(NORTHCAPE_CMT_DIRECT), .cmt_base(cmt_base_addr),
                               .valid_test(1), .is_root_capability(0),
                               .device_id(request_device_id + 1), .task_id(request_task_id - 1),
                               .token_id(capability_accessors_t::capability_get_id(
                                   capability_tokens[number_indirect_caps]
                               )),
                               .token_tag(capability_accessors_t::capability_get_tag(
                                   capability_tokens[number_indirect_caps]
                               )),
                               // dealing with the offset is the MMU's job
                               .token_offset('0), .access_len(resolved_access_len),
                               .parent(dummy_parent),
                               .lock_key(lock_key),
                               .request_type(access_type), .parent_token(parent_token),
                               .restriction_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND));

          // populate all of the non-default structures
          if (entry.randomize() != 1) begin
            `uvm_fatal_context(COMPONENT_NAME, $sformatf("Could not randomize direct entry!",),
                               uvm_root::get());
          end

          entries.push_front(entry);

          for (int i = number_indirect_caps - 1; i >= 0; i--) begin
            entry = new("CMT entry");
            // lock holder token is at the front
            // everything else need not match restrictions
            entry.set_attributes(
                .entry_type(i == 0 ? NORTHCAPE_CMT_LOCK_HOLDER : NORTHCAPE_CMT_INDIRECT),
                .cmt_base(cmt_base_addr), .valid_test(1), .is_root_capability(0),
                .device_id(i == 0 ? request_device_id : request_device_id + 1),
                .task_id(i == 0 ? request_task_id : request_task_id - 1),
                .token_id(capability_accessors_t::capability_get_id(capability_tokens[i])),
                .token_tag(capability_accessors_t::capability_get_tag(capability_tokens[i])),
                .token_offset('0), .access_len(resolved_access_len),
                .parent(entries[0].get_entry()), .lock_key(test_type == NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_CHILD ? lock_key : lock_key - 1), .request_type(access_type),
                .parent_token(capability_tokens[i+1]),
                .restriction_type(i == 0 ? restriction_type : NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND));

            if(i == 0)
            begin
              `uvm_info_context(COMPONENT_NAME, $sformatf("First lock-holder will get token %x", capability_tokens[i]), UVM_HIGH, uvm_root::get());
            end

            // populate all of the non-default structures
            if (entry.randomize() != 1) begin
              `uvm_fatal_context(COMPONENT_NAME, $sformatf(
                                 "Could not randomize indirect entry %d with parent_offset %d + segment_length %d + token_offset_provided %d + access_len_provided %d <= parent segment length %d for parent %s!",
                                 i,
                                 entry.parent_offset,
                                 entry.segment_length,
                                 entry.token_offset_provided,
                                 entry.access_len_provided,
                                 entry.get_parent_segment_length(),
                                 entries[0].convert2string()
                                 ), uvm_root::get());
            end

            entries.push_front(entry);
          end

          if(number_indirect_caps > 1)
          begin
            /* could be indirect child - lock holder - lock holder - direct */
            first_entry = entries[1];
          end

          /* 0...n children of lock-holder */
          for (int i = number_indirect_caps - 1; i >= 0; i--) begin
            entry = new("CMT entry");
            // lock holder token is at the front
            // everything else need not match restrictions
            entry.set_attributes(
                .entry_type((i == 0 && test_type inside {NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE_CHILD}) ? NORTHCAPE_CMT_LOCK_HOLDER : NORTHCAPE_CMT_INDIRECT),
                .cmt_base(cmt_base_addr), .valid_test(1), .is_root_capability(0),
                .device_id(i == 0 ? request_device_id : request_device_id + 1),
                .task_id(i == 0 ? request_task_id : request_task_id - 1),
                .token_id(capability_accessors_t::capability_get_id(capability_tokens[i])),
                .token_tag(capability_accessors_t::capability_get_tag(capability_tokens[i])),
                .token_offset('0), .access_len(resolved_access_len),
                .parent(i == number_indirect_caps - 1 ? first_entry.get_entry() : entries[0].get_entry()), .lock_key(lock_key), .request_type(access_type),
                .parent_token(i == number_indirect_caps - 1 ? capability_tokens[0] : capability_tokens[i+1]),
                .restriction_type(i == 0 ? restriction_type : NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND));

            // populate all of the non-default structures
            if (entry.randomize() != 1) begin
              `uvm_fatal_context(COMPONENT_NAME, $sformatf(
                                 "Could not randomize indirect entry %d with parent_offset %d + segment_length %d + token_offset_provided %d + access_len_provided %d <= parent segment length %d for parent %s!",
                                 i,
                                 entry.parent_offset,
                                 entry.segment_length,
                                 entry.token_offset_provided,
                                 entry.access_len_provided,
                                 entry.get_parent_segment_length(),
                                 entries[0].convert2string()
                                 ), uvm_root::get());
            end

            entries.push_front(entry);
          end

          if(number_indirect_caps > 1)
          begin
            /* could be indirect child - lock holder - lock holder - direct */
            first_entry = entries[1];
          end

          if(test_type == NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE_CHILD)
          begin
            /* 0...n children of second lock-holder */
          for (int i = number_indirect_caps - 1; i >= 0; i--) begin
            entry = new("CMT entry");
            // only indirect capabilities now - two lock-holders in the tree
            entry.set_attributes(
                .entry_type(NORTHCAPE_CMT_INDIRECT),
                .cmt_base(cmt_base_addr), .valid_test(1), .is_root_capability(0),
                .device_id(i == 0 ? request_device_id : request_device_id + 1),
                .task_id(i == 0 ? request_task_id : request_task_id - 1),
                .token_id(capability_accessors_t::capability_get_id(capability_tokens[i])),
                .token_tag(capability_accessors_t::capability_get_tag(capability_tokens[i])),
                .token_offset('0), .access_len(resolved_access_len),
                .parent(i == number_indirect_caps - 1 ? first_entry.get_entry() : entries[0].get_entry()),
                .lock_key(lock_key), .request_type(access_type),
                .parent_token(i == number_indirect_caps - 1 ? capability_tokens[0] : capability_tokens[i+1]),
                .restriction_type(i == 0 ? restriction_type : NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND));

            // populate all of the non-default structures
            if (entry.randomize() != 1) begin
              `uvm_fatal_context(COMPONENT_NAME, $sformatf(
                                 "Could not randomize indirect entry %d with parent_offset %d + segment_length %d + token_offset_provided %d + access_len_provided %d <= parent segment length %d for parent %s!",
                                 i,
                                 entry.parent_offset,
                                 entry.segment_length,
                                 entry.token_offset_provided,
                                 entry.access_len_provided,
                                 entry.get_parent_segment_length(),
                                 entries[0].convert2string()
                                 ), uvm_root::get());
            end

            entries.push_front(entry);
          end
          end
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_INVALID_ENTRY: begin
          my_type_t entry;
          bit [AXI_ADDR_WIDTH-1:0] parent_token;

          parent_token = '0;
          // only makes sense when we also have a lock holder token
          lock_key = '0;

          entry = new("CMT entry");
          entry.set_attributes(
              .entry_type(NORTHCAPE_CMT_INVALID), .cmt_base(cmt_base_addr), .valid_test(1),
              .is_root_capability(0), .device_id(request_device_id), .task_id(request_task_id),
              .token_id(capability_accessors_t::capability_get_id(
                  capability_tokens[number_indirect_caps]
              )),
              .token_tag(capability_accessors_t::capability_get_tag(
                  capability_tokens[number_indirect_caps]
              )),
              // dealing with the offset is the MMU's job
              .token_offset('0), .access_len(resolved_access_len), .parent(dummy_parent),
              .lock_key(lock_key), .request_type(access_type), .parent_token(parent_token),
              .restriction_type(restriction_type));

          // populate all of the non-default structures
          if (entry.randomize() != 1) begin
            `uvm_fatal_context(COMPONENT_NAME, $sformatf("Could not randomize direct entry!",),
                               uvm_root::get());
          end

          entries.push_front(entry);

          for (int i = number_indirect_caps - 1; i >= 0; i--) begin
            entry = new("CMT entry");
            entry.set_attributes(
                .entry_type(NORTHCAPE_CMT_INDIRECT), .cmt_base(cmt_base_addr), .valid_test(1),
                .is_root_capability(0), .device_id(request_device_id), .task_id(request_task_id),
                .token_id(capability_accessors_t::capability_get_id(capability_tokens[i])),
                .token_tag(capability_accessors_t::capability_get_tag(capability_tokens[i])),
                .token_offset('0), .access_len(resolved_access_len),
                .parent(entries[0].get_entry()), .lock_key(lock_key), .request_type(access_type),
                .parent_token(capability_tokens[i+1]), .restriction_type(restriction_type));

            // populate all of the non-default structures
            if (entry.randomize() != 1) begin
              `uvm_fatal_context(COMPONENT_NAME, $sformatf(
                                 "Could not randomize indirect entry %d with parent_offset %d + segment_length %d + token_offset_provided %d + access_len_provided %d <= parent segment length %d for parent %s!",
                                 i,
                                 entry.parent_offset,
                                 entry.segment_length,
                                 entry.token_offset_provided,
                                 entry.access_len_provided,
                                 entry.get_parent_segment_length(),
                                 entries[0].convert2string()
                                 ), uvm_root::get());
            end

            entries.push_front(entry);
          end
        end
        default: begin
          `uvm_fatal_context(COMPONENT_NAME, "Not supported!", uvm_root::get());
        end
      endcase

      foreach (entries[i]) begin
        `uvm_info_context(COMPONENT_NAME, $sformatf(
                          "Have entry %d: %s tag %x",
                          i,
                          entries[i].convert2string(),
                          capability_accessors_t::capability_get_tag(
                              capability_tokens[i]
                          )
                          ), UVM_DEBUG, uvm_root::get());
      end

      return entries;
    endfunction

    static function string format_entry_list(my_type_list entries);
      string all_cmts = "[";

      foreach (entries[i]) begin
        all_cmts = {all_cmts, "{", entries[i].convert2string(), "}"};
      end

      all_cmts = {all_cmts, "]"};

      return all_cmts;
    endfunction


  endclass

  class automatic NorthcapeCapabilityResolverTransaction #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      // parameters for AXIs request interface (input of the resolver)
      parameter AXIS_REQUEST_TDATA_WIDTH = -1,
      parameter AXIS_REQUEST_TID_WIDTH   = -1,
      parameter AXIS_REQUEST_TDEST_WIDTH = -1,
      parameter AXIS_REQUEST_TUSER_WIDTH = -1,

      // parameters for AXIs response interface (output of the resolver)
      parameter AXIS_RESPONSE_TDATA_WIDTH = -1,
      parameter AXIS_RESPONSE_TID_WIDTH   = -1,
      parameter AXIS_RESPONSE_TDEST_WIDTH = -1,
      parameter AXIS_RESPONSE_TUSER_WIDTH = -1
  ) extends uvm_sequence_item;
    `uvm_object_param_utils(
        NorthcapeCapabilityResolverTransaction#(AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_ID_WIDTH, AXI_USER_WIDTH, AXIS_REQUEST_TDATA_WIDTH, AXIS_REQUEST_TID_WIDTH, AXIS_REQUEST_TDEST_WIDTH, AXIS_REQUEST_TUSER_WIDTH, AXIS_RESPONSE_TDATA_WIDTH, AXIS_RESPONSE_TID_WIDTH, AXIS_RESPONSE_TDEST_WIDTH, AXIS_RESPONSE_TUSER_WIDTH));

    localparam string COMPONENT_NAME = "Northcape Capability Resolver Transaction";

    Axi5DelayGenerator delay_gen;

    typedef capability_accessors#(AXI_ADDR_WIDTH) capability_accessors_t;
    typedef NorthcapeCapabilityResolverTransactionCMTEntry#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .HASH_TYPE(HASH_TYPE_IDENTITY)
    ) cmt_entry_t;

    typedef NorthcapeCapabilityResolverTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXIS_REQUEST_TDATA_WIDTH(AXIS_REQUEST_TDATA_WIDTH),
        .AXIS_REQUEST_TID_WIDTH  (AXIS_REQUEST_TID_WIDTH),
        .AXIS_REQUEST_TDEST_WIDTH(AXIS_REQUEST_TDEST_WIDTH),
        .AXIS_REQUEST_TUSER_WIDTH(AXIS_REQUEST_TUSER_WIDTH),

        .AXIS_RESPONSE_TDATA_WIDTH(AXIS_RESPONSE_TDATA_WIDTH),
        .AXIS_RESPONSE_TID_WIDTH  (AXIS_RESPONSE_TID_WIDTH),
        .AXIS_RESPONSE_TDEST_WIDTH(AXIS_RESPONSE_TDEST_WIDTH),
        .AXIS_RESPONSE_TUSER_WIDTH(AXIS_RESPONSE_TUSER_WIDTH)
    ) my_type_t;

    rand northcape_capability_resolver_transaction_type_t test_type;

    constraint supported_test_types_only {
      test_type inside {NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_ROOT_CAPABILITY,
                        NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_DIRECT_CAPABILITY,
                        NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_INDIRECT_CAPABILITY,
                        NORTHCAPE_CAPABILITY_RESOLVER_TEST_INVALID_ENTRY,
                        NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_OK,
                        NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_FAIL,
                        NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_CHILD,
                        NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE,
                        NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE_CHILD,
                        NORTHCAPE_CAPABILITY_RESOLVER_TEST_BUS_ERROR,
                        NORTHCAPE_CAPABILITY_RESOLVER_TEST_VALIDATION_ERROR,
                        NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_FRONT,
                        NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_BACK,
                        NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_FRONT,
                        NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_BACK,
                        NORTHCAPE_CAPABILITY_RESOLVER_TEST_REVOCATION_CAPABILITY};
    }

    // base address of the capability metadata table in memory
    rand bit [AXI_ADDR_WIDTH - 1 : 0] cmt_base_addr;

    int table_size_clog_2;

    // identity of the requester
    rand task_id_t request_task_id;
    rand device_id_t request_device_id;

    cmt_entry_t entries[$];

    // need at least two entries in the table
    constraint table_size_cannot_be_0 {table_size_clog_2 != 0;}

    // we will parse out the individual components and generate the corresponding CMT entries
    rand bit [63 : 0] capability_tokens[MAX_INDIRECT_CAPABILITIES+1];

    // bounds of the access
    // to guarantee that we test with realistic values
    rand axi_size_t access_size;
    rand axi_len_t access_len;

    rand northcape_lock_key_t lock_key;
    rand axis_validate_request_perm_t access_type;

    rand northcape_restriction_type_t restriction_type;

    constraint access_type_is_allowed {
      access_type != PERM_RESERVED && access_type != ACCESS_DERIVE_RECURSION && access_type != ACCESS_NONE;
    }

    rand int unsigned number_indirect_caps;

    constraint suitable_number_indirect_caps {
      number_indirect_caps >= 1 && number_indirect_caps <= MAX_INDIRECT_CAPABILITIES;
    }

    function new(string name = "");
      super.new(name);
      // no collisions - this is something the ops module needs to deal with, not us!
      table_size_clog_2 = AXI_ADDR_WIDTH / 32;

      delay_gen = new();
    endfunction

    function void post_randomize();

      if(test_type != NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_OK && test_type != NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_FAIL && test_type != NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_FRONT && test_type != NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_BACK && test_type != NORTHCAPE_CAPABILITY_RESOLVER_TEST_VALIDATION_ERROR)
      begin
        // tests where we do not generate a lock-holder token will fail on lock_key != 0
        lock_key = '0;
      end

      if(test_type inside {NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_FRONT, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_BACK})
      begin
        if (number_indirect_caps == 1) begin
          // need at least one extra indirect capability after the lock holder to be able to be out of bounds
          number_indirect_caps++;
        end
      end

      entries = cmt_entry_t::generate_test_entries(
          test_type,
          access_type,
          access_size,
          access_len,
          capability_tokens,
          cmt_base_addr,
          request_device_id,
          request_task_id,
          lock_key,
          number_indirect_caps,
          restriction_type
      );
    endfunction

    function void do_copy(uvm_object rhs);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "Copy RHS is null!");
      end

      super.do_copy(rhs);

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Casting other transaction of type %s to myself (%s)",
                $typename(
                    rhs
                ),
                $typename(
                    other_transaction
                )
                ), UVM_DEBUG);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      delay_gen = other_transaction.delay_gen;
      test_type = other_transaction.test_type;
      cmt_base_addr = other_transaction.cmt_base_addr;
      table_size_clog_2 = other_transaction.table_size_clog_2;
      request_task_id = other_transaction.request_task_id;
      request_device_id = other_transaction.request_device_id;

      foreach (other_transaction.entries[i]) begin
        cmt_entry_t entry;
        assert ($cast(entry, other_transaction.entries[i].clone()));

        entries.push_back(entry);
      end

      capability_tokens = other_transaction.capability_tokens;
      access_size = other_transaction.access_size;
      access_len = other_transaction.access_len;
      lock_key = other_transaction.lock_key;
      access_type = other_transaction.access_type;


    endfunction

    function string convert2string();
      return $sformatf(
          "Test type %s CMT base %x table size clog2 %d request task id %d request device id %d capability token %x access size %d access len %d lock key %x access type %s number indirect %d CMT entries %s",
          test_type.name(),
          cmt_base_addr,
          table_size_clog_2,
          request_task_id,
          request_device_id,
          capability_tokens,
          access_size,
          access_len,
          lock_key,
          access_type.name(),
          number_indirect_caps,
          cmt_entry_t::format_entry_list(
              entries
          )
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

      foreach (other_transaction.entries[i]) begin
        if (entries[i].compare(other_transaction.entries[i]) == 0) begin
          `uvm_error(COMPONENT_NAME, $sformatf(
                     "Entry %d (%s) does not match %s",
                     i,
                     entries[i].convert2string(),
                     other_transaction.entries[i].convert2string()
                     ));
          return 0;
        end
      end

      return delay_gen == other_transaction.delay_gen &&
            test_type == other_transaction.test_type &&
            cmt_base_addr == other_transaction.cmt_base_addr &&
            table_size_clog_2 == other_transaction.table_size_clog_2 &&
            request_task_id == other_transaction.request_task_id &&
            request_device_id == other_transaction.request_device_id &&
            capability_tokens == other_transaction.capability_tokens &&
            access_size == other_transaction.access_size &&
            access_len == other_transaction.access_len &&
            lock_key == other_transaction.lock_key &&
            access_type == other_transaction.access_type;
    endfunction

  endclass

  class automatic NorthcapeCapabilityResolverTransactionAxiMaster #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      // parameters for AXIs request interface (input of the resolver)
      parameter AXIS_REQUEST_TDATA_WIDTH = -1,
      parameter AXIS_REQUEST_TID_WIDTH   = -1,
      parameter AXIS_REQUEST_TDEST_WIDTH = -1,
      parameter AXIS_REQUEST_TUSER_WIDTH = -1,

      // parameters for AXIs response interface (output of the resolver)
      parameter AXIS_RESPONSE_TDATA_WIDTH = -1,
      parameter AXIS_RESPONSE_TID_WIDTH   = -1,
      parameter AXIS_RESPONSE_TDEST_WIDTH = -1,
      parameter AXIS_RESPONSE_TUSER_WIDTH = -1

  ) extends NorthcapeCapabilityResolverTransaction #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXIS_REQUEST_TDATA_WIDTH(AXIS_REQUEST_TDATA_WIDTH),
      .AXIS_REQUEST_TID_WIDTH  (AXIS_REQUEST_TID_WIDTH),
      .AXIS_REQUEST_TDEST_WIDTH(AXIS_REQUEST_TDEST_WIDTH),
      .AXIS_REQUEST_TUSER_WIDTH(AXIS_REQUEST_TUSER_WIDTH),

      .AXIS_RESPONSE_TDATA_WIDTH(AXIS_RESPONSE_TDATA_WIDTH),
      .AXIS_RESPONSE_TID_WIDTH  (AXIS_RESPONSE_TID_WIDTH),
      .AXIS_RESPONSE_TDEST_WIDTH(AXIS_RESPONSE_TDEST_WIDTH),
      .AXIS_RESPONSE_TUSER_WIDTH(AXIS_RESPONSE_TUSER_WIDTH)
  ) implements INorthcapeAXITransactionMasterSide#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  );
    localparam COMPONENT_NAME = "Northcape Capability Resolver Transaction AXI Master";

    // for indirect capabilities.
    // indicates which entry we need to return 
    int unsigned entry_number;

    /**
          * Implementation of AXI transaction
          * AXI interface returns CMT entry if address and other parameters are correct
          */
    virtual function axi_test_request_type_t get_axi_request_type();
      // currently a read-only module
      return AXI_TEST_READ;
    endfunction

    virtual function bit [AXI_ID_WIDTH-1:0] get_test_id();
      return '0;
    endfunction

    virtual function bit [AXI_USER_WIDTH-1:0] get_test_user();
      return '0;
    endfunction

    virtual function axi_len_t get_test_len();
      // designed to be possible in burst of one
      return 0;
    endfunction

    // (read only) provided response
    virtual function bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] get_response_data();
      unique case (test_type)
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_BUS_ERROR,NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_ROOT_CAPABILITY,NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_DIRECT_CAPABILITY, NORTHCAPE_CAPABILITY_RESOLVER_TEST_VALIDATION_ERROR: begin
          return entries[0].get_entry();
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_INDIRECT_CAPABILITY,NORTHCAPE_CAPABILITY_RESOLVER_TEST_INVALID_ENTRY,NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_OK, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_FAIL, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_FRONT, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_BACK, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_FRONT, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_BACK, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_CHILD, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE_CHILD, NORTHCAPE_CAPABILITY_RESOLVER_TEST_REVOCATION_CAPABILITY: begin
          return entries[entry_number].get_entry();
        end
        default: begin
          `uvm_fatal(COMPONENT_NAME, "Not supported");
        end
      endcase
    endfunction

    // (write only) type of atomic transfer
    virtual function axi5_atop_t get_atomic_type();
      return ATOMIC_NONE;
    endfunction

    // (read only) response
    virtual function axi_resp_t get_given_response();
      unique case (test_type)
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_ROOT_CAPABILITY,NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_DIRECT_CAPABILITY, NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_INDIRECT_CAPABILITY,NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_OK, NORTHCAPE_CAPABILITY_RESOLVER_TEST_INVALID_ENTRY, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_FAIL, NORTHCAPE_CAPABILITY_RESOLVER_TEST_VALIDATION_ERROR, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_FRONT, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_BACK, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_FRONT, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_BACK, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_CHILD, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE_CHILD, NORTHCAPE_CAPABILITY_RESOLVER_TEST_REVOCATION_CAPABILITY: begin
          return axi5::OKAY;
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_BUS_ERROR: begin
          return axi5::DECERR;
        end
        default: begin
          `uvm_fatal(COMPONENT_NAME, "Not supported!");
        end
      endcase
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

    function new(string name = "");
      super.new(name);
      entry_number = 0;
    endfunction

    function string convert2string();
      return $sformatf("%s entry number %d", super.convert2string(), entry_number);
    endfunction

    virtual function string to_string();
      return convert2string();
    endfunction

  endclass


  class automatic NorthcapeCapabilityResolverTransactionAxisTransmitter #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      // parameters for AXIs request interface (input of the resolver)
      parameter AXIS_REQUEST_TDATA_WIDTH = -1,
      parameter AXIS_REQUEST_TID_WIDTH   = -1,
      parameter AXIS_REQUEST_TDEST_WIDTH = -1,
      parameter AXIS_REQUEST_TUSER_WIDTH = -1,

      // parameters for AXIs response interface (output of the resolver)
      parameter AXIS_RESPONSE_TDATA_WIDTH = -1,
      parameter AXIS_RESPONSE_TID_WIDTH   = -1,
      parameter AXIS_RESPONSE_TDEST_WIDTH = -1,
      parameter AXIS_RESPONSE_TUSER_WIDTH = -1
  ) extends NorthcapeCapabilityResolverTransaction #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXIS_REQUEST_TDATA_WIDTH(AXIS_REQUEST_TDATA_WIDTH),
      .AXIS_REQUEST_TID_WIDTH  (AXIS_REQUEST_TID_WIDTH),
      .AXIS_REQUEST_TDEST_WIDTH(AXIS_REQUEST_TDEST_WIDTH),
      .AXIS_REQUEST_TUSER_WIDTH(AXIS_REQUEST_TUSER_WIDTH),

      .AXIS_RESPONSE_TDATA_WIDTH(AXIS_RESPONSE_TDATA_WIDTH),
      .AXIS_RESPONSE_TID_WIDTH  (AXIS_RESPONSE_TID_WIDTH),
      .AXIS_RESPONSE_TDEST_WIDTH(AXIS_RESPONSE_TDEST_WIDTH),
      .AXIS_RESPONSE_TUSER_WIDTH(AXIS_RESPONSE_TUSER_WIDTH)
  ) implements IAxis5TransmitterTransaction#(
      .AXIS_TDATA_WIDTH(AXIS_REQUEST_TDATA_WIDTH),
      .AXIS_TID_WIDTH  (AXIS_REQUEST_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_REQUEST_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_REQUEST_TUSER_WIDTH)
  );
    localparam COMPONENT_NAME = "Northcape Capability Resolver Transaction AXIS TRANSMITTER";

    int unsigned entry_number;

    /**
          * Implementation of AXIS request scoreboard
          * This is where we request capability resolution
          */
    virtual function bit [AXIS_REQUEST_TDATA_WIDTH-1:0] get_transmitter_tdata();
      axis_validate_request_tdata_t ret;

      ret = '0;

      ret.address =
          capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(capability_tokens[entry_number]);
      ret.tag = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(
          capability_tokens[entry_number]);
      ret.access_type = access_type;
      ret.device_id = request_device_id;
      ret.task_id = request_task_id;

      `uvm_info(COMPONENT_NAME, $sformatf("I have seen tag %x", ret.tag), UVM_DEBUG);

      return ret;
    endfunction

    /**
          * Default from here, not necessary
          */
    virtual function bit [AXIS_REQUEST_TDATA_WIDTH/8-1:0] get_transmitter_tstrb();
      return '1;
    endfunction

    virtual function bit [AXIS_REQUEST_TDATA_WIDTH/8-1:0] get_transmitter_tkeep();
      return '1;
    endfunction

    virtual function bit [AXIS_REQUEST_TID_WIDTH-1:0] get_transmitter_tid();
      return '0;
    endfunction

    virtual function bit [AXIS_REQUEST_TDEST_WIDTH-1:0] get_transmitter_tdest();
      return '0;
    endfunction

    virtual function bit [AXIS_REQUEST_TUSER_WIDTH-1:0] get_transmitter_tuser();
      return '0;
    endfunction

    function new(string name = "");
      super.new(name);
      entry_number = 0;
    endfunction

    function string convert2string();
      return $sformatf("%s entry number %d", super.convert2string(), entry_number);
    endfunction

  endclass


endpackage
