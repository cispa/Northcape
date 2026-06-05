/**
  * Northcape capability cache core cache implementation - direct mapped, write-through, using flip-flops as backing storage.
  */
module northcape_capability_cache_wt_direct_ff #(
    parameter NUM_ENTRIES = -1,
    parameter bit SUPPORT_SPECULATIVE_RESOLVER_LOADS = 1'b0
) (
    input logic clk_i,
    input logic rst_ni,

    input northcape_types::capability_id_t  lookup_capability_resolver_id_i,
    input northcape_types::capability_tag_t lookup_capability_resolver_tag_i,
    input northcape_types::capability_id_t  lookup_capability_ops_id_i,
    input northcape_types::capability_tag_t lookup_capability_ops_tag_i,

    input logic lookup_read_write_hazard_i,

    output logic cache_miss_resolver_o,
    output logic cache_miss_ops_o,
    output northcape_types::northcape_cmt_entry_t lookup_capability_cmt_entry_resolver_o,
    output northcape_types::northcape_cmt_entry_t lookup_capability_cmt_entry_ops_o,

    input logic missunit_write_i,
    input northcape_types::northcape_cmt_entry_t missunit_cmt_entry_i,

    input logic ops_write_i,
    input northcape_types::northcape_cmt_entry_t ops_cmt_entry_i,
    input logic ops_write_uncacheable_i,

    input logic resolver_flush_i,
    input logic resolver_close_speculation_window_i,
    input logic ops_flush_i
);

  import northcape_types::*;


  `include "northcape_unread.vh"

  typedef logic [$clog2(NUM_ENTRIES)-1:0] cache_idx_t;

  typedef struct packed {
    logic valid;
    // set on load from resolver missunit, removed when speculation window closed
    logic speculative;
    // needed to ensure this is the correct capability
    capability_id_t capability_id;
  } cache_metadata_t;

  northcape_cmt_entry_t [NUM_ENTRIES-1:0] cache_d, cache_q;

  cache_metadata_t [NUM_ENTRIES-1:0] cache_metadata_d, cache_metadata_q;

  cache_metadata_t current_metadata_resolver, current_metadata_ops;

  cache_idx_t cache_line_resolver, cache_line_ops;

  logic resolver_cacheable, ops_cacheable;

  /*
     * We use the last bits of the tag as a set identifier
     * Direct mapped, so this immediately identifies a single cache line
     * This should work reasonably well, as bits have high entropy (Quarma output)
     */
  assign cache_line_resolver = lookup_capability_resolver_tag_i;
  assign cache_line_ops = lookup_capability_ops_tag_i;

  // in the same place for all types of capability
  assign resolver_cacheable = missunit_cmt_entry_i.permissions.direct_capability_permissions.cacheable_tlb;
  // operations module can also explicitly disable cacheability on write
  assign ops_cacheable = ops_cmt_entry_i.permissions.direct_capability_permissions.cacheable_tlb && !ops_write_uncacheable_i;

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : cacheReg
    if (!rst_ni) begin
      cache_q <= '0;
      cache_metadata_q <= '0;
    end else begin
      cache_q <= cache_d;
      cache_metadata_q <= cache_metadata_d;
    end
  end : cacheReg

  function automatic cache_metadata_t [NUM_ENTRIES-1:0] clear_cache_metadata_flush(
      input cache_metadata_t [NUM_ENTRIES-1:0] cache_metadata);
    cache_metadata_t [NUM_ENTRIES-1:0] ret = cache_metadata;
    if (SUPPORT_SPECULATIVE_RESOLVER_LOADS) begin
      for (int i = 0; i < NUM_ENTRIES; i++) begin
        // no need to check valid - will be invalid again if it was not previously
        if (ret[i].speculative) begin
          ret[i].valid = 1'b0;
        end
      end
    end
    return ret;
  endfunction

  function automatic cache_metadata_t [NUM_ENTRIES-1:0] clear_cache_metadata_end_speculation_entry(
      input cache_metadata_t [NUM_ENTRIES-1:0] cache_metadata);
    cache_metadata_t [NUM_ENTRIES-1:0] ret = cache_metadata;
    if (SUPPORT_SPECULATIVE_RESOLVER_LOADS) begin
      for (int i = 0; i < NUM_ENTRIES; i++) begin
        ret[i].speculative = 1'b0;
      end
    end
    return ret;
  endfunction

  always_comb begin : cacheReadLogic
    lookup_capability_cmt_entry_resolver_o = cache_q[cache_line_resolver];
    current_metadata_resolver = cache_metadata_q[cache_line_resolver];

    cache_miss_resolver_o = !(current_metadata_resolver.valid && current_metadata_resolver.capability_id == lookup_capability_resolver_id_i);

    lookup_capability_cmt_entry_ops_o = cache_q[cache_line_ops];
    current_metadata_ops = cache_metadata_q[cache_line_ops];

    cache_miss_ops_o = !(current_metadata_ops.valid && current_metadata_ops.capability_id == lookup_capability_ops_id_i);
  end : cacheReadLogic

  always_comb begin : cacheWriteLogic
    cache_d = cache_q;
    cache_metadata_d = cache_metadata_q;

    unique case ({
      ops_flush_i, resolver_flush_i, missunit_write_i, ops_write_i
    })
      4'b0000: begin
        // nothing to be done
      end
      4'b0001: begin
        // singular ops write
        if (ops_cacheable) begin
          cache_d[cache_line_ops] = ops_cmt_entry_i;
          cache_metadata_d[cache_line_ops].valid = 1'b1;
          // ops module's state machines ensures that there are no speculative loads
          cache_metadata_d[cache_line_ops].speculative = 1'b0;
          cache_metadata_d[cache_line_ops].capability_id = lookup_capability_ops_id_i;
        end else begin
          if (!cache_miss_ops_o) begin
            // removed TLB cacheable permission - no write, invalidate the cacheline if stale value
            cache_metadata_d[cache_line_ops].valid = 1'b0;
          end
        end
      end
      4'b0010: begin
        // singular resolver write
        if (resolver_cacheable) begin
          cache_d[cache_line_resolver] = missunit_cmt_entry_i;
          cache_metadata_d[cache_line_resolver].valid = 1'b1;
          // speculative load - released when speculation window is closed or on flush
          cache_metadata_d[cache_line_resolver].speculative = 1'b1;
          cache_metadata_d[cache_line_resolver].capability_id = lookup_capability_resolver_id_i;
        end
      end
      4'b0011: begin
        // ops and missunit write
        // missunit takes precedence, except if the capability is the same - in this case, the missunit's value is discarded
        if (lookup_read_write_hazard_i) begin
          // we HAVE to write here - otherwise, possibly stale value
          cache_d[cache_line_ops] = ops_cmt_entry_i;
          cache_metadata_d[cache_line_ops].valid = ops_cacheable;
          // ops module's state machines ensures that there are no speculative loads
          cache_metadata_d[cache_line_ops].speculative = 1'b0;
          cache_metadata_d[cache_line_ops].capability_id = lookup_capability_ops_id_i;
        end else begin
          if (ops_cacheable) begin
            cache_d[cache_line_ops] = ops_cmt_entry_i;
            cache_metadata_d[cache_line_ops].valid = 1'b1;
            // ops module's state machines ensures that there are no speculative loads
            cache_metadata_d[cache_line_ops].speculative = 1'b0;
            cache_metadata_d[cache_line_ops].capability_id = lookup_capability_ops_id_i;
          end else begin
            if (!cache_miss_ops_o) begin
              // removed TLB cacheable permission - no write, invalidate the cacheline if stale value
              cache_metadata_d[cache_line_ops].valid = 1'b0;
            end
          end

          if (resolver_cacheable) begin
            cache_d[cache_line_resolver] = missunit_cmt_entry_i;
            cache_metadata_d[cache_line_resolver].valid = 1'b1;
            // missunit reads always
            cache_metadata_d[cache_line_ops].speculative = 1'b1;
            cache_metadata_d[cache_line_resolver].capability_id = lookup_capability_resolver_id_i;
          end
        end
      end
      4'b0100: begin
        // resolver flush - clear everything
        cache_metadata_d = clear_cache_metadata_flush(cache_metadata_d);
      end
      4'b0101: begin
        // resolver flush and ops write - flush cache and accept write from ops
        cache_metadata_d = clear_cache_metadata_flush(cache_metadata_d);
        if (ops_cacheable) begin
          cache_d[cache_line_ops] = ops_cmt_entry_i;
          cache_metadata_d[cache_line_ops].valid = 1'b1;
          // ops module's state machines ensures that there are no speculative loads
          cache_metadata_d[cache_line_ops].speculative = 1'b0;
          cache_metadata_d[cache_line_ops].capability_id = lookup_capability_ops_id_i;
        end else begin
          if (!cache_miss_ops_o) begin
            // removed TLB cacheable permission - no write, invalidate the cacheline if stale value
            cache_metadata_d[cache_line_ops].valid = 1'b0;
          end
        end
      end
      4'b0110: begin
        // resolver flush and missunit write - discard missunit
        cache_metadata_d = clear_cache_metadata_flush(cache_metadata_d);
      end
      4'b0111: begin
        // resolver flush and both missunit and ops write - discard missunit, but keep ops
        cache_metadata_d = clear_cache_metadata_flush(cache_metadata_d);
        if (ops_cacheable) begin
          cache_d[cache_line_ops] = ops_cmt_entry_i;
          cache_metadata_d[cache_line_ops].valid = 1'b1;
          // ops module's state machines ensures that there are no speculative loads
          cache_metadata_d[cache_line_ops].speculative = 1'b0;
          cache_metadata_d[cache_line_ops].capability_id = lookup_capability_ops_id_i;
        end else begin
          if (!cache_miss_ops_o) begin
            // removed TLB cacheable permission - no write, invalidate the cacheline if stale value
            cache_metadata_d[cache_line_ops].valid = 1'b0;
          end
        end
      end
      4'b1000: begin
        // ops flush - clear everything
        cache_metadata_d = '0;
      end
      4'b1001: begin
        // ops flush and write - keep ops write
        cache_metadata_d = '0;
        // no need to invalidate if not cacheable - we just flushed the cache
        if (ops_cacheable) begin
          cache_d[cache_line_ops] = ops_cmt_entry_i;
          cache_metadata_d[cache_line_ops].valid = 1'b1;
          // ops module's state machines ensures that there are no speculative loads
          cache_metadata_d[cache_line_ops].speculative = 1'b0;
          cache_metadata_d[cache_line_ops].capability_id = lookup_capability_ops_id_i;
        end
      end
      4'b1010: begin
        // ops flush and missunit write - clear everything
        cache_metadata_d = '0;
      end
      4'b1011: begin
        // ops flush and both missunit and ops write - keep ops write only
        cache_metadata_d = '0;
        // no need to invalidate if not cacheable - we just flushed the cache
        if (ops_cacheable) begin
          cache_d[cache_line_ops] = ops_cmt_entry_i;
          cache_metadata_d[cache_line_ops].valid = 1'b1;
          // ops module's state machines ensures that there are no speculative loads
          cache_metadata_d[cache_line_ops].speculative = 1'b0;
          cache_metadata_d[cache_line_ops].capability_id = lookup_capability_ops_id_i;
        end
      end
      4'b1100: begin
        // resolver and ops flush - clear everything
        cache_metadata_d = '0;
      end
      4'b1101: begin
        // resolver and ops flush and ops write - keep ops write
        cache_metadata_d = '0;
        // no need to invalidate if not cacheable - we just flushed the cache
        if (ops_cacheable) begin
          cache_d[cache_line_ops] = ops_cmt_entry_i;
          cache_metadata_d[cache_line_ops].valid = 1'b1;
          // ops module's state machines ensures that there are no speculative loads
          cache_metadata_d[cache_line_ops].speculative = 1'b0;
          cache_metadata_d[cache_line_ops].capability_id = lookup_capability_ops_id_i;
        end
      end
      4'b1110: begin
        // resolver and ops flush and missunit write - clear everything
        cache_metadata_d = '0;
      end
      4'b1111: begin
        // resolver and ops flush and missunit and ops write - keep ops write
        cache_metadata_d = '0;
        // no need to invalidate if not cacheable - we just flushed the cache
        if (ops_cacheable) begin
          cache_d[cache_line_ops] = ops_cmt_entry_i;
          cache_metadata_d[cache_line_ops].valid = 1'b1;
          // ops module's state machines ensures that there are no speculative loads
          cache_metadata_d[cache_line_ops].speculative = 1'b0;
          cache_metadata_d[cache_line_ops].capability_id = lookup_capability_ops_id_i;
        end
      end
      default: begin
        $display("Unreachable state!");
      end
    endcase

    if (resolver_close_speculation_window_i) begin
      // do this last - any new entry written this cycle will be accounted for
      // this is the correct behavior, as the resolver will indicate this flag in the same cycle as the missunit writes
      cache_metadata_d = clear_cache_metadata_end_speculation_entry(cache_metadata_d);
    end
  end : cacheWriteLogic

  // some bits unused
  `NORTHCAPE_UNREAD(lookup_capability_resolver_tag_i);
  `NORTHCAPE_UNREAD(lookup_capability_ops_tag_i);
endmodule
