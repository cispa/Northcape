import axi5::*;
import northcape_types::*;

`include "ariane_xlnx_mapper.svh"
`include "northcape_xilinx_wrapper.vh"

module northcape_mmu_wrapper
#(
    parameter ACCEPT_AXI_WRAP_BURSTS = 0,
    parameter AXI_ID_WIDTH=-1,
    parameter AXI_ADDR_WIDTH=-1,
    parameter AXI_DATA_WIDTH=-1,
    parameter AXI_USER_WIDTH=-1,
    parameter TDATA_WIDTH=-1,
    parameter TID_WIDTH=-1,
    parameter TDEST_WIDTH=-1,
    parameter TUSER_WIDTH = -1,
    // set to one to error on requests that resolve into the CMT, even if otherwise valid
    parameter SELF_PRESERVATION_MODE_ACTIVE=1,
    parameter READ_CHAN_DEVICE_ID = -1,
    parameter WRITE_CHAN_DEVICE_ID = -1,
    parameter bit SHIFTING_ACTIVE = 1,
    // cover edge case where bursts partially leave the capability and we need to censor information?
    parameter bit MASKING_ACTIVE = 1,
    parameter bit ENABLE_ILA = 0,
    parameter bit DEVICE_INDICATES_EXECUTE = 1'b0,
    parameter bit MMU_BYPASS_UNTIL_CMT_RESET_DONE_ENABLED = 1'b0,
    parameter CAPABILITY_ID_WIDTH=-1
)
(
    input logic clk_i,
    input logic rst_ni,

    `AXI_INTERFACE_MODULE_INPUT(s_axi_in),
    `AXI_INTERFACE_MODULE_OUTPUT(m_axi_out),

    `AXIS_MODULE_OUTPUT(axis_validate_request_read),
    `AXIS_MODULE_OUTPUT(axis_validate_request_write),

    `AXIS_MODULE_INPUT(axis_validate_response_read),
    `AXIS_MODULE_INPUT(axis_validate_response_write),

    // to CMT interface
    input int unsigned cmt_table_size_clog2,
    input wire [AXI_ADDR_WIDTH - 1 : 0] cmt_base,
    input wire cmt_reset_done,
    input wire cmt_need_flush_data_caches,
    input wire cmt_wrote_any_capability,
    input wire [CAPABILITY_ID_WIDTH-1:0] cmt_written_capability

);
import axi5::*;

// TODO use exactly as many bits as needed
Axis5#(.AXIS_TDATA_WIDTH(TDATA_WIDTH), .AXIS_TID_WIDTH(TID_WIDTH), .AXIS_TDEST_WIDTH(TDEST_WIDTH), .AXIS_TUSER_WIDTH(TUSER_WIDTH)) northcape_axis_validate_request_read(.clk_i(clk_i),.rst_ni(rst_ni)), northcape_axis_validate_request_write(.clk_i(clk_i),.rst_ni(rst_ni));
Axis5#(.AXIS_TDATA_WIDTH(TDATA_WIDTH), .AXIS_TID_WIDTH(TID_WIDTH), .AXIS_TDEST_WIDTH(TDEST_WIDTH), .AXIS_TUSER_WIDTH(TUSER_WIDTH)) northcape_axis_validate_response_read(.clk_i(clk_i),.rst_ni(rst_ni)), northcape_axis_validate_response_write(.clk_i(clk_i),.rst_ni(rst_ni));

// interface that goes to SLAVE port of MMU
Axi5#(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_ID_WIDTH(AXI_ID_WIDTH), .AXI_DATA_WIDTH(AXI_DATA_WIDTH), .AXI_USER_WIDTH(AXI_USER_WIDTH))   northcape_mmu_axi_in(.clk_i(clk_i),.rst_ni(rst_ni));
  
// interface that goes to MASTER port of MMU
Axi5#(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_ID_WIDTH(AXI_ID_WIDTH), .AXI_DATA_WIDTH(AXI_DATA_WIDTH), .AXI_USER_WIDTH(AXI_USER_WIDTH))   northcape_mmu_axi_out(.clk_i(clk_i),.rst_ni(rst_ni));

NorthcapeCMTInterface#(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) cmt_interface(.clk_i(clk_i));

assign cmt_interface.table_size_clog2 = cmt_table_size_clog2;
assign cmt_interface.cmt_base = cmt_base;
assign cmt_interface.reset_done = cmt_reset_done;
assign cmt_interface.need_flush_data_caches = cmt_need_flush_data_caches;
assign cmt_interface.wrote_any_capability = cmt_wrote_any_capability;
assign cmt_interface.written_capability = cmt_written_capability;

northcape_mmu 
#(
  .ACCEPT_AXI_WRAP_BURSTS(ACCEPT_AXI_WRAP_BURSTS),
  .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
  .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
  .AXI_ID_WIDTH(AXI_ID_WIDTH),
  .AXI_USER_WIDTH(AXI_USER_WIDTH),

  .SELF_PRESERVATION_MODE_ACTIVE(SELF_PRESERVATION_MODE_ACTIVE),
  .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
  .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),


  .MASKING_ACTIVE(MASKING_ACTIVE),
  .SHIFTING_ACTIVE(SHIFTING_ACTIVE),

  .ENABLE_ILA(ENABLE_ILA),

  .DEVICE_INDICATES_EXECUTE(DEVICE_INDICATES_EXECUTE),
  .MMU_BYPASS_UNTIL_CMT_RESET_DONE_ENABLED(MMU_BYPASS_UNTIL_CMT_RESET_DONE_ENABLED)
)
i_northcape_mmu
(
  .clk_i(clk_i),
  .rst_ni(rst_ni),

  // AXI Slave interface
  .axi_slave(northcape_mmu_axi_in),

  // AXI Master interface
  .axi_master(northcape_mmu_axi_out),

  .axis_validate_request_read(northcape_axis_validate_request_read.TRANSMITTER),
  .axis_validate_response_read(northcape_axis_validate_response_read.RECEIVER),
  .axis_validate_request_write(northcape_axis_validate_request_write.TRANSMITTER),
  .axis_validate_response_write(northcape_axis_validate_response_write.RECEIVER),
  .cmt_interface(cmt_interface)
);

`NORTHCAPE_MAP_XILINX_AXI_INTERFACES(northcape_mmu_axi_in,northcape_mmu_axi_out,s_axi_in,m_axi_out)

`NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(northcape_axis_validate_response_read, axis_validate_response_read)
`NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(northcape_axis_validate_response_write, axis_validate_response_write)

`NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(northcape_axis_validate_request_read, axis_validate_request_read)
`NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(northcape_axis_validate_request_write, axis_validate_request_write)

generate
  
  if(TDATA_WIDTH < AXIS_VALIDATE_REQUEST_TDATA_WIDTH || TDATA_WIDTH < AXIS_VALIDATE_RESPONSE_TDATA_WIDTH)
  begin
    $error("TDATA is too small!");
    $fatal(1);
  end
  
endgenerate

endmodule
