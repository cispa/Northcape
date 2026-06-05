/**
  * Dummy capability resolver.
  * Acts as if only the root capability existed in the system and answers queries accordingly.
  */

import northcape_types::*;

module northcape_capability_resolver_dummy (
    Axis5 axis_validate_request,
    Axis5 axis_validate_response
);
  //===================================
  // Default assignments
  //===================================
  assign axis_validate_response.tstrb   = '1;
  assign axis_validate_response.tkeep   = '1;
  assign axis_validate_response.tid     = 0;
  assign axis_validate_response.tdest   = 0;
  assign axis_validate_response.tuser   = 0;
  assign axis_validate_response.twakeup = 1;
  assign axis_validate_response.tlast   = 1;

  typedef enum {
    DUMMY_IDLE,
    DUMMY_WAIT_CONFIRM_RESPONSE
  } northcape_dummy_state_t;

  //===================================
  //  state + wires
  //===================================

  logic clk_i, rst_ni;

  assign clk_i  = axis_validate_request.clk_i;
  assign rst_ni = axis_validate_request.rst_ni;

  northcape_dummy_state_t current_dummy_state, next_dummy_state;

  axis_validate_request_tdata_t current_request;

  axis_validate_response_tdata_t current_response, next_response;

  capability_id_t  current_capability_id;
  capability_tag_t current_capability_tag;

  //===================================
  // Sequential Logic
  //===================================

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : dummyStateFF
    if (rst_ni == 0) begin
      current_dummy_state <= DUMMY_IDLE;
    end else begin
      current_dummy_state <= next_dummy_state;
    end
  end : dummyStateFF

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : requestInterfaceReadyLogic
    if (rst_ni == 0) begin
      axis_validate_request.tready <= 1;
    end else begin
      axis_validate_request.tready <= (next_dummy_state == DUMMY_IDLE);
    end
  end : requestInterfaceReadyLogic

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : responseInterfaceFFLogic
    if (rst_ni == 0) begin
      axis_validate_response.tvalid <= 0;
      axis_validate_response.tdata  <= '0;
    end else begin
      axis_validate_response.tdata <= current_response;
      unique case (current_dummy_state)
        DUMMY_IDLE: begin
          axis_validate_response.tvalid <= 0;
        end
        DUMMY_WAIT_CONFIRM_RESPONSE: begin
          axis_validate_response.tvalid <= !(axis_validate_response.tvalid && axis_validate_response.tready);
        end
      endcase

    end
  end : responseInterfaceFFLogic

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : currentResponseFF
    if (rst_ni == 0) begin
      current_response.address <= '0;
      current_response.segment_length <= '0;
    end else begin
      if (current_dummy_state == DUMMY_IDLE && axis_validate_request.tvalid) begin
        // next_response computed on valid data
        current_response <= next_response;
      end
    end
  end : currentResponseFF

  //===================================
  // Combinational Logic
  //===================================
  always_comb begin : nextResponseLogic
    current_request = axis_validate_request.tdata;
    current_capability_id = current_request.address;
    current_capability_tag = current_request.tag;

    // MMU will add offset accordingly for original request
    next_response.address = 0;

    if(current_capability_id == NORTHCAPE_ROOT_CAPABILITY_ID && current_capability_tag == NORTHCAPE_ROOT_CAPABILITY_TAG && current_request.access_type != PERM_RESERVED)
    begin
      // valid - can use entire address space
      next_response.segment_length = '1;
    end else begin
      // we are a dummy and do not handle non-root capabilities
      next_response.segment_length = '0;
    end
  end : nextResponseLogic

  always_comb begin : nextStateLogic
    next_dummy_state = current_dummy_state;

    unique case (current_dummy_state)
      DUMMY_IDLE: begin
        if (axis_validate_request.tready && axis_validate_request.tvalid) begin
          // transfer to us took place
          next_dummy_state = DUMMY_WAIT_CONFIRM_RESPONSE;
        end
      end
      DUMMY_WAIT_CONFIRM_RESPONSE: begin
        if (axis_validate_response.tvalid && axis_validate_response.tready) begin
          // transfer from us took place
          next_dummy_state = DUMMY_IDLE;
        end
      end
      default: begin
        // nothing to do...
      end
    endcase
  end : nextStateLogic

endmodule
