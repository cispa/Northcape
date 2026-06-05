`include "northcape_xilinx_wrapper.vh"

module canspi_wrapper_verilog#(
    parameter AXI_LITE_ADDR_WIDTH = -1,
    parameter AXI_LITE_DATA_WIDTH = -1,
    parameter AXI_LITE_USER_WIDTH = -1,
    localparam NORTHCAPE_DEVICE_WIDTH = 16,
    localparam NORTHCAPE_TASK_WIDTH = 32,
    localparam NORTHCAPE_DEVICE_SPECIFIC_WIDTH = 64
)(
    input wire clk_i,
    input wire rst_ni,
    
    (*X_INTERFACE_PARAMETER = "FREQ_HZ 25000000"*)
    `AXI_LITE_INTERFACE_MODULE_INPUT(AXI_IN, wire),
    (*X_INTERFACE_PARAMETER = "FREQ_HZ 25000000"*)
    `AXI_LITE_INTERFACE_MODULE_OUTPUT(AXI_OUT, wire),

    input wire can_interrupt_i,
    input wire can_rx0bf_i,
    input wire can_rx1bf_i,

    input wire [NORTHCAPE_DEVICE_WIDTH-1:0] northcape_active_device_i,
    input wire [NORTHCAPE_TASK_WIDTH-1:0] northcape_active_task_i,
    input wire [NORTHCAPE_DEVICE_SPECIFIC_WIDTH-1:0] northcape_device_specific_restriction_i
);

canspi#(
    .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
    .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
    .AXI_LITE_USER_WIDTH(AXI_LITE_USER_WIDTH),
    .NORTHCAPE_DEVICE_WIDTH(NORTHCAPE_DEVICE_WIDTH),
    .NORTHCAPE_TASK_WIDTH(NORTHCAPE_TASK_WIDTH),
    .NORTHCAPE_DEVICE_SPECIFIC_WIDTH(NORTHCAPE_DEVICE_SPECIFIC_WIDTH)
) i_canspi(
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    `AXI_LITE_INTERFACE_FORWARD(AXI_IN),
    `AXI_LITE_INTERFACE_FORWARD(AXI_OUT),

    .can_interrupt_i(can_interrupt_i),
    .can_rx0bf_i(can_rx0bf_i),
    .can_rx1bf_i(can_rx1bf_i),
    
    .northcape_active_device_i(northcape_active_device_i),
    .northcape_active_task_i(northcape_active_task_i),
    .northcape_device_specific_restriction_i(northcape_device_specific_restriction_i)
);

endmodule
