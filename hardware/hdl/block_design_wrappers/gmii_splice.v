module gmii_splice(
    (*X_INTERFACE_MODE = "Monitor" *)
    (*X_INTERFACE_INFO = "xilinx.com:interface:rgmii_rtl:1.0 rgmii TXC" *)
    input rgmii_txc,
    (*X_INTERFACE_INFO = "xilinx.com:interface:rgmii_rtl:1.0 rgmii TX_CTL" *)
    input rgmii_tx_ctl,
    (*X_INTERFACE_INFO = "xilinx.com:interface:rgmii_rtl:1.0 rgmii TD" *)
    input [3:0] rgmii_td,

    (*X_INTERFACE_INFO = "xilinx.com:interface:rgmii_rtl:1.0 rgmii RXC" *)
    input rgmii_rxc,
    (*X_INTERFACE_INFO = "xilinx.com:interface:rgmii_rtl:1.0 rgmii RX_CTL" *)
    input rgmii_rx_ctl,
    (*X_INTERFACE_INFO = "xilinx.com:interface:rgmii_rtl:1.0 rgmii RD" *)
    input [3:0] rgmii_rd,

    input rst_ni,

    output txc,
    output rxc,
    output reg tx_evt,
    output reg rx_evt
);

    reg tx_ev_last, rx_ev_last;

    always @(posedge(txc), negedge(rst_ni)) begin
       if(!rst_ni) 
       begin
        tx_ev_last <= 0;
        tx_evt <= 0;
       end
       else
       begin
        // data present is indicated at forward edge
        tx_ev_last <= rgmii_tx_ctl;
        tx_evt <= !tx_ev_last & rgmii_tx_ctl;
       end
    end

    always @(posedge(rxc), negedge(rst_ni)) begin
       if(!rst_ni) 
       begin
        rx_ev_last <= 0;
        rx_evt <= 0;
       end
       else
       begin
        // data present is indicated at forward edge
        rx_ev_last <= rgmii_rx_ctl;
        rx_evt <= !rx_ev_last & rgmii_rx_ctl;
       end
    end
    

    assign txc = rgmii_txc;
    assign rxc = rgmii_rxc;
endmodule
