/**
 * Agent for Northcape integration testing.
 */
package northcape_integration_agent;


  import axi5::*;
  import northcape_test::*;
  import northcape_types::*;
  import northcape_mmu_agent::NorthcapeMMUAgent;
  import northcape_capability_ops_agent::NorthcapeCapabilityOpsAgent;

  import northcape_mmu_transaction::NorthcapeMMUTransaction;
  import northcape_capability_ops_transaction::NorthcapeCapabilityOpsTransaction;
  import northcape_sparse_mem_sim::NorthcapeSparseMem;
  import northcape_cmt_parser_pkg::northcape_cmt_parser;
  import northcape_generator::NorthcapeGenerator;
  import northcape_integration_transaction::NorthcapeIntegrationTransaction;
  import northcape_integration_transaction::NorthcapeIntegrationCapabilityDatabase;
  import northcape_capability_resolver_common::NorthcapeCapabilityResolverHash;
  import northcape_capability_ops_common::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class automatic NorthcapeIntegrationAgentConfig #(
      parameter AXI_DATA_WIDTH_OPS = -1,
      parameter AXI_ADDR_WIDTH_OPS = -1,
      parameter bit HAS_CACHE_INTERFACE = 1'b0
  );

    typedef logic [AXI_DATA_WIDTH_OPS-1:0] mem_content_t[$];
    typedef logic [AXI_ADDR_WIDTH_OPS-1:0] mem_index_t;

    typedef NorthcapeSparseMem#(
        .QUEUE_TYPE(mem_content_t),
        .DATA_TYPE(logic [AXI_DATA_WIDTH_OPS-1:0]),
        .INDEX_TYPE(mem_index_t),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH_OPS),
        .ZERO_IF_NOT_EXISTS(HAS_CACHE_INTERFACE)
    ) sparse_mem_t;

    sparse_mem_t northcape_cmt_memory;

    function new(sparse_mem_t northcape_cmt_memory);
      this.northcape_cmt_memory = northcape_cmt_memory;
    endfunction


  endclass


  class automatic NorthcapeIntegrationAgent #(
      // parameters for AXI interfaces (MMU)
      parameter AXI_DATA_WIDTH_MMU = -1,
      parameter AXI_ADDR_WIDTH_MMU = -1,
      parameter AXI_ID_WIDTH_MMU   = -1,
      parameter AXI_USER_WIDTH_MMU = -1,

      // parameters for AXI interfaces (Ops)
      parameter AXI_DATA_WIDTH_OPS = -1,
      parameter AXI_ADDR_WIDTH_OPS = -1,
      parameter AXI_ID_WIDTH_OPS   = -1,
      parameter AXI_USER_WIDTH_OPS = -1,

      // MMU channel IDs
      parameter device_id_t READ_CHAN_DEVICE_ID  = -1,
      parameter device_id_t WRITE_CHAN_DEVICE_ID = -1,

      // parameters AXI Lite interface (ops MMIO)
      parameter AXI_LITE_DATA_WIDTH = -1,
      parameter AXI_LITE_ADDR_WIDTH = -1,

      // capability ops hash type
      parameter int HASH_TYPE = -1,

      // default CMT for ops
      parameter bit [AXI_ADDR_WIDTH_OPS-1:0] INITIAL_CMT_BASE = -1,
      parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1,

      parameter string TRANSACTIONS_QUEUE_NAME_AGENT_MMU = "",
      parameter string TRANSACTIONS_QUEUE_NAME_AGENT_OPS = "",
      parameter string TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION = "",
      parameter string CAPABILITY_OPS_AGENT_CONFIG_NAME = "",
      parameter string MMU_AGENT_CONFIG_NAME = "",

      parameter string CAPABILITY_OPS_AXI_LITE_INTERFACE_NAME = "",

      parameter string INTEGRATION_AGENT_CONFIG_NAME = "",

      parameter bit HAS_CACHE_INTERFACE = 1'b0,

      parameter northcape_capability_ops_tag_method_t OPS_TAG_METHOD = NORTHCAPE_CAPABILITY_OPS_CBC,
      parameter BRAM_DATA_WIDTH = -1,
      parameter BRAM_DATA_DEPTH = -1
  ) extends uvm_agent;

    localparam string COMPONENT_NAME = "Northcape Integration Agent";

    typedef logic [AXI_DATA_WIDTH_OPS-1:0] mem_content_t[$];
    typedef logic [AXI_ADDR_WIDTH_OPS-1:0] mem_index_t;


    typedef NorthcapeIntegrationCapabilityDatabase#(AXI_ADDR_WIDTH_OPS) cap_db_t;

    typedef NorthcapeSparseMem#(
        .QUEUE_TYPE(mem_content_t),
        .DATA_TYPE(logic [AXI_DATA_WIDTH_OPS-1:0]),
        .INDEX_TYPE(mem_index_t),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH_OPS),
        .ZERO_IF_NOT_EXISTS(HAS_CACHE_INTERFACE)
    ) sparse_mem_t;

    sparse_mem_t northcape_cmt_memory;

    typedef NorthcapeIntegrationAgentConfig#(
        .AXI_ADDR_WIDTH_OPS(AXI_ADDR_WIDTH_OPS),
        .AXI_DATA_WIDTH_OPS(AXI_DATA_WIDTH_OPS),
        .HAS_CACHE_INTERFACE(HAS_CACHE_INTERFACE)
    ) integration_config_t;

    integration_config_t agent_config;

    typedef NorthcapeIntegrationTransaction#(AXI_ADDR_WIDTH_OPS) integration_transaction_t;


    typedef NorthcapeMMUAgent#(
        .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
        .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MMU),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH_MMU),
        .AXI_ID_WIDTH(AXI_ID_WIDTH_MMU),
        .AXI_USER_WIDTH(AXI_USER_WIDTH_MMU),
        .CHECK_RESOLVER_RESULT(0),

        .TRANSACTIONS_QUEUE_NAME_AGENT(TRANSACTIONS_QUEUE_NAME_AGENT_MMU),
        .MMU_AGENT_CONFIG_NAME(MMU_AGENT_CONFIG_NAME),
        .CHECK_CMT_OVERLAP(0)
    ) mmu_agent_t;

    typedef NorthcapeMMUTransaction#(
        .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
        .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MMU),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH_MMU),
        .AXI_USER_WIDTH(AXI_USER_WIDTH_MMU),
        .AXI_ID_WIDTH(AXI_ID_WIDTH_MMU),
        // CMT is assumed to live in its separate memory for now
        .CHECK_CMT_OVERLAP(0)
    ) mmu_transaction_t;

    typedef NorthcapeGenerator#(mmu_transaction_t) mmu_gen_t;

    typedef NorthcapeCapabilityOpsTransaction#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH_OPS),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH_OPS),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH_OPS),
        .AXI_USER_WIDTH(AXI_USER_WIDTH_OPS),

        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),

        .HASH_TYPE(HASH_TYPE),
        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) ops_transaction_t;

    typedef NorthcapeCapabilityOpsAgent#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH_OPS),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH_OPS),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH_OPS),
        .AXI_USER_WIDTH(AXI_USER_WIDTH_OPS),

        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),

        .HASH_TYPE(HASH_TYPE),

        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2),

        .TRANSACTIONS_QUEUE_NAME_AGENT(TRANSACTIONS_QUEUE_NAME_AGENT_OPS),
        .CAPABILITY_OPS_AGENT_CONFIG_NAME(CAPABILITY_OPS_AGENT_CONFIG_NAME),

        .AXI_LITE_INTERFACE_NAME(CAPABILITY_OPS_AXI_LITE_INTERFACE_NAME),
        // integration test - this is already checked in unit test
        .CHECK_AXI_TRANSACTIONS(0),
        // no RNG interface - use real generator
        .RNG_INTERFACE_NAME(""),
        .PROVIDE_RNG_INTERFACE(0),
        .OPS_TAG_METHOD(OPS_TAG_METHOD),
        .BRAM_DATA_WIDTH(BRAM_DATA_WIDTH),
        .BRAM_DATA_DEPTH(BRAM_DATA_DEPTH),
    ) ops_agent_t;

    typedef NorthcapeCapabilityResolverHash#(.HASH_TYPE(HASH_TYPE)) hash_t;

    capability_id_t created_capabilities[capability_type_t];


    mmu_agent_t mmu_agent;
    ops_agent_t ops_agent;

    semaphore transactions_available_event_mmu, transactions_available_event_ops;
    semaphore mmu_finished, ops_finished;

    cap_db_t cap_db;

    function new(string name = "", uvm_component parent);
      super.new(name, parent);

      // root capability (implicitly)
      created_capabilities[OFFSET_32_BIT] = 1;

      created_capabilities[OFFSET_24_BIT] = 0;
      created_capabilities[OFFSET_16_BIT] = 0;
      created_capabilities[OFFSET_8_BIT]  = 0;

      cap_db = cap_db_t::get_inst();
    endfunction

    // due to back-off mechanism, created ID n can have number n+x
    // we keep an array of the created IDs, which we look the given ID up in
    function capability_id_t translate_capability_id(capability_id_t capability_number);
      capability_id_t ret;
      if(!cap_db.capability_exists(capability_number))
      begin
        `uvm_fatal(COMPONENT_NAME,$sformatf("Could not find capability number %d in DB!",capability_number));
      end
      ret = capability_accessors#(AXI_ADDR_WIDTH_OPS)::capability_get_id(cap_db.get_capability(capability_number).token);
      
      `uvm_info(COMPONENT_NAME,$sformatf("Resolved capability number %d to physical ID %d (token %x)!",capability_number,ret,cap_db.get_capability(capability_number).token),UVM_DEBUG);

      return ret;
    endfunction

    function void build_phase(uvm_phase phase);
      mmu_agent = new("MMU Agent", this);
      ops_agent = new("Operations Agent", this);

      if (uvm_config_db#(integration_config_t)::get(
              this, "", INTEGRATION_AGENT_CONFIG_NAME, agent_config
          ) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not get integration agent config!");
      end

      this.northcape_cmt_memory = agent_config.northcape_cmt_memory;

      this.transactions_available_event_mmu = new();
      this.transactions_available_event_ops = new();

      this.mmu_finished = new();
      this.ops_finished = new();

      this.ops_agent.ops_transactions_available = transactions_available_event_ops;
      this.ops_agent.ops_finished = ops_finished;

      this.mmu_agent.mmu_transactions_available = transactions_available_event_mmu;
      this.mmu_agent.mmu_finished = mmu_finished;
    endfunction

    function northcape_cmt_entry_t lookup_capability(input capability_id_t key);
      capability_id_t hashed_key;
      bit [AXI_ADDR_WIDTH_OPS-1:0] lookup_addr;
      mem_content_t memory_content;

      hashed_key = hash_t::compute_hash(key, INITIAL_CMT_SIZE_CLOG2);
      lookup_addr = hashed_key * $bits(northcape_cmt_entry_t) / 8 + INITIAL_CMT_BASE;
      // guaranteed to fit in 1 entry
      memory_content = northcape_cmt_memory.read_mem(lookup_addr, 1);

      if (memory_content.size() != 1) begin
        `uvm_fatal(COMPONENT_NAME, $sformatf(
                   "Memory content for lookup addr %x has wrong length %d!",
                   lookup_addr,
                   memory_content.size()
                   ));
      end

      return memory_content.pop_front();
    endfunction

    typedef NorthcapeCapabilityOpsGenerator#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH_OPS),
        .HASH_TYPE(HASH_TYPE)
    ) gen_t;

    protected function capability_type_t select_capability_type(
        input integration_transaction_t transaction, output bit capability_length_satisfyable);
      capability_length_satisfyable = 1;

      if (transaction.new_segment_length < max_length_for_capability_type(
              OFFSET_8_BIT
          ) && created_capabilities[OFFSET_8_BIT] < NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_8) begin
        return OFFSET_8_BIT;
      end

      if (transaction.new_segment_length < max_length_for_capability_type(
              OFFSET_16_BIT
          ) && created_capabilities[OFFSET_16_BIT] < NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_16) begin
        return OFFSET_16_BIT;
      end

      if (transaction.new_segment_length < max_length_for_capability_type(
              OFFSET_24_BIT
          ) && created_capabilities[OFFSET_24_BIT] < NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_24) begin
        return OFFSET_24_BIT;
      end

      if (transaction.new_segment_length < max_length_for_capability_type(
              OFFSET_32_BIT
          ) && created_capabilities[OFFSET_32_BIT] < NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_32) begin
        return OFFSET_32_BIT;
      end

      capability_length_satisfyable = 0;
      return OFFSET_32_BIT;


    endfunction

    protected function ops_transaction_t generate_ops_transaction(
        input integration_transaction_t current_transaction, input bit first);
      ops_transaction_t ops_transaction;
      northcape_cmt_entry_t input_cmt_entry;
      capability_id_t translated_capability, translated_capability_right;
      bit capability_length_satisfyable;

      // SWEEP has no args
      if(current_transaction.operation != NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP)
      begin
        translated_capability = translate_capability_id(current_transaction.capability_to_operate_on);
      
        // otherwise possibly undef
        if(current_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE)
        begin
          translated_capability_right = translate_capability_id(current_transaction.capability_to_operate_on_right);
        end
      end

      ops_transaction = new("Ops transaction");

      // we will over-write everything we care about and leave the rest random
      if (ops_transaction.randomize() != 1) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize Ops transaction!");
      end

      ops_transaction.intended_capability_type =
          select_capability_type(current_transaction, capability_length_satisfyable);

      if(current_transaction.operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE, NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT, NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP})
      begin
        // never an issue for certain operations
        capability_length_satisfyable = 1;
      end


      if (translated_capability != NORTHCAPE_ROOT_CAPABILITY_ID || !first) begin
        input_cmt_entry = lookup_capability(translated_capability);
      end else begin
        input_cmt_entry = gen_t::generate_root_capability();
      end

      if (!capability_length_satisfyable) begin
        `uvm_warning(
            COMPONENT_NAME, $sformatf(
            "Could not create capability with length %d", current_transaction.new_segment_length));
      end else begin
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Selected capability type %s for segment length %d",
                  ops_transaction.intended_capability_type.name(),
                  current_transaction.new_segment_length
                  ), UVM_HIGH);
      end

      ops_transaction.direction = current_transaction.direction;

      // integration test only tests valid scenarios
      // tests for individual components are responsible for catching outliers
      ops_transaction.valid_test  = capability_length_satisfyable && current_transaction.capability_is_ops_accessible;
      // token includes encoding, such as capability type etc.
      if(current_transaction.operation != NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP)
      begin
        ops_transaction.input_token = cap_db.get_capability(current_transaction.capability_to_operate_on).token;
      end
      else
      begin
        // no input
        ops_transaction.input_token = '0;
        // always valid
        ops_transaction.valid_test = 1'b1;
      end

      if(current_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE)
      begin
        ops_transaction.input_token_right = cap_db.get_capability(current_transaction.capability_to_operate_on_right).token;
        ops_transaction.input_cmt_entry_right = lookup_capability(translated_capability_right);

        // basic sanity check found in regression testing
        if(input_cmt_entry.capability_type != NORTHCAPE_CMT_DIRECT || ops_transaction.input_cmt_entry_right.capability_type != NORTHCAPE_CMT_DIRECT || input_cmt_entry.location.physical_location.base + input_cmt_entry.location.physical_location.length != ops_transaction.input_cmt_entry_right.location.physical_location.base || input_cmt_entry.refcount != 0|| ops_transaction.input_cmt_entry_right.refcount != 0)
        begin
          `uvm_fatal(COMPONENT_NAME,$sformatf("I was given invalid capabilities for merge: left %s right %s",print_cmt_entry(input_cmt_entry),print_cmt_entry(ops_transaction.input_cmt_entry_right)));
        end
      end

      ops_transaction.device_id_restriction = current_transaction.capability_restrictions.body.task_restriction.device_id;
      ops_transaction.task_id_restriction = current_transaction.capability_restrictions.body.task_restriction.task_id;
      ops_transaction.device_interpreted_restriction = current_transaction.capability_restrictions.body.device_interpreted_bits;
      ops_transaction.restriction_type = current_transaction.capability_restrictions.restriction_type;
      // this is somewhat duplicated, but for restrict it actually matters
      ops_transaction.restriction_enabled = current_transaction.capability_restrictions.restriction_type != NORTHCAPE_RESTRICTIONS_NONE;

      // these values only ever matter when the source is exactly the same
      ops_transaction.device_id_current = current_transaction.requesting_device_id;
      ops_transaction.task_id_current = current_transaction.requesting_task_id;

      // TODO make this variable
      ops_transaction.read_perm = 1'b1;
      ops_transaction.write_perm = 1'b1;
      ops_transaction.x_perm = 1'b1;
      ops_transaction.irq_accessible_perm = 1'b1;
      ops_transaction.lockable_perm = 1'b1;
      ops_transaction.cacheable_tlb_perm = 1'b1;
      ops_transaction.cacheable_access_perm = 1'b1;
      
      // inspect is not one of the operations we test here
      ops_transaction.use_isr_fsm = 1'b0;

      ops_transaction.parent_offset = current_transaction.parent_offset;

      if (current_transaction.operation != NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP && !ops_transaction.read_perm && !ops_transaction.write_perm) begin
        // in this case, generating an MMU transaction would time out
        if (input_cmt_entry.permissions.direct_capability_permissions.read_permission) begin
          ops_transaction.read_perm = 1;
        end
        else if(input_cmt_entry.permissions.direct_capability_permissions.write_permission)
        begin
          ops_transaction.write_perm = 1;
        end else begin
          `uvm_warning(COMPONENT_NAME, "Input capability has neither read or write perm!");
          ops_transaction.valid_test = 0;
        end
      end

      ops_transaction.operation = current_transaction.operation;

      ops_transaction.input_cmt_entry = input_cmt_entry;
      ops_transaction.orphans = current_transaction.orphans;

      if(current_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT)
      begin
        ops_transaction.new_segment_length = current_transaction.new_segment_length;
      end

      if(!(current_transaction.operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE, NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE, NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP}))
      begin

        if (current_transaction.new_segment_length > northcape_cmt_parser::entry_get_phys_length(
                input_cmt_entry
            )) begin
          segment_length_t old_length;
          old_length = current_transaction.new_segment_length;
          current_transaction.new_segment_length =
              $urandom_range(northcape_cmt_parser::entry_get_phys_length(input_cmt_entry), 1);

          `uvm_info(COMPONENT_NAME, $sformatf(
                    "Truncated new segment length from %d to %d",
                    old_length,
                    current_transaction.new_segment_length
                    ), UVM_HIGH);
        end

        if(current_transaction.new_segment_length == 0 || northcape_cmt_parser::entry_get_phys_length(
                input_cmt_entry
            ) == 0 || input_cmt_entry.capability_type == NORTHCAPE_CMT_INVALID) begin
          `uvm_warning(COMPONENT_NAME,
                      "Dropped segment length to 0 or invalid/0-length input capability!");
          // 0 length is not supported - expect error
          ops_transaction.valid_test = 0;
        end

        ops_transaction.new_segment_length = current_transaction.new_segment_length;

        if (ops_transaction.valid_test) begin
          // drop removes one cap, revoke keeps the number the same
          // all other operations add one capability
          if(ops_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP)
          begin
            created_capabilities[ops_transaction.intended_capability_type]--;
          end
          else if(ops_transaction != NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE)
          begin
            created_capabilities[ops_transaction.intended_capability_type]++;
          end
        end

      end

      return ops_transaction;
    endfunction

    localparam MAX_MMU_ATTEMPTS = 1024;

    protected function mmu_transaction_t generate_mmu_transaction(
        input bit [AXI_ADDR_WIDTH_MMU-1:0] last_created_token,
        input northcape_capability_operation_t last_operation,
        bit is_fetch,
        bit is_irq,
        axi_test_request_type_t mmu_axi_request_type,
        bit capability_is_mmu_accessible = 1'b1);
      capability_id_t last_capability_id;
      northcape_cmt_entry_t mmu_capability, bounds_check_capability;
      mmu_transaction_t ret;
      int unsigned number_attempts;
      int unsigned fails_invalid;
      int unsigned fails_test_mode;
      int unsigned fails_len;

      number_attempts = 0;

      last_capability_id =
          capability_accessors#(AXI_ADDR_WIDTH_MMU)::capability_get_id(last_created_token);
      mmu_capability = lookup_capability(last_capability_id);

      // lock holder capability has no base/length!
      if(mmu_capability.capability_type == NORTHCAPE_CMT_LOCK_HOLDER)
      begin
        capability_id_t parent_id;

        parent_id = capability_accessors#(AXI_ADDR_WIDTH_MMU)::capability_get_id(mmu_capability.location.lock_holder_location.parent);
        bounds_check_capability = lookup_capability(parent_id);
      end
      else
      begin
        bounds_check_capability = mmu_capability;
      end

      `uvm_info(COMPONENT_NAME,$sformatf("I have retrieved capability entry %s for ID %x tag %x!",print_cmt_entry(mmu_capability),last_capability_id,last_created_token),UVM_DEBUG);

      forever begin : genValidTransaction
        bit broke_inner;
        bit invalid_access;

        invalid_access = 1'b0;

        if(!capability_is_mmu_accessible)
        begin
          `uvm_warning(COMPONENT_NAME,$sformatf("Assuming capability %x not MMU accessible!",last_created_token));
          invalid_access = 1'b1;
        end

        broke_inner = 1'b0;

        ret = mmu_gen_t::generate_transaction_ephemeral();

        ret.instruction_fetch = is_fetch;
        ret.is_irq = is_irq;

        // TODO this implies offset=0
        ret.capability_token = last_created_token;
        ret.physical_address = northcape_cmt_parser::entry_get_phys_addr(bounds_check_capability);
        ret.resolver_response.address = ret.physical_address;
        ret.resolver_response.segment_length =
            northcape_cmt_parser::entry_get_phys_length(bounds_check_capability);
        ret.resolver_response_restriction = mmu_capability.restrictions.restriction_type;
        ret.resolver_response.restriction = mmu_capability.restrictions.body;
        ret.axi_request_type = mmu_axi_request_type;
        if(ret.physical_address % (AXI_ADDR_WIDTH_MMU/8))
        begin
          // single-byte transfer - avoids potential alignment error
          ret.test_size = '0;
        end
        
        if(number_attempts == MAX_MMU_ATTEMPTS)
        begin
          `uvm_warning(COMPONENT_NAME,"Invalid access - timeout!");
          invalid_access = 1'b1;
        end

        // lock holder is always 0-length
        if(northcape_cmt_parser::entry_get_phys_length(
                bounds_check_capability) == 0)
        begin
          `uvm_warning(COMPONENT_NAME,"Zero-length capability!");
          invalid_access = 1'b1;
        end

        if(mmu_capability.capability_type == NORTHCAPE_CMT_INVALID)
        begin
          `uvm_warning(COMPONENT_NAME,"Invalid / destroyed capability!");
          invalid_access = 1'b1;
        end

        if(mmu_capability.tag != capability_accessors#(AXI_ADDR_WIDTH_MMU)::capability_get_tag(last_created_token))
        begin
          // we have already checked whether the capability is invalid
          `uvm_warning(COMPONENT_NAME,"Tag mismatch for retrieved capability!");
          invalid_access = 1'b1;
        end

        if (invalid_access) begin

          ret.invalid_access = 1;

          // MMU should error out and not even forward the request
          ret.expected_response = DECERR;
          
          ret.post_randomize();

          `uvm_warning(COMPONENT_NAME, $sformatf(
                       "Timed out trying to figure out valid MMU access for capability id %d CMT entry %s: fails invalid %d fails test mode %d fails len %d",
                       last_capability_id,
                       print_cmt_entry(
                           mmu_capability
                       ),
                       fails_invalid,
                       fails_test_mode,
                       fails_len
                       ));

          return ret;
        end

        if (number_attempts && number_attempts % 1024 == 0) begin
          `uvm_warning(COMPONENT_NAME, $sformatf(
                       "Have already used %d attempts to find a valid MMU request", number_attempts
                       ));
        end

        number_attempts++;

        if (ret.invalid_access) begin
          fails_invalid++;
          continue;
        end

        // TODO WRAP bursts are difficult to constrain and test
        // also currently not used at all in the capability SoC
        // WRAP bursts are already tested in the MMU itself
        if(ret.burst_type == WRAP)begin
          fails_invalid++;
          continue;
        end

        unique case (ret.axi_request_type)
          AXI_TEST_READ: begin
            if (!mmu_capability.permissions.direct_capability_permissions.read_permission) begin
              fails_test_mode++;
              continue;
            end
          end
          AXI_TEST_WRITE: begin
            if (!mmu_capability.permissions.direct_capability_permissions.write_permission) begin
              fails_test_mode++;
              continue;
            end
            if (ret.atomic_type != ATOMIC_NONE && ret.atomic_type != ATOMIC_STORE) begin
              if (!mmu_capability.permissions.direct_capability_permissions.read_permission) begin
                fails_test_mode++;
                continue;
              end
            end
          end
        endcase

        while (ret.get_bytes_in_burst() > northcape_cmt_parser::entry_get_phys_length(
            bounds_check_capability
        )) begin
          if(ret.get_bytes_in_burst() <= AXI_DATA_WIDTH_MMU/8 && northcape_cmt_parser::entry_get_phys_length(
            bounds_check_capability) <= AXI_DATA_WIDTH_MMU/8 && northcape_cmt_parser::entry_get_phys_length(
            bounds_check_capability) > 0)
            begin
              // for accesses <= 1 beat, the MMU will accept and mask the access
              // each otherwise valid capability must allow access to >= 1 byte
              break;
            end
          if (ret.test_len == 0) begin
            // exhausted adjustments - try again
            // break inner loop first
            broke_inner = 1'b1;
            break;
          end
          ret.test_len--;
        end

        if (broke_inner) begin
          fails_test_mode++;
          continue;
        end

        // masks etc. might have changed
        ret.post_randomize();

        `uvm_info(COMPONENT_NAME, $sformatf("Created MMU transaction %s", ret.convert2string()),
                  UVM_DEBUG);

        // did not fail any sanity checks - assume valid
        return ret;

      end : genValidTransaction

      `uvm_fatal(COMPONENT_NAME, "Could not create MMU transaction - would have to return null!");
      return null;
    endfunction

    function automatic mmu_transaction_t generate_mmu_transaction_independent(
        axi_test_request_type_t request_type, logic [AXI_ADDR_WIDTH_MMU-1:0] cap_token,
        axi_len_t test_len, axi_burst_t burst_type, axi_size_t test_size, axi_resp_t response,
        axi_atop_t atomic_type = ATOMIC_NONE);
      mmu_transaction_t mmu_transaction;
      bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH_MMU-1:0] test_data;
      axi_test_request_result_t result;

      mmu_transaction = mmu_gen_t::generate_transaction_ephemeral();
      mmu_transaction.invalid_access = 0;

      mmu_transaction.axi_request_type = request_type;
      mmu_transaction.capability_token = cap_token;
      mmu_transaction.test_len = test_len;
      mmu_transaction.burst_type = burst_type;
      mmu_transaction.atomic_type.atop_type = ATOMIC_NONE;
      mmu_transaction.atomic_type.atop_subtype = '0;

      mmu_transaction.resolver_response_restriction = NORTHCAPE_RESTRICTIONS_NONE;
      mmu_transaction.resolver_response.restriction = '0;
      mmu_transaction.resolver_response.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;

      // unused / default
      mmu_transaction.test_id = '0;
      mmu_transaction.test_lock = 0;
      mmu_transaction.test_cache = '0;
      mmu_transaction.test_prot = '0;
      mmu_transaction.test_qos = '0;
      mmu_transaction.test_region = '0;
      mmu_transaction.test_size = test_size;

      mmu_transaction.cmt_base_addr = INITIAL_CMT_BASE;
      mmu_transaction.cmt_size_clog2 = INITIAL_CMT_SIZE_CLOG2;

      // 1:1 translation
      mmu_transaction.physical_address = cap_token;
      mmu_transaction.test_len = test_len;
      mmu_transaction.burst_type = burst_type;
      mmu_transaction.atomic_type.atop_type = atomic_type;
      mmu_transaction.atomic_type.atop_subtype = '0;
      mmu_transaction.given_response = response;
      mmu_transaction.expected_response = response;

      for (int i = 0; i < test_len; i++) begin
        // such that all bits are populated
        test_data[i] = -i;
      end

      mmu_transaction.expected_data = test_data;
      mmu_transaction.response_data = test_data;
      mmu_transaction.write_data = test_data;
      mmu_transaction.expected_write_data = test_data;

      mmu_transaction.write_strobes = '1;
      mmu_transaction.expected_write_strobes = '1;

      return mmu_transaction;


    endfunction

    // must be aligned to be accepted as valid
    localparam logic [AXI_ADDR_WIDTH_MMU-1:0] root_cap_token = 64'hdead0000;
    localparam axi_len_t root_cap_test_len = 1;
    localparam axi_burst_t root_cap_test_burst = INCR;
    localparam axi_size_t root_cap_test_size = $clog2(AXI_DATA_WIDTH_MMU/8);
    localparam axi_resp_t root_cap_test_resp = OKAY;

    // quick smoke test to figure out whether it even makes sense to continue
    function automatic mmu_transaction_t do_mmu_test();
      return generate_mmu_transaction_independent(
          AXI_TEST_READ,
          root_cap_token,
          root_cap_test_len,
          root_cap_test_burst,
          root_cap_test_size,
          root_cap_test_resp
      );
    endfunction

    task run_phase(uvm_phase phase);
      mmu_transaction_t mmu_transaction;
      ops_transaction_t ops_transaction;
      integration_transaction_t integration_transaction;
      capability_id_t last_created_capability_index;

      bit first;

      uvm_queue #(mmu_transaction_t) mmu_queue;
      uvm_queue #(ops_transaction_t) ops_queue;
      uvm_queue #(integration_transaction_t) integration_queue;

      phase.raise_objection(this);


      last_created_capability_index = NORTHCAPE_ROOT_CAPABILITY_ID;


      `uvm_info(COMPONENT_NAME, "Creating initial dummy transaction for MMU", UVM_DEBUG);

      first = 1;

      assert (uvm_config_db#(uvm_queue#(mmu_transaction_t))::get(
          null, "", TRANSACTIONS_QUEUE_NAME_AGENT_MMU, mmu_queue
      ));
      assert (uvm_config_db#(uvm_queue#(ops_transaction_t))::get(
          null, "", TRANSACTIONS_QUEUE_NAME_AGENT_OPS, ops_queue
      ));
      assert (uvm_config_db#(uvm_queue#(integration_transaction_t))::get(
          null, "", TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION, integration_queue
      ));

      while (integration_queue.size() > 0) begin

        integration_transaction = integration_queue.pop_front();

        `uvm_info(COMPONENT_NAME,$sformatf("Have retrieved transaction %s from queue!",integration_transaction.convert2string()),UVM_DEBUG);

        ops_transaction = generate_ops_transaction(integration_transaction, first);
        if(first && integration_transaction.capability_to_operate_on != NORTHCAPE_ROOT_CAPABILITY_ID)
        begin
          `uvm_fatal(COMPONENT_NAME, "First capability ID MUST be root capability ID!");
        end
        // otherwise, by the time we are done, root capability exists
        first = 1'b0;

        ops_queue.push_back(ops_transaction);

        transactions_available_event_ops.put();

        `uvm_info(COMPONENT_NAME, "Waiting for lockstep barrier Ops", UVM_HIGH);
        ops_finished.get();
        `uvm_info(COMPONENT_NAME, "Lockstep barrier Ops released", UVM_HIGH);

        if(integration_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE || integration_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE || integration_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE || integration_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE || integration_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE || integration_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK)
        begin
          bit [AXI_ADDR_WIDTH_OPS-1:0] output_token;

          last_created_capability_index++;
          
          output_token = ops_agent.get_output_capability_token();

          `uvm_info(COMPONENT_NAME, $sformatf("Created capability index %d with token %x!",last_created_capability_index,output_token),UVM_HIGH);

          if(!cap_db.capability_exists(last_created_capability_index))
          begin
            `uvm_fatal(COMPONENT_NAME,"Capability was not expected in test!");
          end
          
          cap_db.get_capability(last_created_capability_index).token = output_token;
        end
        mmu_transaction = generate_mmu_transaction(cap_db.get_capability(integration_transaction.capability_to_access_in_mmu).token,ops_transaction.operation, integration_transaction.mmu_access_is_instruction_fetch, integration_transaction.mmu_access_is_irq, integration_transaction.mmu_axi_request_type, .capability_is_mmu_accessible(integration_transaction.capability_is_mmu_accessible));
        mmu_queue.push_back(mmu_transaction);

        transactions_available_event_mmu.put();

        `uvm_info(COMPONENT_NAME, "Waiting for lockstep barrier MMU", UVM_HIGH);
        mmu_finished.get();
        `uvm_info(COMPONENT_NAME, "Lockstep barrier MMU released", UVM_HIGH);

      end

      // give MMU agent a chance to detect the last transaction and raise objection
      #100ns;

      `uvm_info(COMPONENT_NAME, "Integration agent finished!", UVM_HIGH);
      // both should see the empty queue and finish as well
      transactions_available_event_ops.put();
      transactions_available_event_mmu.put();

      phase.drop_objection(this);

    endtask

  endclass

endpackage
