/**
  * Simple n:1 AXI5 Stream multiplexer w/ static priority defined by port order.
  */

module Axis5Demux #(
    // 16 ports MAX
    parameter bit [3:0] NUMBER_OUT_PORTS = -1
) (
    Axis5.RECEIVER in_port,
    Axis5.TRANSMITTER out_ports[NUMBER_OUT_PORTS]
);
  `include "northcape_unread.vh"
  int unsigned treadys;

  logic [NUMBER_OUT_PORTS-1:0] clocks, resets;

  genvar i, j;

  generate
    for (i = 0; i < NUMBER_OUT_PORTS; i++) begin
      always_comb begin
        out_ports[i].twakeup = 1;
        if (in_port.tdest == i) begin
          out_ports[i].tvalid = in_port.tvalid;
          out_ports[i].tdata  = in_port.tdata;
          out_ports[i].tstrb  = in_port.tstrb;
          out_ports[i].tkeep  = in_port.tkeep;
          out_ports[i].tlast  = in_port.tlast;
          out_ports[i].tid    = in_port.tid;
          out_ports[i].tdest  = in_port.tdest;
          out_ports[i].tuser  = in_port.tuser;
        end else begin
          out_ports[i].tvalid = 0;
          out_ports[i].tdata = '0;
          out_ports[i].tstrb = 0;
          out_ports[i].tkeep = 0;
          out_ports[i].tlast = 0;
          out_ports[i].tid = 0;
          out_ports[i].tdest = 0;
          out_ports[i].tuser = 0;
        end
        treadys[i] = out_ports[i].tready;

        clocks[i]  = out_ports[i].clk_i;
        resets[i]  = out_ports[i].rst_ni;
      end
    end
    for (j = NUMBER_OUT_PORTS; j < $bits(treadys); j++) begin
      always_comb begin
        treadys[j] = 0;
      end
    end
  endgenerate

  always_comb begin : treadyLogic
    in_port.tready = treadys[in_port.tdest];
  end


  `NORTHCAPE_UNREAD(in_port.clk_i);
  `NORTHCAPE_UNREAD(in_port.rst_ni);
  `NORTHCAPE_UNREAD(in_port.twakeup);

  `NORTHCAPE_UNREAD(clocks);
  `NORTHCAPE_UNREAD(resets);


endmodule
