/**
 * Constants for Northcape integration testing.
 */
package northcape_integration_test_constants;

  import axi5::*;
  import northcape_types::*;
  import northcape_capability_ops_common::NORTHCAPE_CAPABILITY_OPS_CTR;
  import northcape_capability_ops_common::northcape_capability_ops_tag_method_t;


  // increased data width such that we can fit an entire CMT entry into one clock cycle
  localparam AXI_DATA_WIDTH_MEM = 256;
  localparam AXI_DATA_WIDTH_MMU = 64;
  localparam AXI_ADDR_WIDTH = 64;
  localparam AXI_USER_WIDTH = $bits(northcape_axi_user_t);
  localparam AXI_ID_WIDTH = 4;

  // resolver FIFO width - number of max parallel requests
  localparam FIFO_DEPTH_CLOG_2 = 2;
  localparam MAX_AXI_TRANSACTIONS = 4;

  localparam AXI_LITE_ADDR_WIDTH = 64;
  localparam AXI_LITE_DATA_WIDTH = 64;

  localparam INITIAL_CMT_BASE = 64'h0;
  localparam INITIAL_CMT_SIZE_CLOG2 = 32'd12;

  localparam device_id_t READ_CHAN_DEVICE_ID = 0;
  localparam device_id_t WRITE_CHAN_DEVICE_ID = 1;

  localparam bit HAS_CACHE_INTERFACE = 1'b1;

  localparam NUM_CACHE_ENTRIES = 16;
  localparam CACHE_STORE_BUFFER_SIZE = 8;
  localparam int CACHE_ASSOCIATIVITY = 4;

  localparam bit SUPPORT_SPECULATIVE_RESOLVER_LOADS = 1'b1;

  localparam bit KEEP_TOP_CMT_ENTRIES_ONLY = 1'b1;

  localparam string TRANSACTIONS_QUEUE_NAME_AGENT_MMU = "integration_test_transactions_queue_mmu";
  localparam string TRANSACTIONS_QUEUE_NAME_AGENT_OPS = "integration_test_transactions_queue_ops";
  localparam string TRANSACTIONS_QUEUE_NAME_AGENT_INTEGRATION = "integration_test_transactions_queue_integration";
  localparam string CAPABILITY_OPS_AGENT_CONFIG_NAME = "integration_test_capability_ops_agent_config";
  localparam string INTEGRATION_AGENT_CONFIG_NAME = "integration_test_integration_ops_agent_config";
  localparam string MMU_AGENT_CONFIG_NAME = "integration_test_mmu_agent_config";

  localparam string INTEGRATION_TEST_RESET_INTERFACE_NAME = "integration_test_reset_interface";

  localparam string INTEGRATION_TEST_CAPABILITY_OPS_AXI_LITE_INTERFACE_NAME = "integration_test_capability_ops_axi_lite_interface";

  localparam bit CACHE_RECURSION_SKIP = 1'b1;

  localparam bit INPUT_PIPELINE_STAGE_ENABLED = 1'b1;
  localparam bit PARSER_PIPELINE_STAGE_ENABLED = 1'b0;
  localparam bit OUTPUT_PIPELINE_STAGE_ENABLED = 1'b1;

  localparam int OPS_BRAM_DATA_WIDTH = 64;


  localparam northcape_capability_ops_tag_method_t OPS_TAG_METHOD = NORTHCAPE_CAPABILITY_OPS_CTR;
endpackage
