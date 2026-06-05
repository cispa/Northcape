/**
  * Simple direct-mapped first-level cache for cva6 MMU.
  * Cleared on any capability operation that does a write.
  */
module northcape_cva6_mmu_cache #(
    parameter CACHE_SIZE = -1
) (
    input logic clk_i,
    input logic rst_ni,

    input northcape_types::capability_id_t  lookup_capability_i,
    input northcape_types::capability_tag_t lookup_tag_i,

    output northcape_types::axis_validate_response_tdata_t lookup_response_o,
    output logic cache_miss_o,

    input northcape_types::axis_validate_response_tdata_t missunit_response_i,
    input logic missunit_response_valid_i,

    input logic cache_flush_i,

    NorthcapeCMTInterface.CONSUMER cmt_interface
);
  import northcape_types::*;
  import northcape_capability_resolver_common::NorthcapeCapabilityResolverHash;
  import northcape_capability_resolver_common::HASH_TYPE_DJB2;
  `include "northcape_unread.vh"

  typedef struct packed {
    capability_id_t capability;
    capability_tag_t tag;
    logic valid;
  } cache_metadata_t;

  typedef NorthcapeCapabilityResolverHash#(HASH_TYPE_DJB2) hash_gen_t;

  cache_metadata_t [CACHE_SIZE-1:0] metadata_q, metadata_d;
  cache_metadata_t lookup_metadata;
  axis_validate_response_tdata_t [CACHE_SIZE-1:0] cache_q, cache_d;

  logic [$clog2(CACHE_SIZE)-1:0] lookup_set;

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : cacheFFs
    if (!rst_ni) begin
      metadata_q <= '0;
      cache_q <= '0;
    end else begin
      metadata_q <= metadata_d;
      cache_q <= cache_d;
    end
  end : cacheFFs

  always_comb begin : lookupLogic
    // direct mapped
    // we increment here to prevent the same capabilities to conflict in both the CVA6 MMU cache (L1) and the resolver cache (L2)
    lookup_set = lookup_tag_i;
    lookup_set++;
    lookup_metadata = metadata_q[lookup_set];

    lookup_response_o = cache_q[lookup_set];

    cache_miss_o = !lookup_metadata.valid || lookup_metadata.capability != lookup_capability_i || lookup_metadata.tag != lookup_tag_i || cache_flush_i;
  end : lookupLogic

  always_comb begin : writeLogic
    cache_d = cache_q;
    metadata_d = metadata_q;

    if (missunit_response_valid_i) begin
      metadata_d[lookup_set].valid = 1'b1;
      metadata_d[lookup_set].capability = lookup_capability_i;
      metadata_d[lookup_set].tag = lookup_tag_i;
      cache_d[lookup_set] = missunit_response_i;
    end

    if (cmt_interface.wrote_any_capability) begin
      for (int i = 0; i < CACHE_SIZE; i++) begin
        if (metadata_d[i].capability == cmt_interface.written_capability) begin
          metadata_d[i].valid = 1'b0;
        end
      end
    end

    if (cache_flush_i) begin
      metadata_d = '0;
    end

  end : writeLogic

  `NORTHCAPE_UNREAD(cmt_interface.clk_i);
  `NORTHCAPE_UNREAD(cmt_interface.table_size_clog2);
  `NORTHCAPE_UNREAD(cmt_interface.cmt_base);
  `NORTHCAPE_UNREAD(cmt_interface.reset_done);
  `NORTHCAPE_UNREAD(cmt_interface.need_flush_data_caches);

endmodule
