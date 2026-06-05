/**
  * Northcape Confused Deputy DMA test constants.
  */
package northcape_confused_deputy_dma_test_constants;
  import northcape_confused_deputy_dma_agent::NorthcapeConfusedDeputyDMATestAgent;
  localparam AXI_DATA_WIDTH = 64;
  localparam AXI_ADDR_WIDTH = 64;
  localparam AXI_LITE_ADDR_WIDTH = 64;
  localparam AXI_LITE_DATA_WIDTH = 64;
  localparam AXI_USER_WIDTH = 64;
  localparam AXI_ID_WIDTH = 32;

  localparam logic [AXI_DATA_WIDTH - 1 : 0] evil_mode_address = 64'hfacecafe;
  localparam logic [AXI_DATA_WIDTH - 1 : 0] evil_mode_write = 64'hfeedbeef;
  localparam logic [AXI_DATA_WIDTH / 8 - 1 : 0] evil_mode_write_mask = 8'hfe;

  localparam logic [AXI_DATA_WIDTH - 1 : 0] evil_mode_trigger_address = 64'hdecade00;
  localparam logic [AXI_DATA_WIDTH - 1 : 0] evil_mode_trigger_address_mask = 64'hffffffffffffff00;

  localparam DMA_TRANSACTION_QUEUE_NAME = "northcape_dma_transactions";
  localparam DMA_RESET_INTERFACE_NAME = "dma_reset";

  typedef NorthcapeConfusedDeputyDMATestAgent#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),

      .evil_mode_address(evil_mode_address),
      .evil_mode_write(evil_mode_write),
      .evil_mode_write_mask(evil_mode_write_mask),
      .evil_mode_trigger_address(evil_mode_trigger_address),
      .evil_mode_trigger_address_mask(evil_mode_trigger_address_mask),

      .TRANSACTIONS_QUEUE_NAME_AGENT(DMA_TRANSACTION_QUEUE_NAME)
  ) dma_agent_t;
endpackage
