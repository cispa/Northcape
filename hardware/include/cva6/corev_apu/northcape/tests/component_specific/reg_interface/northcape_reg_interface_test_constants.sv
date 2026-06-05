/**
 * Constants for the Northcape Register Interface.
 */
package northcape_reg_interface_test_constants;
  localparam NUM_REGS = 4;

  localparam AXI_DATA_WIDTH = 32;
  localparam AXI_LITE_ADDR_WIDTH = $clog2(NUM_REGS * (AXI_DATA_WIDTH / 8));

  localparam string REGISTER_INTERFACE_TRANSACTION_QUEUE_NAME = "register_interface_transaction_queue";
  localparam string REGISTER_INTERFACE_NAME_MMIO_INTERFACE = "register_interface_mmio";
  localparam string REGISTER_INTERFACE_NAME_REG_INTERFACE = "register_interface_registers";
  localparam string REGISTER_INTERFACE_RESET_INTERFACE_NAME = "register_interface_reset";

endpackage
