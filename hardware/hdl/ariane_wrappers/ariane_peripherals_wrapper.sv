`include "ariane_xlnx_mapper.svh"
module ariane_peripherals_wrapper
#(
    parameter AXI_ID_WIDTH=10,
    parameter AXI_ADDR_WIDTH=64,
    parameter AXI_DATA_WIDTH=64,
    parameter AXI_USER_WIDTH=1, 
    parameter NUMBER_INTERRUPTS=4
)
(
    input logic aclk,
    input logic aresetn,

    input wire [NUMBER_INTERRUPTS - 1 : 0] irqs_in,
    input wire [NUMBER_INTERRUPTS - 1 : 0] irq_levels_in,


    `AXI_INTERFACE_MODULE_INPUT(s_axi_plic),
    `AXI_INTERFACE_MODULE_INPUT(s_axi_timer),


    output logic [1:0] irq_out
    
);

AXI_BUS #(
    .AXI_ADDR_WIDTH ( AXI_ADDR_WIDTH     ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH     ),
    .AXI_ID_WIDTH   ( AXI_ID_WIDTH ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH     )
) master[ariane_soc::NB_PERIPHERALS-1:0]();


`ASSIGN_ARIANE_INTERFACE_FROM_XLNX_STYLE_INPUTS(s_axi_plic,master[ariane_soc::PLIC])
`ASSIGN_ARIANE_INTERFACE_FROM_XLNX_STYLE_INPUTS(s_axi_timer,master[ariane_soc::Timer])


ariane_peripherals #(
    .AxiAddrWidth ( AXI_ADDR_WIDTH     ),
    .AxiDataWidth ( AXI_DATA_WIDTH     ),
    .AxiIdWidth   ( AXI_ID_WIDTH       ),
    .AxiUserWidth ( AXI_USER_WIDTH     ),
    .InclUART     ( 1'b0               ),
    .InclGPIO     ( 1'b0               ),
    .InclSPI      ( 1'b0               ),
    .InclEthernet ( 1'b0               ),
    .ExtraIrqs    ( NUMBER_INTERRUPTS  )
) i_ariane_peripherals (
    .clk_i        ( aclk               ),
    .clk_200MHz_i ( 0                  ),
    .rst_ni       ( aresetn            ),
    .plic         ( master[ariane_soc::PLIC]     ),
    .uart         ( master[ariane_soc::UART]     ),
    .spi          ( master[ariane_soc::SPI]      ),
    .gpio         ( master[ariane_soc::GPIO]     ),
    .eth_clk_i    ( 0                            ),
    .ethernet     ( master[ariane_soc::Ethernet] ),
    .timer        ( master[ariane_soc::Timer]    ),
    .irq_i        ( irqs_in                      ),
    .irq_levels_i ( irq_levels_in                ),
    .irq_o        ( irq_out                      ),
    .rx_i         ( 0                            ),
    .tx_o         ( /* not used*/                ),
    .eth_txck(),
    .eth_rxck(0),
    .eth_rxctl(0),
    .eth_rxd(0),
    .eth_rst_n(),
    .eth_txctl(),
    .eth_txd(),
    .eth_mdio(),
    .eth_mdc(),
    .phy_tx_clk_i   ( 0                    ),
    .sd_clk_i       ( 0                    ),
    .spi_clk_o      (    /* not used*/     ),
    .spi_mosi       (                      ),
    .spi_miso       (                      ),
    .spi_ss         (                      ),
    .leds_o         ( /* not used*/        ),
    .dip_switches_i ( /* not used*/        )
    
);

endmodule
