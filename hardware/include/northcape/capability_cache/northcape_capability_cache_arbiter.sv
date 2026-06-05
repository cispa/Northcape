/**
  * Generic arbiter for missunit: performs type-agnostic arbitration and holds result until completed.
  * Statically prefers the resolver.
  *
  */

module northcape_capability_cache_arbiter #(
    parameter type arbitration_type_t = logic
) (
    input logic clk_i,
    input logic rst_ni,
    input arbitration_type_t input_resolver_i,
    input arbitration_type_t input_ops_i,
    input logic request_resolver_i,
    input logic request_ops_i,
    input logic operation_complete_i,

    output arbitration_type_t arbited_input_o,
    output logic any_request_o,
    output northcape_capability_cache_common::northcape_capability_cache_arbitration_type_t arbitration_result_o
);

  import northcape_capability_cache_common::*;

  //===================================
  // declarations and static assignments
  //===================================

  typedef enum logic {
    IDLE,
    WAIT_COMPLETE
  } state_t;

  state_t state_q, state_d;

  northcape_capability_cache_arbitration_type_t grant_q, grant_d, next_grant;

  //===================================
  // sequential logic
  //===================================

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : stateFFs
    if (!rst_ni) begin
      state_q <= IDLE;
      grant_q <= NORTHCAPE_CAP_CACHE_RESOLVER;
    end else begin
      state_q <= state_d;
      grant_q <= grant_d;
    end
  end : stateFFs

  //===================================
  // combinational logic
  //===================================

  always_comb begin : stateLogic
    state_d = state_q;

    unique case (state_q)
      IDLE: begin
        if (request_resolver_i || request_ops_i) begin
          state_d = WAIT_COMPLETE;
        end
      end
      WAIT_COMPLETE: begin
        if (operation_complete_i) begin
          // have to keep the output stable for one cycle so it can be read
          state_d = IDLE;
        end
      end
      default: ;
    endcase

  end : stateLogic

  always_comb begin : grantLogic
    grant_d = grant_q;


    next_grant = NORTHCAPE_CAP_CACHE_RESOLVER;

    // statically prefer resolver for real-time guarantees
    if (request_resolver_i) begin
      next_grant = NORTHCAPE_CAP_CACHE_RESOLVER;
    end else begin
      next_grant = NORTHCAPE_CAP_CACHE_OPS;
    end

    unique case (state_q)
      IDLE: begin
        grant_d = next_grant;
      end
      default: ;  // keep grant during this cycle, so the operation can complete
    endcase
  end : grantLogic

  always_comb begin : outputLogic
    arbited_input_o = grant_d == NORTHCAPE_CAP_CACHE_RESOLVER ? input_resolver_i : input_ops_i;
    arbitration_result_o = grant_d;
    any_request_o = request_resolver_i || request_ops_i;
  end : outputLogic
endmodule
