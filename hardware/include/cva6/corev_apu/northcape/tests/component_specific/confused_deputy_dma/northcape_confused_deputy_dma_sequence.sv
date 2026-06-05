/**
  * Start and check sequences for DMA.
  */
package northcape_confused_deputy_dma_sequence;
  import uvm_pkg::*;
  import northcape_types::*;
  import axi5::*;
  import northcape_test::*;

  import northcape_reg_interface_transaction::NorthcapeRegInterfaceAxiLiteTransaction;

  `include "uvm_macros.svh"

  /**
      * DMA start sequence.
      * Starts a DMA transaction.
      */
  class automatic NorthcapeDMAStartSequence #(
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_DATA_WIDTH = -1
  ) extends uvm_sequence #(NorthcapeRegInterfaceAxiLiteTransaction #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
  ));
    bit [AXI_ADDR_WIDTH-1:0] source_addr;
    bit [AXI_ADDR_WIDTH-1:0] dst_addr;
    int unsigned axi_transfer_len;

    typedef NorthcapeRegInterfaceAxiLiteTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) transaction_t;

    function new(string name = "", bit [AXI_ADDR_WIDTH-1:0] source_addr,
                 bit [AXI_ADDR_WIDTH-1:0] dst_addr, int unsigned axi_transfer_len);
      super.new(name);
      this.source_addr = source_addr;
      this.dst_addr = dst_addr;
      this.axi_transfer_len = axi_transfer_len;
    endfunction

    localparam COMPONENT_NAME = "Northcape DMA Start Sequence";

    localparam AXI_DATA_WIDTH_BYTES = AXI_DATA_WIDTH / 8;

    task body();
      transaction_t transaction;

      transaction = new("Axi lite transaction");

      // unused
      transaction.transaction_prot = '0;

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      transaction.transaction_type = AXI_TEST_READ;
      transaction.transaction_addr = 6'h0;

      finish_item(transaction);

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      transaction.transaction_type = AXI_TEST_WRITE;
      transaction.transaction_addr = 6'(AXI_DATA_WIDTH_BYTES);
      transaction.transaction_data = source_addr;
      transaction.transaction_write_strobe = '1;

      finish_item(transaction);

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      transaction.transaction_type = AXI_TEST_WRITE;
      transaction.transaction_addr = 6'(AXI_DATA_WIDTH_BYTES * 2);
      transaction.transaction_data = dst_addr;
      transaction.transaction_write_strobe = '1;

      finish_item(transaction);

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      transaction.transaction_type = AXI_TEST_WRITE;
      transaction.transaction_addr = 6'(AXI_DATA_WIDTH_BYTES * 3);
      transaction.transaction_data = axi_transfer_len;
      transaction.transaction_write_strobe = '1;

      finish_item(transaction);

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      transaction.transaction_type = AXI_TEST_WRITE;
      transaction.transaction_addr = 6'h0;
      transaction.transaction_data = 64'h1;
      transaction.transaction_write_strobe = '1;

      finish_item(transaction);

      // this is to check that the DMA is in progress
      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      transaction.transaction_type = AXI_TEST_READ;
      transaction.transaction_addr = 6'h0;

      finish_item(transaction);

    endtask

  endclass

  /**
      * DMA stop sequence.
      * Checks if DMA is complete.
      */
  class automatic NorthcapeDMAStopSequence #(
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_DATA_WIDTH = -1
  ) extends uvm_sequence #(NorthcapeRegInterfaceAxiLiteTransaction #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
  ));


    typedef NorthcapeRegInterfaceAxiLiteTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) transaction_t;

    function new(string name = "");
      super.new(name);
    endfunction

    localparam COMPONENT_NAME = "Northcape DMA Stop Sequence";

    task body();
      transaction_t transaction;

      transaction = new("MMIO transaction");

      // unused
      transaction.transaction_prot = '0;

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      transaction.transaction_type = AXI_TEST_READ;
      transaction.transaction_addr = 6'h0;

      finish_item(transaction);
    endtask

  endclass
endpackage
