/**
 * Testbench module for Northcape FIFO verification.
 */
module northcape_fifo_top;
  import northcape_fifo_test_constants::*;
  import uvm_pkg::*;

  `include "uvm_macros.svh"

  localparam CLOCK_PERIOD_NS = 10;

  logic clk_i;
  logic rst_ni;

  northcape_test_clock_generator #(
      .CLOCK_PERIOD_NS(CLOCK_PERIOD_NS)
  ) clock_generator (
      .clk_i(clk_i)
  );

  NorthcapeFifoInterface #(
      .FIFO_DATA_WIDTH(FIFO_DATA_WIDTH)
  ) fifo_intf (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  NorthcapeFifoInterfaceTest #(
      .FIFO_DATA_WIDTH(FIFO_DATA_WIDTH)
  ) fifo_intf_test (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  assign fifo_intf.enable_rd = fifo_intf_test.enable_rd;
  assign fifo_intf.enable_wr = fifo_intf_test.enable_wr;
  assign fifo_intf.wr_data = fifo_intf_test.wr_data;

  assign fifo_intf_test.is_empty = fifo_intf.is_empty;
  assign fifo_intf_test.is_full = fifo_intf.is_full;
  assign fifo_intf_test.rd_data = fifo_intf.rd_data;

  northcape_fifo #(
      .FIFO_DATA_WIDTH  (FIFO_DATA_WIDTH),
      .FIFO_DEPTH_CLOG_2(FIFO_DEPTH_CLOG_2)
  ) i_dut (
      .fifo_interface(fifo_intf.FIFO)
  );

  northcape_test_reset reset_intf (.clk_i(clk_i));

  assign rst_ni = reset_intf.resetn;

  typedef virtual NorthcapeFifoInterfaceTest #(.FIFO_DATA_WIDTH(FIFO_DATA_WIDTH)) fifo_intf_t;

  typedef virtual northcape_test_reset reset_intf_t;

  initial begin
    uvm_config_db#(reset_intf_t)::set(null, "", FIFO_RESET_INTERFACE_NAME, reset_intf);
    uvm_config_db#(fifo_intf_t)::set(null, "", FIFO_INTERFACE_NAME, fifo_intf_test);
  end



endmodule
