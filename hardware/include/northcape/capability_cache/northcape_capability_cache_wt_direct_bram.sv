/**
  * Northcape capability cache core cache implementation - direct mapped, write-through, using block RAM as backing storage.
  */
module northcape_capability_cache_wt_direct_bram #(
    parameter NUM_ENTRIES = -1
) (
    input logic clk_i,
    input logic rst_ni,

    input northcape_types::capability_id_t lookup_capability_resolver_id_i,
    input logic lookup_capability_resolver_valid_i,
    input logic lookup_capability_resolver_ready_i,

    input northcape_types::capability_id_t lookup_capability_ops_id_i,
    input logic lookup_capability_ops_valid_i,
    input logic lookup_capability_ops_ready_i,


    input logic lookup_read_write_hazard_i,

    output logic cache_miss_resolver_o,
    output logic cache_miss_ops_o,
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

    input logic resolver_flush_i,
    input logic resolver_close_speculation_window_i,
    input logic ops_flush_i
);

  import northcape_types::*;
  import northcape_capability_resolver_common::NorthcapeCapabilityResolverHash;
  import northcape_capability_resolver_common::HASH_TYPE_DJB2;

  typedef NorthcapeCapabilityResolverHash#(HASH_TYPE_DJB2) hash_t;


  `include "northcape_unread.vh"

  typedef struct packed {
    // needed to ensure this is the correct capability
    capability_id_t capability_id;
    // the full entry
    northcape_cmt_entry_t entry;
  } cache_data_t;

  cache_data_t metadata_resolver_out, metadata_ops_out;
  cache_data_t metadata_resolver_in, metadata_ops_in;

  localparam int CACHE_DATA_WIDTH = $bits(cache_data_t);

  localparam int CACHE_ADDR_WIDTH = $clog2(NUM_ENTRIES);

  localparam int CACHE_NUM_ENTRIES = 2 ** CACHE_ADDR_WIDTH;

  logic [CACHE_DATA_WIDTH-1:0]
      cache_wdata_resolver, cache_wdata_ops, cache_rdata_resolver, cache_rdata_ops;
  logic [CACHE_ADDR_WIDTH-1:0] cache_addr_resolver, cache_addr_ops;

  logic cache_wenable_resolver, cache_wenable_ops;
  logic cache_enable_resolver, cache_enable_ops;


  logic cache_ready_resolver_q, cache_ready_resolver_d;
  logic cache_ready_ops_q, cache_ready_ops_d;

  logic resolver_cacheable, ops_cacheable;

  // 1-bit bitmap for valid, speculative. Needed to be able to close speculation window in 1 cycle.
  // Hazard handling via state machine would be possible but expensive, as delay would be needed.
  logic [CACHE_NUM_ENTRIES-1:0]
      valid_bitmap_d, valid_bitmap_q, speculative_bitmap_d, speculative_bitmap_q;

  logic [CACHE_ADDR_WIDTH-1:0] resolver_id_hash, ops_id_hash;


  northcape_sram_dport #(
      // prevent out-of-bounds "issues"
      .DATA_WIDTH  (CACHE_DATA_WIDTH),
      .DATA_DEPTH  (CACHE_NUM_ENTRIES),
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


  // in the same place for all types of capability
  assign resolver_cacheable = missunit_cmt_entry_i.permissions.direct_capability_permissions.cacheable_tlb;
  // operations module can also explicitly disable cacheability on write
  assign ops_cacheable = ops_cmt_entry_i.permissions.direct_capability_permissions.cacheable_tlb && !ops_write_uncacheable_i;
  // simple pass-throughs
  assign cache_wdata_resolver = metadata_resolver_in;
  assign cache_wdata_ops = metadata_ops_in;

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : readyRegs
    if (!rst_ni) begin
      cache_ready_resolver_q <= 1'b0;
      cache_ready_ops_q <= 1'b0;
    end else begin
      cache_ready_resolver_q <= cache_ready_resolver_d;
      cache_ready_ops_q <= cache_ready_ops_d;
    end
  end : readyRegs

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : bitmapRegs
    if (!rst_ni) begin
      valid_bitmap_q <= '0;
      speculative_bitmap_q <= '0;
    end else begin
      valid_bitmap_q <= valid_bitmap_d;
      speculative_bitmap_q <= speculative_bitmap_d;
    end
  end : bitmapRegs


  always_comb begin : resolverOutputLogic
    cache_ready_resolver_d = cache_ready_resolver_q;
    cache_miss_resolver_o = 1'b1;

    cache_ready_resolver_o = cache_ready_resolver_q;

    metadata_resolver_out = cache_rdata_resolver;

    // validity controlled below
    lookup_capability_cmt_entry_resolver_o = metadata_resolver_out.entry;

    // cache is in quiescent state (IDLE) or write-disabled (END_SPECULATION)
    if (cache_ready_resolver_q) begin
      // output data are valid
      cache_miss_resolver_o = !(valid_bitmap_q[cache_addr_resolver] && metadata_resolver_out.capability_id == lookup_capability_resolver_id_i);
      // RAW hazard: in case of back-to-back requests from resolver, could return same entry twice
      // have to enforce a 1-cycle break starting in the cycle the resolver accepts the output, so we get new address and wait one cycle again
      // however, need to hold the ready signal high in a cache miss until the missunit responds
      cache_ready_resolver_d = !lookup_capability_resolver_ready_i || (cache_miss_resolver_o && !missunit_valid_i);
    end else begin
      // 1-cycle latency assumed
      cache_ready_resolver_d = lookup_capability_resolver_valid_i;
    end
    // in case of RW hazard, need to wait for Ops write to commit before I can indicate ready - otherwise, might return stale data
    cache_ready_resolver_d &= !lookup_read_write_hazard_i;
  end : resolverOutputLogic

  always_comb begin : resolverCacheLogic
    // destroy structure of hash ID
    resolver_id_hash = hash_t::compute_hash_djb2(lookup_capability_resolver_id_i);
    cache_addr_resolver = resolver_id_hash;
    // this is a power saving feature - can discard read result in certain (rare) conditions
    cache_enable_resolver = lookup_capability_resolver_valid_i || (missunit_valid_i && missunit_write_i);

    metadata_resolver_in.capability_id = lookup_capability_resolver_id_i;
    metadata_resolver_in.entry = missunit_cmt_entry_i;

    cache_wenable_resolver = missunit_valid_i && missunit_write_i && !lookup_read_write_hazard_i;
  end : resolverCacheLogic

  always_comb begin : opsOutputLogic
    cache_ready_ops_d = cache_ready_ops_q;
    cache_miss_ops_o = 1'b1;

    cache_ready_ops_o = cache_ready_ops_q;

    metadata_ops_out = cache_rdata_ops;

    // validity controlled below
    lookup_capability_cmt_entry_ops_o = metadata_ops_out.entry;

    // cache is in quiescent state (IDLE) or write-disabled (END_SPECULATION)
    if (cache_ready_ops_q) begin
      // output data are always valid on write, otherwise, depends on fetched entry
      cache_miss_ops_o = ops_write_i ? 1'b0: !(valid_bitmap_q[cache_addr_ops] && metadata_ops_out.capability_id == lookup_capability_ops_id_i);
      // hold high as long as miss unit is going, so we do not stop requesting
      cache_ready_ops_d = cache_miss_ops_o && !missunit_write_ops_i;
    end else begin
      // 1-cycle latency assumed
      // for write, this is 1-cycle --> nothing to do!
      cache_ready_ops_d = lookup_capability_ops_valid_i && !ops_write_i;
    end
  end : opsOutputLogic

  always_comb begin : opsCacheLogic
    // destroy structure of hash ID
    ops_id_hash = hash_t::compute_hash_djb2(lookup_capability_ops_id_i);
    cache_addr_ops = ops_id_hash;
    // this is a power saving feature - can discard read result in certain (rare) conditions
    cache_enable_ops = lookup_capability_ops_valid_i || ops_write_i;

    metadata_ops_in.capability_id = lookup_capability_ops_id_i;
    metadata_ops_in.entry = ops_cmt_entry_i;

    cache_wenable_ops = 1'b0;
    if (!(missunit_valid_i && missunit_write_i)) begin
      // ops can write irregardless
      cache_wenable_ops = ops_write_i;
    end else begin
      if (lookup_read_write_hazard_i || (cache_addr_ops != cache_addr_resolver)) begin
        // either raw hazard, and we accept write, or different address - ops can write
        cache_wenable_ops = ops_write_i;
      end
    end
  end : opsCacheLogic

  always_comb begin : validLogic
    valid_bitmap_d = valid_bitmap_q;

    if (cache_wenable_resolver) begin
      // in case of restrict(), would have stale data if this happens to be the same capability
      valid_bitmap_d[cache_addr_resolver] = resolver_cacheable;
    end

    if (resolver_flush_i) begin
      // resolver wants us to kick the speculative entries
      valid_bitmap_d = valid_bitmap_d & (~speculative_bitmap_q);
    end

    if (ops_flush_i) begin
      // total invalidation
      valid_bitmap_d = '0;
    end

    // ops write takes precedence over flushes - writes a new, valid capability into previously occupied slot
    if (cache_wenable_ops) begin
      // in case of restrict(), would have stale data if this happens to be the same capability
      valid_bitmap_d[cache_addr_ops] = ops_cacheable;
    end
  end : validLogic

  always_comb begin : speculativeLogic
    speculative_bitmap_d = speculative_bitmap_q;

    if (cache_wenable_resolver) begin
      // missunit loads are always speculative
      speculative_bitmap_d[cache_addr_resolver] = 1'b1;
    end
    if (cache_wenable_ops) begin
      // ops loads are NEVER speculative
      // resolver always does a full recursion, so no attack
      speculative_bitmap_d[cache_addr_ops] = 1'b0;
    end

    if (resolver_flush_i || resolver_close_speculation_window_i) begin
      // same handling - if the window is closed, valid entries stay, otherwise, valid entries go
      speculative_bitmap_d = '0;
    end
  end : speculativeLogic
endmodule
