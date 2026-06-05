# sets connections between ha1588 and internal GMII interface
puts "--------------------------------------"
puts "Connecting ha1588 to internal GMII"

disconnect_net -net {SoC_i/eth_0/<const0>} -pinlist [get_pins -of_objects [get_cells SoC_i/eth_0/ha1588_axi_0]]


disconnect_net -net SoC_i/eth_0/peripheral_aclk -pinlist [get_pins -of_objects [get_cells SoC_i/eth_0/led_pps_0]]

connect_net -net {SoC_i/eth_0/<const0>} -objects SoC_i/eth_0/ha1588_axi_0/tx_tsu_bypass_evt
connect_net -net {SoC_i/eth_0/<const0>} -objects SoC_i/eth_0/ha1588_axi_0/rx_tsu_bypass_evt

# tx
# TX clock
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/gtx_clk_out -objects SoC_i/eth_0/ha1588_axi_0/tx_gmii_clk
# TX enable
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_tx_en_int -objects SoC_i/eth_0/ha1588_axi_0/tx_gmii_ctrl 
# TX data
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_txd_int[0] -objects SoC_i/eth_0/ha1588_axi_0/tx_gmii_data[0]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_txd_int[1] -objects SoC_i/eth_0/ha1588_axi_0/tx_gmii_data[1]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_txd_int[2] -objects SoC_i/eth_0/ha1588_axi_0/tx_gmii_data[2]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_txd_int[3] -objects SoC_i/eth_0/ha1588_axi_0/tx_gmii_data[3]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_txd_int[4] -objects SoC_i/eth_0/ha1588_axi_0/tx_gmii_data[4]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_txd_int[5] -objects SoC_i/eth_0/ha1588_axi_0/tx_gmii_data[5]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_txd_int[6] -objects SoC_i/eth_0/ha1588_axi_0/tx_gmii_data[6]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_txd_int[7] -objects SoC_i/eth_0/ha1588_axi_0/tx_gmii_data[7]
# Giga mode via inverter
disconnect_net -net {SoC_i/eth_0/<const0>} -pinlist [get_pins -of_objects [get_cells SoC_i/eth_0/is_10_100_to_giga_mode_tx]]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/speed_is_10_100 -objects SoC_i/eth_0/is_10_100_to_giga_mode_tx/Op1

# rx
# RX clock
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/rgmii_interface/bufr_rgmii_rx_clk_0 -objects SoC_i/eth_0/ha1588_rx_ila/clk
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/rgmii_interface/bufr_rgmii_rx_clk_0 -objects SoC_i/eth_0/led_pps_0/clk_i

connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/rgmii_interface/bufr_rgmii_rx_clk_0 -objects SoC_i/eth_0/ha1588_axi_0/rtc_clk
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/rgmii_interface/bufr_rgmii_rx_clk_0 -objects SoC_i/eth_0/ha1588_axi_0/rx_gmii_clk
# RX dv
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_rx_dv_int -objects SoC_i/eth_0/ha1588_axi_0/rx_gmii_ctrl
# RX data
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_rxd_int[0] -objects SoC_i/eth_0/ha1588_axi_0/rx_gmii_data[0]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_rxd_int[1] -objects SoC_i/eth_0/ha1588_axi_0/rx_gmii_data[1]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_rxd_int[2] -objects SoC_i/eth_0/ha1588_axi_0/rx_gmii_data[2]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_rxd_int[3] -objects SoC_i/eth_0/ha1588_axi_0/rx_gmii_data[3]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_rxd_int[4] -objects SoC_i/eth_0/ha1588_axi_0/rx_gmii_data[4]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_rxd_int[5] -objects SoC_i/eth_0/ha1588_axi_0/rx_gmii_data[5]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_rxd_int[6] -objects SoC_i/eth_0/ha1588_axi_0/rx_gmii_data[6]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/gmii_rxd_int[7] -objects SoC_i/eth_0/ha1588_axi_0/rx_gmii_data[7]
# Giga mode via inverter
disconnect_net -net {SoC_i/eth_0/<const0>} -pinlist [get_pins -of_objects [get_cells SoC_i/eth_0/is_10_100_to_giga_mode_rx]]
connect_net -hierarchical -net SoC_i/eth_0/axi_ethernet_0/inst/mac/inst/tri_mode_ethernet_mac_i/speed_is_10_100 -objects SoC_i/eth_0/is_10_100_to_giga_mode_rx/Op1

puts "Connected ha1588 to internal GMII"
puts "--------------------------------------"
