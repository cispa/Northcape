/**
  * Constants for Capability Cache test.
  */
package northcape_capability_cache_test_constants;
  import northcape_capability_cache_agent::NorthcapeCapabilityCacheAgentConfig;
  import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;

  // increased data width such that we can fit an entire CMT entry into one clock cycle
  localparam AXI_DATA_WIDTH = 256;
  localparam AXI_ADDR_WIDTH = 64;
  localparam AXI_USER_WIDTH = 1;
  localparam AXI_ID_WIDTH = 4;

  localparam INITIAL_CMT_BASE = 64'h0;
  localparam INITIAL_CMT_SIZE_CLOG2 = 32'd8;

  localparam NUM_ENTRIES = 16;

  localparam CACHE_STORE_BUFFER_SIZE = 8;

  localparam bit SUPPORT_SPECULATIVE_RESOLVER_LOADS = 1'b1;

  localparam bit KEEP_TOP_CMT_ENTRIES_ONLY = 1'b1;

  localparam string CAPABILITY_CACHE_TRANSACTION_QUEUE_NAME = "capability_cache_transactions";

  localparam string CAPABILITY_CACHE_AGENT_CONFIG_NAME = "capability_cache_agent_config";

  localparam int CACHE_ASSOCIATIVITY = 4;


  typedef NorthcapeCapabilityCacheAgentConfig#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),

      .HASH_TYPE(HASH_TYPE_IDENTITY),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
  ) agent_config_t;
endpackage
