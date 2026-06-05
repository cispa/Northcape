`include "northcape_xilinx_wrapper.vh"

module canspi#(
    parameter AXI_LITE_ADDR_WIDTH = -1,
    parameter AXI_LITE_DATA_WIDTH = -1,
    parameter AXI_LITE_USER_WIDTH = -1,
    parameter NORTHCAPE_DEVICE_WIDTH = 16,
    parameter NORTHCAPE_TASK_WIDTH = 32,
    parameter NORTHCAPE_DEVICE_SPECIFIC_WIDTH = 64
)(
    // 25 MHz clock
    input logic clk_i,
    // active-low asynchronous reset
    input logic rst_ni,

    `AXI_LITE_INTERFACE_MODULE_INPUT(AXI_IN, logic),
    `AXI_LITE_INTERFACE_MODULE_OUTPUT(AXI_OUT, logic),
    // interrupts provided by the PMOD (INT, Rx0BF, Rx1BF in schematic)
    input logic can_interrupt_i,
    input logic can_rx0bf_i,
    input logic can_rx1bf_i,

    // task, device, device-specific restriction from Northcape capability
    // only valid when AWVALID/ARVALID are high!
    input logic [NORTHCAPE_DEVICE_WIDTH-1:0] northcape_active_device_i,
    input logic [NORTHCAPE_TASK_WIDTH-1:0] northcape_active_task_i,
    input logic [NORTHCAPE_DEVICE_SPECIFIC_WIDTH-1:0] northcape_device_specific_restriction_i
);

// TODO for now, simply forwards the AXI LITE and ignores everything else...
assign AXI_OUT_AWADDR = AXI_IN_AWADDR;
assign AXI_OUT_AWPROT = AXI_IN_AWPROT;
assign AXI_OUT_AWVALID = AXI_IN_AWVALID;
assign AXI_OUT_AWUSER = AXI_IN_AWUSER;
assign AXI_IN_AWREADY = AXI_OUT_AWREADY;

assign AXI_OUT_WDATA = AXI_IN_WDATA;
assign AXI_OUT_WSTRB = AXI_IN_WSTRB;
assign AXI_OUT_WVALID = AXI_IN_WVALID;
assign AXI_IN_WREADY = AXI_OUT_WREADY;

assign AXI_IN_BRESP = AXI_OUT_BRESP;
assign AXI_IN_BVALID = AXI_OUT_BVALID;
assign AXI_OUT_BREADY = AXI_IN_BREADY;

assign AXI_OUT_ARADDR = AXI_IN_ARADDR;
assign AXI_OUT_ARPROT = AXI_IN_ARPROT;
assign AXI_OUT_ARVALID = AXI_IN_ARVALID;
assign AXI_OUT_ARUSER = AXI_IN_ARUSER;
assign AXI_IN_ARREADY = AXI_OUT_ARREADY;

assign AXI_IN_RRESP = AXI_OUT_RRESP;
assign AXI_IN_RDATA = AXI_OUT_RDATA;
assign AXI_IN_RVALID = AXI_OUT_RVALID;
assign AXI_OUT_RREADY = AXI_IN_RREADY;

endmodule
