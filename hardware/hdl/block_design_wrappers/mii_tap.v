module mii_tap#(
    parameter IS_GMII = 1'b0
)(
    (*X_INTERFACE_INFO = "xilinx.com:interface:mii_rtl:1.0 mii COL" *)
    input wire mii_col,
    (*X_INTERFACE_INFO = "xilinx.com:interface:mii_rtl:1.0 mii CRS" *)
    input wire mii_crs,
    (*X_INTERFACE_INFO = "xilinx.com:interface:mii_rtl:1.0 mii RST_N" *)
    input wire mii_rst_n,
    (*X_INTERFACE_INFO = "xilinx.com:interface:mii_rtl:1.0 mii RX_CLK" *)
    input wire mii_rx_clk,
    (*X_INTERFACE_INFO = "xilinx.com:interface:mii_rtl:1.0 mii RX_DV" *)
    input wire mii_dv,
    (*X_INTERFACE_INFO = "xilinx.com:interface:mii_rtl:1.0 mii RX_ER" *)
    input wire mii_rx_er,
    (*X_INTERFACE_INFO = "xilinx.com:interface:mii_rtl:1.0 mii RXD" *)
    input wire [(IS_GMII ? 7 : 3) : 0] mii_rx_data,
    (*X_INTERFACE_INFO = "xilinx.com:interface:mii_rtl:1.0 mii TX_CLK" *)
    input wire mii_tx_clk,
    (*X_INTERFACE_INFO = "xilinx.com:interface:mii_rtl:1.0 mii TX_EN" *)
    input wire mii_tx_en,
    (*X_INTERFACE_INFO = "xilinx.com:interface:mii_rtl:1.0 mii TXD" *)
    (* X_INTERFACE_MODE = "monitor" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME mii, MODE Monitor" *)
    input wire [(IS_GMII ? 7 : 3) : 0] mii_tx_data,


    output wire mii_col_o,
    output wire mii_crs_o,
    output wire mii_rst_n_o,
    output wire mii_rx_clk_o,
    output wire mii_dv_o,
    output wire mii_rx_er_o,
    output wire [(IS_GMII ? 7 : 3) : 0] mii_rx_data_o,
    output wire mii_tx_clk_o,
    output wire mii_tx_en_o,
    output wire [(IS_GMII ? 7 : 3) : 0] mii_tx_data_o
);

assign mii_col_o = mii_col;
assign mii_crs_o = mii_crs;
assign mii_rst_n_o = mii_rst_n;
assign mii_rx_clk_o = mii_rx_clk;
assign mii_dv_o = mii_dv;
assign mii_rx_er_o = mii_rx_er;
assign mii_rx_data_o = mii_rx_data;
assign mii_tx_clk_o = mii_tx_clk;
assign mii_tx_en_o = mii_tx_en;
assign mii_tx_data_o = mii_tx_data;


endmodule
