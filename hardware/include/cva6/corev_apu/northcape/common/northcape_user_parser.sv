/**
 * Parses Northcape AXI User bits and extracts device, task, device-specific restrictions.
 * Assumes that read/write transactions never appear in the same clock cycle, raises error if they do.
 * The device is responsible for only accepting one request at a time.
 * For used with AXI-to-AXI-Lite-converters, set PASSTHROUGH_MODE to 0 and place it BEFORE the converter, such that it has time to latch the user bus.
 * For use with AXI buses, set PASSTHROUGH_MODE to 1 and select whether this should parse the AW or AR channel (PASSTHROUGH_CHANNEL=0 --> AR, otherwise AW)
 */

module northcape_user_parser #(
    parameter int AXI_USER_WIDTH = -1,
    // used to instead of latching 
    parameter bit PASSTHROUGH_MODE = 1'b0,
    parameter bit PASSTHROUGH_CHANNEL = 1'b0
) (
    input logic clk_i,
    input logic rst_ni,

    input logic s_axi_arvalid,
    input logic s_axi_arready,
    input logic [AXI_USER_WIDTH-1:0] s_axi_aruser,

    input logic s_axi_awvalid,
    input logic s_axi_awready,
    input logic [AXI_USER_WIDTH-1:0] s_axi_awuser,

    NorthcapeCurrentDeviceTaskInterface.USER_WRAPPER device_task_intf
);
  `include "northcape_unread.vh"

northcape_types::northcape_axi_user_t parsed_user_ar, parsed_user_aw;

  assign parsed_user_ar = s_axi_aruser;
  assign parsed_user_aw = s_axi_awuser;

  generate

    if (PASSTHROUGH_MODE == 1'b0) begin : latchMode

      northcape_types::device_id_t active_device_d;
      northcape_types::task_id_t active_task_d;
      northcape_types::northcape_device_interpreted_restriction_t device_specific_restriction_d;
      logic parsing_error_d;

      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : deviceTaskInterfacePopulatorFFs
        if (rst_ni == 0) begin
          device_task_intf.device_specific_restriction <= '0;
          device_task_intf.active_device <= '0;
          device_task_intf.active_task <= '0;
          device_task_intf.parsing_error <= 1'b1;
        end else begin
          device_task_intf.device_specific_restriction <= device_specific_restriction_d;
          device_task_intf.active_device <= active_device_d;
          device_task_intf.active_task <= active_task_d;
          device_task_intf.parsing_error <= parsing_error_d;
        end
      end : deviceTaskInterfacePopulatorFFs

      always_comb begin : deviceTaskInterfacePopulatorLogic
        active_device_d = device_task_intf.active_device;
        active_task_d = device_task_intf.active_task;
        device_specific_restriction_d = device_task_intf.device_specific_restriction;
        parsing_error_d = device_task_intf.parsing_error;

        // if read and write at the same time, they could belong to different tasks/devices
        // in this case, we propagate read, as it might leak information
        // we also raise a parsing error if this happens
        if (s_axi_arvalid && s_axi_arready) begin

          device_specific_restriction_d = parsed_user_ar.device_interpreted_restriction;
          active_device_d = parsed_user_ar.current_device_id;
          active_task_d = parsed_user_ar.current_task_id;
        end else if (s_axi_awvalid && s_axi_awready) begin

          device_specific_restriction_d = parsed_user_aw.device_interpreted_restriction;
          active_device_d = parsed_user_aw.current_device_id;
          active_task_d = parsed_user_aw.current_task_id;
        end

        if (s_axi_arvalid && s_axi_arready && s_axi_awvalid && s_axi_awready) begin
          parsing_error_d = 1'b1;
        end else begin
          parsing_error_d = 1'b0;
        end
      end : deviceTaskInterfacePopulatorLogic

    end : latchMode
    else begin : passthroughMode

      if (PASSTHROUGH_CHANNEL == 1'b0) begin : ARChanPassthrough
        assign device_task_intf.device_specific_restriction = parsed_user_ar.device_interpreted_restriction;
        assign device_task_intf.active_device = parsed_user_ar.current_device_id;
        assign device_task_intf.active_task = parsed_user_ar.current_task_id;
        assign device_task_intf.parsing_error = 1'b0;
      end : ARChanPassthrough
      else begin : AWChanPassthrough
        assign device_task_intf.device_specific_restriction = parsed_user_aw.device_interpreted_restriction;
        assign device_task_intf.active_device = parsed_user_aw.current_device_id;
        assign device_task_intf.active_task = parsed_user_aw.current_task_id;
        assign device_task_intf.parsing_error = 1'b0;
      end : AWChanPassthrough

    end : passthroughMode

  endgenerate

  `NORTHCAPE_UNREAD(parsed_user_ar.reserved);
  `NORTHCAPE_UNREAD(parsed_user_aw.reserved);

  `NORTHCAPE_UNREAD(device_task_intf.clk_i);

endmodule
