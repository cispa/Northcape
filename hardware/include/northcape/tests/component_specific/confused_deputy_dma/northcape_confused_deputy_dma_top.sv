/**
  * Testbench module for Northcape Confused Deputy DMA verification.
  */
module northcape_confused_deputy_dma_top;
  import axi5::*;
  import northcape_types::*;
  import northcape_test::*;
  import northcape_confused_deputy_dma_test_constants::*;
  import northcape_confused_deputy_dma_transaction::*;

  import uvm_pkg::*;
  `include "axi5_assign.svh"
  `include "uvm_macros.svh"

  typedef uvm_analysis_port#(Axi5MasterDriverResultTransaction#(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )) master_analysis_port_t;

  typedef virtual northcape_test_reset reset_intf_t;


  logic clk_i;
  logic rst_ni;

  northcape_test_reset reset_intf (.clk_i(clk_i));

  assign rst_ni = reset_intf.resetn;

  // clock period 10 ns = 100 MHz clock
  localparam clock_period_ns = 10;


  northcape_test_clock_generator #(
      .CLOCK_PERIOD_NS(clock_period_ns)
  ) clock_generator (
      .clk_i(clk_i)
  );


  Axi5Lite #(
      .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH)
  ) axi_in (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  typedef virtual Axi5Lite #(
      .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH)
  ) axi_lite_interface_t;

  // AXI Master (DMA) Interface and interfaces to checkers
  Axi5 #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )
      axi_out (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      axi_out_read (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      axi_out_write (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );

  `NORTHCAPE_MAP_INTERFACES_READ(assign, axi_out_read, =, axi_out);
  `NORTHCAPE_MAP_INTERFACES_WRITE(assign, axi_out_write, =, axi_out);

  // unused / default assignments
  assign axi_in.wstrb  = '1;
  assign axi_in.awprot = '0;
  assign axi_in.arprot = '0;

  // queue of master test requests
  typedef INorthcapeAXITransactionMasterSide#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) mailbox_transaction_t;
  mailbox #(mailbox_transaction_t) requests_in_master_read, requests_in_master_write;

  master_analysis_port_t master_analysis_port_read, master_analysis_port_write;

  typedef NorthcapeDMATransaction#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH)
  ) transaction_t;

  initial begin
    automatic uvm_queue #(transaction_t) transactions;

    requests_in_master_read = new;
    requests_in_master_write = new;

    transactions = new("transaction_queue");
    transactions.delete();


    master_analysis_port_read  = new("master_analysis_port_read", null);
    master_analysis_port_write = new("master_analysis_port_write", null);

    uvm_config_db#(master_analysis_port_t)::set(null, "", "dma_master_analysis_port_read",
                                                master_analysis_port_read);
    uvm_config_db#(master_analysis_port_t)::set(null, "", "dma_master_analysis_port_write",
                                                master_analysis_port_write);

    uvm_config_db#(reset_intf_t)::set(null, "", DMA_RESET_INTERFACE_NAME, reset_intf);


    uvm_config_db#(uvm_queue#(transaction_t))::set(null, "", DMA_TRANSACTION_QUEUE_NAME,
                                                   transactions);

    uvm_config_db#(axi_lite_interface_t)::set(null, "", "axi_lite_interface", axi_in);

    uvm_config_db#(mailbox#(mailbox_transaction_t))::set(null, "", "dma_mailbox_read",
                                                         requests_in_master_read);
    uvm_config_db#(mailbox#(mailbox_transaction_t))::set(null, "", "dma_mailbox_write",
                                                         requests_in_master_write);
  end

  // simulates and checks AXI writes
  axi5_master_driver #(
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
  ) i_axi_master_read (
      .requests_in(requests_in_master_read),

      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .axi_master(axi_out_read),


      .ap_i(master_analysis_port_read)
  );

  // simulates and checks AXI writes
  axi5_master_driver #(
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
  ) i_axi_master_write (
      .requests_in(requests_in_master_write),

      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .axi_master(axi_out_write),


      .ap_i(master_analysis_port_write)
  );

  northcape_confused_deputy_dma #(
      .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_LITE_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),

      .ENABLE_BACKDOOR(1),
      .BACKDOOR_WRITE_ADDRESS(evil_mode_address),
      .BACKDOOR_WRITE_WORD(evil_mode_write),
      .BACKDOOR_WRITE_MASK(evil_mode_write_mask),
      .BACKDOOR_TRIGGER_ADDRESS(evil_mode_trigger_address),
      .BACKDOOR_TRIGGER_ADDRESS_MASK(evil_mode_trigger_address_mask)
  ) i_northcape_confused_deputy_dma (
      .clk_i (clk_i),
      .rst_ni(rst_ni),


      .axi_master(axi_out.FROM),

      .axi_slave(axi_in.TO)

  );

endmodule
