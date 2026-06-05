module sram_hpdcache_wrapper(
`ifdef USE_POWER_PINS
    vccd1,
    vssd1,
`endif
    clk0,csb0,web0,wmask0,addr0,din0,dout0
  );

  parameter NUM_WMASKS = 8 ;
  parameter DATA_WIDTH = 64 ;
  parameter ADDR_WIDTH = 8 ;

`ifdef USE_POWER_PINS
    inout vccd1;
    inout vssd1;
`endif
  input  clk0; // clock
  input   csb0; // active low chip select
  input  web0; // active low write control
  input [ADDR_WIDTH-1:0]  addr0;
  input [NUM_WMASKS-1:0]   wmask0; // write mask
  input [DATA_WIDTH-1:0]  din0;
  output [DATA_WIDTH-1:0] dout0;

// instantiation of the macro requires the assignment to the power pins...


    sram_hpdcache_64x128 sram0(
    .clk0(clk0),
    .csb0(csb0),
    .web0(web0),
    .wmask0(wmask0),
    .addr0(addr0),
    .din0({1'b0,din0}), // 1 spare bit not used
    .dout0(dout0)
    );

endmodule
