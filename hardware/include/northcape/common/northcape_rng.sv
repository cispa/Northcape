/**
  * Wrapper around True Random Number Generator (TRNG) generator module.
  */
interface NorthcapeRNGInterface #(
    parameter RNG_DATA_WIDTH = -1
) (
    input logic clk_i,
    input logic rst_ni
);

  logic [RNG_DATA_WIDTH - 1 : 0] rng_out;

  logic rng_valid;
  logic rng_consumer_ready;

  modport RNG(
      input clk_i,
      input rst_ni,

      output rng_out,
      output rng_valid,

      input rng_consumer_ready
  );

  modport RNG_CONSUMER(
      input clk_i,
      input rst_ni,

      input rng_out,
      input rng_valid,

      output rng_consumer_ready
  );

`ifndef VERILATOR

  clocking test_producer_clocking @(posedge (clk_i));
    input rst_ni;

    output rng_out;
    output rng_valid;

    input rng_consumer_ready;
  endclocking

  modport TEST_PRODUCER(clocking test_producer_clocking);

`endif

endinterface

module northcape_rng #(
    parameter RNG_DATA_WIDTH = -1
) (
    NorthcapeRNGInterface.RNG intf
);

  logic [RNG_DATA_WIDTH - 1 : 0] current_rng_output_q, current_rng_output_d;
  logic [$clog2(RNG_DATA_WIDTH) - 1 : 0] output_index_q, output_index_d;

  logic clk_i;
  logic rst_ni;

  logic reset_synchronizer_q, reset_synchronizer_d;

  logic rand_bit_d;

  logic [RNG_DATA_WIDTH - 1 : 0] rng_out_d;

  logic rng_valid_d;

  typedef enum {
    IDLE,
    ENABLE_RNG,
    BUSY,
    OUTPUT
  } state_t;

  state_t state_q, state_d;

  assign clk_i  = intf.clk_i;
  assign rst_ni = intf.rst_ni;

  trng i_trng (
      .clk(intf.clk_i),
      .rst(reset_synchronizer_q),
      .\rand (rand_bit_d)
  );

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : resetSynchronizerFF
    if (rst_ni == 0) begin
      reset_synchronizer_q <= 1;
    end else begin
      reset_synchronizer_q <= reset_synchronizer_d;
    end
  end : resetSynchronizerFF

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : stateFF
    if (rst_ni == 0) begin
      state_q <= IDLE;
    end else begin
      state_q <= state_d;
    end
  end : stateFF

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : rngOutputFF
    if (rst_ni == 0) begin
      current_rng_output_q <= '0;
      output_index_q <= '0;

      intf.rng_out <= '0;
      intf.rng_valid <= 0;
    end else begin
      current_rng_output_q <= current_rng_output_d;
      output_index_q <= output_index_d;

      intf.rng_out <= rng_out_d;
      intf.rng_valid <= rng_valid_d;
    end
  end : rngOutputFF

  always_comb begin : resetSynchronizerLogic
    unique case (state_q)
      ENABLE_RNG, BUSY, OUTPUT: reset_synchronizer_d = 0;
      default: reset_synchronizer_d = 1;
    endcase
  end : resetSynchronizerLogic

  always_comb begin : rngOutputLogic
    // maintain
    current_rng_output_d = current_rng_output_q;
    output_index_d = output_index_q;

    rng_out_d = intf.rng_out;
    rng_valid_d = intf.rng_valid;

    unique case (state_q)
      BUSY: begin
        current_rng_output_d[output_index_q] = rand_bit_d;
        output_index_d = output_index_q + 1;

        rng_out_d = '0;
        rng_valid_d = 0;
      end
      OUTPUT: begin
        rng_out_d   = current_rng_output_d;
        rng_valid_d = 1;
      end
      default: begin
        rng_out_d = '0;
        rng_valid_d = 0;
        current_rng_output_d = '0;
        output_index_d = '0;
      end
    endcase
  end : rngOutputLogic

  always_comb begin : nextStateLogic
    state_d = state_q;

    unique case (state_q)
      IDLE: begin
        if (intf.rng_consumer_ready) begin
          state_d = ENABLE_RNG;
        end
      end
      ENABLE_RNG: begin
        // RNG needs one cycle to get ready
        state_d = BUSY;
      end
      BUSY: begin
        if (output_index_q == RNG_DATA_WIDTH - 1) begin
          state_d = OUTPUT;
        end
      end
      OUTPUT: begin
        state_d = IDLE;
      end
      default: begin
        state_d = state_q;
      end
    endcase

  end : nextStateLogic


endmodule
