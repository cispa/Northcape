/**
 * Constants for Northcape MMU verification.
 */
package northcape_mmu_test_constants;
  import northcape_types::device_id_t;
  import northcape_types::northcape_axi_user_t;
  import northcape_mmu_agent::NorthcapeMMUAgent;

  localparam AXI_USER_WIDTH = $bits(northcape_axi_user_t);
  localparam AXI_ID_WIDTH = 4;
  localparam AXI_DATA_WIDTH = 64;
  localparam AXI_ADDR_WIDTH = 64;
  localparam device_id_t READ_CHAN_DEVICE_ID = 0;
  localparam device_id_t WRITE_CHAN_DEVICE_ID = 1;

  localparam string MMU_TRANSACTION_QUEUE_NAME = "mmu_transactions";
  localparam bit CHECK_RESOLVER_RESULT = 1;

  localparam string MMU_RESET_INTERFACE_NAME = "mmu_reset";

  localparam string MMU_AGENT_CONFIG_NAME = "mmu_test_agent_config";

  typedef NorthcapeMMUAgent#(
      .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
      .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .CHECK_RESOLVER_RESULT(CHECK_RESOLVER_RESULT),
      .TRANSACTIONS_QUEUE_NAME_AGENT(MMU_TRANSACTION_QUEUE_NAME),
      .MMU_AGENT_CONFIG_NAME(MMU_AGENT_CONFIG_NAME),
      .CHECK_CMT_OVERLAP(1)
  ) mmu_agent_t;
endpackage
