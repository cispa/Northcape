
`include "uvm_macros.svh"
import northcape_test::*;
import northcape_mmu_transaction::*;
import northcape_types::*;
import uvm_pkg::*;

/**
  * Simulates a Northcape capability resolver for either read or write.
  * Given a NorthcapeMMUScoreboard, also verifies that the behavior of the request matches the expectation and gives the response according to the transaction.
  */
module northcape_axis_validate_driver (
    input mailbox#(INorthcapeCapabilityResolverTransaction) requests_in,

    input logic clk_i,
    input logic rst_ni,

    Axis5 axis_validate_request,
    Axis5 axis_validate_response,

    input uvm_analysis_port#(AxisValidateResultTransaction) ap_i
);

  localparam COMPONENT_NAME = "AXIS Validate Driver";

  typedef enum {
    IDLE,
    WAIT_REQUEST,
    GIVE_RESPONSE,
    TEST_OK,
    TEST_ERR
  } northcape_axis_validate_driver_state_t;

  northcape_axis_validate_driver_state_t current_state, next_state;

  INorthcapeCapabilityResolverTransaction current_transaction;

  initial begin
    NorthcapeMMUTransactionResolver #(
        .AXI_ADDR_WIDTH(64),
        .AXI_DATA_WIDTH(64),
        .AXI_ID_WIDTH  (32),
        .AXI_USER_WIDTH(64)
    ) tmp;
    // garbage values, only used such that we can get access to its delay gen
    tmp = new("");
    current_transaction = tmp;
  end

  logic have_test_request;

  bit   validate_request_error;

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : currentStateFFLogic
    if (rst_ni == 0) begin
      current_state <= IDLE;
    end else begin
      current_state <= next_state;
    end
  end

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : testRequestExtraction
    if (rst_ni == 0) begin
      have_test_request <= 0;
    end else begin
      unique case (current_state)
        IDLE: begin
          if (requests_in.num() > 0 && !have_test_request) begin
            automatic INorthcapeCapabilityResolverTransaction tmp;
            have_test_request <= requests_in.try_get(tmp) == 0 ? 0 : 1;
            current_transaction = tmp;
          end
        end
        default begin
          have_test_request <= 0;
        end
      endcase
    end
  end

  axis_validate_request_tdata_t parsed_response;

  assign parsed_response = axis_validate_request.tdata;

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : validateRequestFFLogic
    if (rst_ni == 0) begin
      validate_request_error <= 0;
      axis_validate_request.tready <= 0;
    end else begin
      unique case (current_state)
        WAIT_REQUEST: begin
          axis_validate_request.tready <= 1;
          if (axis_validate_request.tvalid && axis_validate_request.tready) begin
            automatic AxisValidateResultTransaction result;
            result = new("Result transaction");
            result.request_data = parsed_response;
`ifdef DEBUG
            $display("Reporting result transaction %s", result.convert2string());
`endif

            ap_i.write(result);


            validate_request_error <= 0;
          end
        end
        GIVE_RESPONSE, TEST_OK, TEST_ERR: begin
          // do not accidentally accept next transaction
          axis_validate_request.tready <= 1'b0;
          if (axis_validate_request.tvalid) begin
            // second request for the same transaction
            `uvm_error(COMPONENT_NAME, "axis_validate_request unexpectedly valid!");
            validate_request_error <= 1;
          end
        end
        default: begin
          axis_validate_request.tready <= 0;
          validate_request_error <= 0;
        end
      endcase
    end
  end

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : validateResponseFFLogic
    if (rst_ni == 0) begin
      axis_validate_response.tvalid <= 0;
    end else begin
      unique case (current_state)
        GIVE_RESPONSE: begin
          automatic axis_validate_response_tdata_t response;

          response = current_transaction.get_resolver_response();

          `uvm_info(COMPONENT_NAME, $sformatf(
                    "Resolver responding with base address %x length %x!",
                    response.address,
                    response.segment_length
                    ), UVM_DEBUG);
          axis_validate_response.tvalid <= !(axis_validate_response.tvalid && axis_validate_response.tready);
          axis_validate_response.tdata <= response;
          axis_validate_response.tstrb <= '1;
          axis_validate_response.tkeep <= '1;
          axis_validate_response.tlast <= 1;
        end
        default: begin
          axis_validate_response.tvalid <= 0;
          // the true resolver is allowed to / expected to destroy the data as long as tvalid is low
          axis_validate_response.tdata  <= '0;
          axis_validate_response.tstrb  <= '0;
          axis_validate_response.tkeep  <= '0;
          axis_validate_response.tlast  <= 0;
        end
      endcase
    end
  end

  always_comb begin : nextStateLogic
    next_state = current_state;

    unique case (current_state)
      IDLE: begin
        if (have_test_request) begin
          next_state = WAIT_REQUEST;
        end
      end
      WAIT_REQUEST: begin
        if (axis_validate_request.tvalid && axis_validate_request.tready) begin
          next_state = validate_request_error ? TEST_ERR : GIVE_RESPONSE;
        end
      end
      GIVE_RESPONSE: begin
        if (validate_request_error) begin
          next_state = TEST_ERR;
        end else if (axis_validate_response.tvalid && axis_validate_response.tready) begin
          next_state = TEST_OK;
        end
      end
      TEST_OK, TEST_ERR: begin
        `uvm_info(COMPONENT_NAME, "Info: Resolver transitioning back to idle!", UVM_DEBUG);
        next_state = IDLE;
      end
    endcase
  end

endmodule
