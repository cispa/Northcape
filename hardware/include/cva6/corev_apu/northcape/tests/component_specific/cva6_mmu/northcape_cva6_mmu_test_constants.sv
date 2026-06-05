/**
 * Constants for Northcape MMU verification.
 */
package northcape_cva6_mmu_test_constants;
  import northcape_types::*;

  localparam AXI_ADDR_WIDTH = 64;
  localparam device_id_t INSTR_CHAN_DEVICE_ID = 0;
  localparam device_id_t DATA_CHAN_DEVICE_ID = 1;

  localparam string CVA6_MMU_TRANSACTION_QUEUE_NAME = "cva6_mmu_transactions";

  localparam string CVA6_MMU_RESET_INTERFACE_NAME = "cva6_mmu_reset";

  localparam string CVA6_MMU_AGENT_CONFIG_NAME = "cva6_mmu_test_agent_config";
endpackage
