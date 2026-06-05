`include "ariane_xlnx_mapper.svh"
module cva6_wrapper_verilog_arty
#(
    parameter AXI_ID_WIDTH=10,
    parameter AXI_ADDR_WIDTH=64,
    parameter AXI_DATA_WIDTH=64,
    parameter AXI_USER_WIDTH=128,
    parameter AXI_CUT_BYPASS=1,
    parameter CAPABILITY_ID_WIDTH = 38,
    
    parameter CSR_REQ_WIDTH=256,
    parameter CSR_RSP_WIDTH=256,

    parameter TDATA_WIDTH=512,
    parameter TID_WIDTH=1,
    parameter TDEST_WIDTH=16,
    parameter TUSER_WIDTH = 1,
    parameter BOOT_ADDR_OVERWRITE = 0
)
(
    // TODO if this port is not named CLK, device tree generation in Vitis fails...
    (*X_INTERFACE_PARAMETER = "FREQ_HZ 25000000"*)
    input wire aclk,
    input wire aresetn,
    (*X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irqs_in INTERRUPT", X_INTERFACE_PARAMETER = "SENSITIVITY EDGE_RISING" *)
    input wire [1 : 0] irqs_in,
    (*X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 ipi_in INTERRUPT", X_INTERFACE_PARAMETER = "SENSITIVITY EDGE_RISING" *)
    input wire ipi_in,
    (*X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 timer_irq_i INTERRUPT", X_INTERFACE_PARAMETER = "SENSITIVITY EDGE_RISING" *)
    input wire timer_irq_i,
    (*X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 debug_req_irq INTERRUPT", X_INTERFACE_PARAMETER = "SENSITIVITY EDGE_RISING" *)
    input wire debug_req_irq,
    

    `AXI_INTERFACE_MODULE_OUTPUT(m_axi_cpu),

    `AXIS_MODULE_OUTPUT(axis_validate_request_instr),
    `AXIS_MODULE_OUTPUT(axis_validate_request_data),
    `AXIS_MODULE_INPUT(axis_validate_response_instr),
    `AXIS_MODULE_INPUT(axis_validate_response_data),
    
    output wire [CSR_REQ_WIDTH-1:0] csr_req_o,
    input wire [CSR_RSP_WIDTH-1:0] csr_rsp_i,

    // to CMT interface
    input wire[31:0] cmt_table_size_clog2,
    input wire [AXI_ADDR_WIDTH - 1 : 0] cmt_base,
    input wire cmt_reset_done,
    input wire cmt_need_flush_data_caches,
    input wire cmt_wrote_any_capability,
    input wire [CAPABILITY_ID_WIDTH-1:0] cmt_written_capability,
    // performance counter events from Northcape cache
    input wire northcape_l2_resolver_miss_i,
    input wire northcape_l2_resolver_spec_fail_i,
    input wire northcape_l2_ops_miss_i,
    input wire northcape_cache_flush_i,
    input wire northcape_cache_missunit_stall_i,
    input wire northcape_ops_write_stall_i
);

cva6_wrapper
#(
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),
    .AXI_CUT_BYPASS(AXI_CUT_BYPASS),
    .CAPABILITY_ID_WIDTH(CAPABILITY_ID_WIDTH),
    .TDATA_WIDTH(TDATA_WIDTH),
    .TID_WIDTH(TID_WIDTH),
    .TDEST_WIDTH(TDEST_WIDTH),
    .TUSER_WIDTH(TUSER_WIDTH),
    .CSR_REQ_WIDTH(CSR_REQ_WIDTH),
    .CSR_RSP_WIDTH(CSR_RSP_WIDTH),
    .BOOT_ADDR_OVERWRITE(BOOT_ADDR_OVERWRITE)
)
i_cva6_wrapper
(
    .aclk(aclk),
    .aresetn(aresetn),
    .irqs_in(irqs_in),
    .ipi_in(ipi_in),
    .timer_irq_i(timer_irq_i),
    .debug_req_irq(debug_req_irq),

    `AXI_INTERFACE_FORWARD(m_axi_cpu),

    `AXIS_INPUT_FORWARD(axis_validate_request_instr),
    `AXIS_INPUT_FORWARD(axis_validate_request_data),

    `AXIS_INPUT_FORWARD(axis_validate_response_instr),
    `AXIS_INPUT_FORWARD(axis_validate_response_data),
    
    .csr_req_o(csr_req_o),
    .csr_rsp_i(csr_rsp_i),

    .cmt_base(cmt_base),
    .cmt_table_size_clog2(cmt_table_size_clog2),
    .cmt_reset_done(cmt_reset_done),
    .cmt_need_flush_data_caches(cmt_need_flush_data_caches),
    .cmt_wrote_any_capability(cmt_wrote_any_capability),
    .cmt_written_capability(cmt_written_capability),
    .northcape_l2_resolver_miss_i(northcape_l2_resolver_miss_i),
    .northcape_l2_resolver_spec_fail_i(northcape_l2_resolver_spec_fail_i),
    .northcape_l2_ops_miss_i(northcape_l2_ops_miss_i),
    .northcape_cache_flush_i(northcape_cache_flush_i),
    .northcape_cache_missunit_stall_i(northcape_cache_missunit_stall_i),
    .northcape_ops_write_stall_i(northcape_ops_write_stall_i)
);

endmodule
