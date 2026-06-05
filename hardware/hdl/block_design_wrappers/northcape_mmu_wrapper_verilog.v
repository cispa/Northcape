
`include "ariane_xlnx_mapper.svh"
`include "northcape_unread.vh"

module northcape_mmu_wrapper_verilog
#(  parameter BYPASS_NORTHCAPE=0,
    parameter ACCEPT_AXI_WRAP_BURSTS = 0,
    parameter AXI_ID_WIDTH=10,
    parameter AXI_ADDR_WIDTH=64,
    parameter AXI_DATA_WIDTH=64,
    parameter AXI_USER_WIDTH=128,
    parameter TDATA_WIDTH=512,
    parameter TID_WIDTH=1,
    parameter TDEST_WIDTH=16,
    parameter TUSER_WIDTH = 1,

    parameter SELF_PRESERVATION_MODE_ACTIVE=1,
    parameter READ_CHAN_DEVICE_ID = -1,
    parameter WRITE_CHAN_DEVICE_ID = -1,

    parameter CAPABILITY_ID_WIDTH = 38,

    parameter SHIFTING_ACTIVE = 1,
    // cover edge case where bursts partially leave the capability and we need to censor information?
    parameter MASKING_ACTIVE = 1,

    parameter ENABLE_ILA = 0,

    parameter DEVICE_INDICATES_EXECUTE = 1'b1,
    parameter MMU_BYPASS_UNTIL_CMT_RESET_DONE_ENABLED = 1'b1
)
(
    // TODO if this port is not named CLK, device tree generation in Vitis fails...
    (*X_INTERFACE_PARAMETER = "FREQ_HZ 50000000"*)
    input wire CLK,
    input wire aresetn,

    `AXI_INTERFACE_MODULE_INPUT(s_axi_in),
    `AXI_INTERFACE_MODULE_OUTPUT(m_axi_out),

    `AXIS_MODULE_OUTPUT(axis_validate_request_read),
    `AXIS_MODULE_OUTPUT(axis_validate_request_write),

    `AXIS_MODULE_INPUT(axis_validate_response_read),
    `AXIS_MODULE_INPUT(axis_validate_response_write),


    input wire[31:0] cmt_table_size_clog2,
    input wire [AXI_ADDR_WIDTH - 1 : 0] cmt_base,
    input wire cmt_reset_done,
    input wire cmt_need_flush_data_caches,
    input wire cmt_wrote_any_capability,
    input wire [CAPABILITY_ID_WIDTH-1:0] cmt_written_capability,
    
    
      // TODO dummy interrupt for device tree generation in Vitis
    (*X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 dummy_irq_in INTERRUPT", X_INTERFACE_PARAMETER = "SENSITIVITY EDGE_RISING" *)
    input wire [1 : 0] dummy_irq_in

);

generate
  if(BYPASS_NORTHCAPE)
  begin
`ifndef ASIC
    $info("Bypassing northcape MMU!");
`endif
    `ASSIGN_XLNX_MASTER_FROM_XLNX_SLAVE(s_axi_in,m_axi_out)
   end 
  else
  begin
`ifndef ASIC
    $info("Implementing northcape MMU!");
`endif
    northcape_mmu_wrapper
    #(
      .ACCEPT_AXI_WRAP_BURSTS(ACCEPT_AXI_WRAP_BURSTS),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .TDATA_WIDTH(TDATA_WIDTH),
      .TID_WIDTH(TID_WIDTH),
      .TDEST_WIDTH(TDEST_WIDTH),
      .TUSER_WIDTH(TUSER_WIDTH),
      .SELF_PRESERVATION_MODE_ACTIVE(SELF_PRESERVATION_MODE_ACTIVE),
      .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
      .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
      .MASKING_ACTIVE(MASKING_ACTIVE),
      .SHIFTING_ACTIVE(SHIFTING_ACTIVE),
      .ENABLE_ILA(ENABLE_ILA),
      .DEVICE_INDICATES_EXECUTE(DEVICE_INDICATES_EXECUTE),
      .MMU_BYPASS_UNTIL_CMT_RESET_DONE_ENABLED(MMU_BYPASS_UNTIL_CMT_RESET_DONE_ENABLED),
      .CAPABILITY_ID_WIDTH(CAPABILITY_ID_WIDTH)
    )
    i_northcape_mmu
    (
      .clk_i(CLK),
      .rst_ni(aresetn),
      `AXI_INTERFACE_FORWARD(s_axi_in),
      `AXI_INTERFACE_FORWARD(m_axi_out),

      `AXIS_INPUT_FORWARD(axis_validate_request_read),
      `AXIS_INPUT_FORWARD(axis_validate_request_write),

      `AXIS_INPUT_FORWARD(axis_validate_response_read),
      `AXIS_INPUT_FORWARD(axis_validate_response_write),

      .cmt_base(cmt_base),
      .cmt_table_size_clog2(cmt_table_size_clog2),
      .cmt_reset_done(cmt_reset_done),
      .cmt_need_flush_data_caches(cmt_need_flush_data_caches),
      .cmt_wrote_any_capability(cmt_wrote_any_capability),
      .cmt_written_capability(cmt_written_capability)
    );
  end
endgenerate

`NORTHCAPE_UNREAD_EXPLICIT_WIDTH(dummy_irq_in, 2);

endmodule
