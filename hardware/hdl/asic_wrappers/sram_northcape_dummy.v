(* blackbox *)
module sram_northcape_32x128(
// Port 0: RW
    clk0,csb0,web0,addr0,din0,dout0,
// Port 1: RW
    clk1,csb1,web1,addr1,din1,dout1
  );

  `define DATA_WIDTH 32
  `define ADDR_WIDTH 7
  `define RAM_DEPTH (1 << ADDR_WIDTH)
  // FIXME: This delay is arbitrary.
  `define DELAY 3
  //Set to 0 to only display warnings
  `define VERBOSE 1 
  //Delay to hold dout value after posedge. Value is arbitrary
  `define T_HOLD 1


  input  clk0; // clock
  input   csb0; // active low chip select
  input  web0; // active low write control
  input [`ADDR_WIDTH-1:0]  addr0;
  input [`DATA_WIDTH-1:0]  din0;
  output [`DATA_WIDTH-1:0] dout0;
  input  clk1; // clock
  input   csb1; // active low chip select
  input  web1; // active low write control
  input [`ADDR_WIDTH-1:0]  addr1;
  input [`DATA_WIDTH-1:0]  din1;
  output [`DATA_WIDTH-1:0] dout1;


endmodule

`undef DATA_WIDTH
`undef ADDR_WIDTH
`undef RAM_DEPTH
`undef DELAY
`undef VERBOSE
`undef T_HOLD

(* blackbox *)
module sram_northcape_256x64(
`ifdef USE_POWER_PINS
    vccd1,
    vssd1,
`endif
// Port 0: RW
    clk0,csb0,web0,addr0,din0,dout0,
// Port 1: RW
    clk1,csb1,web1,addr1,din1,dout1
  );

  `define DATA_WIDTH 256
  `define ADDR_WIDTH 6
  `define RAM_DEPTH (1 << ADDR_WIDTH)
  // FIXME: This delay is arbitrary.
  `define DELAY 3
  //Set to 0 to only display warnings
  `define VERBOSE 1
  //Delay to hold dout value after posedge. Value is arbitrary
  `define T_HOLD 1

`ifdef USE_POWER_PINS
    inout vccd1;
    inout vssd1;
`endif
  input  clk0; // clock
  input   csb0; // active low chip select
  input  web0; // active low write control
  input [`ADDR_WIDTH-1:0]  addr0;
  input [`DATA_WIDTH-1:0]  din0;
  output [`DATA_WIDTH-1:0] dout0;
  input  clk1; // clock
  input   csb1; // active low chip select
  input  web1; // active low write control
  input [`ADDR_WIDTH-1:0]  addr1;
  input [`DATA_WIDTH-1:0]  din1;
  output [`DATA_WIDTH-1:0] dout1;


endmodule

`undef DATA_WIDTH
`undef ADDR_WIDTH
`undef RAM_DEPTH
`undef DELAY
`undef VERBOSE
`undef T_HOLD

