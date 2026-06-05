module ha1588_resetsync#(
   // resets are MOSTLY active-high in this design
   parameter RST_ACTIVE_HIGH = 1
   )(
    input wire dst_clk_i,
    input wire src_rst_ni,
    output wire dst_rst_no
);
// Xilinx' primitive for a reset synchronizer
xpm_cdc_async_rst #(
   .DEST_SYNC_FF(4),    // DECIMAL; range: 2-10
   .INIT_SYNC_FF(0),    // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
   .RST_ACTIVE_HIGH(RST_ACTIVE_HIGH)  // DECIMAL; 0=active low reset, 1=active high reset
)
xpm_cdc_async_rst_inst (
   .dest_arst(dst_rst_no),  // 1-bit output: src_arst asynchronous reset signal synchronized to destination
                            // clock domain. This output is registered. NOTE: Signal asserts asynchronously
                            // but deasserts synchronously to dest_clk. Width of the reset signal is at least
                            // (DEST_SYNC_FF*dest_clk) period.

   .dest_clk(dst_clk_i),    // 1-bit input: Destination clock.
   .src_arst(src_rst_ni)    // 1-bit input: Source asynchronous reset signal.
);


endmodule
