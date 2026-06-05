/**
  * Stretches a synchronous pps signal to be displayed on an LED
  */
module led_pps#(
    parameter SYNCHRONIZE_RESET = 0
)(
    input wire clk_i,
    (*X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 source_resetn RST", X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW"*)
    input wire rst_ni,
    input wire pps_i,
    output wire led_o
);

    reg led_q;
    wire led_d;
    wire reset_int_n;

    generate
        if(SYNCHRONIZE_RESET)
        begin: resetSync
            xpm_cdc_async_rst #(
                .DEST_SYNC_FF(4),    // DECIMAL; range: 2-10
                .INIT_SYNC_FF(0),    // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
                .RST_ACTIVE_HIGH(0)  // DECIMAL; 0=active low reset, 1=active high reset
            )
            xpm_cdc_async_rst_inst (
                .dest_arst(reset_int_n),  // 1-bit output: src_arst asynchronous reset signal synchronized to destination
                                            // clock domain. This output is registered. NOTE: Signal asserts asynchronously
                                            // but deasserts synchronously to dest_clk. Width of the reset signal is at least
                                            // (DEST_SYNC_FF*dest_clk) period.

                .dest_clk(clk_i),    // 1-bit input: Destination clock.
                .src_arst(rst_ni)    // 1-bit input: Source asynchronous reset signal.
            );
        end
        else
        begin
            assign reset_int_n = rst_ni;
        end
    endgenerate

    always @(posedge(clk_i), negedge(reset_int_n)) begin
        if(!reset_int_n)
        begin
            led_q <= 1'b0;
        end
        else
        begin
            led_q <= led_d;
        end
    end

    assign led_d = (pps_i) ? !led_q : led_q;
    assign led_o = led_q;
    
endmodule
