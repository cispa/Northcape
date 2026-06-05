/**
  * Interfaces and other definitions for Northcape capability cache.
  *
  */

package northcape_capability_cache_common;
  import northcape_types::*;
  typedef enum logic [2:0] {
    NORTHCAPE_CAPABILITY_TYPE_COMMON_NO_CACHE,
    NORTHCAPE_CAPABILITY_TYPE_WT_DIRECT_FF,
    NORTHCAPE_CAPABILITY_TYPE_WT_FULLY_ASSOC_FF,
    NORTHCAPE_CAPABILITY_TYPE_WT_DIRECT_BRAM,
    NORTHCAPE_CAPABILITY_TYPE_WT_N_ASSOC_BRAM
  } northcape_capability_cache_common_cache_type_t;

  typedef enum logic {
    NORTHCAPE_CAP_CACHE_RESOLVER,
    NORTHCAPE_CAP_CACHE_OPS
  } northcape_capability_cache_arbitration_type_t;
endpackage

// TODO tooling bug: test interfaces with clocking and synthesizable interfaces separated
// without this, Vivado would go into an endless loop for some reason

interface NorthcapeCapabilityCacheInterfaceResolver (
    input logic clk_i
);

  logic request_valid;
  /* ID of the queried capability */
  northcape_types::capability_id_t request_capability_id;
  /* tag of the queried capability - only used to determine cache set */
  northcape_types::capability_tag_t request_capability_tag;

  /* flow control in the resolver */
  logic response_ready;

  /* flush triggered by resolver - on indirect resolution failure; remove all speculatively fetched entries */
  logic request_cache_flush;
  /* resolver: speculative (recursive) fetch done - mark all speculatively fetched entries as valid */
  logic request_close_speculation_window;
  /* resolver: does the request originate in recursion or is this the top CMT entry? */
  logic request_is_recursion;

  logic response_valid;
  logic response_err;
  northcape_types::northcape_cmt_entry_t response_cmt_entry;
  /* was this a cache hit? if so, can optionally skip recursion in resolver */
  logic response_cache_hit;

  modport RESOLVER_INTERFACE(
      input clk_i,
      output request_valid,
      output request_capability_id,
      output request_capability_tag,
      output response_ready,
      output request_cache_flush,
      output request_close_speculation_window,
      output request_is_recursion,
      input response_valid,
      input response_err,
      input response_cmt_entry,
      input response_cache_hit
  );

  modport CAP_CACHE(
      input clk_i,
      input request_valid,
      input request_capability_id,
      input request_capability_tag,
      input response_ready,
      input request_cache_flush,
      input request_close_speculation_window,
      input request_is_recursion,
      output response_valid,
      output response_err,
      output response_cmt_entry,
      output response_cache_hit
  );
endinterface

interface NorthcapeCapabilityCacheInterfaceResolverTest (
    input logic clk_i
);

  logic request_valid;
  /* ID of the queried capability */
  northcape_types::capability_id_t request_capability_id;
  /* tag of the queried capability - only used to determine cache set */
  northcape_types::capability_tag_t request_capability_tag;

  /* flush triggered by resolver - on indirect resolution failure; remove all speculatively fetched entries */
  logic request_cache_flush;
  /* resolver: speculative (recursive) fetch done - mark all speculatively fetched entries as valid */
  logic request_close_speculation_window;
  /* resolver: does the request originate in recursion or is this the top CMT entry? */
  logic request_is_recursion;

  /* flow control in the resolver */
  logic response_ready;

  logic response_valid;
  logic response_err;
  northcape_types::northcape_cmt_entry_t response_cmt_entry;
  /* response_cache_hit deliberately missing - we only test behavior */

`ifndef VERILATOR
  /* used solely by driver for tests */
  clocking test_resolver_clocking @(posedge (clk_i));
    output request_valid;
    output request_capability_id;
    output request_capability_tag;
    output response_ready;
    output request_cache_flush;
    output request_close_speculation_window;
    output request_is_recursion;
    input response_valid;
    input response_err;
    input response_cmt_entry;
  endclocking

  modport TEST_RESOLVER(clocking test_resolver_clocking);
`endif

endinterface

interface NorthcapeCapabilityCacheInterfaceOps (
    input logic clk_i
);
  logic request_valid;
  /* ID of the queried capability */
  northcape_types::capability_id_t request_capability_id;
  /* tag of the queried capability - only used to determine cache set */
  northcape_types::capability_tag_t request_capability_tag;
  /* read or write request? */
  logic is_write;
  northcape_types::northcape_cmt_entry_t write_request_capability;
  /* after writing the capability, clear out the remainder of the cache - needed after grandparent modification */
  logic write_request_flush;
  /* do not write this into the cache */
  logic request_is_uncacheable;

  logic response_valid;
  logic response_err;
  northcape_types::northcape_cmt_entry_t response_cmt_entry;


  modport OPS_INTERFACE(
      input clk_i,
      output request_valid,
      output request_capability_id,
      output request_capability_tag,
      output is_write,
      output write_request_capability,
      output write_request_flush,
      output request_is_uncacheable,
      input response_valid,
      input response_err,
      input response_cmt_entry
  );

  modport CAP_CACHE(
      input clk_i,
      input request_valid,
      input request_capability_id,
      input request_capability_tag,
      input is_write,
      input write_request_capability,
      input write_request_flush,
      input request_is_uncacheable,
      output response_valid,
      output response_err,
      output response_cmt_entry
  );

endinterface

interface NorthcapeCapabilityCacheInterfaceOpsTest (
    input logic clk_i
);
  logic request_valid;
  /* ID of the queried capability */
  northcape_types::capability_id_t request_capability_id;
  /* tag of the queried capability - only used to determine cache set */
  northcape_types::capability_tag_t request_capability_tag;
  /* read or write request? */
  logic is_write;
  northcape_types::northcape_cmt_entry_t write_request_capability;
  /* after writing the capability, clear out the remainder of the cache - needed after grandparent modification */
  logic write_request_flush;
  /* do not write this into the cache */
  logic request_is_uncacheable;

  logic response_valid;
  logic response_err;
  northcape_types::northcape_cmt_entry_t response_cmt_entry;


`ifndef VERILATOR
  /* used solely by driver for tests */
  clocking test_ops_clocking @(posedge (clk_i));
    output request_valid;
    output request_capability_id;
    output request_capability_tag;
    output is_write;
    output write_request_capability;
    output write_request_flush;
    output request_is_uncacheable;
    input response_valid;
    input response_err;
    input response_cmt_entry;
  endclocking

  modport TEST_OPS(clocking test_ops_clocking);
`endif


endinterface
