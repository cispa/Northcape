`include "ariane_xlnx_mapper.svh"
`include "northcape_xilinx_wrapper.vh"

module northcape_cap_ops_wrapper_verilog_nocache#(
    // AXI parameters
    parameter AXI_ADDR_WIDTH = 64,
    parameter AXI_LITE_ADDR_WIDTH = 64,
    parameter AXI_LITE_DATA_WIDTH = 64,
    parameter AXI_LITE_USER_WIDTH = 128,
    parameter AXI_DATA_WIDTH = 256,
    parameter AXI_ID_WIDTH = 4,
    parameter AXI_USER_WIDTH = 1,
    parameter CAPABILITY_COUNTER_ACTIVE = 1'b1,
    parameter CAPABILITY_ID_WIDTH = 38,
    parameter INITIAL_CMT_SIZE_CLOG2 = 13,
    parameter WAIT_FOR_MEMORY_READY = 1'b1,
    // is this the ARTY? If so, smaller DRAM!
    parameter IS_ARTY_A7 = 1'b0
)
(
    input wire aclk,
    input wire aresetn,

    input wire [15:0] active_device,
    input wire [31:0] active_task,
    input wire [63:0] active_device_specific_restriction,
    input wire parsing_error,


    `AXI_LITE_INTERFACE_MODULE_INPUT(S_AXI, wire),
    `AXI_INTERFACE_MODULE_OUTPUT(m_axi_out),

    input wire memory_ready_i,

    // from CMT interface
    output wire[31:0] cmt_table_size_clog2,
    output wire [AXI_ADDR_WIDTH - 1 : 0] cmt_base,
    output wire cmt_reset_done,
    output wire cmt_need_flush_data_caches,
    output wire cmt_wrote_any_capability,
    output wire [CAPABILITY_ID_WIDTH-1:0] cmt_written_capability,
    output wire interrupt,

    output wire [4:0] debug_state_q,
    output wire debug_is_unlock,
    output wire debug_input_capability_valid,
    output wire [1:0] debug_update_complete,
    output wire [2:0] debug_capabilities_valid,
    output wire debug_is_revoke,
    output wire [AXI_ADDR_WIDTH-1:0] debug_capability_token_o,
    output wire [3:0] debug_capability_operation_o,
    output wire [2:0] zero_segment_debug_state_o,
    output wire [3:0] debug_top_state_o,
    output wire [8:0] debug_zero_len_o
);
// Arty A7 has smaller Memory
localparam CMT_BASE_GENESYS = 64'hBFFC0000;
localparam CMT_BASE_ARTY_A7 = 64'h8FFC0000;

northcape_cap_ops_wrapper #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),
    .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
    .AXI_LITE_USER_WIDTH(AXI_LITE_USER_WIDTH),
    .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
    .CAPABILITY_ID_WIDTH(CAPABILITY_ID_WIDTH),

    .CAPABILITY_COUNTER_ACTIVE(CAPABILITY_COUNTER_ACTIVE),

    // TODO Vivado does NOT let me override this via parameter
    .INITIAL_CMT_BASE(IS_ARTY_A7 ? CMT_BASE_ARTY_A7 : CMT_BASE_GENESYS),
    .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2),
    .WAIT_FOR_MEMORY_READY(WAIT_FOR_MEMORY_READY)
)
i_northcape_cap_ops_wrapper ( 
    .clk_i(aclk),
    .rst_ni(aresetn),

    .active_device(active_device),
    .active_task(active_task),
    .active_device_specific_restriction(active_device_specific_restriction),
    .parsing_error(parsing_error),

    .memory_ready_i(memory_ready_i),


    `AXI_LITE_INTERFACE_FORWARD(S_AXI),
    `AXI_INTERFACE_FORWARD(m_axi_out),

    .cmt_table_size_clog2(cmt_table_size_clog2),
    .cmt_base(cmt_base),
    .cmt_reset_done(cmt_reset_done),
    .cmt_need_flush_data_caches(cmt_need_flush_data_caches),
    .cmt_wrote_any_capability(cmt_wrote_any_capability),
    .cmt_written_capability(cmt_written_capability),
    .interrupt(interrupt),

    .debug_state_q(debug_state_q),
    .debug_is_unlock(debug_is_unlock),
    .debug_input_capability_valid(debug_input_capability_valid),
    .debug_update_complete(debug_update_complete),
    .debug_capabilities_valid(debug_capabilities_valid),
    .debug_is_revoke(debug_is_revoke),
    .debug_capability_token_o(debug_capability_token_o),
    .debug_capability_operation_o(debug_capability_operation_o),
    .zero_segment_debug_state_o(zero_segment_debug_state_o),
    .debug_top_state_o(debug_top_state_o),
    .debug_zero_len_o(debug_zero_len_o)
 );


endmodule
