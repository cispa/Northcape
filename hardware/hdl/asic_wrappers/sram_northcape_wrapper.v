module sram_northcape_wrapper(
`ifdef USE_POWER_PINS
    vccd1,
    vssd1,
`endif
// Port 0: RW
    clk0,csb0,web0,addr0,din0,dout0,
// Port 1: RW
    clk1,csb1,web1,addr1,din1,dout1
  );

  parameter DATA_WIDTH = 32 ;
  parameter ADDR_WIDTH = 7 ;

  input  clk0; // clock
  input   csb0; // active low chip select
  input  web0; // active low write control
  input [ADDR_WIDTH-1:0]  addr0;
  input [DATA_WIDTH-1:0]  din0;
  output [DATA_WIDTH-1:0] dout0;
  input  clk1; // clock
  input   csb1; // active low chip select
  input  web1; // active low write control
  input [ADDR_WIDTH-1:0]  addr1;
  input [DATA_WIDTH-1:0]  din1;
  output [DATA_WIDTH-1:0] dout1;

// instantiation of the macro requires the assignment to the power pins...

`ifdef USE_POWER_PINS
    inout vccd1;
    inout vssd1;
`endif

generate
    if(DATA_WIDTH >= 256)
    begin: gen_large_sram
        sram_northcape_256x64 sram0(
        .clk0(clk0),
        .csb0(csb0),
        .web0(web0),
        .addr0(addr0),
        .din0(din0),
        .dout0(dout0),
        .clk1(clk1),
        .csb1(csb1),
        .web1(web1),
        .addr1(addr1),
        .din1(din1),
        .dout1(dout1)
        );
    end: gen_large_sram
    else
    begin: gen_small_sram
        sram_northcape_32x128 sram0(
        .clk0(clk0),
        .csb0(csb0),
        .web0(web0),
        .addr0(addr0),
        .din0(din0),
        .dout0(dout0),
        .clk1(clk1),
        .csb1(csb1),
        .web1(web1),
        .addr1(addr1),
        .din1(din1),
        .dout1(dout1)
        );
    end: gen_small_sram
endgenerate

endmodule
