/**
  * Interface modelling the AXI-Stream (AXIS) 5 protocol.
  */
interface Axis5 #(
    parameter AXIS_TDATA_WIDTH = -1,
    parameter AXIS_TID_WIDTH   = -1,
    parameter AXIS_TDEST_WIDTH = -1,
    parameter AXIS_TUSER_WIDTH = -1
) (
    input logic clk_i,
    input logic rst_ni
);

  // transmitter has valid data
  logic tvalid;
  // receiver is ready to receive
  logic tready;
  // transfer
  logic [AXIS_TDATA_WIDTH-1:0] tdata;
  // bytes of the transfer that are valid, for padding the last transfer beat
  logic [AXIS_TDATA_WIDTH/8-1:0] tstrb;
  // bytes of the transfer to be ignored/skipped, for use in transfer
  logic [AXIS_TDATA_WIDTH/8-1:0] tkeep;
  // this is the last transfer beat
  logic tlast;
  // transfer ID
  logic [AXIS_TID_WIDTH-1:0] tid;
  // transfer destination
  logic [AXIS_TDEST_WIDTH-1:0] tdest;
  // custom annotations
  logic [AXIS_TUSER_WIDTH-1:0] tuser;
  // activity on the interface - precedes tvalid on transfer
  logic twakeup;

  modport TRANSMITTER(
      input clk_i, rst_ni, tready,
      output tvalid, tdata, tstrb, tkeep, tlast, tid, tdest, tuser, twakeup
  );
  modport RECEIVER(
      input clk_i, rst_ni, tvalid, tdata, tstrb, tkeep, tlast, tid, tdest, tuser, twakeup,
      output tready
  );
endinterface

/* TODO Vivado tooling bug with clocking */
interface Axis5Test #(
    parameter AXIS_TDATA_WIDTH = -1,
    parameter AXIS_TID_WIDTH   = -1,
    parameter AXIS_TDEST_WIDTH = -1,
    parameter AXIS_TUSER_WIDTH = -1
) (
    input logic clk_i,
    input logic rst_ni
);

  // transmitter has valid data
  logic tvalid;
  // receiver is ready to receive
  logic tready;
  // transfer
  logic [AXIS_TDATA_WIDTH-1:0] tdata;
  // bytes of the transfer that are valid, for padding the last transfer beat
  logic [AXIS_TDATA_WIDTH/8-1:0] tstrb;
  // bytes of the transfer to be ignored/skipped, for use in transfer
  logic [AXIS_TDATA_WIDTH/8-1:0] tkeep;
  // this is the last transfer beat
  logic tlast;
  // transfer ID
  logic [AXIS_TID_WIDTH-1:0] tid;
  // transfer destination
  logic [AXIS_TDEST_WIDTH-1:0] tdest;
  // custom annotations
  logic [AXIS_TUSER_WIDTH-1:0] tuser;
  // activity on the interface - precedes tvalid on transfer
  logic twakeup;

`ifndef VERILATOR
  clocking transmitter_clocking @(posedge (clk_i));
    input clk_i;
    input rst_ni;
    input tready;
    output tvalid;
    output tdata;
    output tstrb;
    output tkeep;
    output tlast;
    output tid;
    output tdest;
    output tuser;
    output twakeup;
  endclocking

  clocking receiver_clocking @(posedge (clk_i));
    input clk_i;
    input rst_ni;
    output tready;
    input tvalid;
    input tdata;
    input tstrb;
    input tkeep;
    input tlast;
    input tid;
    input tdest;
    input tuser;
    input twakeup;
  endclocking
`endif

`ifndef VERILATOR
  modport TEST_TRANSMITTER(clocking transmitter_clocking);
  modport TEST_RECEIVER(clocking receiver_clocking);
`endif

endinterface
