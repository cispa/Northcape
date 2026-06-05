/**
  * Type-generic parametrized pipeline stage for capability resolver.
  */
module axis5_pipeline_stage #(
    parameter bit PIPELINE_STAGE_ENABLED = 1'b1,


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

  generate
    if (PIPELINE_STAGE_ENABLED) begin : gen_pipeline_stage
      logic clk_i;
      logic rst_ni;

      logic pipeline_used_q, pipeline_used_d;
      logic [PIPELINE_DATA_SIZE-1:0] pipeline_tdata_q, pipeline_tdata_d;
      logic [PIPELINE_STROBE_SIZE-1:0] pipeline_tstrb_q, pipeline_tstrb_d;
      logic [PIPELINE_STROBE_SIZE-1:0] pipeline_tkeep_q, pipeline_tkeep_d;
      logic pipeline_tlast_q, pipeline_tlast_d;
      logic [AXIS_TID_WIDTH-1:0] pipeline_tid_q, pipeline_tid_d;
      logic [AXIS_TDEST_WIDTH-1:0] pipeline_tdest_q, pipeline_tdest_d;
      logic [AXIS_TUSER_WIDTH-1:0] pipeline_tuser_q, pipeline_tuser_d;
      logic pipeline_twakeup_q, pipeline_twakeup_d;

      assign clk_i  = port_in.clk_i;
      assign rst_ni = port_in.rst_ni;

      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : pipelineFFs
        if (!rst_ni) begin
          pipeline_used_q <= '0;
          pipeline_tdata_q <= '0;
          pipeline_tstrb_q <= '0;
          pipeline_tkeep_q <= '0;
          pipeline_tlast_q <= '0;
          pipeline_tid_q <= '0;
          pipeline_tdest_q <= '0;
          pipeline_tuser_q <= '0;
          pipeline_twakeup_q <= '0;
        end else begin
          pipeline_used_q <= pipeline_used_d;
          pipeline_tdata_q <= pipeline_tdata_d;
          pipeline_tstrb_q <= pipeline_tstrb_d;
          pipeline_tkeep_q <= pipeline_tkeep_d;
          pipeline_tlast_q <= pipeline_tlast_d;
          pipeline_tid_q <= pipeline_tid_d;
          pipeline_tdest_q <= pipeline_tdest_d;
          pipeline_tuser_q <= pipeline_tuser_d;
          pipeline_twakeup_q <= pipeline_twakeup_d;
        end
      end : pipelineFFs

      always_comb begin : inputLogic
        // either already empty or will be after this cycle
        port_in.tready = port_out.tready || !pipeline_used_q;

        pipeline_tdata_d = pipeline_tdata_q;
        pipeline_tstrb_d = pipeline_tstrb_q;
        pipeline_tkeep_d = pipeline_tkeep_q;
        pipeline_tlast_d = pipeline_tlast_q;
        pipeline_tid_d = pipeline_tid_q;
        pipeline_tdest_d = pipeline_tdest_q;
        pipeline_tuser_d = pipeline_tuser_q;
        pipeline_twakeup_d = pipeline_twakeup_q;
        if (!pipeline_used_q || port_out.tready) begin
          // nothing pipelined OR last data consumed in this cycle
          pipeline_tdata_d = port_in.tdata;
          pipeline_tstrb_d = port_in.tstrb;
          pipeline_tkeep_d = port_in.tkeep;
          pipeline_tlast_d = port_in.tlast;
          pipeline_tid_d = port_in.tid;
          pipeline_tdest_d = port_in.tdest;
          pipeline_tuser_d = port_in.tuser;
          pipeline_twakeup_d = port_in.twakeup;
        end

        if (pipeline_used_q) begin
          if (port_out.tready) begin
            // last transaction just accepted - are we getting a new one?
            pipeline_used_d = port_in.tvalid;
          end else begin
            // need to hold until accepted
            pipeline_used_d = 1'b1;
          end
        end else begin
          // pipeline used as soon as tvalid brings new data
          pipeline_used_d = port_in.tvalid;
        end

      end : inputLogic

      always_comb begin : outputLogic
        port_out.tvalid = pipeline_used_q;
        port_out.tdata = pipeline_tdata_q;
        port_out.tstrb = pipeline_tstrb_q;
        port_out.tkeep = pipeline_tkeep_q;
        port_out.tlast = pipeline_tlast_q;
        port_out.tid = pipeline_tid_q;
        port_out.tdest = pipeline_tdest_q;
        port_out.tuser = pipeline_tuser_q;
        port_out.twakeup = pipeline_twakeup_q;
      end : outputLogic
    end : gen_pipeline_stage
    else begin : gen_skip_pipeline_stage
      always_comb begin : skipLogic
        port_out.tdata = port_in.tdata;
        port_out.tvalid = port_in.tvalid;
        port_out.tid = port_in.tid;
        port_out.tdest = port_in.tdest;
        port_out.tuser = port_in.tuser;
        port_out.tstrb = port_in.tstrb;
        port_out.tkeep = port_in.tkeep;
        port_out.tlast = port_in.tlast;
        port_out.twakeup = port_in.twakeup;

        port_in.tready = port_out.tready;
      end : skipLogic
    end : gen_skip_pipeline_stage
  endgenerate

  // sometimes (partially) optimized away
  `NORTHCAPE_UNREAD(port_in.tdata);

  `NORTHCAPE_UNREAD(port_out.clk_i);
  `NORTHCAPE_UNREAD(port_out.rst_ni);

  `NORTHCAPE_UNREAD(port_in.clk_i);
  `NORTHCAPE_UNREAD(port_in.rst_ni);

  // not always used
  `NORTHCAPE_UNREAD(port_in.tstrb);
  `NORTHCAPE_UNREAD(port_in.tkeep);

endmodule
