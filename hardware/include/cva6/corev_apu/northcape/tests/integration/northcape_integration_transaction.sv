/**
* Contains transactions for testing the entire northcape stack.
*/
package northcape_integration_transaction;
  import northcape_capability_ops_transaction::*;
  import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
  import northcape_types::*;
  import northcape_test::*;
  import northcape_integration_test_constants::*;
  import northcape_capability_ops_common::*;

  import axi5::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  /**
    * High-level representation of a capability that should exist at a certain point in the database
    */
  class automatic NorthcapeIntegrationCapabilityDatabaseEntry #(
      parameter AXI_ADDR_WIDTH = -1
  );

    typedef NorthcapeIntegrationCapabilityDatabaseEntry#(AXI_ADDR_WIDTH) my_type_t;

    northcape_physical_address_t base;
    segment_length_t segment_length;
    // we cannot create if we have references
    northcape_reference_count_t refcount;

    bit [AXI_ADDR_WIDTH-1:0] token;

    northcape_cmt_entry_type_t capability_type;

    my_type_t parent_cap;

    bit was_deleted;
    bit revoke_orphan;

    bit is_locked;
    int lock_key;
    int prev_lock_key;

    localparam string COMPONENT_NAME = "Northcape Integration Capability Database Entry";


    northcape_restrictions_t current_restrictions;

    function new(northcape_physical_address_t base, segment_length_t segment_length,
                 northcape_cmt_entry_type_t capability_type, my_type_t parent_cap,
                 northcape_restrictions_t current_restrictions);
      this.base = base;
      this.segment_length = segment_length;
      this.refcount = 0;
      this.token = '0;
      this.capability_type = capability_type;
      this.parent_cap = parent_cap;

      this.was_deleted = 0;
      this.revoke_orphan = 1'b0;
      this.is_locked = 1'b0;

      this.current_restrictions = current_restrictions;
    endfunction

    function void lock(int lock_key);
      my_type_t current_parent;

      current_parent = parent_cap;
      while (current_parent != null) begin
        current_parent.is_locked = 1'b1;
        prev_lock_key = current_parent.lock_key;
        if (current_parent.capability_type == NORTHCAPE_CMT_DIRECT) begin
          current_parent.lock_key = lock_key;
        end
        current_parent = current_parent.parent_cap;
      end
      this.lock_key = lock_key;
    endfunction

    function void unlock();
      my_type_t current_parent;

      current_parent = parent_cap;
      while (current_parent != null) begin
        if (prev_lock_key == '0) begin
          current_parent.is_locked = 1'b0;
        end else begin
          current_parent.lock_key = prev_lock_key;
        end
        current_parent = current_parent.parent_cap;
      end
    endfunction

    function bit is_accessible();
      my_type_t current_parent;

      int found_lock_key = 0;

      if (was_deleted) begin
        return 1'b0;
      end

      if (!get_direct_parent().is_locked) begin
        return 1'b1;
      end

      current_parent = this;
      while (current_parent) begin
        if (current_parent.capability_type == NORTHCAPE_CMT_LOCK_HOLDER) begin
          // first lock key wins
          found_lock_key = current_parent.lock_key;
          break;
        end
        current_parent = current_parent.parent_cap;
      end

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Comparing direct parent lock key %x vs found lock key %x", lock_key, found_lock_key
                ), UVM_DEBUG);

      return get_direct_parent().lock_key == found_lock_key;
    endfunction

    function my_type_t get_direct_parent();
      my_type_t ret;

      ret = this;

      while (ret.parent_cap != null) begin
        ret = ret.parent_cap;
      end

      return ret;
    endfunction

    function bit restrictions_satisfyable(input device_id_t device_id, input task_id_t task_id);
      unique case (current_restrictions.restriction_type)
        NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND: begin
          return device_id == current_restrictions.body.task_restriction.device_id && task_id == current_restrictions.body.task_restriction.task_id;
        end
        NORTHCAPE_RESTRICTIONS_NONE, NORTHCAPE_RESTRICTIONS_SET_TASK_ID, NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED:
        begin
          return 1'b1;
        end
        default: begin
          return 1'b0;
        end
      endcase
    endfunction


  endclass

  typedef class NorthcapeIntegrationTransaction;


  /**
    * Database of capabilities that exist at point X during integration testing.
    * Used for creating randomized / directed capability operation transactions.
    */
  class automatic NorthcapeIntegrationCapabilityDatabase #(
      parameter AXI_ADDR_WIDTH = -1
  );
    typedef NorthcapeIntegrationCapabilityDatabaseEntry#(AXI_ADDR_WIDTH) cap_db_entry_t;
    typedef NorthcapeIntegrationTransaction#(AXI_ADDR_WIDTH) integration_transaction_t;

    // key: capability ID
    // entry: is valid at current time (not locked / deleted / ...)
    protected cap_db_entry_t entry_db[capability_id_t];


    capability_id_t max_capability;

    task_id_t mmu_current_task_irq, mmu_current_task_non_irq;
    device_id_t mmu_current_device;

    static protected NorthcapeIntegrationCapabilityDatabase #(AXI_ADDR_WIDTH) inst;

    int lock_key = 1;

    localparam string COMPONENT_NAME = "Northcape Integration Capability Database";

    function void add_capability(input capability_id_t key, input cap_db_entry_t value);
      entry_db[key] = value;
    endfunction

    function cap_db_entry_t get_capability(input capability_id_t key);
      return entry_db[key];
    endfunction

    function void delete_capability(input capability_id_t key);
      entry_db[key].was_deleted = 1'b1;
    endfunction

    function int capability_exists(input capability_id_t key);
      return entry_db.exists(key);
    endfunction

    function int count_orphans();
      int ret = 0;

      foreach (entry_db[id]) begin
        // we track orphans on revoke()
        if (entry_db[id].revoke_orphan) begin
          `uvm_info(COMPONENT_NAME, $sformatf("Capability %d is an orphan!", id), UVM_HIGH);
          ret++;
        end
      end

      return ret;
    endfunction

    function void add_predicted_capability_after_operation(
        integration_transaction_t integration_transaction);
      cap_db_entry_t mmu_capability;

      unique case (integration_transaction.operation)
        NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE: begin
          cap_db_entry_t parent;
          `uvm_info(COMPONENT_NAME, $sformatf(
                    "Have created from capability %d - decreasing segment length!",
                    integration_transaction.capability_to_operate_on
                    ), UVM_HIGH);
          parent = this.get_capability(integration_transaction.capability_to_operate_on);

          this.max_capability++;
          this.add_capability(this.max_capability, cap_db_entry_t::new(
                              integration_transaction.direction ? parent.base : parent.base + parent.segment_length - integration_transaction.new_segment_length,
                              integration_transaction.new_segment_length,
                              NORTHCAPE_CMT_DIRECT,
                              null,
                              integration_transaction.capability_restrictions
                              ));

          parent.segment_length -= integration_transaction.new_segment_length;
          if (this.get_capability(
                  integration_transaction.capability_to_operate_on
              ).segment_length == 0) begin
            // capability destroyed as side effect of create
            this.delete_capability(integration_transaction.capability_to_operate_on);
          end
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE: begin
          cap_db_entry_t parent;

          parent = this.get_capability(integration_transaction.capability_to_operate_on);
          `uvm_info(COMPONENT_NAME, $sformatf(
                    "Have derived from capability %d - increasing refcount!",
                    integration_transaction.capability_to_operate_on
                    ), UVM_HIGH);
          this.max_capability++;
          this.add_capability(this.max_capability, cap_db_entry_t::new(
                              parent.base + integration_transaction.parent_offset,
                              integration_transaction.new_segment_length,
                              NORTHCAPE_CMT_INDIRECT,
                              parent,
                              integration_transaction.capability_restrictions
                              ));
          parent.refcount++;
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
          cap_db_entry_t parent;

          parent = this.get_capability(integration_transaction.capability_to_operate_on);
          `uvm_info(COMPONENT_NAME, $sformatf(
                    "Have derived from capability %d - increasing refcount!",
                    integration_transaction.capability_to_operate_on
                    ), UVM_HIGH);

          if (parent.capability_type == NORTHCAPE_CMT_INDIRECT) begin
            parent.base += integration_transaction.parent_offset;
            parent.segment_length -= integration_transaction.new_segment_length;
          end
          // for direct capabilities, cannot modify base/length - would leak memory

          parent.current_restrictions = integration_transaction.capability_restrictions;
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE: begin
          cap_db_entry_t parent;

          parent = this.get_capability(integration_transaction.capability_to_operate_on);
          `uvm_info(COMPONENT_NAME, $sformatf(
                    "Have cloned capability %d - increasing refcount!",
                    integration_transaction.capability_to_operate_on
                    ), UVM_HIGH);
          this.max_capability++;
          this.add_capability(this.max_capability, cap_db_entry_t::new(
                              parent.base,
                              parent.segment_length,
                              NORTHCAPE_CMT_INDIRECT,
                              parent,
                              integration_transaction.capability_restrictions
                              ));
          parent.refcount++;
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
          cap_db_entry_t child, parent;

          child = this.get_capability(integration_transaction.capability_to_operate_on);

          if (!child) begin
            `uvm_fatal(COMPONENT_NAME, "Could not find entry for capability to operate on!");
          end

          parent = child.parent_cap;

          if (!child) begin
            `uvm_fatal(COMPONENT_NAME, "Could not find entry for parent capability!");
          end

          `uvm_info(COMPONENT_NAME, $sformatf(
                    "Have derived from capability %d - increasing refcount!",
                    integration_transaction.capability_to_operate_on
                    ), UVM_HIGH);

          parent.refcount--;

          if (child.capability_type == NORTHCAPE_CMT_LOCK_HOLDER) begin
            child.unlock();
          end

          this.delete_capability(integration_transaction.capability_to_operate_on);
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE: begin
          cap_db_entry_t left, right;

          left  = this.get_capability(integration_transaction.capability_to_operate_on);
          right = this.get_capability(integration_transaction.capability_to_operate_on_right);

          this.delete_capability(integration_transaction.capability_to_operate_on);
          this.delete_capability(integration_transaction.capability_to_operate_on_right);

          this.max_capability++;
          this.add_capability(this.max_capability, cap_db_entry_t::new(
                              left.base,
                              left.segment_length + right.segment_length,
                              NORTHCAPE_CMT_DIRECT,
                              null,
                              integration_transaction.capability_restrictions
                              ));
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE: begin
          cap_db_entry_t revoked_entry;

          revoked_entry = this.get_capability(integration_transaction.capability_to_operate_on);

          if (revoked_entry.parent_cap != null) begin
            `uvm_fatal(COMPONENT_NAME, "Invalid revoke!");
          end

          revoked_entry.was_deleted = 1;

          foreach (entry_db[key]) begin
            if (entry_db[key].get_direct_parent() == revoked_entry) begin
              `uvm_info(COMPONENT_NAME, $sformatf(
                        "Revoked capability %d - makes capability %d orphan (was deleted before: %b)!",
                        integration_transaction.capability_to_operate_on,
                        key,
                        entry_db[key].was_deleted
                        ), UVM_DEBUG);
              // if otherwise accessible / alive, becomes an orphan
              if (~entry_db[key].was_deleted) begin
                entry_db[key].revoke_orphan = 1'b1;
              end
              entry_db[key].was_deleted = 1;
            end
          end

          this.max_capability++;
          this.add_capability(this.max_capability, cap_db_entry_t::new(
                              revoked_entry.base,
                              revoked_entry.segment_length,
                              NORTHCAPE_CMT_DIRECT,
                              null,
                              integration_transaction.capability_restrictions
                              ));
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
          cap_db_entry_t parent, new_cap;

          parent = this.get_capability(integration_transaction.capability_to_operate_on);
          `uvm_info(COMPONENT_NAME, $sformatf(
                    "Have locked capability %d - increasing refcount!",
                    integration_transaction.capability_to_operate_on
                    ), UVM_HIGH);
          this.max_capability++;
          this.add_capability(this.max_capability, cap_db_entry_t::new(
                              parent.base,
                              parent.segment_length,
                              NORTHCAPE_CMT_LOCK_HOLDER,
                              parent,
                              integration_transaction.capability_restrictions
                              ));
          new_cap = this.get_capability(this.max_capability);
          new_cap.lock(lock_key++);
          parent.refcount++;

        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT: begin
          // inspect is read-only
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP: begin
          // kicks orphans
          foreach (entry_db[key]) begin
            entry_db[key].revoke_orphan = 1'b0;
          end
        end
        default: begin
          `uvm_fatal(COMPONENT_NAME, $sformatf(
                     "Operation %s (%x) not implemented!",
                     integration_transaction.operation.name(),
                     integration_transaction.operation
                     ));
        end

      endcase

      mmu_capability = this.get_capability(integration_transaction.capability_to_access_in_mmu);

      if (mmu_capability == null) begin
        `uvm_fatal(
            COMPONENT_NAME, $sformatf(
            "Could not find MMU capability %d!", integration_transaction.capability_to_access_in_mmu
            ));
      end

      if(integration_transaction.mmu_axi_request_type == AXI_TEST_READ && integration_transaction.mmu_access_is_instruction_fetch && mmu_capability.current_restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID)
      begin
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "MMU accessing capability with set-task-id restriction %d - updating task from %d to %d in IRQ context? %b!",
                  integration_transaction.capability_to_access_in_mmu,
                  integration_transaction.mmu_access_is_irq ? mmu_current_task_irq : mmu_current_task_non_irq,
                  mmu_capability.current_restrictions.body.task_restriction.task_id,
                  integration_transaction.mmu_access_is_irq
                  ), UVM_DEBUG);
        if (integration_transaction.mmu_access_is_irq) begin
          mmu_current_task_irq = mmu_capability.current_restrictions.body.task_restriction.task_id;
        end else begin
          mmu_current_task_non_irq = mmu_capability.current_restrictions.body.task_restriction.task_id;
        end
      end
    endfunction

    function bit capability_is_mmu_accessible(input capability_id_t key, bit is_irq);
      if (!capability_exists(key)) begin
        return 1'b0;
      end
      return get_capability(
          key
      ).restrictions_satisfyable(
          mmu_current_device, is_irq ? mmu_current_task_irq : mmu_current_task_non_irq
      ) == 1'b1 && get_capability(
          key
      ).is_accessible() == 1'b1;
    endfunction

    function bit capability_is_ops_accessible(
        input capability_id_t key, input device_id_t current_device_id,
        input task_id_t current_task_id, input northcape_capability_operation_t operation);
      if (!capability_exists(key)) begin
        return 1'b0;
      end
      if (!get_capability(key).is_accessible()) begin
        if (operation != NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP || get_capability(
                key
            ).capability_type != NORTHCAPE_CMT_LOCK_HOLDER) begin
          // can drop a lock-holder token
          // otherwise, when the base direct capability is locked, no operation allowed
          return 1'b0;
        end
      end
      return get_capability(
          key
      ).restrictions_satisfyable(
          current_device_id, current_task_id
      ) == 1'b1;
    endfunction

    function cap_db_entry_t get_base_capability(input capability_id_t key);
      cap_db_entry_t ret;

      if (!capability_exists(key)) begin
        return null;
      end

      ret = get_capability(key);


      while (ret.parent_cap != null) begin
        ret = ret.parent_cap;
      end

      return ret;
    endfunction

    function bit capabilities_are_related(input capability_id_t key_left,
                                          input capability_id_t key_right);
      return get_base_capability(key_left) != null &&
          get_base_capability(key_left) == get_base_capability(key_right);
    endfunction



    protected
    function new();
      northcape_restrictions_t root_restrictions;

      root_restrictions.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;

      // root capability exists implicitly
      entry_db[NORTHCAPE_ROOT_CAPABILITY_ID] =
          cap_db_entry_t::new(0, '1, NORTHCAPE_CMT_DIRECT, null, root_restrictions);
      max_capability = NORTHCAPE_ROOT_CAPABILITY_ID;
    endfunction

    static function NorthcapeIntegrationCapabilityDatabase#(AXI_ADDR_WIDTH) get_inst();
      if (inst == null) begin
        inst = new();
      end

      return inst;
    endfunction

  endclass

  class automatic NorthcapeIntegrationTransaction #(
      parameter AXI_ADDR_WIDTH = -1
  ) extends uvm_sequence_item;


    typedef NorthcapeIntegrationCapabilityDatabase#(AXI_ADDR_WIDTH) cap_db_t;

    cap_db_t cap_db;

    localparam string COMPONENT_NAME = "Northcape Integration Transaction";

    function new(string name = "");
      super.new(name);
      cap_db = cap_db_t::get_inst();
      this.requesting_device_id = '0;
      this.requesting_task_id = '0;
    endfunction

    // capability we do the operation on. Must exist at this point in time.
    rand capability_id_t capability_to_operate_on;

    // right capability to operate on
    // currently only used for merge
    rand capability_id_t capability_to_operate_on_right;

    // capability that the MMU will be run against
    rand capability_id_t capability_to_access_in_mmu;

    // the constraint generators cannot always figure out valid operations...
    bit capability_is_mmu_accessible, capability_is_ops_accessible;


    constraint capability_to_operate_on_exists {capability_to_operate_on <= cap_db.max_capability;}

    constraint capability_to_operate_on_right_exists {
      capability_to_operate_on_right <= cap_db.max_capability;
    }

    constraint capability_to_access_exists {capability_to_access_in_mmu <= cap_db.max_capability;}

    // operation to be done
    rand northcape_capability_operation_t operation;

    // in case of create - direction and segment length
    rand bit direction;
    rand segment_length_t new_segment_length;
    // in case of derive - parent offset
    rand segment_length_t parent_offset;

    rand northcape_restrictions_t capability_restrictions;

    rand device_id_t requesting_device_id;
    rand task_id_t requesting_task_id;

    // if this is a data fetch, set-task-id restriction is ignored
    rand bit mmu_access_is_instruction_fetch;
    // jump to / from IRQ context
    rand bit mmu_access_is_irq;
    // read/write in the MMU
    rand axi_test_request_type_t mmu_axi_request_type;
    // number of orphans that sweep should remove
    int orphans;

    constraint capability_restrictions_has_suitable_type {
      // TODO this does not include task_id_bound, set_task_id at the moment
      // the solver often deadlocks after using these restrictions, as accessing capabilities in the MMU and creating new capabilities might become impossible
      capability_restrictions.restriction_type
          inside {NORTHCAPE_RESTRICTIONS_NONE, NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED};
    }

    constraint operation_is_supported {
      // TODO restrict is not supported, because the constraint solver likes to drop all permissions from the root capability, making the MMU side of the test pointless
      // TODO inspect is not supported because the ops scoreboard cannot predict the exact MMIO response
      operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE, NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE, NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE, NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE, NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK, NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP};
    }

    constraint zero_length_segment_not_usable {
      // need at least one byte for the MMU being able to do something with the segment
      new_segment_length > 0;
    }

    constraint segment_length_is_possible {
      if(operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE || operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE){
        cap_db.capability_exists(
            capability_to_operate_on
        ) && new_segment_length <= cap_db.get_capability(
            capability_to_operate_on
        ).segment_length;
      }
    }

    constraint parent_offset_segment_length_are_possible_for_derive {
      if (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE) {
        cap_db.capability_exists(
            capability_to_operate_on
        ) && parent_offset + new_segment_length <= cap_db.get_capability(
            capability_to_operate_on
        ).segment_length;
      }
    }

    constraint create_drop_requires_no_refcount {
      if(operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE || operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP){
        cap_db.capability_exists(
            capability_to_operate_on
        ) && cap_db.get_capability(
            capability_to_operate_on
        ).refcount == 0;
      }
    }

    constraint derive_requires_suitable_refcount {
      if (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE || operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE) {
        cap_db.capability_exists(
            capability_to_operate_on
        ) && cap_db.get_capability(
            capability_to_operate_on
        ).refcount != '1;
      }
    }

    constraint create_revoke_lock_require_direct_capability {
      if (operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE, NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK}) {
        cap_db.capability_exists(
            capability_to_operate_on
        ) && cap_db.get_capability(
            capability_to_operate_on
        ).capability_type == NORTHCAPE_CMT_DIRECT;
      }
    }
    // this limit is somewhat arbitrary
    // it prevents the verification from running for many hours 
    localparam segment_length_t MAX_CAPABILITY_LENGTH_FOR_REVOKE = 1024 * axi5::AXI5_MAX_BURST_LEN;

    constraint revoke_requires_small_capability {
      if (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE) {
        cap_db.capability_exists(
            capability_to_operate_on
        ) && cap_db.get_capability(
            capability_to_operate_on
        ).segment_length <= MAX_CAPABILITY_LENGTH_FOR_REVOKE;
      }
    }

    constraint derive_requires_direct_or_indirect_capability {
      if (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE) {
        cap_db.capability_exists(
            capability_to_operate_on
        ) && (cap_db.get_capability(
            capability_to_operate_on
        ).capability_type == NORTHCAPE_CMT_DIRECT || cap_db.get_capability(
            capability_to_operate_on
        ).capability_type == NORTHCAPE_CMT_INDIRECT);
      }
    }

    constraint drop_requires_indirect_or_lock_holder_capability {
      if (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP) {
        cap_db.capability_exists(
            capability_to_operate_on
        ) && cap_db.get_capability(
            capability_to_operate_on
        ).capability_type inside {NORTHCAPE_CMT_INDIRECT, NORTHCAPE_CMT_LOCK_HOLDER};
      }
    }

    constraint capability_was_not_deleted {
      cap_db.capability_exists(
          capability_to_operate_on
      ) && cap_db.get_capability(
          capability_to_operate_on
      ).was_deleted == 1'b0;
    }

    constraint operations_except_drop_require_unlocked_capability {
      // drop on the lock-holder itself works, because the lock holder is not marked as lock
      // drop on anything below the lock holder should fail
      if (!(operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE})) {
        cap_db.capability_exists(
            capability_to_operate_on
        ) && cap_db.get_capability(
            capability_to_operate_on
        ).is_locked == 1'b0;
      }
    }

    constraint merge_requires_two_adjacent_direct_capabilities_without_references {
      if (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE) {
        cap_db.capability_exists(
            capability_to_operate_on
        ) && cap_db.get_capability(
            capability_to_operate_on
        ).was_deleted == 1'b0 && cap_db.get_capability(
            capability_to_operate_on
        ).refcount == 0;
        cap_db.capability_exists(
            capability_to_operate_on_right
        ) && cap_db.get_capability(
            capability_to_operate_on_right
        ).was_deleted == 1'b0 && cap_db.get_capability(
            capability_to_operate_on_right
        ).refcount == 0;
        cap_db.capability_exists(
            capability_to_operate_on
        ) && cap_db.capability_exists(
            capability_to_operate_on_right
        ) && cap_db.get_capability(
            capability_to_operate_on
        ).base + cap_db.get_capability(
            capability_to_operate_on
        ).segment_length == cap_db.get_capability(
            capability_to_operate_on_right
        ).base;
        cap_db.capability_exists(
            capability_to_operate_on
        ) && cap_db.get_capability(
            capability_to_operate_on
        ).capability_type == NORTHCAPE_CMT_DIRECT;
        cap_db.capability_exists(
            capability_to_operate_on_right
        ) && cap_db.get_capability(
            capability_to_operate_on_right
        ).capability_type == NORTHCAPE_CMT_DIRECT;
      }
    }

    function void post_randomize();
      bit is_mmu_accessible, is_locked_right_now;
      unique case (operation)
        NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE: begin
          if (cap_db.get_capability(capability_to_operate_on).refcount != 0) begin
            `uvm_fatal(COMPONENT_NAME, "Capability to operate on does not have reference count 0!");
          end

        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE: begin
          // nothing to do - constraints + test take care of everything  
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
          // nothing to do
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE: begin
          // nothing to do
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE: begin
          // nothing to do
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE: begin
          // nothing to do
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
          // nothing to do
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP: begin
          orphans = cap_db.count_orphans();
        end
        default: begin
          `uvm_fatal(
              COMPONENT_NAME, $sformatf(
              "Unknown / unsupported operation %d (%s) generated!", operation, operation.name()));
        end
      endcase

      if (operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE) begin
        capability_is_ops_accessible = cap_db.capability_is_ops_accessible(
            capability_to_operate_on, requesting_device_id, requesting_task_id, operation) &&
            cap_db.capability_is_ops_accessible(
            capability_to_operate_on_right, requesting_device_id, requesting_task_id, operation);
      end else begin
        capability_is_ops_accessible = cap_db.capability_is_ops_accessible(
            capability_to_operate_on, requesting_device_id, requesting_task_id, operation);
      end

      if (!capability_is_ops_accessible) begin
        `uvm_warning(COMPONENT_NAME, "Capability is not ops accessible!");
      end

      is_mmu_accessible =
          cap_db.capability_is_mmu_accessible(capability_to_access_in_mmu, mmu_access_is_irq);
      is_locked_right_now =
          cap_db.capabilities_are_related(capability_to_access_in_mmu, capability_to_operate_on) &&
          operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK;
      capability_is_mmu_accessible = is_mmu_accessible && !is_locked_right_now;
      // if we lock the base direct capability capability in the same integration transaction as we access it, this is NOT picked up yet by the is_mmu_accessible check, as this has not been entered into the DB yet
      if (!capability_is_mmu_accessible) begin
        `uvm_warning(COMPONENT_NAME, $sformatf(
                     "Capability is not MMU accessible - expect invalid test on MMU side! Is MMU accessible %b is locked in this operation %b",
                     is_mmu_accessible,
                     is_locked_right_now
                     ));
      end else begin
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Capability is MMU accessible - expect valid test on MMU side! Is MMU accessible %b is locked in this operation %b",
                  is_mmu_accessible,
                  is_locked_right_now
                  ), UVM_DEBUG);
      end
    endfunction

    function void do_copy(uvm_object rhs);
      NorthcapeIntegrationTransaction other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "Copy RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      capability_to_operate_on = other_transaction.capability_to_operate_on;
      capability_to_operate_on_right = other_transaction.capability_to_operate_on_right;
      operation = other_transaction.operation;
      direction = other_transaction.direction;
      new_segment_length = other_transaction.new_segment_length;
      mmu_access_is_instruction_fetch = other_transaction.mmu_access_is_instruction_fetch;
      mmu_access_is_irq = other_transaction.mmu_access_is_irq;
      mmu_axi_request_type = other_transaction.mmu_axi_request_type;
      orphans = other_transaction.orphans;
      capability_is_mmu_accessible = other_transaction.capability_is_mmu_accessible;
      capability_is_ops_accessible = other_transaction.capability_is_ops_accessible;
    endfunction

    function string convert2string();

      return $sformatf(
          "capability id %d right capability id %d operation %x (%s) direction %b new length %d is instruction fetch %b is IRQ %b MMU request type %s is mmu accessible? %b is ops accessible? %b orphans %d",
          capability_to_operate_on,
          capability_to_operate_on_right,
          operation,
          operation.name(),
          direction,
          new_segment_length,
          mmu_access_is_instruction_fetch,
          mmu_access_is_irq,
          mmu_axi_request_type.name(),
          capability_is_mmu_accessible,
          capability_is_ops_accessible,
          orphans
      );

    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      NorthcapeIntegrationTransaction other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "Compare RHS is null!");
      end

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      return capability_to_operate_on == other_transaction.capability_to_operate_on &&
        capability_to_operate_on_right == other_transaction.capability_to_operate_on_right &&
        operation == other_transaction.operation &&
        direction == other_transaction.direction &&
        new_segment_length == other_transaction.new_segment_length &&
        mmu_access_is_instruction_fetch == other_transaction.mmu_access_is_instruction_fetch &&
        mmu_access_is_irq == other_transaction.mmu_access_is_irq &&
        mmu_axi_request_type == other_transaction.mmu_axi_request_type &&
        capability_is_mmu_accessible == other_transaction.capability_is_mmu_accessible &&
        capability_is_ops_accessible == other_transaction.capability_is_ops_accessible &&
        orphans == other_transaction.orphans;
    endfunction


  endclass
endpackage
