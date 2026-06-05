/**
  * Constants for Northcape resolver verification.
  */
package northcape_capability_resolver_test_constants;
  import northcape_capability_resolver_agent::NorthcapeCapabilityResolverAgentConfig;
  import northcape_types::*;

  // increased data width such that we can fit an entire CMT entry into one clock cycle
  localparam AXI_DATA_WIDTH = 256;
  localparam AXI_ADDR_WIDTH = 64;
  localparam AXI_USER_WIDTH = 1;
  localparam AXI_ID_WIDTH = 4;
  localparam FIFO_DEPTH_CLOG_2 = 4;
  localparam MAX_AXI_TRANSACTIONS = 4;

  localparam device_id_t CAPABILITY_RESOLVER_RECURSION_DEVICE_ID = 1;

  localparam bit HAS_CACHE_INTERFACE = 1'b1;

  localparam bit SUPPORT_SPECULATIVE_RESOLVER_LOADS = 1'b1;

  localparam bit KEEP_TOP_CMT_ENTRIES_ONLY = 1'b1;

  localparam CACHE_STORE_BUFFER_SIZE = 16;


  localparam string CAPABILITY_RESOLVER_RESET_INTERFACE_NAME = "capability_resolver_reset";
  localparam string CAPABILITY_RESOLVER_TRANSACTION_QUEUE_NAME = "capability_resolver_transactions";

  localparam string CAPABILITY_RESOLVER_AGENT_CONFIG_NAME = "capability_resolver_agent_config";

  localparam bit INPUT_PIPELINE_STAGE_ENABLED = 1'b1;
  localparam bit PARSER_PIPELINE_STAGE_ENABLED = 1'b0;
  localparam bit OUTPUT_PIPELINE_STAGE_ENABLED = 1'b1;

  typedef NorthcapeCapabilityResolverAgentConfig#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),

      .AXIS_REQUEST_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH),
      .AXIS_REQUEST_TID_WIDTH  (AXIS_VALIDATE_REQUEST_TID_WIDTH),
      .AXIS_REQUEST_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
      .AXIS_REQUEST_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH),

      .AXIS_RESPONSE_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH),
      .AXIS_RESPONSE_TID_WIDTH  (AXIS_VALIDATE_RESPONSE_TID_WIDTH),
      .AXIS_RESPONSE_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH),
      .AXIS_RESPONSE_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH)
  ) agent_config_t;

endpackage
