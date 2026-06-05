/**
  * Type-generic parametrized AXI stream skidbuffer FIFO capability resolver.
  * FIFOs in resolver requests if the next stage is busy.
  */
module axis5_fifo_skidbuffer_stage #(
    parameter NUM_ENTRIES_CLOG2 = -1,


    parameter AXIS_TDATA_WIDTH = -1,
    parameter AXIS_TID_WIDTH   = -1,
    parameter AXIS_TDEST_WIDTH = -1,
    parameter AXIS_TUSER_WIDTH = -1
) (
    Axis5.RECEIVER port_in,
    Axis5.TRANSMITTER port_out
);

  `include "northcape_unread.vh"

  localparam PIPELINE_DATA_SIZE = AXIS_TDATA_WIDTH;
  localparam PIPELINE_STROBE_SIZE = PIPELINE_DATA_SIZE / 8;

  typedef struct packed {
    logic [PIPELINE_DATA_SIZE-1:0] pipeline_tdata;
    logic [PIPELINE_STROBE_SIZE-1:0] pipeline_tstrb;
    logic [PIPELINE_STROBE_SIZE-1:0] pipeline_tkeep;
    logic pipeline_tlast;
    logic [AXIS_TID_WIDTH-1:0] pipeline_tid;
    logic [AXIS_TDEST_WIDTH-1:0] pipeline_tdest;
    logic [AXIS_TUSER_WIDTH-1:0] pipeline_tuser;
    logic pipeline_twakeup;
  } skidbuffer_fifo_t;

  localparam FIFO_DATA_WIDTH = $bits(skidbuffer_fifo_t);

  logic fifo_skip;

  NorthcapeFifoInterface #(
      .FIFO_DATA_WIDTH(FIFO_DATA_WIDTH)
  ) fifo_interface (
      .clk_i (port_in.clk_i),
      .rst_ni(port_in.rst_ni)
  );

  northcape_fifo #(
      .FIFO_DATA_WIDTH  (FIFO_DATA_WIDTH),
      .FIFO_DEPTH_CLOG_2(NUM_ENTRIES_CLOG2)
  ) i_skidbuffer_fifo (
      .fifo_interface(fifo_interface)
  );

  always_comb begin : skipLogic
    fifo_skip = fifo_interface.is_empty;
  end : skipLogic

  always_comb begin : fifoReadLogic
    // in case of skip, the fifo is empty
    fifo_interface.enable_rd = !fifo_interface.is_empty & port_out.tready;
  end : fifoReadLogic

  always_comb begin : fifoWriteLogic
    // in case of skip, the next stage must be able to accept immediately
    // in case the FIFO is full, we can still write a new entry in case we are popping an entry in the same cycle
    fifo_interface.enable_wr = !(fifo_skip & port_out.tready) & (!fifo_interface.is_full | port_out.tready) & port_in.tvalid;
    fifo_interface.wr_data = {
      port_in.tdata,
      port_in.tstrb,
      port_in.tkeep,
      port_in.tlast,
      port_in.tid,
      port_in.tdest,
      port_in.tuser,
      port_in.twakeup
    };
    // this is a precondition for skip as well
    port_in.tready = !fifo_interface.is_full;
  end : fifoWriteLogic

  always_comb begin : outputLogic
    {
      port_out.tdata,
      port_out.tstrb,
      port_out.tkeep,
      port_out.tlast,
      port_out.tid,
      port_out.tdest,
      port_out.tuser,
      port_out.twakeup
    } = fifo_interface.rd_data;

    if (fifo_skip) begin
      port_out.tdata = port_in.tdata;
      port_out.tvalid = port_in.tvalid;
      port_out.tid = port_in.tid;
      port_out.tdest = port_in.tdest;
      port_out.tuser = port_in.tuser;
      port_out.tstrb = port_in.tstrb;
      port_out.tkeep = port_in.tkeep;
      port_out.tlast = port_in.tlast;
      port_out.twakeup = port_in.twakeup;
    end else begin
      port_out.tvalid = !fifo_interface.is_empty;
    end

  end : outputLogic

  // sometimes (partially) optimized away
  `NORTHCAPE_UNREAD(port_in.tdata);

  `NORTHCAPE_UNREAD(port_out.clk_i);
  `NORTHCAPE_UNREAD(port_out.rst_ni);
  `NORTHCAPE_UNREAD(port_out.rst_ni);


  // not always used
  `NORTHCAPE_UNREAD(port_in.tstrb);
  `NORTHCAPE_UNREAD(port_in.tkeep);

endmodule
