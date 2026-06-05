/**
  * SPI Interface (4-wire flavor)
  */

interface Spi ();

  logic sclk;
  logic cs_n;
  logic mosi;
  logic miso;

  modport MASTER(output sclk, cs_n, mosi, input miso);

  modport SLAVE(input sclk, cs_n, mosi, output miso);

endinterface
