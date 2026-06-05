/**
  * Top-level module of the Northcape capability cache.
  * This cache keeps northcape CMT entries and is shared between ops and resolver.
  * It also contains the miss- and writeback-logic.
  *
  */
module northcape_capability_cache #(
    parameter int HASH_TYPE = -1,

    // support request_cache_flush and request_close_speculation_window signals from resolver?
    parameter bit SUPPORT_SPECULATIVE_RESOLVER_LOADS = 1'b0,

    // only store the top CMT entry, not all of its parents, in the case of resolver recursion
    parameter bit KEEP_TOP_CMT_ENTRIES_ONLY = 1'b0,

    parameter northcape_capability_cache_common::northcape_capability_cache_common_cache_type_t CACHE_TYPE = northcape_capability_cache_common::NORTHCAPE_CAPABILITY_TYPE_COMMON_NO_CACHE,
    // size of the optional store buffer, used to increase Operations Write performance. Set to 0 to disable this functionality.
    parameter int STORE_BUFFER_SIZE = 0,

    // associativity for n-times associative caches. MUST be a power of two and smaller than NUM_ENTRIES.
    parameter int ASSOCIATIVITY = -1,

    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,
    // number of cache entries. For n-times associative caches, MUST be a multiple of <ASSOCIATIVITY>. Power of 2 recommended.
    parameter NUM_ENTRIES = -1,
    parameter DEBUG_ILA = 0
) (
`ifdef USE_POWER_PINS
    inout wire vccd1,
    inout wire vssd1,
`endif

    input logic clk_i,
    input logic rst_ni,

    // for missunit / write back
    Axi5.FROM axi_master,

    // connection to the units
    NorthcapeCapabilityCacheInterfaceResolver.CAP_CACHE resolver_port,
    NorthcapeCapabilityCacheInterfaceOps.CAP_CACHE ops_port,

    // current capability metadata (from operations module)
    NorthcapeCMTInterface.CONSUMER cmt_interface,

    output logic resolver_port_miss_o,
    output logic resolver_spec_fail_o,
    output logic ops_port_miss_o,
    output logic missunit_stall_o,
    output logic ops_write_stall_o
);
  import northcape_capability_cache_common::*;
  import northcape_types::*;
  `include "axi5_assign.svh"
  `include "northcape_unread.vh"

  logic cache_miss_resolver, cache_miss_ops;
  logic cache_ready_resolver, cache_ready_ops;
  logic missunit_response_valid;
  logic missunit_response_err;
  logic missunit_request_i;
  logic writeback_unit_valid;
  logic writeback_unit_error;
  northcape_cmt_entry_t cache_cmt_entry_resolver, cache_cmt_entry_ops;
  northcape_cmt_entry_t missunit_cmt_entry;
  logic missunit_response_ready;

  capability_id_t missunit_capability_id;

  northcape_capability_cache_arbitration_type_t missunit_arbitration;

  /*
   * it is possible that we incur a cache miss, start the memory read, and the operations module overwrites the capability
   * before the read completes.
   * We handle this hazard by ignoring the result from the missunit.
   */
  logic missunit_stale_d, missunit_stale_q;
  northcape_cmt_entry_t missunit_stale_buffer_d, missunit_stale_buffer_q;

  logic read_write_hazard;
  logic resolver_missunit_request_d, resolver_missunit_request_d1, resolver_missunit_request_q;
  // need to wait for store buffer to drain...
  logic read_write_store_buffer_hazard;

  /* debug - simulator use only */
  logic [$bits(northcape_cmt_entry_t)-1:0]
      dbg_ops_write_raw, dbg_ops_read_raw, dbg_resolver_read_raw;

  logic ops_write_done;

  logic speculative_resolver;

  assign dbg_ops_write_raw = ops_port.write_request_capability;
  assign dbg_ops_read_raw = ops_port.response_cmt_entry;
  assign dbg_resolver_read_raw = resolver_port.response_cmt_entry;

  assign read_write_hazard = resolver_port.request_valid && ops_port.request_valid && ops_port.is_write && (resolver_port.request_capability_id == ops_port.request_capability_id);


  northcape_capability_cache_arbitration_type_t missunit_arbitration_type;

  Axi5ReadOnly #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) missunit_intf (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  Axi5WriteOnly #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) write_back_intf (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  `NORTHCAPE_MAP_INTERFACES_READ(assign, axi_master, =, missunit_intf);
  `NORTHCAPE_MAP_INTERFACES_WRITE(assign, axi_master, =, write_back_intf);

  generate
    if (CACHE_TYPE == NORTHCAPE_CAPABILITY_TYPE_COMMON_NO_CACHE) begin : gen_no_cache
      assign cache_miss_resolver = resolver_port.request_valid;
      assign cache_miss_ops = ops_port.request_valid && !ops_port.is_write;
      assign cache_ready_ops = 1'b1;
      assign cache_ready_resolver = 1'b1;

      assign cache_cmt_entry_resolver = '0;
      assign cache_cmt_entry_ops = '0;
      // other caches can possibly accept the response on behalf of the resolver
      assign missunit_response_ready = missunit_arbitration_type == NORTHCAPE_CAP_CACHE_OPS || resolver_port.response_ready;

      assign ops_write_done = 1'b1;

      assign speculative_resolver = 1'b0;
      assign resolver_spec_fail_o = resolver_port.request_cache_flush;


      `NORTHCAPE_UNREAD(resolver_port.request_capability_tag);
      `NORTHCAPE_UNREAD(resolver_port.request_cache_flush);
      `NORTHCAPE_UNREAD(ops_port.request_capability_tag);
      `NORTHCAPE_UNREAD(ops_port.write_request_flush);
      `NORTHCAPE_UNREAD(ops_port.request_is_uncacheable);
    end : gen_no_cache
    else if (CACHE_TYPE == NORTHCAPE_CAPABILITY_TYPE_WT_DIRECT_FF) begin : gen_cache_wt_direct_ff
      // missunit response is always consumed immediately by the ops
      assign missunit_response_ready = missunit_arbitration_type == NORTHCAPE_CAP_CACHE_OPS || resolver_port.response_ready;

      assign cache_ready_ops = 1'b1;
      assign cache_ready_resolver = 1'b1;

      assign ops_write_done = 1'b1;

      assign speculative_resolver = 1'b0;
      assign resolver_spec_fail_o = resolver_port.request_cache_flush;

      northcape_capability_cache_wt_direct_ff #(
          .NUM_ENTRIES(NUM_ENTRIES),
          .SUPPORT_SPECULATIVE_RESOLVER_LOADS(SUPPORT_SPECULATIVE_RESOLVER_LOADS)
      ) i_cache_wt_direct_ff (
          .clk_i (clk_i),
          .rst_ni(rst_ni),

          .lookup_capability_resolver_id_i(resolver_port.request_capability_id),
          .lookup_capability_resolver_tag_i(resolver_port.request_capability_tag),
          .lookup_capability_ops_id_i(ops_port.request_capability_id),
          .lookup_capability_ops_tag_i(ops_port.request_capability_tag),

          .lookup_read_write_hazard_i(read_write_hazard),

          .cache_miss_resolver_o(cache_miss_resolver),
          .cache_miss_ops_o(cache_miss_ops),
          .lookup_capability_cmt_entry_resolver_o(cache_cmt_entry_resolver),
          .lookup_capability_cmt_entry_ops_o(cache_cmt_entry_ops),
          // ops does not write through missunit, only reads, to keep invariant resolver assumes for hierarchie skip
          .missunit_write_i(missunit_arbitration_type == NORTHCAPE_CAP_CACHE_RESOLVER && missunit_response_valid && !missunit_response_err && (!KEEP_TOP_CMT_ENTRIES_ONLY || !resolver_port.request_is_recursion)),
          .missunit_cmt_entry_i(missunit_cmt_entry),
          // only want one write operation, so we update the cache at the same time the memory transaction commits
          .ops_write_i(ops_port.request_valid && ops_port.is_write && writeback_unit_valid),
          .ops_cmt_entry_i(ops_port.write_request_capability),
          .ops_write_uncacheable_i(ops_port.request_is_uncacheable),

          .resolver_flush_i(resolver_port.request_cache_flush),
          .resolver_close_speculation_window_i(resolver_port.request_close_speculation_window),
          .ops_flush_i(ops_port.write_request_flush)
      );

    end : gen_cache_wt_direct_ff
    else if(CACHE_TYPE == NORTHCAPE_CAPABILITY_TYPE_WT_FULLY_ASSOC_FF) begin: gen_cache_wt_fully_assoc_ff
      // missunit response is always consumed immediately by the ops
      assign missunit_response_ready = missunit_arbitration_type == NORTHCAPE_CAP_CACHE_OPS || resolver_port.response_ready;

      assign cache_ready_ops = 1'b1;
      assign cache_ready_resolver = 1'b1;

      assign ops_write_done = 1'b1;

      assign speculative_resolver = 1'b0;
      assign resolver_spec_fail_o = resolver_port.request_cache_flush;

      northcape_capability_cache_wt_fully_assoc_ff #(
          .NUM_ENTRIES(NUM_ENTRIES),
          .SUPPORT_SPECULATIVE_RESOLVER_LOADS(SUPPORT_SPECULATIVE_RESOLVER_LOADS)
      ) i_cache_wt_fully_assoc_ff (
          .clk_i (clk_i),
          .rst_ni(rst_ni),

          .lookup_capability_resolver_id_i(resolver_port.request_capability_id),
          .lookup_capability_ops_id_i(ops_port.request_capability_id),
          // replacement is solely controlled by requests from resolver, which is performance-critical
          .lookup_valid_i(resolver_port.request_valid & resolver_port.response_ready),

          .lookup_read_write_hazard_i(read_write_hazard),

          .cache_miss_resolver_o(cache_miss_resolver),
          .cache_miss_ops_o(cache_miss_ops),
          .lookup_capability_cmt_entry_resolver_o(cache_cmt_entry_resolver),
          .lookup_capability_cmt_entry_ops_o(cache_cmt_entry_ops),
          // ops does not write through missunit, only reads, to keep invariant resolver assumes for hierarchie skip
          .missunit_write_i(missunit_arbitration_type == NORTHCAPE_CAP_CACHE_RESOLVER && missunit_response_valid && !missunit_response_err && (!KEEP_TOP_CMT_ENTRIES_ONLY || !resolver_port.request_is_recursion)),
          .missunit_cmt_entry_i(missunit_cmt_entry),
          // only want one write operation, so we update the cache at the same time the memory transaction commits
          .ops_write_i(ops_port.request_valid && ops_port.is_write && writeback_unit_valid),
          .ops_cmt_entry_i(ops_port.write_request_capability),
          .ops_write_uncacheable_i(ops_port.request_is_uncacheable),

          .resolver_flush_i(resolver_port.request_cache_flush),
          .resolver_close_speculation_window_i(resolver_port.request_close_speculation_window),
          .ops_flush_i(ops_port.write_request_flush)
      );
      `NORTHCAPE_UNREAD(resolver_port.request_capability_tag);
      `NORTHCAPE_UNREAD(ops_port.request_capability_tag);
    end : gen_cache_wt_fully_assoc_ff
    else if(CACHE_TYPE == NORTHCAPE_CAPABILITY_TYPE_WT_DIRECT_BRAM) begin: gen_cache_wt_direct_bram
      // missunit response is always consumed immediately by the ops
      assign missunit_response_ready = missunit_arbitration_type == NORTHCAPE_CAP_CACHE_OPS || resolver_port.response_ready;

      assign ops_write_done = 1'b1;

      assign speculative_resolver = 1'b0;
      assign resolver_spec_fail_o = resolver_port.request_cache_flush;

      northcape_capability_cache_wt_direct_bram #(
          .NUM_ENTRIES(NUM_ENTRIES)
      ) i_cache_wt_direct_bram (
          .clk_i (clk_i),
          .rst_ni(rst_ni),

          .lookup_capability_resolver_id_i(resolver_port.request_capability_id),
          .lookup_capability_resolver_valid_i(resolver_port.request_valid),
          .lookup_capability_resolver_ready_i(resolver_port.response_ready),

          .lookup_capability_ops_id_i(ops_port.request_capability_id),
          .lookup_capability_ops_valid_i(ops_port.request_valid),
          .lookup_capability_ops_ready_i(1'b1),  // ops always ready


          .lookup_read_write_hazard_i(read_write_hazard),

          .cache_miss_resolver_o(cache_miss_resolver),
          .cache_miss_ops_o(cache_miss_ops),
          .lookup_capability_cmt_entry_resolver_o(cache_cmt_entry_resolver),
          .lookup_capability_cmt_entry_ops_o(cache_cmt_entry_ops),
          .cache_ready_resolver_o(cache_ready_resolver),
          .cache_ready_ops_o(cache_ready_ops),


          // ops does not write through missunit, only reads, to keep invariant resolver assumes for hierarchie skip
          .missunit_valid_i(missunit_arbitration_type == NORTHCAPE_CAP_CACHE_RESOLVER && missunit_response_valid && !missunit_response_err),
          .missunit_write_i(!KEEP_TOP_CMT_ENTRIES_ONLY || !resolver_port.request_is_recursion),

          // used to hold the start signal high - does not write
          .missunit_write_ops_i(missunit_arbitration_type == NORTHCAPE_CAP_CACHE_OPS && missunit_response_valid && !missunit_response_err),
          .missunit_cmt_entry_i(missunit_cmt_entry),
          // only want one write operation, so we update the cache at the same time the memory transaction commits
          .ops_write_i(ops_port.request_valid && ops_port.is_write && writeback_unit_valid),
          .ops_cmt_entry_i(ops_port.write_request_capability),
          .ops_write_uncacheable_i(ops_port.request_is_uncacheable),

          .resolver_flush_i(resolver_port.request_cache_flush),
          .resolver_close_speculation_window_i(resolver_port.request_close_speculation_window),
          .ops_flush_i(ops_port.write_request_flush)
      );
      `NORTHCAPE_UNREAD(resolver_port.request_capability_tag);
      `NORTHCAPE_UNREAD(ops_port.request_capability_tag);
    end : gen_cache_wt_direct_bram
    else if(CACHE_TYPE == NORTHCAPE_CAPABILITY_TYPE_WT_N_ASSOC_BRAM)
    begin: gen_cache_wt_n_assoc_bram
      // missunit response is always consumed immediately by the ops
      assign missunit_response_ready = missunit_arbitration_type == NORTHCAPE_CAP_CACHE_OPS || resolver_port.response_ready;
      northcape_capability_cache_wt_n_assoc_bram #(
          .NUM_ENTRIES  (NUM_ENTRIES),
          .ASSOCIATIVITY(ASSOCIATIVITY)
      ) i_cache_wt_direct_bram (
`ifdef USE_POWER_PINS
          .vccd1 (vccd1),
          .vssd1 (vssd1),
`endif
          .clk_i (clk_i),
          .rst_ni(rst_ni),

          .lookup_capability_resolver_id_i(resolver_port.request_capability_id),
          .lookup_capability_resolver_valid_i(resolver_port.request_valid),
          .lookup_capability_resolver_ready_i(resolver_port.response_ready),
          .speculative_resolver_o(speculative_resolver),

          .lookup_capability_ops_id_i(ops_port.request_capability_id),
          .lookup_capability_ops_valid_i(ops_port.request_valid),
          .lookup_capability_ops_ready_i(1'b1),  // ops always ready


          .lookup_read_write_hazard_i(read_write_hazard),

          .cache_miss_resolver_o(cache_miss_resolver),
          .cache_miss_ops_o(cache_miss_ops),
          .lookup_capability_cmt_entry_resolver_o(cache_cmt_entry_resolver),
          .lookup_capability_cmt_entry_ops_o(cache_cmt_entry_ops),
          .cache_ready_resolver_o(cache_ready_resolver),
          .cache_ready_ops_o(cache_ready_ops),


          // ops does not write through missunit, only reads, to keep invariant resolver assumes for hierarchie skip
          .missunit_valid_i(missunit_arbitration_type == NORTHCAPE_CAP_CACHE_RESOLVER && missunit_response_valid && !missunit_response_err),
          .missunit_write_i(!KEEP_TOP_CMT_ENTRIES_ONLY || !resolver_port.request_is_recursion),

          // used to hold the start signal high - does not write
          .missunit_write_ops_i(missunit_arbitration_type == NORTHCAPE_CAP_CACHE_OPS && missunit_response_valid && !missunit_response_err),
          .missunit_cmt_entry_i(missunit_cmt_entry),
          // only want one write operation, so we update the cache at the same time the memory transaction commits
          .ops_write_i(ops_port.request_valid && ops_port.is_write && writeback_unit_valid),
          .ops_write_done_o(ops_write_done),
          .ops_cmt_entry_i(ops_port.write_request_capability),
          .ops_write_uncacheable_i(ops_port.request_is_uncacheable),

          .resolver_flush_i(resolver_port.request_cache_flush),
          .resolver_close_speculation_window_i(resolver_port.request_close_speculation_window),
          .resolver_is_recursion_i(resolver_port.request_is_recursion),
          .ops_flush_i(ops_port.write_request_flush),

          .resolver_spec_fail_o(resolver_spec_fail_o)
      );
      `NORTHCAPE_UNREAD(resolver_port.request_capability_tag);
      `NORTHCAPE_UNREAD(ops_port.request_capability_tag);
    end : gen_cache_wt_n_assoc_bram
    else begin : gen_error
      $error("Unknown cache type!");
    end : gen_error
  endgenerate

  northcape_capability_cache_arbiter #(
      .arbitration_type_t(capability_id_t)
  ) i_missunit_arbiter (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .input_resolver_i(resolver_port.request_capability_id),
      .input_ops_i(ops_port.request_capability_id),
      // in case of read-write hazard, immediately use the new value from ops
      .request_resolver_i(resolver_missunit_request_d),
      .request_ops_i(ops_port.request_valid && cache_miss_ops && cache_ready_ops && !ops_port.is_write),
      .operation_complete_i(missunit_response_valid && missunit_response_ready),
      .arbited_input_o(missunit_capability_id),
      .any_request_o(missunit_request_i),
      .arbitration_result_o(missunit_arbitration_type)
  );

  northcape_capability_cache_missunit #(
      .HASH_TYPE(HASH_TYPE),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) i_missunit (
      .rst_ni(rst_ni),

      .axi_master(missunit_intf),
      .cmt_interface(cmt_interface),
      // need to stall the missunit request until store buffer was commited - otherwise, read-after-write hazard!
      .request_capability_id_valid_i(missunit_request_i && !read_write_store_buffer_hazard),
      .request_capability_id_i(missunit_capability_id),

      .response_ready_i(missunit_response_ready),

      .response_capability_o(missunit_cmt_entry),
      .response_valid_o(missunit_response_valid),
      .response_err_o(missunit_response_err)
  );

  assign missunit_stall_o  = missunit_request_i && read_write_store_buffer_hazard;
  assign ops_write_stall_o = ops_port.request_valid && ops_port.is_write && !writeback_unit_valid;

  northcape_capability_cache_writeback_unit #(
      .HASH_TYPE(HASH_TYPE),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .STORE_BUFFER_SIZE(STORE_BUFFER_SIZE),
      .DEBUG_ILA(DEBUG_ILA)
  ) i_writeback_unit (
      .rst_ni(rst_ni),
      .axi_master(write_back_intf),
      .cmt_interface(cmt_interface),
      /* N-times associative cache: needs one extra cycle to write into actual cache, so will hold request valid one cycle too long */
      .request_capability_id_valid_i(ops_port.request_valid && ops_port.is_write && (CACHE_TYPE == NORTHCAPE_CAPABILITY_TYPE_WT_N_ASSOC_BRAM ? ~ops_write_done : 1'b1)),
      .request_capability_id_i(ops_port.request_capability_id),
      .request_capability_i(ops_port.write_request_capability),
      .missunit_capability_id_i(missunit_capability_id),
      .response_valid_o(writeback_unit_valid),
      .response_err_o(writeback_unit_error),
      .store_buffer_hazard_o(read_write_store_buffer_hazard)
  );

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : staleFFs
    if (!rst_ni) begin
      missunit_stale_q <= 1'b0;
      missunit_stale_buffer_q <= '0;
      resolver_missunit_request_q <= 1'b0;
    end else begin
      missunit_stale_q <= missunit_stale_d;
      missunit_stale_buffer_q <= missunit_stale_buffer_d;
      resolver_missunit_request_q <= resolver_missunit_request_d1;
    end
  end : staleFFs

  always_comb begin : missunitStaleLogic
    missunit_stale_d = missunit_stale_q;
    missunit_stale_buffer_d = missunit_stale_buffer_q;

    if (resolver_missunit_request_d && read_write_hazard) begin
      // second cycle of the miss transaction and onward
      // have to complete the miss transaction, but kignore it
      // we stop doing that as soon as the miss unit completes
      missunit_stale_d = 1'b1;
      missunit_stale_buffer_d = ops_port.write_request_capability;
    end

    if (missunit_arbitration_type == NORTHCAPE_CAP_CACHE_RESOLVER && missunit_response_valid) begin
      // missunit completed - do not carry this over into the next transaction
      missunit_stale_d = 1'b0;
    end

  end : missunitStaleLogic

  always_comb begin : resolverResponseGenerator
    resolver_port.response_valid = 1'b0;
    resolver_port.response_cmt_entry = 1'b0;
    resolver_port.response_err = 1'b0;
    resolver_port.response_cache_hit = 1'b0;

    ops_port.response_valid = 1'b0;
    ops_port.response_cmt_entry = 1'b0;
    ops_port.response_err = 1'b0;

    resolver_port_miss_o = 1'b0;
    ops_port_miss_o = 1'b0;

    if (resolver_port.request_valid) begin
      // in case of write hazard, the resolver has to do a full re-check
      resolver_port.response_cache_hit = cache_ready_resolver && !cache_miss_resolver && !read_write_hazard && !speculative_resolver;
      // at least 1 cycle has passed - did the lookup, miss flag is valid
      if (!cache_miss_resolver && cache_ready_resolver) begin
        resolver_port.response_valid = 1'b1;
        resolver_port.response_err   = 1'b0;
        if (read_write_hazard) begin
          // cache hit and read-write hazard - be sure to use the new value from ops
          // next cycle will serve cache hit from ops or start a new fetch
          resolver_port.response_cmt_entry = ops_port.write_request_capability;
        end else begin
          resolver_port.response_cmt_entry = cache_cmt_entry_resolver;
        end
      end
        else if(cache_ready_resolver && missunit_arbitration_type == NORTHCAPE_CAP_CACHE_RESOLVER && missunit_response_valid)
        begin
        resolver_port.response_valid = 1'b1;
        if (missunit_stale_d || read_write_hazard) begin
          // the ops module wrote the same capability in this cycle or at any point between the start of the lookup and now
          // we can use the current or buffered write CMT entry from the ops module, captured when the conflict arose
          resolver_port.response_cmt_entry = missunit_stale_buffer_d;
          resolver_port.response_err = 1'b0;
        end else begin
          // forward from missunit
          resolver_port.response_cmt_entry = missunit_cmt_entry;
          resolver_port.response_err = missunit_response_err;
        end
        // only count the miss in one (final) cycle
        // also, ignore "misses" for non-cacheable capabilities
        resolver_port_miss_o  = missunit_response_ready && resolver_port.response_cmt_entry.permissions.indirect_capability_permissions.cacheable_tlb;
      end
    end

    if (ops_port.request_valid) begin
      if (ops_port.is_write) begin
        // write - need response from writeback unit
        // for N-times assoc BRAM, we need 1 extra cycle to check if value is already in the cache
        // hence, ops cache write is actually the last step
        // so we need to stall for one cycle, giving the cache a chance to complete the transaction
        ops_port.response_valid = CACHE_TYPE == NORTHCAPE_CAPABILITY_TYPE_WT_N_ASSOC_BRAM ? ops_write_done : writeback_unit_valid;
        ops_port.response_err = writeback_unit_error;
      end else begin
        // read - check cache and missunit
        if (!cache_miss_ops && cache_ready_ops) begin
          ops_port.response_valid = 1'b1;
          ops_port.response_cmt_entry = cache_cmt_entry_ops;
        end
          else if(cache_ready_ops && missunit_arbitration_type == NORTHCAPE_CAP_CACHE_OPS && missunit_response_valid)
          begin
          ops_port.response_valid = 1'b1;
          ops_port.response_cmt_entry = missunit_cmt_entry;
          ops_port.response_err = missunit_response_err;
          // ignore "misses" for non-cacheable capabilities
          ops_port_miss_o  = ops_port.response_cmt_entry.permissions.indirect_capability_permissions.cacheable_tlb;
        end
      end
    end
  end : resolverResponseGenerator

  always_comb begin : resolverMissunitRequestLogic
    if (resolver_missunit_request_q) begin
      // we have raised the request - need to maintain it no matter what
      // required by the arbiter, missunit FSMs and the read-write hazard unit
      // we only stop doing the request after processing the response
      resolver_missunit_request_d1 = !(missunit_arbitration_type == NORTHCAPE_CAP_CACHE_RESOLVER && missunit_response_valid && resolver_port.response_ready);
      // need to hold the value for this cycle
      resolver_missunit_request_d = 1'b1;
    end else begin
      // resolver not valid - no miss to resolve
      // no cache miss - no miss to resolve
      // read-write hazard - will resolve with the value to be written immediately
      resolver_missunit_request_d1 = resolver_port.request_valid && cache_miss_resolver && cache_ready_resolver && !read_write_hazard;
      // do we start a new missunit transaction?
      resolver_missunit_request_d = resolver_missunit_request_d1;
    end
  end : resolverMissunitRequestLogic


  generate
    if (DEBUG_ILA) begin : gen_debug_ila
      northcape_capability_cache_ila i_ila (
          .clk(clk_i),
          .probe0(resolver_port.request_valid),  // 1 bit
          .probe1(resolver_port.request_capability_id),  // 38 bits
          .probe2(resolver_port.request_capability_tag),  // 16 bits
          .probe3(ops_port.request_valid),  // 1 bit
          .probe4(ops_port.request_capability_id),  // 38 bits
          .probe5(ops_port.request_capability_tag),  // 16 bits
          .probe6(ops_port.is_write),  // 1 bit
          .probe7(resolver_port.request_cache_flush),  // 1 bit
          .probe8(ops_port.write_request_flush),  // 1 bit
          .probe9(read_write_hazard),  // 1 bit
          .probe10(cache_miss_resolver),  // 1 bit
          .probe11(cache_miss_ops),  // 1 bit
          .probe12(resolver_port.response_valid),  // 1 bit
          .probe13(resolver_port.response_cmt_entry),  // 256 bit
          .probe14(ops_port.response_valid),  // 1 bit
          .probe15(ops_port.response_cmt_entry)  // 256 bit
      );
    end : gen_debug_ila
  endgenerate

  `NORTHCAPE_UNREAD(axi_master.rst_ni);
  `NORTHCAPE_UNREAD(axi_master.bid);
  `NORTHCAPE_UNREAD(axi_master.clk_i);
  `NORTHCAPE_UNREAD(resolver_port.clk_i);
  `NORTHCAPE_UNREAD(ops_port.clk_i);
  `NORTHCAPE_UNREAD(dbg_ops_write_raw);
  `NORTHCAPE_UNREAD(dbg_ops_read_raw);
  `NORTHCAPE_UNREAD(dbg_resolver_read_raw);


endmodule
