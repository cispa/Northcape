/**
  * Size-optimized state machine that zeros out a block RAM.
  */
module northcape_sram_initializer #(
    parameter  int DATA_WIDTH = -1,
    parameter  int DATA_DEPTH = -1,
    parameter  bit START_BUSY = 1'b0,
    localparam int ADDR_WIDTH = $clog2(DATA_DEPTH)
) (
    input logic clk_i,
    input logic rst_ni,

    output logic [DATA_WIDTH-1:0] wdata_o,
    output logic [ADDR_WIDTH-1:0] waddr_o,
    output logic wenable_o,

    input  logic start_i,
    output logic busy_o
);

  logic [ADDR_WIDTH-1:0] addr_q, addr_d;
  typedef enum logic {
    IDLE,
    BUSY
  } state_t;

  state_t state_q, state_d;

  assign wdata_o = '0;
  assign waddr_o = addr_q;
  assign wenable_o = (state_q == BUSY);
  assign busy_o = (state_q == BUSY);


  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : fsmFFs
    if (!rst_ni) begin
      addr_q  <= '0;
      state_q <= START_BUSY ? BUSY : IDLE;
    end else begin
      addr_q  <= addr_d;
      state_q <= state_d;
    end
  end : fsmFFs

  always_comb begin : countLogic
    addr_d = addr_q;

    unique case (state_q)
      BUSY: begin
        addr_d = addr_q + 1;
      end
      default: ;
    endcase
  end : countLogic

  always_comb begin : stateFSM
    state_d = state_q;

    unique case (state_q)
      IDLE: begin
        if (start_i) begin
          state_d = BUSY;
        end
      end
      BUSY: begin
        if (addr_d == '0) begin
          state_d = IDLE;
        end
      end
      default: ;  // unreachable state
    endcase
  end : stateFSM


endmodule
