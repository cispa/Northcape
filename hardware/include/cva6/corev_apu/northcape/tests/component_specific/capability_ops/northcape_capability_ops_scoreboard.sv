/**
  * Test class that predicts capability ops transactions and output.
  */
package northcape_capability_ops_scoreboard;
  import axi5::*;
  import northcape_capability_resolver_common::*;
  import northcape_types::*;
  import northcape_test::*;
  import northcape_generic_checker::NorthcapeGenericCheckerCompItem;
  import northcape_capability_ops_transaction::*;
  import northcape_capability_ops_common::*;
  import northcape_cmt_parser_pkg::northcape_cmt_parser;
  import northcape_mmu_common::NorthcapeMMUCommon;
  import northcape_capability_ops_csr_interface_driver::*;
  import northcape_bram_driver::*;

  // needed to be able to synchronize with the initial key computed by the Ops module
  import northcape_rng_driver::NorthcapeRNGDriver;

  import "DPI-C" function automatic void qarma_cbc_mac(
    const ref bit [3:0][63:0] tag_in,
    const ref bit [127:0] in_key,
    input bit [63:0] tweak,
    output bit [63:0] tag_out
  );
  import "DPI-C" function automatic void qarma_wrapper(
    const ref bit [63:0] in_data,
    const ref bit [127:0] in_key,
    input bit [63:0] tweak,
    output bit [63:0] block_out
  );


  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class automatic NorthcapeCapabilityOpsScoreboard #(
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
      parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1,

      parameter string TRANSACTIONS_QUEUE_NAME_SCOREBOARD = "",


      parameter bit CHECK_AXI_TRANSACTIONS = 1,
      // active in integration test but NOT in module-only test
      parameter bit CHECK_CAPABILITY_COUNT = ~CHECK_AXI_TRANSACTIONS,
      // use CBC MAC of CMT entry or a CTR of the nonce for the tag
      parameter northcape_capability_ops_tag_method_t OPS_TAG_METHOD = NORTHCAPE_CAPABILITY_OPS_CBC,
      parameter BRAM_DATA_WIDTH = -1,
      parameter BRAM_DATA_DEPTH = -1
  ) extends uvm_scoreboard;

    localparam COMPONENT_NAME = "Northcape Capability Ops Scoreboard";

    uvm_tlm_analysis_fifo #(master_result_t) ops_result_fifo;
    uvm_tlm_analysis_fifo #(master_result_t) cache_result_fifo;

    // connected to our checker
    uvm_analysis_port #(NorthcapeGenericCheckerCompItem) checker_port;

    // we have separate counters per capability ID
    capability_id_t current_capability_id[capability_id_t];

    typedef Axi5MasterDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) master_result_t;

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
    ) transaction_t;

    typedef NorthcapeCapabilityOpsGenerator#(
        .HASH_TYPE(HASH_TYPE),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) gen_t;

    typedef AxiLiteResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH)
    ) mmio_result_t;

    typedef NorthcapeCapabilityOpsCSRInterfaceResultTransaction csr_result_t;

    typedef NorthcapeCapabilityOpsTransactionRNGInitial#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_rng_initial_t;


    typedef NorthcapeRNGDriver#(
        .RNG_DATA_WIDTH(NORTHCAPE_CAPABILITY_OPS_RNG_INTERFACE_BITS),
        .INTERFACE_NAME(""),
        .SEQUENCE_ITEM_TYPE(transaction_rng_initial_t),
        .IS_ACTIVE(0)
    ) rng_driver_t;

    // used to re-generate the RNG values given to the ops module
    rng_driver_t rng_driver;

    typedef int unsigned cmt_size_t;

    typedef NorthcapeBRAMRequest#(
        .DATA_WIDTH(BRAM_DATA_WIDTH),
        .DATA_DEPTH(BRAM_DATA_DEPTH)
    ) bram_result_t;

    uvm_tlm_analysis_fifo #(mmio_result_t) mmio_result_fifo;
    uvm_tlm_analysis_fifo #(csr_result_t) csr_result_fifo;
    uvm_tlm_analysis_fifo #(bram_result_t) bram_result_fifo;

    uvm_seq_item_pull_port #(transaction_t, transaction_t) transaction_port;

    // RNG generated during start
    int initial_seed;

    // number of active capabilities - useful to check if we are leaking
    bit [AXI_LITE_DATA_WIDTH-3:0] capability_count;

    northcape_capability_ops_mac_key_t ops_qarma_key;
    bit [63:0] ops_current_nonce;
    northcape_lock_key_t last_used_lock_key;

    function void set_initial_seed(int initial_seed);
      this.initial_seed = initial_seed;
    endfunction

    function void generate_initial_key_nonce();
      transaction_rng_initial_t initial_rng_trans;
      bit [NORTHCAPE_CAPABILITY_OPS_RNG_INTERFACE_BITS-1:0] rng_bits_0, rng_bits_1;
      bit [63:0] nonce_out, data_in;
      bit [127:0] qarma_key;

      initial_rng_trans = new("Scoreboard initial RNG trans");
      initial_rng_trans.initial_seed = initial_seed;

      rng_driver.seed_self(initial_rng_trans);

      rng_bits_0 = rng_driver.generate_random_output();
      rng_bits_1 = rng_driver.generate_random_output();

      qarma_key = {rng_bits_1, rng_bits_0};


      data_in = NORTHCAPE_CAPABILITY_OPS_QARMA_INPUT_KEY_HIGH;
      qarma_wrapper(data_in, qarma_key, '0, ops_qarma_key[127:64]);
      data_in = NORTHCAPE_CAPABILITY_OPS_QARMA_INPUT_KEY_LOW;
      qarma_wrapper(data_in, qarma_key, '0, ops_qarma_key[63:00]);
      data_in = NORTHCAPE_CAPABILITY_OPS_QARMA_INPUT_NONCE;
      qarma_wrapper(data_in, qarma_key, '0, nonce_out);

      // one increment happens for root capability
      ops_current_nonce = nonce_out + 1;

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Scoreboard computed initial nonce %d initial key %x from initial seed %x initial rngs {%x,%x}",
                ops_current_nonce,
                ops_qarma_key,
                initial_seed,
                rng_bits_0,
                rng_bits_1
                ), UVM_MEDIUM);

    endfunction

    function new(string name, uvm_component parent);
      super.new(name, parent);

      last_used_lock_key = '0;
    endfunction

    function void build_phase(uvm_phase phase);
      ops_result_fifo = new("ops_result_fifo", this);
      cache_result_fifo = new("cache_result_fifo", this);

      transaction_port = new("scoreboard_transaction_port", this);

      checker_port = new("checker_port", this);

      mmio_result_fifo = new("mmio_result_fifo");
      csr_result_fifo = new("csr_result_fifo");
      bram_result_fifo = new("bram_result_fifo");


      // Root capability created during reset
      this.current_capability_id[OFFSET_32_BIT] = NORTHCAPE_ROOT_CAPABILITY_ID + 1;
      this.current_capability_id[OFFSET_24_BIT] = NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_32 + 1;
      this.current_capability_id[OFFSET_16_BIT] = NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_24 + 1;
      this.current_capability_id[OFFSET_8_BIT] = NORTHCAPE_MAX_CAPABILITY_ID_OFFSET_16 + 1;

      this.rng_driver = new("Scoreboard RNG driver", this);
    endfunction : build_phase


    const int unsigned max_axi_transfer_bytes = AXI_DATA_WIDTH / 8 * AXI5_MAX_BURST_LEN;


    function master_result_t predict_master_result_zero(bit [AXI_ADDR_WIDTH-1:0] cmt_base,
                                                        int unsigned cmt_size_clog2, bit is_last);
      master_result_t ret;
      cmt_size_t cmt_size;

      axi_len_t axi_length;
      axi_size_t axi_size;


      ret = new("master_result_zero");

      ret.request_type = AXI_TEST_WRITE;

      cmt_size = (1 << cmt_size_clog2) * $bits(northcape_cmt_entry_t) / 8;

      axi_size = $clog2(AXI_DATA_WIDTH / 8);


      if (!is_last) begin
        axi_length = AXI5_MAX_BURST_LEN - 1;
      end else begin
        axi_length = cmt_size % AXI5_MAX_BURST_LEN;
        if (axi_length == 0) begin
          axi_length = AXI5_MAX_BURST_LEN - 1;
        end
      end


      ret.addr = cmt_base;

      ret.len = axi_length;

      ret.burst = INCR;
      ret.size = axi_size;

      ret.write_data = '0;
      ret.write_strobes = '1;

      /**
              * Default from here, not necessary
              */
      ret.lock = 0;
      ret.cache = '0;
      ret.prot = '0;
      ret.qos = '0;
      ret.region = '0;
      ret.id = '0;
      ret.user = '0;

      return ret;
    endfunction

    function master_result_t predict_master_result_insert_root_cap(
        bit [AXI_ADDR_WIDTH-1:0] cmt_base, int unsigned cmt_size_clog2);
      master_result_t ret;
      cmt_size_t cmt_size;

      axi_len_t axi_length;
      axi_size_t axi_size;

      northcape_cmt_entry_t capability_entry = gen_t::generate_root_capability();
      capability_id_t capability_id = NORTHCAPE_ROOT_CAPABILITY_ID;


      ret = new("master_result_zero");

      ret.request_type = AXI_TEST_WRITE;

      cmt_size = (1 << cmt_size_clog2) * $bits(northcape_cmt_entry_t) / 8;

      axi_size = $clog2(AXI_DATA_WIDTH / 8);

      ret.addr = gen_t::get_capability_addr(cmt_base, cmt_size_clog2, capability_id);

      ret.len = 0;

      ret.burst = INCR;
      ret.size = axi_size;

      ret.write_data = capability_entry;
      ret.write_strobes[0] = '1;

      /**
              * Default from here, not necessary
              */
      ret.lock = 0;
      ret.cache = '0;
      ret.prot = '0;
      ret.qos = '0;
      ret.region = '0;
      ret.id = '0;
      ret.user = '0;

      return ret;
    endfunction


    function master_result_t predict_master_result_read_input_cap(
        const ref transaction_t current_transaction, input int unsigned number_indirect_lookup = 0);
      master_result_t ret;
      cmt_size_t cmt_size;

      axi_len_t axi_length;
      axi_size_t axi_size;

      capability_id_t capability_id;

      ret = new("master_result_read_input");

      if (number_indirect_lookup == 0) begin
        capability_id = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
            current_transaction.input_token);
        ret.addr = gen_t::get_capability_addr(current_transaction.cmt_base,
                                              current_transaction.cmt_size_clog2, capability_id);
      end else begin
        ret.addr = current_transaction.recursion_cmt_entries[number_indirect_lookup - 1].get_entry_addr(
            current_transaction.cmt_size_clog2);
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "I have retrieved address %x based on ID %d for recursive lookup %d",
                  ret.addr,
                  current_transaction.recursion_cmt_entries[number_indirect_lookup-1].token_id,
                  number_indirect_lookup - 1
                  ), UVM_DEBUG);
      end



      ret.request_type = AXI_TEST_READ;

      cmt_size = (1 << current_transaction.cmt_size_clog2) * $bits(northcape_cmt_entry_t) / 8;

      axi_size = $clog2(AXI_DATA_WIDTH / 8);

      ret.len = 0;

      ret.burst = INCR;
      ret.size = axi_size;

      /**
              * Default from here, not necessary
              */
      ret.lock = 0;
      ret.cache = '0;
      ret.prot = '0;
      ret.qos = '0;
      ret.region = '0;
      ret.id = '0;
      ret.user = '0;

      return ret;
    endfunction

    function master_result_t predict_master_result_read_input_cap_right(
        const ref transaction_t current_transaction);
      master_result_t ret;
      cmt_size_t cmt_size;

      axi_len_t axi_length;
      axi_size_t axi_size;

      capability_id_t capability_id;

      ret = new("master_result_read_input_right");


      capability_id = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
          current_transaction.input_token_right);
      ret.addr = gen_t::get_capability_addr(current_transaction.cmt_base,
                                            current_transaction.cmt_size_clog2, capability_id);



      ret.request_type = AXI_TEST_READ;

      cmt_size = (1 << current_transaction.cmt_size_clog2) * $bits(northcape_cmt_entry_t) / 8;

      axi_size = $clog2(AXI_DATA_WIDTH / 8);

      ret.len = 0;

      ret.burst = INCR;
      ret.size = axi_size;

      /**
              * Default from here, not necessary
              */
      ret.lock = 0;
      ret.cache = '0;
      ret.prot = '0;
      ret.qos = '0;
      ret.region = '0;
      ret.id = '0;
      ret.user = '0;

      return ret;
    endfunction

    typedef NorthcapeMMUCommon#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .IS_WRITE_CHAN (1)
    ) northcape_mmu_common_t;

    function master_result_t predict_master_result_revoke_write(
        const ref transaction_t current_transaction, int unsigned number_write);
      master_result_t ret;
      axi_size_t axi_size;

      ret = new("master_result_revoke");

      ret.addr = current_transaction.input_cmt_entry.location.physical_location.base + current_transaction.MAX_BYTES_PER_TRANSFER * number_write;



      ret.request_type = AXI_TEST_WRITE;

      axi_size = $clog2(AXI_DATA_WIDTH / 8);

      ret.len = current_transaction.get_revocation_write_len(number_write);

      `uvm_info(COMPONENT_NAME, $sformatf("Got len %d for write num %d", ret.len, number_write),
                UVM_DEBUG);

      ret.burst = INCR;
      ret.size  = axi_size;

      for (int i = 0; i <= ret.len; i++) begin
        ret.write_strobes[i] = northcape_mmu_common_t::get_per_byte_mask_for_addr(
            .current_addr(current_transaction.input_cmt_entry.location.physical_location.base + number_write * current_transaction.MAX_BYTES_PER_TRANSFER + i*(AXI_DATA_WIDTH/8)),
            .segment_start(current_transaction.input_cmt_entry.location.physical_location.base),
            .segment_end(current_transaction.input_cmt_entry.location.physical_location.base + current_transaction.input_cmt_entry.location.physical_location.length)
        );
      end

      /**
              * Default from here, not necessary
              */
      ret.lock = 0;
      ret.cache = '0;
      ret.prot = '0;
      ret.qos = '0;
      ret.region = '0;
      ret.id = '0;
      ret.user = '0;

      return ret;
    endfunction

    function master_result_t predict_master_result_check_occupied(
        const ref transaction_t current_transaction);
      master_result_t ret;
      cmt_size_t cmt_size;

      axi_len_t axi_length;
      axi_size_t axi_size;


      ret = new("master_result_read_input");

      ret.request_type = AXI_TEST_READ;

      cmt_size = (1 << current_transaction.cmt_size_clog2) * $bits(northcape_cmt_entry_t) / 8;

      axi_size = $clog2(AXI_DATA_WIDTH / 8);

      ret.addr = gen_t::get_capability_addr(
          current_transaction.cmt_base,
          current_transaction.cmt_size_clog2,
          current_capability_id[current_transaction.intended_capability_type]
      );

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Predicting capability idle check at addr %x based on ID %d for type %s",
                ret.addr,
                current_capability_id[current_transaction.intended_capability_type],
                current_transaction.intended_capability_type.name()
                ), UVM_DEBUG);

      ret.len = 0;

      ret.burst = INCR;
      ret.size = axi_size;

      /**
              * Default from here, not necessary
              */
      ret.lock = 0;
      ret.cache = '0;
      ret.prot = '0;
      ret.qos = '0;
      ret.region = '0;
      ret.id = '0;
      ret.user = '0;

      // we have to be careful with overflows...
      current_capability_id[current_transaction.intended_capability_type]++;
      current_capability_id[current_transaction.intended_capability_type] &= get_id_mask_for_capability_type(
          current_transaction.intended_capability_type
      );

      return ret;
    endfunction

    northcape_mac_tag_t output_cmt_tag;

    function void set_restrictions(const ref transaction_t current_transaction,
                                   ref northcape_cmt_entry_t ret);
      if (current_transaction.restriction_enabled) begin
        ret.restrictions.restriction_type = current_transaction.restriction_type;
        unique case (current_transaction.restriction_type)
          NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND, NORTHCAPE_RESTRICTIONS_SET_TASK_ID: begin
            ret.restrictions.body.task_restriction.task_id = current_transaction.task_id_restriction;
            ret.restrictions.body.task_restriction.device_id = current_transaction.device_id_restriction;
          end
          NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED: begin
            ret.restrictions.body.device_interpreted_bits = current_transaction.device_interpreted_restriction;
          end
          NORTHCAPE_RESTRICTIONS_NONE: begin
            ret.restrictions.body = '0;
          end
          default: begin
            `uvm_fatal(COMPONENT_NAME, $sformatf(
                       "Unknown restriction type: %s (%d)",
                       current_transaction.restriction_type.name(),
                       current_transaction.restriction_type
                       ));
          end
        endcase

      end
    endfunction

    function northcape_mac_tag_t compute_tag(const ref northcape_cmt_entry_t ret);
      bit [63:0] tag_out;

      unique case (OPS_TAG_METHOD)
        NORTHCAPE_CAPABILITY_OPS_CBC: begin
          bit [3:0][63:0] tag_in;
          tag_in = ret;

          qarma_cbc_mac(tag_in, ops_qarma_key, '0, tag_out);
          `uvm_info(COMPONENT_NAME, $sformatf(
                    "Have computed tag %x for raw capability %x key %x",
                    tag_out[15:0],
                    tag_in,
                    ops_qarma_key
                    ), UVM_DEBUG);
        end
        NORTHCAPE_CAPABILITY_OPS_CTR: begin
          qarma_wrapper(ops_current_nonce, ops_qarma_key, '0, tag_out);
          `uvm_info(COMPONENT_NAME, $sformatf(
                    "Have computed tag %x for current nonce %d key %x",
                    tag_out[15:0],
                    ops_current_nonce,
                    ops_qarma_key
                    ), UVM_DEBUG);
        end
        default: begin
          `uvm_error(COMPONENT_NAME, "Unknown tag method!");
        end
      endcase

      return tag_out[15:0];
    endfunction

    function northcape_cmt_entry_t predict_output_cmt_entry_create(
        const ref transaction_t current_transaction);
      northcape_cmt_entry_t ret;

      ret = '0;

      // must be given a valid direct capability
      ret.capability_type = NORTHCAPE_CMT_DIRECT;
      // lock must be reset
      ret.location.physical_location.locked_key = '0;
      // refcount must be reset
      ret.refcount = '0;

      if (current_transaction.direction == 0) begin
        // new capability is at start of the segment
        ret.location.physical_location.base   = current_transaction.input_cmt_entry.location.physical_location.base;
        ret.location.physical_location.length = current_transaction.new_segment_length;
      end else begin
        ret.location.physical_location.base = current_transaction.input_cmt_entry.location.physical_location.base + current_transaction.input_cmt_entry.location.physical_location.length - current_transaction.new_segment_length;
        ret.location.physical_location.length = current_transaction.new_segment_length;
      end

      set_restrictions(current_transaction, ret);

      // new permissions must be as or more restrictive as the current ones
      if (current_transaction.read_perm) begin
        ret.permissions.direct_capability_permissions.read_permission = 1;
      end
      if (current_transaction.write_perm) begin
        ret.permissions.direct_capability_permissions.write_permission = 1;
      end
      if (current_transaction.x_perm) begin
        ret.permissions.direct_capability_permissions.execute_permission = 1;
      end
      if (current_transaction.lockable_perm) begin
        ret.permissions.direct_capability_permissions.lockable_permission = 1;
      end
      if (current_transaction.irq_accessible_perm) begin
        ret.permissions.direct_capability_permissions.irq_accessible_permission = 1;
      end
      if (current_transaction.cacheable_tlb_perm) begin
        ret.permissions.direct_capability_permissions.cacheable_tlb = 1'b1;
      end
      if (current_transaction.cacheable_access_perm) begin
        ret.permissions.direct_capability_permissions.cacheable_access = 1'b1;
      end

      ret.nonce = ops_current_nonce;

      ret.tag = compute_tag(ret);

      output_cmt_tag = ret.tag;

      return ret;
    endfunction

    function northcape_cmt_entry_t predict_output_cmt_entry_derive(
        const ref transaction_t current_transaction);
      northcape_cmt_entry_t ret;

      ret = '0;

      // must be given a valid direct capability
      ret.capability_type = NORTHCAPE_CMT_INDIRECT;
      // parent is input capability
      ret.location.indirect_location.parent = current_transaction.input_token;
      // 0 is always possible
      void'(capability_accessors#(AXI_ADDR_WIDTH)::capability_set_offset(
          ret.location.indirect_location.parent, 0
      ));
      if (current_transaction.input_cmt_entry.capability_type == NORTHCAPE_CMT_DIRECT) begin
        ret.location.indirect_location.effective_base = current_transaction.input_cmt_entry.location.physical_location.base + current_transaction.parent_offset;
      end else
      if (current_transaction.input_cmt_entry.capability_type == NORTHCAPE_CMT_LOCK_HOLDER) begin
        for (int i = 0; i < current_transaction.recursion_cmt_entries.size(); i++) begin
          ret.location.indirect_location.effective_base = current_transaction.recursion_cmt_entries[i].get_entry().location.indirect_location.effective_base + current_transaction.parent_offset;
          if(current_transaction.recursion_cmt_entries[i].get_entry().capability_type inside {NORTHCAPE_CMT_DIRECT, NORTHCAPE_CMT_INDIRECT})
          begin
            /* found first matching parent */
            break;
          end
        end
      end else begin
        ret.location.indirect_location.effective_base = current_transaction.input_cmt_entry.location.indirect_location.effective_base + current_transaction.parent_offset;
      end
      ret.location.indirect_location.length = current_transaction.new_segment_length;

      // refcount must be reset
      ret.refcount = '0;

      set_restrictions(current_transaction, ret);

      // new permissions must be as or more restrictive as the current ones
      if (current_transaction.read_perm) begin
        ret.permissions.indirect_capability_permissions.read_permission = 1;
      end
      if (current_transaction.write_perm) begin
        ret.permissions.indirect_capability_permissions.write_permission = 1;
      end
      if (current_transaction.x_perm) begin
        ret.permissions.indirect_capability_permissions.execute_permission = 1;
      end
      if (current_transaction.irq_accessible_perm) begin
        ret.permissions.indirect_capability_permissions.irq_accessible_permission = 1;
      end
      if (current_transaction.cacheable_tlb_perm) begin
        ret.permissions.direct_capability_permissions.cacheable_tlb = 1'b1;
      end
      if (current_transaction.cacheable_access_perm) begin
        ret.permissions.direct_capability_permissions.cacheable_access = 1'b1;
      end
      // lockable not defined

      ret.nonce = ops_current_nonce;

      ret.tag = compute_tag(ret);

      output_cmt_tag = ret.tag;

      return ret;
    endfunction

    function northcape_cmt_entry_t predict_output_cmt_entry_clone(
        const ref transaction_t current_transaction);
      northcape_cmt_entry_t ret;

      ret = '0;

      // must be given a valid direct capability
      ret.capability_type = NORTHCAPE_CMT_INDIRECT;
      // parent is input capability
      ret.location.indirect_location.parent = current_transaction.input_token;
      // 0 is always possible
      void'(capability_accessors#(AXI_ADDR_WIDTH)::capability_set_offset(
          ret.location.indirect_location.parent, 0
      ));
      if (current_transaction.input_cmt_entry.capability_type == NORTHCAPE_CMT_DIRECT) begin
        ret.location.indirect_location.effective_base = current_transaction.input_cmt_entry.location.physical_location.base;
        ret.location.indirect_location.length = current_transaction.input_cmt_entry.location.physical_location.length;
      end else
      if (current_transaction.input_cmt_entry.capability_type == NORTHCAPE_CMT_LOCK_HOLDER) begin
        for (int i = 0; i < current_transaction.recursion_cmt_entries.size(); i++) begin
          ret.location.indirect_location.effective_base = current_transaction.recursion_cmt_entries[i].get_entry().location.indirect_location.effective_base;
          ret.location.indirect_location.length = current_transaction.recursion_cmt_entries[i].get_entry().location.indirect_location.length;
          if(current_transaction.recursion_cmt_entries[i].get_entry().capability_type inside {NORTHCAPE_CMT_DIRECT, NORTHCAPE_CMT_INDIRECT})
          begin
            /* found first matching parent */
            break;
          end
        end
      end else begin
        ret.location.indirect_location.effective_base = current_transaction.input_cmt_entry.location.indirect_location.effective_base;
        ret.location.indirect_location.length = current_transaction.input_cmt_entry.location.indirect_location.length;
      end


      // refcount must be reset
      ret.refcount = '0;

      set_restrictions(current_transaction, ret);

      // new permissions must be as or more restrictive as the current ones
      if (current_transaction.read_perm) begin
        ret.permissions.indirect_capability_permissions.read_permission = 1;
      end
      if (current_transaction.write_perm) begin
        ret.permissions.indirect_capability_permissions.write_permission = 1;
      end
      if (current_transaction.x_perm) begin
        ret.permissions.indirect_capability_permissions.execute_permission = 1;
      end
      if (current_transaction.irq_accessible_perm) begin
        ret.permissions.indirect_capability_permissions.irq_accessible_permission = 1;
      end
      if (current_transaction.cacheable_tlb_perm) begin
        ret.permissions.direct_capability_permissions.cacheable_tlb = 1'b1;
      end
      if (current_transaction.cacheable_access_perm) begin
        ret.permissions.direct_capability_permissions.cacheable_access = 1'b1;
      end
      // lockable not defined

      ret.nonce = ops_current_nonce;

      ret.tag = compute_tag(ret);

      output_cmt_tag = ret.tag;

      return ret;
    endfunction

    function northcape_cmt_entry_t predict_output_cmt_entry_lock(
        const ref transaction_t current_transaction);
      northcape_cmt_entry_t ret;

      ret = '0;

      // must be given a valid direct capability
      ret.capability_type = NORTHCAPE_CMT_LOCK_HOLDER;
      // parent is input capability
      ret.location.lock_holder_location.parent = current_transaction.input_token;

      // 0 is always possible
      void'(capability_accessors#(AXI_ADDR_WIDTH)::capability_set_offset(
          ret.location.lock_holder_location.parent, 0
      ));


      // key is sequential for non-reuse
      ret.location.lock_holder_location.lock_key = ++last_used_lock_key;

      if (last_used_lock_key == 0) begin
        // all-zeros is special
        ret.location.lock_holder_location.lock_key = ++last_used_lock_key;
      end
      /* previous locked key goes into lock-holder */
      if (current_transaction.recursion_cmt_entries.size()) begin
        ret.location.lock_holder_location.prev_key = current_transaction.recursion_cmt_entries[current_transaction.recursion_cmt_entries.size()-1].get_entry().location.physical_location.locked_key;
      end else begin
        /* must be direct */
        ret.location.lock_holder_location.prev_key = current_transaction.input_cmt_entry.location.physical_location.locked_key;
        if (current_transaction.input_cmt_entry.capability_type != NORTHCAPE_CMT_DIRECT) begin
          `uvm_fatal(COMPONENT_NAME, "Expected singular direct entry!");
        end
      end



      // refcount must be reset
      ret.refcount = '0;

      set_restrictions(current_transaction, ret);

      // new permissions must be as or more restrictive as the current ones
      if (current_transaction.read_perm) begin
        ret.permissions.indirect_capability_permissions.read_permission = 1;
      end
      if (current_transaction.write_perm) begin
        ret.permissions.indirect_capability_permissions.write_permission = 1;
      end
      if (current_transaction.x_perm) begin
        ret.permissions.indirect_capability_permissions.execute_permission = 1;
      end
      if (current_transaction.irq_accessible_perm) begin
        ret.permissions.indirect_capability_permissions.irq_accessible_permission = 1;
      end
      if (current_transaction.cacheable_tlb_perm) begin
        ret.permissions.direct_capability_permissions.cacheable_tlb = 1'b1;
      end
      if (current_transaction.cacheable_access_perm) begin
        ret.permissions.direct_capability_permissions.cacheable_access = 1'b1;
      end
      // lockable not defined

      ret.nonce = ops_current_nonce;

      ret.tag = compute_tag(ret);

      output_cmt_tag = ret.tag;

      return ret;
    endfunction

    function northcape_cmt_entry_t predict_output_cmt_entry_drop();
      return '0;
    endfunction

    function northcape_cmt_entry_t predict_output_cmt_entry_merge(
        const ref transaction_t current_transaction);
      northcape_cmt_entry_t ret;

      ret = '0;

      // must be given a valid direct capability
      ret.capability_type = NORTHCAPE_CMT_DIRECT;
      // lock must be reset
      ret.location.physical_location.locked_key = '0;
      // refcount must be reset
      ret.refcount = '0;

      ret.location.physical_location.base   = current_transaction.input_cmt_entry.location.physical_location.base;
      ret.location.physical_location.length = current_transaction.input_cmt_entry.location.physical_location.length + current_transaction.input_cmt_entry_right.location.physical_location.length;

      `uvm_info(COMPONENT_NAME, $sformatf(
                "I see left length %d right length %d result length %d",
                current_transaction.input_cmt_entry.location.physical_location.length,
                current_transaction.input_cmt_entry_right.location.physical_location.length,
                ret.location.physical_location.length
                ), UVM_DEBUG);

      set_restrictions(current_transaction, ret);

      // new permissions must be as or more restrictive as the current ones
      if (current_transaction.read_perm) begin
        ret.permissions.direct_capability_permissions.read_permission = 1;
      end
      if (current_transaction.write_perm) begin
        ret.permissions.direct_capability_permissions.write_permission = 1;
      end
      if (current_transaction.x_perm) begin
        ret.permissions.direct_capability_permissions.execute_permission = 1;
      end
      if (current_transaction.lockable_perm) begin
        ret.permissions.direct_capability_permissions.lockable_permission = 1;
      end
      if (current_transaction.irq_accessible_perm) begin
        ret.permissions.direct_capability_permissions.irq_accessible_permission = 1;
      end
      if (current_transaction.cacheable_tlb_perm) begin
        ret.permissions.direct_capability_permissions.cacheable_tlb = 1'b1;
      end
      if (current_transaction.cacheable_access_perm) begin
        ret.permissions.direct_capability_permissions.cacheable_access = 1'b1;
      end

      ret.nonce = ops_current_nonce;

      ret.tag = compute_tag(ret);

      output_cmt_tag = ret.tag;

      return ret;
    endfunction

    function northcape_cmt_entry_t predict_output_cmt_entry_restrict(
        const ref transaction_t current_transaction);
      northcape_cmt_entry_t ret;

      ret = current_transaction.input_cmt_entry;

      if (current_transaction.input_cmt_entry.capability_type == NORTHCAPE_CMT_INDIRECT) begin
        // modification is not allowed for direct capability
        ret.location.indirect_location.effective_base = current_transaction.input_cmt_entry.location.indirect_location.effective_base + current_transaction.parent_offset;
        ret.location.indirect_location.length -= current_transaction.new_segment_length;
      end

      set_restrictions(current_transaction, ret);

      // new permissions must be as or more restrictive as the current ones

      ret.permissions.indirect_capability_permissions.read_permission &= current_transaction.read_perm;


      ret.permissions.indirect_capability_permissions.write_permission &= current_transaction.write_perm;


      ret.permissions.indirect_capability_permissions.execute_permission &= current_transaction.x_perm;

      ret.permissions.indirect_capability_permissions.irq_accessible_permission &= current_transaction.irq_accessible_perm;

      ret.permissions.indirect_capability_permissions.cacheable_tlb &= current_transaction.cacheable_tlb_perm;
      ret.permissions.indirect_capability_permissions.cacheable_access &= current_transaction.cacheable_access_perm;

      // lockable and CoW are not defined for indirect capabilities
      if (ret.capability_type == NORTHCAPE_CMT_DIRECT) begin
        ret.permissions.direct_capability_permissions.lockable_permission &= current_transaction.lockable_perm;
      end

      // other parameters not modified

      return ret;
    endfunction

    function northcape_cmt_entry_t predict_output_cmt_entry_revoke(
        const ref transaction_t current_transaction);
      northcape_cmt_entry_t ret;

      ret = '0;

      // must be given a valid direct capability
      ret.capability_type = NORTHCAPE_CMT_DIRECT;
      // lock must be reset
      ret.location.physical_location.locked_key = '0;
      // refcount must be reset
      ret.refcount = '0;

      ret.location.physical_location.base   = current_transaction.input_cmt_entry.location.physical_location.base;
      ret.location.physical_location.length = current_transaction.input_cmt_entry.location.physical_location.length;


      set_restrictions(current_transaction, ret);

      // new permissions must be as or more restrictive as the current ones
      if (current_transaction.read_perm) begin
        ret.permissions.direct_capability_permissions.read_permission = 1;
      end
      if (current_transaction.write_perm) begin
        ret.permissions.direct_capability_permissions.write_permission = 1;
      end
      if (current_transaction.x_perm) begin
        ret.permissions.direct_capability_permissions.execute_permission = 1;
      end
      if (current_transaction.lockable_perm) begin
        ret.permissions.direct_capability_permissions.lockable_permission = 1;
      end
      if (current_transaction.irq_accessible_perm) begin
        ret.permissions.direct_capability_permissions.irq_accessible_permission = 1;
      end
      if (current_transaction.cacheable_tlb_perm) begin
        ret.permissions.direct_capability_permissions.cacheable_tlb = 1'b1;
      end
      if (current_transaction.cacheable_access_perm) begin
        ret.permissions.direct_capability_permissions.cacheable_access = 1'b1;
      end

      ret.nonce = ops_current_nonce;

      ret.tag = compute_tag(ret);

      output_cmt_tag = ret.tag;

      return ret;
    endfunction

    function master_result_t predict_master_result_insert_output_cap(
        const ref transaction_t current_transaction);
      master_result_t ret;
      cmt_size_t cmt_size;

      axi_len_t axi_length;
      axi_size_t axi_size;

      northcape_cmt_entry_t capability_entry;


      unique case (current_transaction.operation)
        NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE: begin
          capability_entry = predict_output_cmt_entry_create(current_transaction);
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE: begin
          capability_entry = predict_output_cmt_entry_derive(current_transaction);
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE: begin
          capability_entry = predict_output_cmt_entry_clone(current_transaction);
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
          capability_entry = predict_output_cmt_entry_lock(current_transaction);
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
          capability_entry = predict_output_cmt_entry_drop();
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE: begin
          capability_entry = predict_output_cmt_entry_merge(current_transaction);
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE: begin
          capability_entry = predict_output_cmt_entry_revoke(current_transaction);
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
          capability_entry = predict_output_cmt_entry_restrict(current_transaction);
        end
        default: begin
          `uvm_fatal(
              COMPONENT_NAME, $sformatf(
              "Could not check operation: operation %x not known!", current_transaction.operation));
        end
      endcase

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Expecting output capability id %d entry %s",
                current_capability_id[current_transaction.intended_capability_type],
                print_cmt_entry(
                    capability_entry
                )
                ), UVM_DEBUG);

      ret = new("master_result_write_output");

      ret.request_type = AXI_TEST_WRITE;

      cmt_size = (1 << current_transaction.cmt_size_clog2) * $bits(northcape_cmt_entry_t) / 8;

      axi_size = $clog2(AXI_DATA_WIDTH / 8);

      unique case (current_transaction.operation)
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
          capability_id_t capability_id;
          // overwrite the input cap

          capability_id = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
              current_transaction.input_token);
          ret.addr = gen_t::get_capability_addr(current_transaction.cmt_base,
                                                current_transaction.cmt_size_clog2, capability_id);
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE, NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE,NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE,NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE,NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE,NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
          // capability id was bumped in the last occupied check
          ret.addr = gen_t::get_capability_addr(
              current_transaction.cmt_base,
              current_transaction.cmt_size_clog2,
              current_capability_id[current_transaction.intended_capability_type]
          );
        end
        default: begin
          `uvm_fatal(
              COMPONENT_NAME, $sformatf(
              "Could not check operation: operation %x not known!", current_transaction.operation));
        end
      endcase

      ret.len = 0;

      ret.burst = INCR;
      ret.size = axi_size;

      ret.write_data = capability_entry;
      ret.write_strobes[0] = '1;

      /**
              * Default from here, not necessary
              */
      ret.lock = 0;
      ret.cache = '0;
      ret.prot = '0;
      ret.qos = '0;
      ret.region = '0;
      ret.id = '0;
      ret.user = '0;

      return ret;
    endfunction

    function northcape_cmt_entry_t predict_update_cmt_entry_create(
        const ref transaction_t current_transaction);
      northcape_cmt_entry_t ret;

      ret = current_transaction.input_cmt_entry;

      if (current_transaction.new_segment_length >= northcape_cmt_parser::entry_get_phys_length(
              ret
          )) begin
        `uvm_info(COMPONENT_NAME, "Expecting destruction of input capability!", UVM_HIGH);

        ret = '0;
        ret.capability_type = NORTHCAPE_CMT_INVALID;

        return ret;
      end

      if (current_transaction.direction == 0) begin
        // new capability is at start of the segment
        ret.location.physical_location.base += current_transaction.new_segment_length;
        ret.location.physical_location.length -= current_transaction.new_segment_length;
      end else begin
        ret.location.physical_location.length -= current_transaction.new_segment_length;
      end

      return ret;
    endfunction

    function northcape_cmt_entry_t predict_update_cmt_entry_derive(
        const ref transaction_t current_transaction);
      northcape_cmt_entry_t ret;

      ret = current_transaction.input_cmt_entry;
      // one more reference: the capability that we just derived
      ret.refcount += current_transaction.valid_test;

      return ret;
    endfunction

    function northcape_cmt_entry_t predict_update_cmt_entry_lock(
        const ref transaction_t current_transaction);
      northcape_cmt_entry_t ret;

      ret = current_transaction.input_cmt_entry;
      // one more reference: the capability that we just derived
      ret.refcount += current_transaction.valid_test;

      if (current_transaction.input_cmt_entry.capability_type == NORTHCAPE_CMT_DIRECT) begin
        // lock key updated immediately
        // otherwise: separate write for direct cap
        ret.location.physical_location.locked_key = last_used_lock_key;
      end

      return ret;
    endfunction

    function northcape_cmt_entry_t predict_update_cmt_entry_drop(
        const ref transaction_t current_transaction);
      northcape_cmt_entry_t ret;

      ret = current_transaction.recursion_cmt_entries[0].get_entry();
      // one more reference: the capability that we just derived
      ret.refcount -= current_transaction.valid_test;

      if (ret.capability_type == NORTHCAPE_CMT_DIRECT) begin
        if (current_transaction.input_cmt_entry.capability_type == NORTHCAPE_CMT_LOCK_HOLDER) begin
          // direct parent is direct base
          ret.location.physical_location.locked_key = current_transaction.input_cmt_entry.location.lock_holder_location.prev_key;
        end else begin
          // direct parent is direct base
          ret.location.physical_location.locked_key = '0;
        end
      end

      return ret;
    endfunction


    function master_result_t predict_master_result_update_input_cap(
        const ref transaction_t current_transaction);
      master_result_t ret;
      cmt_size_t cmt_size;

      axi_len_t axi_length;
      axi_size_t axi_size;

      northcape_cmt_entry_t capability_entry;


      unique case (current_transaction.operation)
        NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE: begin
          capability_entry = predict_update_cmt_entry_create(current_transaction);
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE: begin
          capability_entry = predict_update_cmt_entry_derive(current_transaction);
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
          capability_entry = predict_update_cmt_entry_drop(current_transaction);
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE, NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE: begin
          capability_entry = '0;
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
          capability_entry = predict_update_cmt_entry_lock(current_transaction);
        end
        default: begin
          `uvm_fatal(
              COMPONENT_NAME, $sformatf(
              "Could not check operation: operation %x not known!", current_transaction.operation));
        end
      endcase



      ret = new("master_result_write_output");

      ret.request_type = AXI_TEST_WRITE;

      cmt_size = (1 << current_transaction.cmt_size_clog2) * $bits(northcape_cmt_entry_t) / 8;

      axi_size = $clog2(AXI_DATA_WIDTH / 8);

      unique case (current_transaction.operation)
        NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE, NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE, NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE, NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
          // capability id was bumped in the last occupied check
          ret.addr = gen_t::get_capability_addr(
              current_transaction.cmt_base,
              current_transaction.cmt_size_clog2,
              capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                  current_transaction.input_token)
          );
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
          ret.addr = current_transaction.recursion_cmt_entries[0].get_entry_addr(
              current_transaction.cmt_size_clog2);
        end
        default: begin
          `uvm_fatal(
              COMPONENT_NAME, $sformatf(
              "Could not check operation: operation %x not known!", current_transaction.operation));
        end
      endcase

      ret.len = 0;

      ret.burst = INCR;
      ret.size = axi_size;

      ret.write_data = capability_entry;
      ret.write_strobes[0] = '1;

      /**
              * Default from here, not necessary
              */
      ret.lock = 0;
      ret.cache = '0;
      ret.prot = '0;
      ret.qos = '0;
      ret.region = '0;
      ret.id = '0;
      ret.user = '0;

      return ret;
    endfunction

    function master_result_t predict_master_result_update_input_cap_right(
        const ref transaction_t current_transaction);
      master_result_t ret;
      cmt_size_t cmt_size;

      axi_len_t axi_length;
      axi_size_t axi_size;

      northcape_cmt_entry_t capability_entry;


      capability_entry = '0;


      ret = new("master_result_write_output_right");

      ret.request_type = AXI_TEST_WRITE;

      cmt_size = (1 << current_transaction.cmt_size_clog2) * $bits(northcape_cmt_entry_t) / 8;

      axi_size = $clog2(AXI_DATA_WIDTH / 8);

      ret.addr = gen_t::get_capability_addr(
          current_transaction.cmt_base,
          current_transaction.cmt_size_clog2,
          capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
              current_transaction.input_token_right)
      );

      ret.len = 0;

      ret.burst = INCR;
      ret.size = axi_size;

      ret.write_data = capability_entry;
      ret.write_strobes[0] = '1;

      /**
              * Default from here, not necessary
              */
      ret.lock = 0;
      ret.cache = '0;
      ret.prot = '0;
      ret.qos = '0;
      ret.region = '0;
      ret.id = '0;
      ret.user = '0;

      return ret;
    endfunction

    function master_result_t predict_master_result_update_direct_cap_lock(
        const ref transaction_t current_transaction);
      master_result_t ret;
      cmt_size_t cmt_size;

      axi_len_t axi_length;
      axi_size_t axi_size;

      northcape_cmt_entry_t capability_entry;


      capability_entry = current_transaction.recursion_cmt_entries[current_transaction.recursion_cmt_entries.size()-1].get_entry();

      capability_entry.location.physical_location.locked_key = last_used_lock_key;


      ret = new("master_result_write_direct_cap");

      ret.request_type = AXI_TEST_WRITE;

      cmt_size = (1 << current_transaction.cmt_size_clog2) * $bits(northcape_cmt_entry_t) / 8;

      axi_size = $clog2(AXI_DATA_WIDTH / 8);

      ret.addr = gen_t::get_capability_addr(
          current_transaction.cmt_base,
          current_transaction.cmt_size_clog2,
          current_transaction.recursion_cmt_entries[current_transaction.recursion_cmt_entries.size()-1].token_id
      );

      ret.len = 0;

      ret.burst = INCR;
      ret.size = axi_size;

      ret.write_data = capability_entry;
      ret.write_strobes[0] = '1;

      /**
              * Default from here, not necessary
              */
      ret.lock = 0;
      ret.cache = '0;
      ret.prot = '0;
      ret.qos = '0;
      ret.region = '0;
      ret.id = '0;
      ret.user = '0;

      return ret;
    endfunction

    function master_result_t predict_master_result_overwrite_locked_key_direct_base(
        const ref transaction_t current_transaction);
      master_result_t ret;
      cmt_size_t cmt_size;

      axi_len_t axi_length;
      axi_size_t axi_size;

      northcape_cmt_entry_t capability_entry;
      northcape_lock_key_t prev_key;

      if (current_transaction.input_cmt_entry.capability_type != NORTHCAPE_CMT_LOCK_HOLDER) begin
        `uvm_fatal(COMPONENT_NAME, "Unlock expected on non-lock holder drop!");
      end
      prev_key = current_transaction.input_cmt_entry.location.lock_holder_location.prev_key;


      capability_entry = current_transaction.recursion_cmt_entries[current_transaction.recursion_cmt_entries.size()-1].get_entry();

      capability_entry.location.physical_location.locked_key = prev_key;


      ret = new("master_result_write_direct_cap");

      ret.request_type = AXI_TEST_WRITE;

      cmt_size = (1 << current_transaction.cmt_size_clog2) * $bits(northcape_cmt_entry_t) / 8;

      axi_size = $clog2(AXI_DATA_WIDTH / 8);

      ret.addr = gen_t::get_capability_addr(
          current_transaction.cmt_base,
          current_transaction.cmt_size_clog2,
          current_transaction.recursion_cmt_entries[current_transaction.recursion_cmt_entries.size()-1].token_id
      );

      ret.len = 0;

      ret.burst = INCR;
      ret.size = axi_size;

      ret.write_data = capability_entry;
      ret.write_strobes[0] = '1;

      /**
              * Default from here, not necessary
              */
      ret.lock = 0;
      ret.cache = '0;
      ret.prot = '0;
      ret.qos = '0;
      ret.region = '0;
      ret.id = '0;
      ret.user = '0;

      return ret;
    endfunction

    function mmio_result_t predict_mmio_write_result();
      mmio_result_t ret;

      ret = new("MMIO result");

      ret.request_type = AXI_TEST_WRITE;
      ret.response = OKAY;

      return ret;
    endfunction

    function mmio_result_t predict_mmio_in_progress();
      mmio_result_t ret;

      ret = new("MMIO result");

      ret.request_type = AXI_TEST_READ;
      ret.response = OKAY;

      // in process - bit 62
      ret.read_data = '0;
      ret.read_data[62] = 1;

      return ret;
    endfunction

    function bit is_partial_reveal(transaction_t transaction);
      return transaction.input_cmt_entry.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID && (transaction.input_cmt_entry.restrictions.body.task_restriction.device_id != transaction.device_id_current || transaction.input_cmt_entry.restrictions.body.task_restriction.task_id != transaction.task_id_current);
    endfunction

    function mmio_result_t predict_mmio_done(transaction_t transaction, bit is_stop);
      mmio_result_t ret;
      // for set-task-id capabilities, allow inspect to reveal restrictions and X+IRQ permissions; this is sufficient to check if the capability is callable
      bit inspect_partial_reveal = is_partial_reveal(transaction);

      ret = new("MMIO result");

      ret.request_type = AXI_TEST_READ;
      ret.response = OKAY;

      // done - bit 63
      // error - bit 61
      ret.read_data = '0;
      ret.read_data[63] = 1;
      ret.read_data[61] = !transaction.valid_test;

      if(transaction.valid_test && transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT && is_stop == 1'b1)
      begin

        if (inspect_partial_reveal) begin
          `uvm_info(COMPONENT_NAME, "Expecting PARTIAL reveal!", UVM_HIGH);
        end

        ret.read_data[47:45] = transaction.input_cmt_entry.restrictions.restriction_type;

        unique case (transaction.input_cmt_entry.capability_type)
          NORTHCAPE_CMT_DIRECT: begin
            ret.read_data[41:10] = !inspect_partial_reveal ? transaction.input_cmt_entry.location.physical_location.length : '0;

            ret.read_data[5] = !inspect_partial_reveal ? transaction.input_cmt_entry.permissions.direct_capability_permissions.lockable_permission : '0;
            ret.read_data[4] = transaction.input_cmt_entry.permissions.direct_capability_permissions.irq_accessible_permission;

          end
          NORTHCAPE_CMT_INDIRECT: begin
            ret.read_data[41:10] = !inspect_partial_reveal ? transaction.input_cmt_entry.location.indirect_location.length : '0;

            ret.read_data[5] = !inspect_partial_reveal ? transaction.recursion_cmt_entries[transaction.recursion_cmt_entries.size()-1].get_entry().permissions.direct_capability_permissions.lockable_permission : '0;
            ret.read_data[4] = transaction.recursion_cmt_entries[transaction.recursion_cmt_entries.size()-1].get_entry().permissions.direct_capability_permissions.irq_accessible_permission;
          end
          NORTHCAPE_CMT_LOCK_HOLDER: begin
            if(transaction.recursion_cmt_entries[0].get_entry().capability_type == NORTHCAPE_CMT_DIRECT)
          begin
              ret.read_data[41:10] = !inspect_partial_reveal ? transaction.recursion_cmt_entries[0].get_entry().location.physical_location.length : '0;
            end else begin
              ret.read_data[41:10] = !inspect_partial_reveal ? transaction.recursion_cmt_entries[0].get_entry().location.indirect_location.length : '0;
            end

            ret.read_data[5] = !inspect_partial_reveal ? transaction.recursion_cmt_entries[transaction.recursion_cmt_entries.size()-1].get_entry().permissions.direct_capability_permissions.lockable_permission : '0;
            ret.read_data[4] = transaction.recursion_cmt_entries[transaction.recursion_cmt_entries.size()-1].get_entry().permissions.direct_capability_permissions.irq_accessible_permission;
          end
          default: begin
            ret.read_data[41:10] = '0;
          end
        endcase

        ret.read_data[8] = !inspect_partial_reveal ? transaction.input_cmt_entry.permissions.indirect_capability_permissions.read_permission : '0;
        ret.read_data[7] = !inspect_partial_reveal ? transaction.input_cmt_entry.permissions.indirect_capability_permissions.write_permission : '0;

        ret.read_data[3] = !inspect_partial_reveal ? transaction.input_cmt_entry.permissions.indirect_capability_permissions.cacheable_tlb : '0;
        ret.read_data[2] = !inspect_partial_reveal ? transaction.input_cmt_entry.permissions.indirect_capability_permissions.cacheable_access : '0;

        ret.read_data[6] = transaction.input_cmt_entry.permissions.indirect_capability_permissions.execute_permission;
      end

      return ret;
    endfunction

    function mmio_result_t predict_mmio_restriction(transaction_t transaction);
      mmio_result_t ret;

      ret = new("MMIO result");

      ret.request_type = AXI_TEST_READ;
      ret.response = OKAY;

      ret.read_data = '0;

      if (transaction.valid_test && transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT) begin
        unique case (transaction.input_cmt_entry.restrictions.restriction_type)
          NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED: begin
            ret.read_data = transaction.input_cmt_entry.restrictions.body.device_interpreted_bits;
          end
          NORTHCAPE_RESTRICTIONS_SET_TASK_ID, NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND: begin
            ret.read_data = {
              16'h0,
              transaction.input_cmt_entry.restrictions.body.task_restriction.device_id,
              transaction.input_cmt_entry.restrictions.body.task_restriction.task_id
            };
          end
          default: begin
            ret.read_data = '0;
          end
        endcase
      end

      return ret;
    endfunction

    /* MMIO aux register */
    function mmio_result_t predict_mmio_aux_out(transaction_t transaction);
      mmio_result_t ret;

      ret = new("MMIO result");

      ret.request_type = AXI_TEST_READ;
      ret.response = OKAY;

      // done - bit 63
      // error - bit 61
      ret.read_data = '0;

      if (transaction.valid_test && transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT) begin
        bit inspect_partial_reveal = is_partial_reveal(transaction);

        ret.read_data[47:32] = inspect_partial_reveal ? '0 : transaction.input_cmt_entry.refcount;

        unique case (transaction.input_cmt_entry.capability_type)
          NORTHCAPE_CMT_DIRECT: begin
            ret.read_data[31:0] = !inspect_partial_reveal ? transaction.input_cmt_entry.location.physical_location.base : '0;
          end
          NORTHCAPE_CMT_INDIRECT: begin
            ret.read_data[31:0] = !inspect_partial_reveal ? transaction.input_cmt_entry.location.indirect_location.effective_base : '0;
          end
          NORTHCAPE_CMT_LOCK_HOLDER: begin
            if(transaction.recursion_cmt_entries[0].get_entry().capability_type == NORTHCAPE_CMT_DIRECT)
          begin
              ret.read_data[31:0] = !inspect_partial_reveal ? transaction.recursion_cmt_entries[0].get_entry().location.physical_location.base : '0;
            end else begin
              ret.read_data[31:0] = !inspect_partial_reveal ? transaction.recursion_cmt_entries[0].get_entry().location.indirect_location.effective_base : '0;
            end
          end
          default: begin
            ret.read_data = '0;
          end
        endcase
      end

      return ret;
    endfunction

    function mmio_result_t predict_mmio_cleared();
      mmio_result_t ret;

      ret = new("MMIO result");

      ret.request_type = AXI_TEST_READ;
      ret.response = OKAY;

      // nothing set
      ret.read_data = '0;

      return ret;
    endfunction

    function mmio_result_t predict_mmio_token(transaction_t transaction);
      mmio_result_t ret;
      bit [AXI_ADDR_WIDTH -1 : 0] expected_token;

      ret = new("MMIO result");

      ret.request_type = AXI_TEST_READ;
      ret.response = OKAY;

      expected_token = '0;

      expected_token = capability_accessors#(AXI_ADDR_WIDTH)::capability_set_type(
          expected_token, transaction.intended_capability_type);
      expected_token = capability_accessors#(AXI_ADDR_WIDTH)::capability_set_id(
          expected_token, current_capability_id[transaction.intended_capability_type]);
      expected_token =
          capability_accessors#(AXI_ADDR_WIDTH)::capability_set_tag(expected_token, output_cmt_tag);


      if (transaction.valid_test) begin
        ret.read_data = expected_token;
      end else begin
        // nothing to be returned
        ret.read_data = '0;
      end

      return ret;
    endfunction

    function mmio_result_t predict_mmio_token_erased();
      mmio_result_t ret;

      ret = new("MMIO result");

      ret.request_type = AXI_TEST_READ;
      ret.response = OKAY;

      ret.read_data = '0;

      return ret;
    endfunction

    function mmio_result_t predict_mmio_capability_count();
      mmio_result_t ret;

      ret = new("MMIO result");

      ret.request_type = AXI_TEST_READ;
      ret.response = OKAY;
      // MSB is status bit - should indicated Ops is initialized
      ret.read_data = {
        1'b1, 1'b0, capability_count
      };

      return ret;
    endfunction

    task check_cmt_reset();
      bit [AXI_ADDR_WIDTH-1:0] current_cmt_base, cmt_end;
      int unsigned transaction_num;

      master_result_t predicted_master_result, real_master_result;

      transaction_num = 0;

      current_cmt_base = INITIAL_CMT_BASE;
      cmt_end = current_cmt_base + $bits(northcape_cmt_entry_t) / 8 * (1 << INITIAL_CMT_SIZE_CLOG2);

      while (current_cmt_base < cmt_end) begin


        predicted_master_result = predict_master_result_zero(
            current_cmt_base,
            INITIAL_CMT_SIZE_CLOG2,
            (current_cmt_base + max_axi_transfer_bytes >= cmt_end)
        );
        ops_result_fifo.get(real_master_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_master_result, predicted_master_result));

        transaction_num++;

        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Scoreboard completed overwrite transaction %d", transaction_num), UVM_MEDIUM);


        current_cmt_base += max_axi_transfer_bytes;
      end

      `uvm_info(COMPONENT_NAME, "Waiting for CMT root capability create transaction", UVM_MEDIUM);


      predicted_master_result =
          predict_master_result_insert_root_cap(INITIAL_CMT_BASE, INITIAL_CMT_SIZE_CLOG2);
      cache_result_fifo.get(real_master_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_master_result, predicted_master_result));

      predict_occupied_update(NORTHCAPE_ROOT_CAPABILITY_ID, 1'b1, .is_root_cap(1'b1));

      `uvm_info(COMPONENT_NAME, "Completed CMT root capability create transaction", UVM_MEDIUM);
    endtask

    function csr_result_t mmio_result_to_csr_result(mmio_result_t mmio_result);
      csr_result_t ret;
      northcape_cap_ops_rcsr_resp_t resp;

      resp = '0;
      resp.ok = mmio_result.response == OKAY;
      resp.reg_old_val = mmio_result.read_data;

      ret = new(resp, "Predicted CSR result");
      return ret;
    endfunction

    task check_start_sequence_mmio(const ref transaction_t current_transaction);
      mmio_result_t predicted_mmio_result, real_mmio_result;

      // 4 writes for setup

      // input capability
      predicted_mmio_result = predict_mmio_write_result();
      mmio_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));

      // restrictions
      predicted_mmio_result = predict_mmio_write_result();
      mmio_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));

      // Aux 1
      predicted_mmio_result = predict_mmio_write_result();
      mmio_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));
      // Operation
      predicted_mmio_result = predict_mmio_write_result();
      mmio_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));

      // one read to check in progress
      if (current_transaction.valid_test || current_transaction.operation_is_supported()) begin
        predicted_mmio_result = predict_mmio_in_progress();
      end else begin
        // can already output error
        predicted_mmio_result = predict_mmio_done(current_transaction, 1'b0);
      end
      mmio_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));
    endtask

    task check_start_sequence_csr(const ref transaction_t current_transaction);
      csr_result_t predicted_mmio_result, real_mmio_result;

      // 4 writes for setup

      // input capability
      predicted_mmio_result = mmio_result_to_csr_result(predict_mmio_write_result());
      csr_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));

      // restrictions
      predicted_mmio_result = mmio_result_to_csr_result(predict_mmio_write_result());
      csr_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));

      // Aux 1
      predicted_mmio_result = mmio_result_to_csr_result(predict_mmio_write_result());
      csr_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));
      // Operation
      predicted_mmio_result = mmio_result_to_csr_result(predict_mmio_write_result());
      csr_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));

    endtask



    task check_revocation_writes(const ref transaction_t current_transaction);
      for (int unsigned i = 0; i < current_transaction.get_number_revoke_writes(); i++) begin
        master_result_t predicted_revoke_result, real_revoke_result;
        `uvm_info(COMPONENT_NAME, $sformatf("Waiting for revoke main memory write %d!", i),
                  UVM_DEBUG);

        predicted_revoke_result = predict_master_result_revoke_write(current_transaction, i);
        ops_result_fifo.get(real_revoke_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_revoke_result, predicted_revoke_result));
      end
    endtask

    bit [BRAM_DATA_WIDTH-1:0] last_occupied_write;

    task predict_occupied_update(capability_id_t capability_id, bit is_valid,
                                 bit is_root_cap = 1'b0, capability_id_t last_capability_id = '0,
                                 bit last_capability_valid = 1'b0);
      bram_result_t predicted_bram_read, real_bram_read;
      bram_result_t predicted_bram_write, real_bram_write;

      const int bram_row = (capability_id % 2 ** INITIAL_CMT_SIZE_CLOG2) / BRAM_DATA_WIDTH;
      const
      int
      last_bram_row = (last_capability_id % 2 ** INITIAL_CMT_SIZE_CLOG2) / BRAM_DATA_WIDTH;
      const int bram_col = capability_id % BRAM_DATA_WIDTH;

      // OK occupied check
      predicted_bram_read = new();
      predicted_bram_read.addr = bram_row;
      predicted_bram_read.transaction_type = NORTHCAPE_BRAM_READ;
      predicted_bram_read.data = '0;

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Waiting for BRAM read %s for occupied update ID %d is valid %b",
                predicted_bram_read.convert2string(),
                capability_id,
                is_valid
                ), UVM_HIGH);
      bram_result_fifo.get(real_bram_read);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(real_bram_read, predicted_bram_read));

      predicted_bram_write = new();
      predicted_bram_write.addr = bram_row;
      predicted_bram_write.transaction_type = NORTHCAPE_BRAM_WRITE;
      // the agent always returns all-occupied, except for root capability (where it should be 0)
      predicted_bram_write.data = is_root_cap ? '0 : '1;

      if (last_capability_valid && last_bram_row == bram_row) begin
        // two subsequent writes to the same row are a pipeline hazard in the ops
        // it handles this using renaming: instead of using the read data, it maintains its last write data in a register
        // if the hazard is detected, the ops updates the mask it wrote in the last cycle and discards the read data
        predicted_bram_write.data = last_occupied_write;
      end

      predicted_bram_write.data[bram_col] = is_valid;

      last_occupied_write = predicted_bram_write.data;

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Waiting for BRAM write %s", predicted_bram_write.convert2string()), UVM_HIGH);
      bram_result_fifo.get(real_bram_write);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(real_bram_write, predicted_bram_write
                         ));

    endtask

    task predict_occupied_init();
      bram_result_t predicted_bram_write, real_bram_write;

      for (int bram_row = 0; bram_row < BRAM_DATA_DEPTH; bram_row++) begin
        predicted_bram_write = new();
        predicted_bram_write.addr = bram_row;
        predicted_bram_write.transaction_type = NORTHCAPE_BRAM_WRITE;
        predicted_bram_write.data = '0;
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Waiting for BRAM init write %s with BRAM Depth %d",
                  predicted_bram_write.convert2string(),
                  BRAM_DATA_DEPTH
                  ), UVM_HIGH);
        bram_result_fifo.get(real_bram_write);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_bram_write, predicted_bram_write));
      end
    endtask

    task check_rmw(const ref transaction_t current_transaction);
      master_result_t predicted_master_result, real_master_result;
      capability_id_t last_capability_id;

      `uvm_info(COMPONENT_NAME, "Waiting for input read!", UVM_DEBUG);

      predicted_master_result = predict_master_result_read_input_cap(current_transaction);
      `uvm_info(COMPONENT_NAME, $sformatf(
                "Waiting for read of input cap from addr %x!", predicted_master_result.addr),
                UVM_DEBUG);
      cache_result_fifo.get(real_master_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_master_result, predicted_master_result));

      if(current_transaction.read_resp != OKAY || current_transaction.input_capability_allows_operation(
              1'b0
          ) != NORTHCAPE_NO_ERROR) begin
        // will error out IMMEDIATELY
        return;
      end

      if (current_transaction.operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE, NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT}) begin
        for (int unsigned i = 0; i < current_transaction.recursion_cmt_entries.size(); i++) begin
          predicted_master_result =
              predict_master_result_read_input_cap(current_transaction, i + 1);
          `uvm_info(COMPONENT_NAME, $sformatf(
                    "Waiting for read of recursed cap %d of %d from addr %x!",
                    i,
                    current_transaction.recursion_cmt_entries.size(),
                    predicted_master_result.addr
                    ), UVM_DEBUG);
          cache_result_fifo.get(real_master_result);
          checker_port.write(NorthcapeGenericCheckerCompItem::new(
                             real_master_result, predicted_master_result));
          if (current_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP) begin
            // drop only ever reads the direct parent
            if(current_transaction.input_cmt_entry.capability_type != NORTHCAPE_CMT_LOCK_HOLDER)
            begin
              break;
            end
          end
        end
      end

      if (current_transaction.operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE}) begin
        // read second input capability
        predicted_master_result = predict_master_result_read_input_cap_right(current_transaction);
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Waiting for read of right input cap from addr %x!", predicted_master_result.addr
                  ), UVM_DEBUG);
        cache_result_fifo.get(real_master_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_master_result, predicted_master_result));

        if(current_transaction.read_resp != OKAY || current_transaction.input_capability_allows_operation(
                1'b1
            ) != NORTHCAPE_NO_ERROR) begin
          `uvm_info(COMPONENT_NAME,
                    "Expecting immediate return due to unsupported right input cap!", UVM_HIGH);
          // will error out IMMEDIATELY
          return;
        end

      end

      // drop, inspect, restrict do not do any occupied checks as they only work on existing cap's
      if (!(current_transaction.operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT})) begin
        bram_result_t predicted_occupied_check, real_occupied_check;
        int start_row = current_capability_id[current_transaction.intended_capability_type] / BRAM_DATA_WIDTH;

        for (
            int row = 0; row < current_transaction.unsuccessful_lookups / BRAM_DATA_WIDTH; row++
        ) begin
          predicted_occupied_check = new();
          predicted_occupied_check.addr = row + start_row;
          predicted_occupied_check.transaction_type = NORTHCAPE_BRAM_READ;
          predicted_occupied_check.data = '0;
          `uvm_info(
              COMPONENT_NAME, $sformatf(
              "Waiting for failing occupied check %s", predicted_occupied_check.convert2string()),
              UVM_HIGH);
          bram_result_fifo.get(real_occupied_check);
          checker_port.write(NorthcapeGenericCheckerCompItem::new(
                             real_occupied_check, predicted_occupied_check));

          // we have to be careful with overflows...
          current_capability_id[current_transaction.intended_capability_type] += BRAM_DATA_WIDTH;
          current_capability_id[current_transaction.intended_capability_type] &= get_id_mask_for_capability_type(
              current_transaction.intended_capability_type
          );
        end
        // ops always picks final capability ID based on leading zero count
        current_capability_id[current_transaction.intended_capability_type][
            $clog2(BRAM_DATA_WIDTH)-1:0] = current_transaction.unsuccessful_lookups;

        if (current_transaction.unsuccessful_lookups <= get_max_capability_id(
                current_transaction.intended_capability_type
            )) begin
          // OK occupied check
          predicted_occupied_check = new();
          predicted_occupied_check.addr = start_row + current_transaction.unsuccessful_lookups / BRAM_DATA_WIDTH;
          predicted_occupied_check.transaction_type = NORTHCAPE_BRAM_READ;
          predicted_occupied_check.data = '0;
          `uvm_info(
              COMPONENT_NAME, $sformatf(
              "Waiting for successful occupied check %s", predicted_occupied_check.convert2string()
              ), UVM_HIGH);
          bram_result_fifo.get(real_occupied_check);
          checker_port.write(NorthcapeGenericCheckerCompItem::new(
                             real_occupied_check, predicted_occupied_check));
        end
      end

      if (current_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT) begin
        // no output writes!
        return;
      end

      if (!current_transaction.valid_test) begin
        // no output writes
        return;
      end

      predicted_master_result = predict_master_result_insert_output_cap(current_transaction);
      `uvm_info(COMPONENT_NAME, $sformatf(
                "Waiting for output write at addr %x", predicted_master_result.addr), UVM_DEBUG);
      cache_result_fifo.get(real_master_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_master_result, predicted_master_result));

      unique case (current_transaction.operation)
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
          // restrict, drop update in-place; restrict always keeps the capability valid while drop destroys it no matter what
          predict_occupied_update(
              capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
              current_transaction.input_token),
              current_transaction.operation != NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP);
          last_capability_id = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
              current_transaction.input_token);
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE, NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE,NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE,NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE,NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE,NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
          // a new capability ID was allocated
          predict_occupied_update(
              current_capability_id[current_transaction.intended_capability_type], 1'b1);
          last_capability_id = current_capability_id[current_transaction.intended_capability_type];
        end
        default: ;

      endcase
      if (current_transaction.write_resp != OKAY) begin
        // will error out IMMEDIATELY
        return;
      end

      if (current_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT) begin
        // only does this one write
        return;
      end

      // in case drop was done on a capability whose parent was revoked, there might not be an update write
      if(current_transaction.operation != NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP || current_transaction.drop_make_one_capability_invalid == 1'b0 || current_transaction.number_indirect_caps != 0)
      begin
        predicted_master_result = predict_master_result_update_input_cap(current_transaction);
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Waiting for update write at addr %x!", predicted_master_result.addr), UVM_DEBUG);
        cache_result_fifo.get(real_master_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_master_result, predicted_master_result));

        unique case (current_transaction.operation)
          NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE, NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK: begin
            // create has an edge case where it destroys the input, otherwise, just updates
            predict_occupied_update(capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                                    current_transaction.input_token),
                                    current_transaction.operation != NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE || current_transaction.new_segment_length <  northcape_cmt_parser::entry_get_phys_length(
                                    current_transaction.input_cmt_entry),
                                    .last_capability_valid(1'b1),
                                    .last_capability_id(last_capability_id));
            last_capability_id = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                current_transaction.input_token);
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP: begin
            `uvm_info(
                COMPONENT_NAME, $sformatf(
                "Doing drop update at id %d", current_transaction.recursion_cmt_entries[0].token_id
                ), UVM_DEBUG);
            // just decreases the ref count
            predict_occupied_update(current_transaction.recursion_cmt_entries[0].token_id, 1'b1,
                                    .last_capability_valid(1'b1),
                                    .last_capability_id(last_capability_id));
            last_capability_id = current_transaction.recursion_cmt_entries[0].token_id;
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE, NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE: begin
            // unconditionally kick the input
            predict_occupied_update(capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                                    current_transaction.input_token), 1'b0,
                                    .last_capability_valid(1'b1),
                                    .last_capability_id(last_capability_id));
            last_capability_id = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                current_transaction.input_token);
          end
          default: begin
            `uvm_fatal(
                COMPONENT_NAME, $sformatf(
                "Could not check operation: operation %x not known!", current_transaction.operation
                ));
          end
        endcase

      end

      if(current_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP && current_transaction.input_cmt_entry.capability_type == NORTHCAPE_CMT_LOCK_HOLDER && !current_transaction.drop_make_one_capability_invalid  && current_transaction.number_indirect_caps != 0)
      begin
        // merge needs to overwrite two input caps
        predicted_master_result =
            predict_master_result_overwrite_locked_key_direct_base(current_transaction);
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Waiting for update write direct base at addr %x!", predicted_master_result.addr),
                  UVM_DEBUG);
        cache_result_fifo.get(real_master_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_master_result, predicted_master_result));
        predict_occupied_update(
            current_transaction.recursion_cmt_entries[current_transaction.recursion_cmt_entries.size()-1].token_id,
            1'b1, .last_capability_valid(1'b1), .last_capability_id(last_capability_id));
        last_capability_id = current_transaction.recursion_cmt_entries[current_transaction.recursion_cmt_entries.size()-1].token_id;
      end

      if (current_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE) begin
        // merge needs to overwrite two input caps
        predicted_master_result = predict_master_result_update_input_cap_right(current_transaction);
        `uvm_info(
            COMPONENT_NAME, $sformatf(
            "Waiting for update write second capability at addr %x!", predicted_master_result.addr),
            UVM_DEBUG);
        cache_result_fifo.get(real_master_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_master_result, predicted_master_result));
        // unconditional kick
        predict_occupied_update(capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                                current_transaction.input_token_right), 1'b0,
                                .last_capability_valid(1'b1),
                                .last_capability_id(last_capability_id));
        last_capability_id = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
            current_transaction.input_token_right);

      end

      if (current_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK && current_transaction.input_cmt_entry.capability_type != NORTHCAPE_CMT_DIRECT) begin
        // lock needs to overwrite direct capability to set key
        // in case the direct parent is direct, we do this immediately; otherwise, separately
        predicted_master_result = predict_master_result_update_direct_cap_lock(current_transaction);
        `uvm_info(
            COMPONENT_NAME, $sformatf(
            "Waiting for update write direct capability at addr %x!", predicted_master_result.addr),
            UVM_DEBUG);
        cache_result_fifo.get(real_master_result);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_master_result, predicted_master_result));
        // just an update
        predict_occupied_update(
            current_transaction.recursion_cmt_entries[current_transaction.recursion_cmt_entries.size()-1].token_id,
            1'b1, .last_capability_valid(1'b1), .last_capability_id(last_capability_id));
        last_capability_id = current_transaction.recursion_cmt_entries[current_transaction.recursion_cmt_entries.size()-1].token_id;
      end

      if (current_transaction.operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE}) begin
        // overwrites the segment in main mem
        check_revocation_writes(current_transaction);
      end

      `uvm_info(COMPONENT_NAME, "Capability creation done!", UVM_DEBUG);

    endtask

    function void calculate_capability_count(const ref transaction_t current_transaction);
      unique case (current_transaction.operation)
        NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE: begin
          // create has an edge case: when the size of the created capability as the same as the parent's, the parent capability is destroyed
          // thus, in this case, the count does not change!
          if(current_transaction.new_segment_length != current_transaction.input_cmt_entry.location.physical_location.length)
          begin
            // otherwise, one new capability has been created in the operation if successful
            capability_count += current_transaction.valid_test;
          end
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK:
        begin
          // one new capability has been created in the operation if successful
          capability_count += current_transaction.valid_test;
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE: begin
          // one capability has sized to exist (in total)
          capability_count -= current_transaction.valid_test;
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT:
        begin
          // capability count does not change
        end
        NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP: begin
          // sweep should find and eliminate the orphans
          capability_count -= current_transaction.orphans;
        end
        default: begin
          // TODO tooling issue: this should be a fatal, but might be ignored with Vivado
          `uvm_error(COMPONENT_NAME, $sformatf(
                     "I do not know how capability count should behave for operation %s",
                     current_transaction.operation.name()
                     ));
        end
      endcase

      if (uvm_config_db#(bit [AXI_LITE_DATA_WIDTH-1:0])::exists(
              this, "", northcape_test::NORTHCAPE_CAPABILITY_COUNT_CONFIG_NAME
          )) begin
        bit [AXI_LITE_DATA_WIDTH-1:0] actual_capability_count;
        assert (uvm_config_db#(bit [AXI_LITE_DATA_WIDTH-1:0])::get(
            this,
            "",
            northcape_test::NORTHCAPE_CAPABILITY_COUNT_CONFIG_NAME,
            actual_capability_count
        ));

        if (capability_count != actual_capability_count) begin
          `uvm_error(COMPONENT_NAME, $sformatf(
                     "Ops scoreboard expected %d capabilities to exist but only %d are actually in the CMT!",
                     capability_count,
                     actual_capability_count
                     ));
        end
      end
    endfunction

    bit [AXI_ADDR_WIDTH-1:0] last_output_token;

    function bit [AXI_ADDR_WIDTH - 1 : 0] get_output_capability_token();
      return last_output_token;
    endfunction

    bit [AXI_LITE_DATA_WIDTH-1:0] last_rng_output;

    task check_stop_sequence_mmio(const ref transaction_t current_transaction);
      mmio_result_t predicted_mmio_result, real_mmio_result;

      // one read to check result
      if (current_transaction.valid_test || current_transaction.operation_is_supported()) begin
        predicted_mmio_result = predict_mmio_done(current_transaction, 1'b1);
      end else begin
        // we have already seen the error result earlier
        // data have been cleared
        predicted_mmio_result = predict_mmio_cleared();
      end
      mmio_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));


      // one read to restrictions register
      // only filled in inspect
      predicted_mmio_result = predict_mmio_restriction(current_transaction);
      mmio_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));

      // one read to aux1 register (here: base)
      // only filled in inspect
      predicted_mmio_result = predict_mmio_aux_out(current_transaction);
      mmio_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));

      if (current_transaction.valid_test) begin
        unique case (current_transaction.operation)
          NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE, NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE,NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE,NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE,NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE,NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK:
          begin
            predicted_mmio_result = predict_mmio_token(current_transaction);
          end
          default: begin
            // e.g., DROP, inspect, restrict - no output
            predicted_mmio_result = predict_mmio_token_erased();
          end
        endcase
      end else begin
        // no return as not committed
        predicted_mmio_result = predict_mmio_token_erased();
      end
      mmio_result_fifo.get(real_mmio_result);
      if (CHECK_AXI_TRANSACTIONS) begin
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_mmio_result, predicted_mmio_result));
      end else begin
        // if are in integration test mode, we cannot predict the tag (by design, since we do not know the RNG outputs)
        // hence, consume the response from the FIFO and do a basic sanity check
        if (real_mmio_result.read_data == '0) begin
          if (current_transaction.valid_test && !(current_transaction.operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT, NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP})) begin
            `uvm_error(COMPONENT_NAME, "Read token should never be all-zeros on successfull test!");
          end
        end else begin
          if (!current_transaction.valid_test) begin
            `uvm_error(COMPONENT_NAME, "Read token should be all-zeros on error test!");
          end
        end
        last_output_token = real_mmio_result.read_data;
      end

      predicted_mmio_result = predict_mmio_token_erased();
      mmio_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));

      if (CHECK_CAPABILITY_COUNT) begin
        calculate_capability_count(current_transaction);
      end

      predicted_mmio_result = predict_mmio_capability_count();
      mmio_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));
      // RNG register check
      mmio_result_fifo.get(real_mmio_result);
      if (real_mmio_result.response != OKAY) begin
        `uvm_error(COMPONENT_NAME, $sformatf("RNG read result %s!", real_mmio_result.response.name()
                   ));
      end
      /* in ops-scoped tests, this stops being driven - otherwise, would not be able to predict keys for test */
      if (!CHECK_AXI_TRANSACTIONS) begin
        // invariant: either 0 (error) or not the same value as last time - could otherwise be stolen
        if (real_mmio_result.read_data == '0 || real_mmio_result.read_data == last_rng_output) begin
          `uvm_error(
              COMPONENT_NAME, $sformatf(
              "Read RNG data invalid %x with last %x!", real_mmio_result.read_data, last_rng_output
              ));
        end
      end

      if (real_mmio_result.read_data != '0) begin
        last_rng_output = real_mmio_result.read_data;
      end
    endtask

    task check_stop_sequence_csr(const ref transaction_t current_transaction);
      csr_result_t predicted_mmio_result, real_mmio_result;

      predicted_mmio_result =
          mmio_result_to_csr_result(predict_mmio_done(current_transaction, 1'b1));
      csr_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));


      // one read to restrictions register
      // only filled in inspect
      predicted_mmio_result =
          mmio_result_to_csr_result(predict_mmio_restriction(current_transaction));
      csr_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));

      // one read to aux1 register (here: base)
      // only filled in inspect
      predicted_mmio_result = mmio_result_to_csr_result(predict_mmio_aux_out(current_transaction));
      csr_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));

      if (current_transaction.valid_test) begin
        unique case (current_transaction.operation)
          NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE, NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE,NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE,NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE,NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE,NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK:
          begin
            predicted_mmio_result =
                mmio_result_to_csr_result(predict_mmio_token(current_transaction));
          end
          default: begin
            // e.g., DROP, inspect, restrict - no output
            predicted_mmio_result = mmio_result_to_csr_result(predict_mmio_token_erased());
          end
        endcase
      end else begin
        // no return as not committed
        predicted_mmio_result = mmio_result_to_csr_result(predict_mmio_token_erased());
      end
      csr_result_fifo.get(real_mmio_result);
      if (CHECK_AXI_TRANSACTIONS) begin
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_mmio_result, predicted_mmio_result));
      end else begin
        // if are in integration test mode, we cannot predict the tag (by design, since we do not know the RNG outputs)
        // hence, consume the response from the FIFO and do a basic sanity check
        if (real_mmio_result.response.reg_old_val == '0) begin
          if (current_transaction.valid_test && !(current_transaction.operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT, NORTHCAPE_CAPABILITY_OPS_OPERATION_SWEEP})) begin
            `uvm_error(COMPONENT_NAME, "Read token should never be all-zeros on successfull test!");
          end
        end else begin
          if (!current_transaction.valid_test) begin
            `uvm_error(COMPONENT_NAME, "Read token should be all-zeros on error test!");
          end
        end
        last_output_token = real_mmio_result.response.reg_old_val;
      end

      predicted_mmio_result = mmio_result_to_csr_result(predict_mmio_token_erased());
      csr_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));

      if (CHECK_CAPABILITY_COUNT) begin
        calculate_capability_count(current_transaction);
      end

      predicted_mmio_result = mmio_result_to_csr_result(predict_mmio_capability_count());
      csr_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));
      // RNG register check
      csr_result_fifo.get(real_mmio_result);
      /* in ops-scoped tests, this stops being driven - otherwise, would not be able to predict keys for test */
      if (!CHECK_AXI_TRANSACTIONS) begin
        // invariant: either 0 (error) or not the same value as last time - could otherwise be stolen
        if (real_mmio_result.response.reg_old_val == '0 || real_mmio_result.response.reg_old_val == last_rng_output) begin
          `uvm_error(COMPONENT_NAME, $sformatf(
                     "Read RNG data invalid %x with last %x!",
                     real_mmio_result.response.reg_old_val,
                     last_rng_output
                     ));
        end
      end

      if (real_mmio_result.response.reg_old_val != '0) begin
        last_rng_output = real_mmio_result.response.reg_old_val;
      end
    endtask

    task check_enable_sequence_start_mmio();
      mmio_result_t predicted_mmio_result, real_mmio_result;

      predicted_mmio_result = new("MMIO result");
      predicted_mmio_result.request_type = AXI_TEST_WRITE;
      predicted_mmio_result.response = OKAY;

      mmio_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));
    endtask

    task check_enable_sequence_stop_mmio();
      mmio_result_t predicted_mmio_result, real_mmio_result;

      predicted_mmio_result = new("MMIO result");
      predicted_mmio_result.request_type = AXI_TEST_READ;
      predicted_mmio_result.response = OKAY;
      // OK + one capability (root capability) in the system
      predicted_mmio_result.read_data = {1'b1, 62'h0, CHECK_CAPABILITY_COUNT};

      mmio_result_fifo.get(real_mmio_result);
      checker_port.write(NorthcapeGenericCheckerCompItem::new(
                         real_mmio_result, predicted_mmio_result));
    endtask

    task run_phase(uvm_phase phase);
      transaction_t current_transaction;
      bit have_initial_key_nonce;

      phase.raise_objection(this);
      if (CHECK_AXI_TRANSACTIONS) begin
        // this is always done before everyting else
        predict_occupied_init();
      end

      // enable is always done via MMIO in this testbench
      check_enable_sequence_start_mmio();

      if (CHECK_AXI_TRANSACTIONS) begin
        `uvm_info(COMPONENT_NAME, "Scoreboard waiting for overwrite transactions to complete",
                  UVM_MEDIUM);
        check_cmt_reset();
        `uvm_info(COMPONENT_NAME, "Scoreboard completed overwrite transactions", UVM_MEDIUM);
      end else begin
        // accounts for one capability (root) created without explicit MMIO operation to trigger it
        capability_count++;
      end

      check_enable_sequence_stop_mmio();

      have_initial_key_nonce = 0;


      phase.drop_objection(this);

      forever begin : checkOneTransaction
        mmio_result_t real_mmio_result;
        `uvm_info(COMPONENT_NAME, "Waiting for transaction from FIFO!", UVM_DEBUG);
        transaction_port.get_next_item(current_transaction);
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Got transaction from FIFO: %s!", current_transaction.convert2string()),
                  UVM_DEBUG);

        phase.raise_objection(this);

        // agent will run enable sequence to configure settings
        check_enable_sequence_start_mmio();
        // TODO capability count not checked, but need to retrieve the result to ensure state invariants
        mmio_result_fifo.get(real_mmio_result);

        if (!have_initial_key_nonce) begin
          generate_initial_key_nonce();
          have_initial_key_nonce = 1;
        end

        if (current_transaction.use_rcsr_interface) begin
          check_start_sequence_csr(current_transaction);
        end else begin
          check_start_sequence_mmio(current_transaction);
        end

        if (CHECK_AXI_TRANSACTIONS) begin
          if (current_transaction.valid_test || current_transaction.operation_is_supported()) begin
            unique case (current_transaction.operation)
              NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE,NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE,NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP,NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE,NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE,NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE,NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
                check_rmw(current_transaction);
              end
              default: begin
                `uvm_fatal(COMPONENT_NAME, $sformatf(
                           "Could not check operation: operation %x not known!",
                           current_transaction.operation
                           ));
              end
            endcase
          end
        end

        transaction_port.item_done();

        `uvm_info(COMPONENT_NAME, "Waiting for stop sequence!", UVM_DEBUG);
        if (current_transaction.use_rcsr_interface) begin
          check_stop_sequence_csr(current_transaction);
        end else begin
          check_stop_sequence_mmio(current_transaction);
        end

        if (current_transaction.valid_test && (!current_transaction.use_isr_fsm || current_transaction.operation != NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT)) begin
          // nonce inc'ed for all operations, even if nothing is written
          // exception: inspect operations that go through ISR FSM
          ops_current_nonce++;
        end

        phase.drop_objection(this);
      end : checkOneTransaction

    endtask

  endclass
endpackage
