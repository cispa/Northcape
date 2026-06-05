/**
 * Testbench module for the Northcape Register Interface.
 */
module northcape_reg_interface_top;
  import northcape_reg_interface_transaction::*;
  import northcape_test::*;
  import northcape_types::*;
  import northcape_reg_interface_test_constants::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  logic clk_i;
  logic rst_ni;

  // clock period 10 ns = 100 MHz clock
  localparam half_clock_period_ns = 5;
  localparam clock_period_ns = 2 * half_clock_period_ns;

  localparam COMPONENT_NAME = "Northcape Reg Interface Top";

  typedef NorthcapeRegInterfaceTransaction#(
      .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .NUM_REGS(NUM_REGS)
  ) transaction_t;

  // AXI LITE interface for MMIO
  Axi5Lite #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH)
  ) axi_in (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  typedef virtual Axi5Lite #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH)
  ) axi_lite_interface_t;

  NorthcapeRegInterfaceIO #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .NUM_REGS(NUM_REGS)
  ) reg_intf (
      .clk_i(clk_i)
  );

  typedef virtual NorthcapeRegInterfaceIO #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .NUM_REGS(NUM_REGS)
  ) reg_interface_t;

  northcape_test_reset reset_intf (.clk_i(clk_i));
  assign rst_ni = reset_intf.resetn;

  typedef virtual northcape_test_reset reset_intf_t;

  northcape_test_clock_generator #(.CLOCK_PERIOD_NS(10)) clock_generator (.clk_i(clk_i));

  northcape_reg_interface #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .NUM_REGS(NUM_REGS)
  ) i_northcape_reg_interface (
      .s_axi(axi_in),
      .reg_intf(reg_intf.REG_INTERFACE)
  );

  initial begin
    automatic uvm_queue #(transaction_t) transactions;

    transactions = new("transaction_queue");
    transactions.delete();



    uvm_config_db#(reset_intf_t)::set(null, "", REGISTER_INTERFACE_RESET_INTERFACE_NAME,
                                      reset_intf);


    uvm_config_db#(uvm_queue#(transaction_t))::set(
        null, "", REGISTER_INTERFACE_TRANSACTION_QUEUE_NAME, transactions);


    `uvm_info(COMPONENT_NAME, $sformatf(
              "Set register interface MMIO interface with type %s key %s addr width %d data width %d",
              $typename(
                  reg_intf
              ),
              REGISTER_INTERFACE_NAME_MMIO_INTERFACE,
              AXI_LITE_ADDR_WIDTH,
              AXI_DATA_WIDTH
              ), UVM_DEBUG);
    uvm_config_db#(axi_lite_interface_t)::set(null, "", REGISTER_INTERFACE_NAME_MMIO_INTERFACE,
                                              axi_in);
    uvm_config_db#(reg_interface_t)::set(null, "", REGISTER_INTERFACE_NAME_REG_INTERFACE, reg_intf);
  end

endmodule
