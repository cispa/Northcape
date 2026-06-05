
`include "ariane_xlnx_mapper.svh"
module northcape_user_parser_wrapper#(
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter PASSTHROUGH_MODE = -1
)(
    input logic clk_i,
    input logic rst_ni,

    `AXI_INTERFACE_MODULE_MONITOR(s_axi),

    output logic [15:0] active_device,
    output logic [31:0] active_task,
    output logic [63:0] active_device_specific_restriction,
    output logic parsing_error
);
  `include "northcape_unread.vh"

  NorthcapeCurrentDeviceTaskInterface current_device_task_interface(.clk_i(clk_i));

  assign active_device = current_device_task_interface.active_device;
  assign active_task = current_device_task_interface.active_task;
  assign active_device_specific_restriction = current_device_task_interface.device_specific_restriction;
  assign parsing_error = current_device_task_interface.parsing_error;

  // AXI-LITE does not (always) have user bus
  // so we parse it separately
  northcape_user_parser#(
    .AXI_USER_WIDTH(AXI_USER_WIDTH),
    .PASSTHROUGH_MODE(PASSTHROUGH_MODE)
  ) i_user_parser(
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_aruser(s_axi_aruser),

    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_awuser(s_axi_awuser),

    .device_task_intf(current_device_task_interface)
  );


  `NORTHCAPE_UNREAD(s_axi_awid);
  `NORTHCAPE_UNREAD(s_axi_awaddr);
  `NORTHCAPE_UNREAD(s_axi_awlen);
  `NORTHCAPE_UNREAD(s_axi_awsize);
  `NORTHCAPE_UNREAD(s_axi_awburst);
  `NORTHCAPE_UNREAD(s_axi_awlock);
  `NORTHCAPE_UNREAD(s_axi_awcache);
  `NORTHCAPE_UNREAD(s_axi_awprot);
  `NORTHCAPE_UNREAD(s_axi_awqos);
  `NORTHCAPE_UNREAD(s_axi_awatop);
  `NORTHCAPE_UNREAD(s_axi_awregion);
  `NORTHCAPE_UNREAD(s_axi_wdata);
  `NORTHCAPE_UNREAD(s_axi_wstrb);
  `NORTHCAPE_UNREAD(s_axi_wlast);
  `NORTHCAPE_UNREAD(s_axi_wuser);
  `NORTHCAPE_UNREAD(s_axi_wvalid);
  `NORTHCAPE_UNREAD(s_axi_wready);
  `NORTHCAPE_UNREAD(s_axi_bid);
  `NORTHCAPE_UNREAD(s_axi_bresp);
  `NORTHCAPE_UNREAD(s_axi_buser);
  `NORTHCAPE_UNREAD(s_axi_bvalid);
  `NORTHCAPE_UNREAD(s_axi_bready);
  `NORTHCAPE_UNREAD(s_axi_arid);
  `NORTHCAPE_UNREAD(s_axi_araddr);
  `NORTHCAPE_UNREAD(s_axi_arlen);
  `NORTHCAPE_UNREAD(s_axi_arsize);
  `NORTHCAPE_UNREAD(s_axi_arburst);
  `NORTHCAPE_UNREAD(s_axi_arlock);
  `NORTHCAPE_UNREAD(s_axi_arcache);
  `NORTHCAPE_UNREAD(s_axi_arprot);
  `NORTHCAPE_UNREAD(s_axi_arqos);
  `NORTHCAPE_UNREAD(s_axi_arregion);
  `NORTHCAPE_UNREAD(s_axi_rdata);
  `NORTHCAPE_UNREAD(s_axi_rresp);
  `NORTHCAPE_UNREAD(s_axi_rlast);
  `NORTHCAPE_UNREAD(s_axi_rid);
  `NORTHCAPE_UNREAD(s_axi_ruser);
  `NORTHCAPE_UNREAD(s_axi_rvalid);
  `NORTHCAPE_UNREAD(s_axi_rready);


endmodule
