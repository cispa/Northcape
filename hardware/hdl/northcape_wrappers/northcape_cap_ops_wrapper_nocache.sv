import axi5::*;

`include "ariane_xlnx_mapper.svh"
`include "northcape_xilinx_wrapper.vh"

module northcape_cap_ops_wrapper_nocache#(
    // AXI parameters
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_LITE_ADDR_WIDTH = -1,
    parameter AXI_LITE_DATA_WIDTH = -1,
    parameter AXI_LITE_USER_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,

    parameter CAPABILITY_COUNTER_ACTIVE = 1'b1,
    parameter CAPABILITY_ID_WIDTH = -1,

    parameter INITIAL_CMT_BASE=-1,
    parameter INITIAL_CMT_SIZE_CLOG2 = -1,
    parameter WAIT_FOR_MEMORY_READY = 1'b1
)(
    input logic clk_i,
    input logic rst_ni,

    input logic [15:0] active_device,
    input logic [31:0] active_task,
    input logic [63:0] active_device_specific_restriction,
    input logic parsing_error,

    `AXI_LITE_INTERFACE_MODULE_INPUT(S_AXI, logic),
    `AXI_INTERFACE_MODULE_OUTPUT(m_axi_out),

    input logic memory_ready_i,

    // from CMT interface
    output int unsigned cmt_table_size_clog2,
    output wire [AXI_ADDR_WIDTH - 1 : 0] cmt_base,
    output wire cmt_reset_done,
    output wire cmt_need_flush_data_caches,
    output wire cmt_wrote_any_capability,
    output wire [CAPABILITY_ID_WIDTH-1:0] cmt_written_capability,
    output logic interrupt,

    output logic [4:0] debug_state_q,
    output logic debug_is_unlock,
    output logic debug_input_capability_valid,
    output logic [1:0] debug_update_complete,
    output logic [2:0] debug_capabilities_valid,
    output logic debug_is_revoke,
    output logic [AXI_ADDR_WIDTH-1:0] debug_capability_token_o,
    output logic [3:0] debug_capability_operation_o,
    output logic [2:0] zero_segment_debug_state_o,
    output logic [3:0] debug_top_state_o,
    output logic [8:0] debug_zero_len_o
);

import axi5::*;
import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
import northcape_capability_ops_common::NORTHCAPE_CAPABILITY_OPS_RNG_INTERFACE_BITS;
import northcape_capability_ops_common::NORTHCAPE_CAPABILITY_OPS_NUM_IRQS;

`include "northcape_unread.vh"

// interface for manipulating CMT
Axi5#(.AXI_DATA_WIDTH(AXI_DATA_WIDTH), .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_ID_WIDTH(AXI_ID_WIDTH), .AXI_USER_WIDTH(AXI_USER_WIDTH))   axi_out(.clk_i(clk_i),.rst_ni(rst_ni));

Axi5Lite#(.AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH),.AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH)) axi_in(.clk_i(clk_i),.rst_ni(rst_ni));
  
NorthcapeCMTInterface#(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) cmt_interface(.clk_i(clk_i));

assign cmt_table_size_clog2 = cmt_interface.table_size_clog2;
assign cmt_base = cmt_interface.cmt_base;
assign cmt_reset_done = cmt_interface.reset_done;
assign cmt_need_flush_data_caches = cmt_interface.need_flush_data_caches;
assign cmt_wrote_any_capability = cmt_interface.wrote_any_capability;
assign cmt_written_capability = cmt_interface.written_capability;

NorthcapeRNGInterface#(.RNG_DATA_WIDTH(NORTHCAPE_CAPABILITY_OPS_RNG_INTERFACE_BITS)) rng_intf(.clk_i(clk_i),.rst_ni(rst_ni));

NorthcapeInterruptInterface #(
      .NUMBER_INTERRUPT_PINS(NORTHCAPE_CAPABILITY_OPS_NUM_IRQS)
  ) irq_interface (
      .clk_i(clk_i)
  );

assign interrupt = irq_interface.irqs[0];

NorthcapeCurrentDeviceTaskInterface current_device_task_interface(.clk_i(clk_i));

assign current_device_task_interface.active_device=active_device;
assign current_device_task_interface.active_task=active_task;
assign current_device_task_interface.device_specific_restriction=active_device_specific_restriction;
assign current_device_task_interface.parsing_error = parsing_error;

NorthcapeCapabilityCacheInterfaceOps ops_interface (.clk_i(clk_i));

assign ops_interface.response_valid = 1'b0;
assign ops_interface.response_err = 1'b0;
assign ops_interface.response_cmt_entry = '0;
// RNG
northcape_rng#(
.RNG_DATA_WIDTH(NORTHCAPE_CAPABILITY_OPS_RNG_INTERFACE_BITS)
) i_rng(
.intf(rng_intf)
);

northcape_capability_ops#(
    .HASH_TYPE(HASH_TYPE_IDENTITY),

    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),

    .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
    .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),

    .CAPABILITY_COUNTER_ACTIVE(CAPABILITY_COUNTER_ACTIVE),

    .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
    .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2),
    .WAIT_FOR_MEMORY_READY(WAIT_FOR_MEMORY_READY)
  )
  i_northcape_capability_ops (
      .clk_i(clk_i),
      .rst_ni(rst_ni),

      .axi_master(axi_out),
      .axi_slave(axi_in),
      .cache_interface(ops_interface),
      
      .cmt_interface(cmt_interface),

      .rng_interface(rng_intf),

      .current_device_task_interface(current_device_task_interface),
      .irq_out(irq_interface),

      .memory_ready_i(memory_ready_i),

      .debug_state_o(debug_state_q),
      .debug_is_unlock_o(debug_is_unlock),
      .debug_input_capability_valid_o(debug_input_capability_valid),
      .debug_update_complete_o(debug_update_complete),
      .debug_capabilities_valid_o(debug_capabilities_valid),
      .debug_is_revoke_o(debug_is_revoke),
      .debug_capability_token_o(debug_capability_token_o),
      .debug_capability_operation_o(debug_capability_operation_o),
      .zero_segment_debug_state_o(zero_segment_debug_state_o),
      .debug_top_state_o(debug_top_state_o),
      .debug_zero_len_o(debug_zero_len_o)
  );
  

`NORTHCAPE_MAP_XILINX_AXI_INTERFACES_OUT(axi_out,m_axi_out)
`NORTHCAPE_MAP_FROM_XILINX_AXI_LITE_INTERFACE(axi_in,S_AXI)

`NORTHCAPE_UNREAD(S_AXI_AWUSER);
`NORTHCAPE_UNREAD(S_AXI_ARUSER);
endmodule
