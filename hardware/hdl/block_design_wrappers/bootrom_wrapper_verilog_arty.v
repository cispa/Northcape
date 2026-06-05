`include "northcape_xilinx_wrapper.vh"
`include "ariane_xlnx_mapper.svh"
// wraps a RAM or ROM with the boot image. AXI 64-bit interface.
module bootrom_wrapper_verilog_arty #(
    // AXI parameters
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,
    parameter BOOTROM_SIZE_BYTES = 1048576,  // 1 Mib
    parameter AXI_ADDR_WIDTH = $clog2(BOOTROM_SIZE_BYTES),
    parameter WRITABLE = 1'b1  // 1: is boot RAM (writable), 0: is boot ROM (not writable)
) (
    (*X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_i CLK" *)
   (*X_INTERFACE_PARAMETER = "FREQ_HZ 25000000, ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET rst_ni"*)
    input wire clk_i,
    input wire rst_ni,
    `AXI_INTERFACE_MODULE_INPUT(S_AXI)
);

  bootrom_wrapper #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .BOOTROM_SIZE_BYTES(BOOTROM_SIZE_BYTES),
      .WRITABLE(WRITABLE)
  ) i_bootrom_wrapper (
      .clk_i (clk_i),
      .rst_ni(rst_ni),
      `AXI_INTERFACE_FORWARD(S_AXI)
  );


endmodule
