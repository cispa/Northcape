/**
  * Northcape capability cache core cache implementation - n-times associative, write-through, using block RAM as backing storage.
  */
module northcape_capability_cache_wt_n_assoc_bram #(
    parameter NUM_ENTRIES = -1,
    // log2 of max. size of speculation window (not relevant for security/performance - only to re-validate speculative entries "early")
    parameter SPEC_WINDOW_FIFO_SIZE_CLOG2 = 3,
    parameter ASSOCIATIVITY = -1
) (
    input logic clk_i,
    input logic rst_ni,

`ifdef USE_POWER_PINS
    inout wire vccd1,
    inout wire vssd1,
`endif

    input northcape_types::capability_id_t lookup_capability_resolver_id_i,
    input logic lookup_capability_resolver_valid_i,
    input logic lookup_capability_resolver_ready_i,

    input northcape_types::capability_id_t lookup_capability_ops_id_i,
    input logic lookup_capability_ops_valid_i,
    input logic lookup_capability_ops_ready_i,


    input logic lookup_read_write_hazard_i,

    output logic cache_miss_resolver_o,
    output logic cache_miss_ops_o,
    output logic speculative_resolver_o,
    output northcape_types::northcape_cmt_entry_t lookup_capability_cmt_entry_resolver_o,
    output northcape_types::northcape_cmt_entry_t lookup_capability_cmt_entry_ops_o,
    // account for SRAM latency
    output logic cache_ready_resolver_o,
    output logic cache_ready_ops_o,

    // commit missunit result
    input logic missunit_write_i,
    // missunit has valid response - important for ready flag
    input logic missunit_valid_i,
    input logic missunit_write_ops_i,
    input northcape_types::northcape_cmt_entry_t missunit_cmt_entry_i,

    input logic ops_write_i,
    input northcape_types::northcape_cmt_entry_t ops_cmt_entry_i,
    input logic ops_write_uncacheable_i,
    // handshake for write - takes 2 cycles for this cache
    output logic ops_write_done_o,

    input logic resolver_flush_i,
    input logic resolver_is_recursion_i,
    input logic resolver_close_speculation_window_i,
    input logic ops_flush_i,

    // to performance counter
    output logic resolver_spec_fail_o
);

  import northcape_types::*;
  import northcape_capability_resolver_common::NorthcapeCapabilityResolverHash;
  import northcape_capability_resolver_common::HASH_TYPE_DJB2;

  typedef NorthcapeCapabilityResolverHash#(HASH_TYPE_DJB2) hash_t;

  localparam int BYTE_WIDTH = 8;


  `include "northcape_unread.vh"

  typedef struct packed {
    // needs to be pack-able into a byte-addressed data structure - otherwise, cannot use byte-granular write strobes!
    logic [(BYTE_WIDTH - (($bits(
capability_id_t
) + $bits(
northcape_cmt_entry_t
)) % BYTE_WIDTH)) - 1 : 0] padding;
    // needed to ensure this is the correct capability
    capability_id_t capability_id;
    // the full entry
    northcape_cmt_entry_t entry;
  } cache_data_t;


  generate
    if ($bits(cache_data_t) % 8) begin
      $error("Invalid padding!");
    end
    if (NUM_ENTRIES % ASSOCIATIVITY || NUM_ENTRIES <= ASSOCIATIVITY) begin
      $error("Invalid number of entries / associativity!");
    end
  endgenerate

  // SRAM stores one associative set in parallel
  cache_data_t [ASSOCIATIVITY-1:0] metadata_resolver_out, metadata_ops_out;
  cache_data_t [ASSOCIATIVITY-1:0] metadata_resolver_in, metadata_ops_in;

  localparam int CACHE_DATA_BYTES_PER_ENTRY = (($bits(cache_data_t) + BYTE_WIDTH - 1) / BYTE_WIDTH);

  localparam int CACHE_DATA_BYTES = CACHE_DATA_BYTES_PER_ENTRY * ASSOCIATIVITY;

  localparam int CACHE_DATA_WIDTH = CACHE_DATA_BYTES * BYTE_WIDTH;


  typedef logic [ASSOCIATIVITY-1:0] assoc_set_t;

  typedef logic [$clog2(ASSOCIATIVITY)-1:0] assoc_set_idx_t;

  localparam int NUM_ASSOC_SETS = NUM_ENTRIES / ASSOCIATIVITY;

  // one data width = one associativity set
  localparam int CACHE_ADDR_WIDTH = $clog2(NUM_ASSOC_SETS);

  localparam int CACHE_NUM_ENTRIES = 2 ** CACHE_ADDR_WIDTH;

  typedef logic [$clog2(NUM_ENTRIES)-1:0] slot_index_t;

  typedef logic [SPEC_WINDOW_FIFO_SIZE_CLOG2-1:0] spec_fifo_index_t;

  slot_index_t current_index;

  spec_fifo_index_t spec_fifo_wr_ptr_d, spec_fifo_wr_ptr_d1, spec_fifo_wr_ptr_q;

  // speculation FIFO: tracks slots in the current speculation window.
  logic [2**SPEC_WINDOW_FIFO_SIZE_CLOG2 - 1 : 0][$clog2(NUM_ENTRIES)-1:0] spec_fifo_d, spec_fifo_q;


  logic [CACHE_DATA_WIDTH-1:0]
      cache_wdata_resolver, cache_wdata_ops, cache_rdata_resolver, cache_rdata_ops;
  logic [CACHE_ADDR_WIDTH-1:0] cache_addr_resolver, cache_addr_ops;

  logic cache_wenable_resolver, cache_wenable_ops;
  logic cache_enable_resolver, cache_enable_ops;


  logic cache_ready_resolver_q, cache_ready_resolver_d;
  logic cache_ready_ops_q, cache_ready_ops_d;

  logic resolver_cacheable, ops_cacheable;

  logic resolver_flush_q, resolver_flush_d;
  logic resolver_close_speculation_window_q, resolver_close_speculation_window_d;

  // read-after-write hazard: for the case in which a capability is already in the cache when the ops writes it, 
  // I need to do a lookup in the cache BEFORE I write and (if necessary) overwrite the previous entry
  // only needed for ops, as for the resolver, I only write from the missunit
  // as the ops write is buffered, I need to buffer the control signals too
  logic ops_write_q, ops_write_d;
  logic lookup_read_write_hazard_d, lookup_read_write_hazard_q;

  // ops_write_q should only be valid for 1 cycle, so we can do the write
  // ops_write_i will continue high for that one cycle, as everyone waits for the cache
  assign ops_write_d = ops_write_i && !ops_write_q;

  // 1-bit bitmap for valid, speculative, used (for replacement). Needed to be able to close speculation window in 1 cycle.
  // Hazard handling via state machine would be possible but expensive, as delay would be needed.
  // ordered by associativity set
  assoc_set_t [NUM_ASSOC_SETS-1:0]
      valid_bitmap_d,
      valid_bitmap_q,
      speculative_bitmap_d,
      speculative_bitmap_q,
      used_bitmap_d,
      used_bitmap_q;


  assoc_set_t cache_match_resolver, cache_match_ops;

  assoc_set_t unused_entries_ops, unused_entries_resolver;

  // LZC has a one bit larger output, used when the input vector is all ones - we discard this bit and rely on wrap around instead
  logic [$clog2(ASSOCIATIVITY):0]
      cache_line_resolver_read_out,
      cache_line_ops_read_out,
      cache_line_update_resolver_out,
      cache_line_update_ops_out;

  assoc_set_idx_t
      cache_line_resolver_read,
      cache_line_ops_read,
      cache_line_update_resolver,
      cache_line_update_ops,
      cache_line_update_resolver_final,
      cache_line_update_ops_final;

  assign cache_line_resolver_read = ASSOCIATIVITY - cache_line_resolver_read_out[$clog2(
      ASSOCIATIVITY
  )-1:0] - 1;
  assign cache_line_ops_read = ASSOCIATIVITY - cache_line_ops_read_out[$clog2(
      ASSOCIATIVITY
  )-1:0] - 1;
  assign cache_line_update_resolver = ASSOCIATIVITY - cache_line_update_resolver_out[$clog2(
      ASSOCIATIVITY
  )-1:0] - 1;
  assign cache_line_update_ops = ASSOCIATIVITY - cache_line_update_ops_out[$clog2(
      ASSOCIATIVITY
  )-1:0] - 1;

  northcape_sram_dport #(
      .DATA_WIDTH  (CACHE_DATA_WIDTH),
      .DATA_DEPTH  (NUM_ASSOC_SETS),
      // needed to handle cases where the ops writes at the same time the resolver is waiting for a read -> RAW hazard
      .WRITE_FIRST (1'b1),
      .INIT_TO_ZERO(1'b1)
  ) i_cache_sram (
`ifdef USE_POWER_PINS
      .vccd1(vccd1),
      .vssd1(vssd1),
`endif

      .clk_i(clk_i),

      .a_wdata_i  (cache_wdata_resolver),
      .a_wenable_i(cache_wenable_resolver),

      .a_addr_i  (cache_addr_resolver),
      .a_rdata_o (cache_rdata_resolver),
      .a_enable_i(cache_enable_resolver),


      .b_wdata_i  (cache_wdata_ops),
      .b_wenable_i(cache_wenable_ops),

      .b_addr_i  (cache_addr_ops),
      .b_rdata_o (cache_rdata_ops),
      .b_enable_i(cache_enable_ops)
  );

  northcape_leading_zero_count #(
      .SIZE(ASSOCIATIVITY)
  ) i_resolver_hit_count (
      .one_hot_i(cache_match_resolver),
      .leading_zero_count_o(cache_line_resolver_read_out)
  );

  northcape_leading_zero_count #(
      .SIZE(ASSOCIATIVITY)
  ) i_resolver_update (
      .one_hot_i(unused_entries_resolver),
      .leading_zero_count_o(cache_line_update_resolver_out)
  );

  northcape_leading_zero_count #(
      .SIZE(ASSOCIATIVITY)
  ) i_ops_hit_count (
      .one_hot_i(cache_match_ops),
      .leading_zero_count_o(cache_line_ops_read_out)
  );

  northcape_leading_zero_count #(
      .SIZE(ASSOCIATIVITY)
  ) i_ops_update (
      .one_hot_i(unused_entries_ops),
      .leading_zero_count_o(cache_line_update_ops_out)
  );

  logic [63:0] resolver_id_hash, ops_id_hash;


  // in the same place for all types of capability
  assign resolver_cacheable = missunit_cmt_entry_i.permissions.direct_capability_permissions.cacheable_tlb;
  // operations module can also explicitly disable cacheability on write
  assign ops_cacheable = ops_cmt_entry_i.permissions.direct_capability_permissions.cacheable_tlb && !ops_write_uncacheable_i;
  // simple pass-throughs
  assign cache_wdata_resolver = metadata_resolver_in;
  assign cache_wdata_ops = metadata_ops_in;

  // ops_write_done_q is high in the actual cycle we commence the write only
  assign ops_write_done_o = ops_write_q;

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : readyRegs
    if (!rst_ni) begin
      cache_ready_resolver_q <= 1'b0;
      cache_ready_ops_q <= 1'b0;
    end else begin
      cache_ready_resolver_q <= cache_ready_resolver_d;
      cache_ready_ops_q <= cache_ready_ops_d;
    end
  end : readyRegs

  // cannot possibly be valid 1 cycle after it happened -> need to lower the signal again
  assign resolver_flush_d = resolver_flush_q ? 1'b0 : resolver_flush_i;
  assign resolver_close_speculation_window_d = resolver_close_speculation_window_q ? 1'b0 : resolver_close_speculation_window_i;

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : bitmapRegs
    if (!rst_ni) begin
      valid_bitmap_q <= '0;
      speculative_bitmap_q <= '0;
      used_bitmap_q <= '0;
      spec_fifo_q <= '0;
      spec_fifo_wr_ptr_q <= '0;
      resolver_flush_q <= 1'b0;
      resolver_close_speculation_window_q <= 1'b0;
    end else begin
      valid_bitmap_q <= valid_bitmap_d;
      speculative_bitmap_q <= speculative_bitmap_d;
      used_bitmap_q <= used_bitmap_d;
      spec_fifo_q <= spec_fifo_d;
      spec_fifo_wr_ptr_q <= spec_fifo_wr_ptr_d1;
      resolver_flush_q <= resolver_flush_i;
      resolver_close_speculation_window_q <= resolver_close_speculation_window_d;
    end
  end : bitmapRegs

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : writeBufferRegs
    if (!rst_ni) begin
      ops_write_q <= 1'b0;
      lookup_read_write_hazard_q <= 1'b0;
    end else begin
      ops_write_q <= ops_write_d;
      lookup_read_write_hazard_q <= lookup_read_write_hazard_i;
    end
  end : writeBufferRegs

  always_comb begin : cacheHitLogic
    cache_match_resolver = '0;
    cache_match_ops = '0;

    // parallel comparison - we load a set at a time
    for (int i = 0; i < ASSOCIATIVITY; i++) begin
      cache_match_resolver[i] = valid_bitmap_q[cache_addr_resolver][i] && metadata_resolver_out[i].capability_id == lookup_capability_resolver_id_i;
      cache_match_ops[i] = valid_bitmap_q[cache_addr_ops][i] && metadata_ops_out[i].capability_id == lookup_capability_ops_id_i;
    end
  end : cacheHitLogic

  always_comb begin : cacheUsedLogic
    unused_entries_resolver = '0;
    unused_entries_ops = '0;

    // parallel comparison on the hit set
    for (int i = 0; i < ASSOCIATIVITY; i++) begin
      unused_entries_resolver[i] = !used_bitmap_q[cache_addr_resolver][i];
      unused_entries_ops[i] = !used_bitmap_q[cache_addr_ops][i];
    end
  end : cacheUsedLogic

  always_comb begin : resolverOutputLogic
    cache_ready_resolver_d = cache_ready_resolver_q;
    cache_miss_resolver_o = 1'b1;

    cache_ready_resolver_o = cache_ready_resolver_q;

    metadata_resolver_out = cache_rdata_resolver;

    // validity controlled below
    lookup_capability_cmt_entry_resolver_o = metadata_resolver_out[cache_line_resolver_read].entry;
    speculative_resolver_o = speculative_bitmap_d[cache_addr_resolver][cache_line_resolver_read];

    // cache is in quiescent state (IDLE) or write-disabled (END_SPECULATION)
    if (cache_ready_resolver_q) begin
      // output data are valid
      cache_miss_resolver_o = cache_match_resolver == '0;
      // RAW hazard: in case of back-to-back requests from resolver, could return same entry twice
      // have to enforce a 1-cycle break starting in the cycle the resolver accepts the output, so we get new address and wait one cycle again
      // however, need to hold the ready signal high in a cache miss until the missunit responds
      // in case of write, we still need to finish the write, so we need to wait 1 cycle
      cache_ready_resolver_d = !lookup_capability_resolver_ready_i || (cache_miss_resolver_o && !missunit_valid_i) && !ops_write_q;
    end else begin
      // 1-cycle latency assumed
      cache_ready_resolver_d = lookup_capability_resolver_valid_i && !ops_write_q;
    end
    // in case of RW hazard, need to wait for Ops write to commit before I can indicate ready - otherwise, might return stale data
    // ops write is also buffered by one cycle
    cache_ready_resolver_d &= !lookup_read_write_hazard_i && !lookup_read_write_hazard_q;

    if (ops_write_q && lookup_capability_resolver_id_i == lookup_capability_ops_id_i) begin
      // edge case: we read the capability that the ops was JUST about to write -> return the new data irregardless of control signals
      lookup_capability_cmt_entry_resolver_o = ops_cmt_entry_i;
    end
  end : resolverOutputLogic

  always_comb begin : resolverCacheLogic
    cache_wenable_resolver = 1'b0;
    // we always write from missunit after a valid read, so this MUST be the current cache set
    metadata_resolver_in = metadata_resolver_out;
    cache_line_update_resolver_final = cache_line_update_resolver;

    if (!cache_miss_resolver_o) begin
      // already in the cache - must overwrite it!
      cache_line_update_resolver_final = cache_line_update_resolver;
    end

    // ID is always big enough
    resolver_id_hash = hash_t::compute_hash_djb2(lookup_capability_resolver_id_i);
    cache_addr_resolver = resolver_id_hash[CACHE_ADDR_WIDTH-1:0];
    // this is a power saving feature - can discard read result in certain (rare) conditions
    cache_enable_resolver = lookup_capability_resolver_valid_i || (missunit_valid_i && missunit_write_i);

    // this number will wrap to zero in case all entries are used, otherwise indicate the first not recently used entry
    metadata_resolver_in[cache_line_update_resolver_final].capability_id = lookup_capability_resolver_id_i;
    metadata_resolver_in[cache_line_update_resolver_final].entry = missunit_cmt_entry_i;

    // write when the missunit is giving us a new value
    // hazard 1: read-after-write between ops and resolver -> ops has precedence (new / correct value), we discard the value from the missunit
    // hazard 2: ops and resolver want to write the same set -> ops has precedence (to prevent stale value - if any - to remain)
    cache_wenable_resolver = missunit_valid_i && missunit_write_i && !lookup_read_write_hazard_i && !lookup_read_write_hazard_q && (cache_addr_resolver != cache_addr_ops);

  end : resolverCacheLogic

  always_comb begin : opsOutputLogic
    cache_ready_ops_d = cache_ready_ops_q;
    cache_miss_ops_o = 1'b1;

    cache_ready_ops_o = cache_ready_ops_q;

    metadata_ops_out = cache_rdata_ops;

    // validity controlled below
    lookup_capability_cmt_entry_ops_o = metadata_ops_out[cache_line_ops_read].entry;

    // cache is in quiescent state (IDLE) or write-disabled (END_SPECULATION)
    if (cache_ready_ops_q) begin
      // output data are always valid on write, otherwise, depends on fetched entry
      // in case of unfinished write, also indicate miss - if ops is already on the next read, we would otherwise return complete garbage
      cache_miss_ops_o = ops_write_i ? 1'b0 : (cache_match_ops == '0) || ops_write_q;
      // hold high as long as miss unit is going, so we do not stop requesting
      // however, once a response was generated, need to go low again to avoid triggering spurious misses
      cache_ready_ops_d = cache_miss_ops_o && !missunit_write_ops_i && lookup_capability_ops_valid_i;
    end else begin
      // 1-cycle latency assumed
      // only used for write
      cache_ready_ops_d = lookup_capability_ops_valid_i && !ops_write_i;
    end
  end : opsOutputLogic

  always_comb begin : opsCacheLogic
    cache_wenable_ops = 1'b0;
    // ops ALWAYS does a read before writing, so this needs to be the current data for this set
    metadata_ops_in = metadata_ops_out;

    cache_line_update_ops_final = cache_line_update_ops;

    if (cache_match_ops) begin
      // already in the cache - MUST overwrite it instead of writing into a new slot!
      cache_line_update_ops_final = cache_line_ops_read;
    end

    ops_id_hash = hash_t::compute_hash_djb2(lookup_capability_ops_id_i);

    if (ops_write_q) begin
      // this is a power saving feature - can discard read result in certain (rare) conditions
      cache_enable_ops = 1'b1;
    end else begin
      // this is a power saving feature - can discard read result in certain (rare) conditions
      cache_enable_ops = lookup_capability_ops_valid_i || ops_write_i;
    end

    // cache address are assigned based on some structure
    // so we use a djb2 hash to destroy it
    cache_addr_ops = ops_id_hash[CACHE_ADDR_WIDTH-1:0];

    // always buffered
    metadata_ops_in[cache_line_update_ops_final].capability_id = lookup_capability_ops_id_i;
    metadata_ops_in[cache_line_update_ops_final].entry = ops_cmt_entry_i;

    // in case of conflict between missunit and ops, ops always takes precedence, so can write at all times
    // write when the missunit is giving us a new value
    // hazard 1: read-after-write between ops and resolver -> ops has precedence (new / correct value), we discard the value from the missunit
    // hazard 2: ops and resolver want to write the same set -> ops has precedence (to prevent stale value - if any - to remain)
    cache_wenable_ops = ops_write_q;
  end : opsCacheLogic

  always_comb begin : validLogic
    valid_bitmap_d = valid_bitmap_q;
    resolver_spec_fail_o = 1'b0;

    if (cache_wenable_resolver) begin
      // in case of restrict(), would have stale data if this happens to be the same capability
      valid_bitmap_d[cache_addr_resolver][cache_line_update_resolver_final] = resolver_cacheable;
    end

    if (resolver_flush_q) begin
      if (spec_fifo_wr_ptr_q < 2 ** SPEC_WINDOW_FIFO_SIZE_CLOG2 - 1) begin
        // did not overrun the FIFO -> can simply invalidate FIFO entries
        // note that if the FIFO is full, we do not know if there are more
        // entries in the speculation window that did not fit...
        for (int i = 0; i < 2 ** SPEC_WINDOW_FIFO_SIZE_CLOG2; i++) begin
          if (i <= spec_fifo_wr_ptr_q) begin
            // part of the closed speculation window --> whole window is invalid
            valid_bitmap_d[spec_fifo_q[i]/ASSOCIATIVITY][spec_fifo_q[i]%ASSOCIATIVITY] = 1'b0;
          end
        end
      end else begin
        // total invalidation
        // we have no idea which entries belong to the speculation window...
        valid_bitmap_d = '0;
        resolver_spec_fail_o = 1'b1;
      end
    end

    // ops write takes precedence over flushes - writes a new, valid capability into previously occupied slot
    if (cache_wenable_ops) begin
      // in case of restrict(), would have stale data if this happens to be the same capability
      valid_bitmap_d[cache_addr_ops][cache_line_update_ops_final] = ops_cacheable;
    end
  end : validLogic

  always_comb begin : speculativeLogic
    speculative_bitmap_d = speculative_bitmap_q;

    if (cache_wenable_resolver) begin
      // missunit loads are never speculative -> resolver will do a full recursion and check if they are valid.
      // if they are invalid, the cache will be kicked.
      speculative_bitmap_d[cache_addr_resolver][cache_line_update_resolver_final] = 1'b0;
    end
    if (cache_wenable_ops) begin
      // consider lock(): ops will first write lock-holder, then parent + grandparent
      // -> parent and grandparent need to be recursed by resolver!
      speculative_bitmap_d[cache_addr_ops][cache_line_update_ops_final] = 1'b1;
    end

    if (resolver_close_speculation_window_q) begin
      for (int i = 0; i < 2 ** SPEC_WINDOW_FIFO_SIZE_CLOG2; i++) begin
        // in case the FIFO is full, some entries will remain speculative
        // we will get them when they are actually used
        if (i <= spec_fifo_wr_ptr_q) begin
          // part of the closed speculation window --> was verified by the resolver to be valid
          speculative_bitmap_d[spec_fifo_q[i]/ASSOCIATIVITY][spec_fifo_q[i]%ASSOCIATIVITY] = 1'b0;
        end
      end
    end

    if (resolver_flush_q) begin
      if (spec_fifo_wr_ptr_q < 2 ** SPEC_WINDOW_FIFO_SIZE_CLOG2 - 1) begin
        // did not overrun the FIFO -> can simply invalidate FIFO entries
        // if the FIFO is full, we do not know how many entries we missed ->
        // total invalidation
        for (int i = 0; i < 2 ** SPEC_WINDOW_FIFO_SIZE_CLOG2; i++) begin
          if (i <= spec_fifo_wr_ptr_q) begin
            // part of the closed speculation window --> whole window is invalid
            speculative_bitmap_d[spec_fifo_q[i]/ASSOCIATIVITY][spec_fifo_q[i]%ASSOCIATIVITY] = 1'b0;
          end
        end
      end else begin
        // total invalidation
        // we have no idea which entries belong to the speculation window...
        speculative_bitmap_d = '0;
      end
    end

    if (ops_flush_i) begin
      // lock, revoke just completed - need to do full recursive resolution
      // for all entries from here!
      speculative_bitmap_d = '1;
    end
  end : speculativeLogic

  always_comb begin : usedLogic
    used_bitmap_d = used_bitmap_q;

    for (int i = 0; i < NUM_ASSOC_SETS; i++) begin
      // not valid -> not used
      used_bitmap_d[i] &= valid_bitmap_q[i];

      if (&used_bitmap_d[i]) begin
        // wrap around
        used_bitmap_d[i] = '0;
      end
    end

    if (cache_wenable_resolver) begin
      // written value -> used
      used_bitmap_d[cache_addr_resolver][cache_line_update_resolver_final] = 1'b1;
    end
    if (cache_wenable_ops) begin
      // written value -> used
      used_bitmap_d[cache_addr_ops][cache_line_update_ops_final] = 1'b1;
    end

    if (lookup_capability_resolver_valid_i && !cache_miss_resolver_o && cache_ready_resolver_q) begin
      // cache hit -> used
      // resolver is performance-critical, so the same is NOT done for ops
      used_bitmap_d[cache_addr_resolver][cache_line_resolver_read] = 1'b1;
    end
    if (resolver_flush_q) begin
      if (spec_fifo_wr_ptr_q < 2 ** SPEC_WINDOW_FIFO_SIZE_CLOG2 - 1) begin
        // did not overrun the FIFO -> can simply invalidate FIFO entries
        // if the FIFO is full, we do not know how many entries we missed ->
        // total invalidation
        for (int i = 0; i < 2 ** SPEC_WINDOW_FIFO_SIZE_CLOG2; i++) begin
          if (i <= spec_fifo_wr_ptr_q) begin
            // part of the closed speculation window --> whole window is invalid
            used_bitmap_d[spec_fifo_q[i]/ASSOCIATIVITY][spec_fifo_q[i]%ASSOCIATIVITY] = 1'b0;
          end
        end
      end else begin
        // total invalidation
        used_bitmap_d = '0;
      end
    end
  end : usedLogic

  always_comb begin : specWindowFifoLogic
    spec_fifo_wr_ptr_d = spec_fifo_wr_ptr_q;
    spec_fifo_d = spec_fifo_q;

    current_index = cache_addr_resolver;
    current_index *= ASSOCIATIVITY;
    if (missunit_valid_i) begin
      // cache miss -> need to remember where I put the entry!
      current_index += cache_line_update_resolver;
    end else begin
      // cache hit -> use cache line used for read
      current_index += cache_line_resolver_read;
    end


    if(cache_ready_resolver_q && (!cache_miss_resolver_o || cache_wenable_resolver) && lookup_capability_resolver_ready_i)
    begin
      // valid lookup, accepted by resolver
      if (spec_fifo_wr_ptr_d < 2 ** SPEC_WINDOW_FIFO_SIZE_CLOG2 - 1) begin
        // room in the FIFO
        spec_fifo_d[spec_fifo_wr_ptr_d++] = current_index;
      end
    end

    spec_fifo_wr_ptr_d1 = spec_fifo_wr_ptr_d;

    if (resolver_close_speculation_window_q || resolver_flush_q) begin
      // next request starts a new speculation window
      spec_fifo_wr_ptr_d1 = 0;
    end


  end : specWindowFifoLogic
  `NORTHCAPE_UNREAD(lookup_capability_ops_ready_i);
  `NORTHCAPE_UNREAD(resolver_is_recursion_i);
endmodule
