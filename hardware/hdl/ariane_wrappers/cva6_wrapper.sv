`include "ariane_xlnx_mapper.svh"
`include "northcape_xilinx_wrapper.vh"

import cva6_config_pkg::*;

module cva6_wrapper
#(
  parameter AXI_ID_WIDTH=10,
  parameter AXI_ADDR_WIDTH=64,
  parameter AXI_DATA_WIDTH=64,
  parameter AXI_USER_WIDTH=128,
  parameter AXI_CUT_BYPASS=1,
  parameter TDATA_WIDTH=-1,
  parameter TID_WIDTH=-1,
  parameter TDEST_WIDTH=-1,
  parameter TUSER_WIDTH = -1,
  parameter CAPABILITY_ID_WIDTH=-1,
  parameter bit MMIO_INTERFACE_SUPPORTED = 1'b1,
  parameter bit CSR_INTERFACE_SUPPORTED  = 1'b1,
  parameter CSR_REQ_WIDTH=256,
  parameter CSR_RSP_WIDTH=256,
  parameter BOOT_ADDR_OVERWRITE = 0
)(
`ifdef USE_POWER_PINS
    inout wire vccd1,
    inout wire vssd1,
`endif
    input logic aclk,
    input logic aresetn,
    input logic [1:0] irqs_in,
    input logic ipi_in,
    input logic timer_irq_i,
    input logic debug_req_irq,
    `AXI_INTERFACE_MODULE_OUTPUT(m_axi_cpu),

    `AXIS_MODULE_OUTPUT(axis_validate_request_instr),
    `AXIS_MODULE_OUTPUT(axis_validate_request_data),
    `AXIS_MODULE_INPUT(axis_validate_response_instr),
    `AXIS_MODULE_INPUT(axis_validate_response_data),

    // to CMT interface
    input int unsigned cmt_table_size_clog2,
    input wire [AXI_ADDR_WIDTH - 1 : 0] cmt_base,
    input wire cmt_reset_done,
    input wire cmt_need_flush_data_caches,
    input wire cmt_wrote_any_capability,
    input wire [CAPABILITY_ID_WIDTH-1:0] cmt_written_capability,
    // performance counter events from Northcape cache
    input logic northcape_l2_resolver_miss_i,
    input logic northcape_l2_resolver_spec_fail_i,
    input logic northcape_l2_ops_miss_i,
    input logic northcape_cache_missunit_stall_i,
    input logic northcape_ops_write_stall_i,
    // cache flush needed?
    input logic northcape_cache_flush_i,
    // remote CSR interface to cap ops
    output logic [CSR_REQ_WIDTH-1:0] csr_req_o,
    input logic [CSR_RSP_WIDTH-1:0] csr_rsp_i
);


`include "cva6_config.svh"

`include "assign.svh"
`include "rvfi_types.svh"
`include "northcape_unread.vh"

localparam CVA6ConfigWtDcacheWbufDepth = 8;  

ariane_axi::req_t    axi_ariane_req, axi_cut_req;
ariane_axi::resp_t   axi_ariane_resp, axi_cut_resp;

AXI_BUS #(
    .AXI_ADDR_WIDTH ( AXI_ADDR_WIDTH          ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH          ),
    .AXI_ID_WIDTH   ( AXI_ID_WIDTH            ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH          )
) tmp_bus (), cpu_bus ();

Axis5#(.AXIS_TDATA_WIDTH(TDATA_WIDTH), .AXIS_TID_WIDTH(TID_WIDTH), .AXIS_TDEST_WIDTH(TDEST_WIDTH), .AXIS_TUSER_WIDTH(TUSER_WIDTH)) axis_validate_request_instr_bus(.clk_i(aclk),.rst_ni(aresetn)), axis_validate_request_data_bus(.clk_i(aclk), .rst_ni(aresetn));
Axis5#(.AXIS_TDATA_WIDTH(TDATA_WIDTH), .AXIS_TID_WIDTH(TID_WIDTH), .AXIS_TDEST_WIDTH(TDEST_WIDTH), .AXIS_TUSER_WIDTH(TUSER_WIDTH)) axis_validate_response_instr_bus(.clk_i(aclk),.rst_ni(aresetn)), axis_validate_response_data_bus(.clk_i(aclk),.rst_ni(aresetn));


import axi_pkg::BURST_FIXED;
import axi_pkg::BURST_INCR;
import axi_pkg::BURST_WRAP;

import axi_pkg::RESP_OKAY;
import axi_pkg::RESP_EXOKAY;
import axi_pkg::RESP_DECERR;
import axi_pkg::RESP_SLVERR;

localparam type rvfi_probes_instr_t = `RVFI_PROBES_INSTR_T(CVA6Cfg);
localparam type rvfi_probes_csr_t = `RVFI_PROBES_CSR_T(CVA6Cfg);
localparam type rvfi_probes_t = struct packed {
  logic csr;
  logic instr;
};

NorthcapeCMTInterface#(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) cmt_interface(.clk_i(aclk));

assign cmt_interface.table_size_clog2 = cmt_table_size_clog2;
assign cmt_interface.cmt_base = cmt_base;
assign cmt_interface.reset_done = cmt_reset_done;
assign cmt_interface.need_flush_data_caches = cmt_need_flush_data_caches;
assign cmt_interface.wrote_any_capability = cmt_wrote_any_capability;
assign cmt_interface.written_capability = cmt_written_capability;



northcape_types::northcape_cap_ops_rcsr_req_t  csr_req;
northcape_types::northcape_cap_ops_rcsr_resp_t csr_rsp;

assign csr_req_o = csr_req;
assign csr_rsp = csr_rsp_i;

ariane #(
    .CVA6Cfg ( CVA6Cfg ),
    .rvfi_probes_instr_t ( rvfi_probes_instr_t ),
    .rvfi_probes_csr_t ( rvfi_probes_csr_t ),
    .rvfi_probes_t ( rvfi_probes_t )
) i_ariane (
`ifdef USE_POWER_PINS
    .vccd1(vccd1),
    .vssd1(vssd1),
`endif
    .clk_i        ( aclk                 ),
    .rst_ni       ( aresetn                ),
    .boot_addr_i  ( BOOT_ADDR_OVERWRITE ? BOOT_ADDR_OVERWRITE : ariane_soc::ROMBase ), // start fetching from ROM
    .hart_id_i    ( '0                  ),
    .irq_i        ( irqs_in                 ),
    .ipi_i        ( ipi_in                 ),
    .time_irq_i   ( timer_irq_i           ),
    .rvfi_probes_o( /* open */          ),
    .debug_req_i  ( debug_req_irq       ),
    .noc_req_o    ( axi_ariane_req      ),
    .noc_resp_i   ( axi_ariane_resp     ),
    .axis_validate_request_instr(axis_validate_request_instr_bus),
    .axis_validate_request_data(axis_validate_request_data_bus),
    .axis_validate_response_instr(axis_validate_response_instr_bus),
    .axis_validate_response_data(axis_validate_response_data_bus),
    .northcape_l2_resolver_miss_i(northcape_l2_resolver_miss_i),
    .northcape_l2_resolver_spec_fail_i(northcape_l2_resolver_spec_fail_i),
    .northcape_l2_ops_miss_i(northcape_l2_ops_miss_i),
    .cmt_interface(cmt_interface),
    .northcape_cache_flush_i(northcape_cache_flush_i),
    .northcape_cache_missunit_stall_i(northcape_cache_missunit_stall_i),
    .northcape_ops_write_stall_i(northcape_ops_write_stall_i),
    .northcape_csr_req_o(csr_req),
    .northcape_csr_rsp_i(csr_rsp)
);

`AXI_ASSIGN_FROM_REQ(cpu_bus,axi_ariane_req)
`AXI_ASSIGN_TO_RESP(axi_ariane_resp,cpu_bus)

`NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(axis_validate_request_instr_bus, axis_validate_request_instr)
`NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(axis_validate_request_data_bus, axis_validate_request_data)

`NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(axis_validate_response_instr_bus, axis_validate_response_instr)
`NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(axis_validate_response_data_bus, axis_validate_response_data)

axi_cut_intf#(
    .ADDR_WIDTH(AXI_ADDR_WIDTH),
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_ID_WIDTH),
    .USER_WIDTH(AXI_USER_WIDTH),
    .BYPASS(AXI_CUT_BYPASS)
) i_axi_cut(
    .clk_i(aclk),
    .rst_ni(aresetn),
    .in(cpu_bus),
    .out(tmp_bus)
);

generate
    if($bits(cmt_written_capability) != $bits(northcape_types::capability_id_t) || CSR_REQ_WIDTH < $bits(northcape_types::northcape_cap_ops_rcsr_req_t) || CSR_RSP_WIDTH < $bits(northcape_types::northcape_cap_ops_rcsr_resp_t))
    begin
        $error("Invalid width!");
    end
endgenerate


`ASSIGN_XLNX_INTERFACE_FROM_ARIANE_STYLE_INPUTS(m_axi_cpu,tmp_bus)

`NORTHCAPE_UNREAD(csr_rsp_i);
endmodule
