/**
  * Fully associative first-level cache for cva6 MMU.
  * Cleared on any capability operation that does a write.
  */
module northcape_cva6_mmu_cache_full_assoc #(
    parameter CACHE_SIZE = -1
) (
    input logic clk_i,
    input logic rst_ni,

    input northcape_types::capability_id_t lookup_capability_i,
    input northcape_types::capability_tag_t lookup_tag_i,
    input logic lookup_valid_i,

    output northcape_types::axis_validate_response_tdata_t lookup_response_o,
    output logic cache_miss_o,

    input northcape_types::axis_validate_response_tdata_t missunit_response_i,
    input logic missunit_response_valid_i,

    input logic cache_flush_i,

    NorthcapeCMTInterface.CONSUMER cmt_interface
);
  import northcape_types::*;
  `include "northcape_unread.vh"

  typedef struct packed {
    capability_id_t capability;
    capability_tag_t tag;
    logic recently_used;
    logic valid;
  } cache_metadata_t;


  cache_metadata_t [CACHE_SIZE-1:0] metadata_q, metadata_d;
  cache_metadata_t lookup_metadata;
  axis_validate_response_tdata_t [CACHE_SIZE-1:0] cache_q, cache_d;

  /* break combinatorial path on update */
  capability_id_t lookup_capability_q;
  capability_tag_t lookup_tag_q;

  logic [CACHE_SIZE-1:0] cache_match;
  logic [CACHE_SIZE-1:0] cache_unused;

  logic [$clog2(CACHE_SIZE):0] cache_line_read_out, cache_line_update_out;
  logic [$clog2(CACHE_SIZE)-1:0] cache_line_read, cache_line_update, cache_line_read_q;
  logic cache_update_q, cache_update_d;

  northcape_leading_zero_count #(
      .SIZE(CACHE_SIZE)
  ) i_read_hit_count (
      .one_hot_i(cache_match),
      .leading_zero_count_o(cache_line_read_out)
  );

  assign cache_line_read = CACHE_SIZE - cache_line_read_out[$clog2(CACHE_SIZE)-1:0] - 1;
  // wrap-over to zero does not matter
  `NORTHCAPE_UNREAD(cache_line_read_out[$clog2(CACHE_SIZE)]);

  northcape_leading_zero_count #(
      .SIZE(CACHE_SIZE)
  ) i_update_hit_count (
      .one_hot_i(cache_unused),
      .leading_zero_count_o(cache_line_update_out)
  );

  assign cache_line_update = CACHE_SIZE - cache_line_update_out[$clog2(CACHE_SIZE)-1:0] - 1;
  // wrap-over to zero is intended - part of the strategy
  `NORTHCAPE_UNREAD(cache_line_update_out[$clog2(CACHE_SIZE)]);


  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : cacheFFs
    if (!rst_ni) begin
      metadata_q <= '0;
      cache_q <= '0;
      lookup_capability_q <= '0;
      lookup_tag_q <= '0;
      cache_update_q <= 1'b0;
      cache_line_read_q <= '0;
    end else begin
      metadata_q <= metadata_d;
      cache_q <= cache_d;
      lookup_capability_q <= lookup_capability_i;
      lookup_tag_q <= lookup_tag_i;
      cache_update_q <= cache_update_d;
      cache_line_read_q <= cache_line_read;
    end
  end : cacheFFs

  always_comb begin : lookupLogic

    cache_match = '0;

    for (int cache_index = 0; cache_index < CACHE_SIZE; cache_index++) begin
      cache_match[cache_index] = metadata_q[cache_index].valid && metadata_q[cache_index].capability == lookup_capability_i && metadata_q[cache_index].tag == lookup_tag_i;
    end

    lookup_metadata = metadata_q[cache_line_read];

    lookup_response_o = cache_q[cache_line_read];

    cache_miss_o = !(|cache_match) || cache_flush_i;
  end : lookupLogic

  always_comb begin : replacementLogic
    for (int cache_index = 0; cache_index < CACHE_SIZE; cache_index++) begin
      cache_unused[cache_index] = !metadata_q[cache_index].valid || !metadata_q[cache_index].recently_used;
    end
  end : replacementLogic

  always_comb begin : writeLogic
    cache_d = cache_q;
    metadata_d = metadata_q;
    cache_update_d = 1'b0;

    if (cache_unused == '0) begin
      for (int cache_index = 0; cache_index < CACHE_SIZE; cache_index++) begin
        metadata_d[cache_index].recently_used = 1'b0;
      end
    end

    if (lookup_valid_i && !cache_miss_o) begin
      cache_update_d = 1'b1;
    end

    if (cache_update_q) begin
      metadata_d[cache_line_read_q].recently_used = 1'b1;
    end

    if (missunit_response_valid_i) begin
      /* use values from last cycle to break comb. path - response CANNOT come in first cycle */
      metadata_d[cache_line_update].valid = 1'b1;
      metadata_d[cache_line_update].capability = lookup_capability_q;
      metadata_d[cache_line_update].tag = lookup_tag_q;
      metadata_d[cache_line_update].recently_used = 1'b1;
      cache_d[cache_line_update] = missunit_response_i;
    end

    if (cmt_interface.wrote_any_capability) begin
      for (int i = 0; i < CACHE_SIZE; i++) begin
        if (metadata_d[i].capability == cmt_interface.written_capability) begin
          metadata_d[i].valid = 1'b0;
          /* suppress update */
          cache_update_d = 1'b0;
        end
      end
    end

    if (cache_flush_i) begin
      metadata_d = '0;
      /* suppress update */
      cache_update_d = 1'b0;
    end

  end : writeLogic

  `NORTHCAPE_UNREAD(cmt_interface.clk_i);
  `NORTHCAPE_UNREAD(cmt_interface.table_size_clog2);
  `NORTHCAPE_UNREAD(cmt_interface.cmt_base);
  `NORTHCAPE_UNREAD(cmt_interface.reset_done);
  `NORTHCAPE_UNREAD(cmt_interface.need_flush_data_caches);

endmodule
