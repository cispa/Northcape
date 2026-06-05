(* blackbox *)
module sram_hpdcache_64x128(
`ifdef USE_POWER_PINS
    vccd1,
    vssd1,
`endif
    clk0,csb0,web0,wmask0,addr0,din0,dout0
  );

  `define NUM_WMASKS 8
  `define DATA_WIDTH 64
  `define ADDR_WIDTH 8

`ifdef USE_POWER_PINS
    inout vccd1;
    inout vssd1;
`endif
  input  clk0; // clock
  input   csb0; // active low chip select
  input  web0; // active low write control
  input [`ADDR_WIDTH-1:0]  addr0;
  input [`NUM_WMASKS-1:0]   wmask0; // write mask
  input [`DATA_WIDTH-1:0]  din0;
  output [`DATA_WIDTH-1:0] dout0;


endmodule
