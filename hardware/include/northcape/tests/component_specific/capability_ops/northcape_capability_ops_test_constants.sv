/**
  * Constants for Operations test.
  */
package northcape_capability_ops_test_constants;
  import northcape_capability_ops_common::NORTHCAPE_CAPABILITY_OPS_CTR;
  import northcape_capability_ops_common::northcape_capability_ops_tag_method_t;
  import northcape_capability_ops_agent::NorthcapeCapabilityOpsAgentConfig;
  import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;

  // increased data width such that we can fit an entire CMT entry into one clock cycle
  localparam AXI_DATA_WIDTH = 256;
  localparam AXI_ADDR_WIDTH = 64;
  localparam AXI_USER_WIDTH = 1;
  localparam AXI_ID_WIDTH = 4;

  localparam AXI_LITE_ADDR_WIDTH = 64;
  localparam AXI_LITE_DATA_WIDTH = 64;

  localparam INITIAL_CMT_BASE = 64'h0;
  localparam INITIAL_CMT_SIZE_CLOG2 = 32'd8;
  // we make assumptions about the order of transactions in the scoreboard
  localparam CACHE_STORE_BUFFER_SIZE = 0;

  localparam bit HAS_CACHE_INTERFACE = 1'b1;

  localparam bit SUPPORT_SPECULATIVE_RESOLVER_LOADS = 1'b1;

  localparam bit KEEP_TOP_CMT_ENTRIES_ONLY = 1'b1;

  localparam string CAPABILITY_OPS_TRANSACTION_QUEUE_NAME = "capability_ops_transactions";

  localparam string CAPABILITY_OPS_AGENT_CONFIG_NAME = "capability_ops_agent_config";

  localparam string CAPABILITY_OPS_AXI_LITE_INTERFACE_NAME = "capability_ops_axi_lite_interface";

  localparam string CAPABILITY_OPS_RNG_INTERFACE_NAME = "capability_ops_rng_interface_name";

  localparam northcape_capability_ops_tag_method_t OPS_TAG_METHOD = NORTHCAPE_CAPABILITY_OPS_CTR;

  localparam int OPS_BRAM_DATA_WIDTH = 64;


  typedef NorthcapeCapabilityOpsAgentConfig#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
      .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),

      .HASH_TYPE(HASH_TYPE_IDENTITY),

      .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
      .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
  ) agent_config_t;
endpackage
