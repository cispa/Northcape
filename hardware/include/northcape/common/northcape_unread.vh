/**
  * Dummy module, used to ignore a signal
  */
`ifndef NORTHCAPE_UNREAD_VH
`define NORTHCAPE_UNREAD_VH

`ifndef VERILATOR
/* verilog_format: off */
`define NORTHCAPE_UNREAD_EXPLICIT_WIDTH(SIGNAL, WIDTH) \
/* verilog_format: on */    \
        wire [WIDTH-1:0] dummy_internal_signal_```__LINE__``; \
        northcape_unread#(.NUMBER_BITS(WIDTH)) i_unread_```__LINE__``(.unread(SIGNAL), .dummy_output(dummy_internal_signal_```__LINE__``))

`define NORTHCAPE_UNREAD(SIGNAL) \
        `NORTHCAPE_UNREAD_EXPLICIT_WIDTH(SIGNAL,$bits(SIGNAL))

`else

/* verilog_format: off */
`define NORTHCAPE_UNREAD_EXPLICIT_WIDTH(SIGNAL, WIDTH)
/* verilog_format: on */
`define NORTHCAPE_UNREAD(SIGNAL)

`endif

`endif
