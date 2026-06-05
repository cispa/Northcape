import axi5::*;

`include "ariane_xlnx_mapper.svh"
`include "northcape_xilinx_wrapper.vh"

module northcape_confused_deputy_dma_wrapper#(
    // AXI parameters
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_LITE_ADDR_WIDTH = -1,
    parameter AXI_LITE_DATA_WIDTH = -1,
    parameter AXI_LITE_USER_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,

    // backdoor parameters :evil:
    parameter logic ENABLE_BACKDOOR=1,
    parameter logic [AXI_DATA_WIDTH - 1 : 0] BACKDOOR_WRITE_ADDRESS = 0,
    parameter logic [AXI_DATA_WIDTH - 1 : 0] BACKDOOR_WRITE_WORD = 0,
    parameter logic [AXI_DATA_WIDTH / 8 - 1 : 0] BACKDOOR_WRITE_MASK = 0,

    parameter logic [AXI_DATA_WIDTH - 1 : 0] BACKDOOR_TRIGGER_ADDRESS = 0,
    parameter logic [AXI_DATA_WIDTH - 1 : 0] BACKDOOR_TRIGGER_ADDRESS_MASK = 0
)(
    input logic clk_i,
    input logic rst_ni,

    `AXI_LITE_INTERFACE_MODULE_INPUT(S_AXI, logic),
    `AXI_INTERFACE_MODULE_OUTPUT(m_axi_out)
);
import axi5::*;
// interface that goes to SLAVE port of MMU
Axi5   axi_out(.clk_i(clk_i),.rst_ni(rst_ni));

Axi5Lite#(.AXI_DATA_WIDTH(AXI_DATA_WIDTH),.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) axi_in(.clk_i(clk_i),.rst_ni(rst_ni));
  

northcape_confused_deputy_dma #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),
    .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
    .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),

    .ENABLE_BACKDOOR(1),
    .BACKDOOR_WRITE_ADDRESS(BACKDOOR_WRITE_ADDRESS),
    .BACKDOOR_WRITE_WORD(BACKDOOR_WRITE_WORD),
    .BACKDOOR_WRITE_MASK(BACKDOOR_WRITE_MASK),
    .BACKDOOR_TRIGGER_ADDRESS(BACKDOOR_TRIGGER_ADDRESS),
    .BACKDOOR_TRIGGER_ADDRESS_MASK(BACKDOOR_TRIGGER_ADDRESS_MASK)
)
i_northcape_confused_deputy_dma ( 
    .clk_i(clk_i),
    .rst_ni(rst_ni),


    .axi_master(axi_out.FROM),
    .axi_slave(axi_in.TO)
 );
  

`NORTHCAPE_MAP_XILINX_AXI_INTERFACES_OUT(axi_out,m_axi_out)
`NORTHCAPE_MAP_FROM_XILINX_AXI_LITE_INTERFACE(axi_in,S_AXI)
endmodule
