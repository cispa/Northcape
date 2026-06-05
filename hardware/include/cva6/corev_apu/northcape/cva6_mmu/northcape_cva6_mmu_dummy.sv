import northcape_types::*;

module northcape_cva6_mmu #(
    parameter int XLEN = 64,
    parameter type access_size_t = logic [$clog2(8)-1:0],
    parameter bit IS_EXECUTE = 1'b0
) (
    input logic clk_i,
    input logic rst_ni,

    // cva6 -> northcape: translate this token please
    input logic [XLEN-1:0] data_address_i,
    input logic data_is_store_i,
    input access_size_t data_access_size_i,
    // precondition to translation_immediate_o
    input logic data_is_immediate_i,
    input logic data_is_atomic_i,
    // are we in IRQ context?
    input logic data_is_irq_i,
    input logic data_is_valid_i,

    // northcape -> cva6: translated token, error if any
    output logic [XLEN-1:0] translated_address_o,
    output logic translation_error_o,
    output logic translation_valid_o,
    // response in same cycle
    output logic translation_immediate_o,
    // is non-cacheable?
    output logic translation_requires_non_cacheable_o,

    // conveys task ID
    // not actually tristate: write-only if IS_EXECUTE=1, read-only otherwise
    inout wire [NORTHCAPE_TASK_ID_WIDTH-1:0] current_task_id_irq,
    inout wire [NORTHCAPE_TASK_ID_WIDTH-1:0] current_task_id_non_irq,

    // interface to capability resolver
    Axis5.TRANSMITTER axis_validate_request,
    Axis5.RECEIVER axis_validate_response,

    // current CMT metadata from operations module
    NorthcapeCMTInterface.CONSUMER cmt_interface
);
  //===================================
  // Default assignments
  //===================================
  assign axis_validate_request.tstrb        = '1;
  assign axis_validate_request.tkeep        = '1;
  assign axis_validate_request.tid          = 1'b0;
  assign axis_validate_request.tdest        = 1'b0;
  assign axis_validate_request.tuser        = 1'b0;
  assign axis_validate_request.twakeup      = 1'b1;
  assign axis_validate_request.tlast        = 1'b1;


  // interface never used
  assign axis_validate_request.tdata        = '0;
  assign axis_validate_request.tvalid       = 1'b0;

  assign axis_validate_response.tready      = 1'b0;

  // forwards
  assign translated_address_o               = data_address_i;
  assign translation_error_o                = 1'b0;
  assign translation_valid_o                = data_is_valid_i;
  assign translation_immediate_o            = data_is_immediate_i;
  assign translation_requires_non_cacheable = 1'b0;

  // not used
  assign current_task_id_irq                = 'z;
  assign current_task_id_non_irq            = 'z;
endmodule
