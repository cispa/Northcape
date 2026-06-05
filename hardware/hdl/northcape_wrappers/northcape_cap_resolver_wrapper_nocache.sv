`include "ariane_xlnx_mapper.svh"
`include "northcape_xilinx_wrapper.vh"
module northcape_cap_resolver_wrapper_nocache
#(
    parameter TDATA_WIDTH=-1,
    parameter TID_WIDTH=-1,
    parameter TDEST_WIDTH=-1,
    parameter TUSER_WIDTH = -1,

    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,
    parameter CAPABILITY_ID_WIDTH = -1,

    // size of the FIFO that buffers requests
    // indicates number of max parallel requests
    parameter FIFO_DEPTH_CLOG_2=-1,
    parameter MAX_AXI_TRANSACTIONS=-1
)
(
    input logic clk_i,
    input logic rst_ni,

    `AXI_INTERFACE_MODULE_OUTPUT(m_resolver_out),

    // TODO currently forced to define these manually...
    `AXIS_MODULE_INPUT(axis_validate_request_0),
    `AXIS_MODULE_OUTPUT(axis_validate_response_0),
    `AXIS_MODULE_INPUT(axis_validate_request_1),
    `AXIS_MODULE_OUTPUT(axis_validate_response_1),
    `AXIS_MODULE_INPUT(axis_validate_request_2),
    `AXIS_MODULE_OUTPUT(axis_validate_response_2),
    `AXIS_MODULE_INPUT(axis_validate_request_3),
    `AXIS_MODULE_OUTPUT(axis_validate_response_3),
    `AXIS_MODULE_INPUT(axis_validate_request_4),
    `AXIS_MODULE_OUTPUT(axis_validate_response_4),
    `AXIS_MODULE_INPUT(axis_validate_request_5),
    `AXIS_MODULE_OUTPUT(axis_validate_response_5),

    // to CMT interface
    input int unsigned cmt_table_size_clog2,
    input wire [AXI_ADDR_WIDTH - 1 : 0] cmt_base,
    input wire cmt_reset_done,
    input wire cmt_need_flush_data_caches,
    input wire cmt_wrote_any_capability,
    input wire [CAPABILITY_ID_WIDTH-1:0] cmt_written_capability
);

import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
import axi5::*;

localparam NUMBER_PORTS = 6;

Axis5#(.AXIS_TDATA_WIDTH(TDATA_WIDTH), .AXIS_TID_WIDTH(TID_WIDTH), .AXIS_TDEST_WIDTH(TDEST_WIDTH), .AXIS_TUSER_WIDTH(TUSER_WIDTH)) northcape_axis_validate_request_in[NUMBER_PORTS+1](.clk_i(clk_i),.rst_ni(rst_ni)), northcape_axis_validate_request(.clk_i(clk_i),.rst_ni(rst_ni));
Axis5#(.AXIS_TDATA_WIDTH(TDATA_WIDTH), .AXIS_TID_WIDTH(TID_WIDTH), .AXIS_TDEST_WIDTH(TDEST_WIDTH), .AXIS_TUSER_WIDTH(TUSER_WIDTH)) northcape_axis_validate_response_out[NUMBER_PORTS](.clk_i(clk_i),.rst_ni(rst_ni)), northcape_axis_validate_response(.clk_i(clk_i),.rst_ni(rst_ni));

Axi5#(.AXI_DATA_WIDTH(AXI_DATA_WIDTH), .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_ID_WIDTH(AXI_ID_WIDTH), .AXI_USER_WIDTH(AXI_USER_WIDTH)) northcape_resolver_axi_out(.clk_i(clk_i),.rst_ni(rst_ni));

NorthcapeCMTInterface#(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) cmt_interface(.clk_i(clk_i));

assign cmt_interface.table_size_clog2 = cmt_table_size_clog2;
assign cmt_interface.cmt_base = cmt_base;
assign cmt_interface.reset_done = cmt_reset_done;
assign cmt_interface.need_flush_data_caches = cmt_need_flush_data_caches;
assign cmt_interface.wrote_any_capability = cmt_wrote_any_capability;
assign cmt_interface.written_capability = cmt_written_capability;

NorthcapeCapabilityCacheInterfaceResolver resolver_interface (.clk_i(clk_i));
// not used here
assign resolver_interface.response_valid = 1'b0;
assign resolver_interface.response_err = '0;
assign resolver_interface.response_cmt_entry = '0;

// input ports + 1 for recursion
Axis5Mux#(
    .NUMBER_IN_PORTS(NUMBER_PORTS+1)
  ) i_mux(
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .in_ports(northcape_axis_validate_request_in),
    .out_port(northcape_axis_validate_request.TRANSMITTER)
  );

northcape_capability_resolver#(
    .HASH_TYPE(HASH_TYPE_IDENTITY),

    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),
    .FIFO_DEPTH_CLOG_2(FIFO_DEPTH_CLOG_2),
    .MAX_AXI_TRANSACTIONS(MAX_AXI_TRANSACTIONS)    
  )
  i_northcape_capability_resolver (
      .clk_i(clk_i),
      .rst_ni(rst_ni),

      .cache_interface(resolver_interface),

      .validate_request(northcape_axis_validate_request.RECEIVER),
      .axi_master(northcape_resolver_axi_out),
      .validate_response(northcape_axis_validate_response.TRANSMITTER),
      .validate_request_recursion(northcape_axis_validate_request_in[NUMBER_PORTS].TRANSMITTER),
      
      .cmt_interface(cmt_interface)
  );

  Axis5Demux#(
    .NUMBER_OUT_PORTS(NUMBER_PORTS)
  ) i_demux(
    .in_port(northcape_axis_validate_response.RECEIVER),
    .out_ports(northcape_axis_validate_response_out)
  );

`NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(northcape_axis_validate_response_out[0], axis_validate_response_0)
`NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(northcape_axis_validate_request_in[0], axis_validate_request_0)
`NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(northcape_axis_validate_response_out[1], axis_validate_response_1)
`NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(northcape_axis_validate_request_in[1], axis_validate_request_1)
`NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(northcape_axis_validate_response_out[2], axis_validate_response_2)
`NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(northcape_axis_validate_request_in[2], axis_validate_request_2)
`NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(northcape_axis_validate_response_out[3], axis_validate_response_3)
`NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(northcape_axis_validate_request_in[3], axis_validate_request_3)
`NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(northcape_axis_validate_response_out[4], axis_validate_response_4)
`NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(northcape_axis_validate_request_in[4], axis_validate_request_4)
`NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(northcape_axis_validate_response_out[5], axis_validate_response_5)
`NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(northcape_axis_validate_request_in[5], axis_validate_request_5)

`NORTHCAPE_MAP_XILINX_AXI_INTERFACES_OUT(northcape_resolver_axi_out,m_resolver_out)

generate
  
  if(TDATA_WIDTH < northcape_types::AXIS_VALIDATE_REQUEST_TDATA_WIDTH || TDATA_WIDTH < northcape_types::AXIS_VALIDATE_RESPONSE_TDATA_WIDTH)
  begin
    $error("TDATA is too small!");
    $fatal(1);
  end
  
endgenerate

endmodule
