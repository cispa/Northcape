// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Florian Zaruba, ETH Zurich
// Date: 19/04/2017
// Description: Memory Management Unit for Ariane, contains TLB and
//              address translation unit. SV39 as defined in RISC-V
//              privilege specification 1.11-WIP


module mmu
  import ariane_pkg::*;
  import northcape_types::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg           = config_pkg::cva6_cfg_empty,
    parameter type                   icache_areq_t     = logic,
    parameter type                   icache_arsp_t     = logic,
    parameter type                   icache_dreq_t     = logic,
    parameter type                   icache_drsp_t     = logic,
    parameter type                   dcache_req_i_t    = logic,
    parameter type                   dcache_req_o_t    = logic,
    parameter type                   exception_t       = logic,
    parameter int unsigned           INSTR_TLB_ENTRIES = 4,
    parameter int unsigned           DATA_TLB_ENTRIES  = 4
) (
    input logic clk_i,
    input logic rst_ni,
    input logic flush_i,
    input logic enable_translation_i,
    input logic en_ld_st_translation_i,  // enable virtual memory translation for load/stores
    // IF interface
    input icache_arsp_t icache_areq_i,
    output icache_areq_t icache_areq_o,
    // MTVEC translation interface - Northcape
    input icache_arsp_t mtvec_areq_i,
    output icache_areq_t mtvec_areq_o,
    // LSU interface
    // this is a more minimalistic interface because the actual addressing logic is handled
    // in the LSU as we distinguish load and stores, what we do here is simple address translation
    input exception_t misaligned_ex_i,
    input logic lsu_req_i,  // request address translation
    input logic [CVA6Cfg.VLEN-1:0] lsu_vaddr_i,  // virtual address in
    input logic lsu_is_store_i,  // the translation is requested by a store
    input logic [$clog2(CVA6Cfg.VLEN/8)-1:0] lsu_size_i,
    input logic lsu_is_irq_i,
    input northcape_types::task_id_t lsu_task_id_i, // task ID that this instruction refers to
    input logic lsu_is_atomic_i,
    input logic lsu_abort_i,
    input logic lsu_is_cbo_i,
    // if we need to walk the page table we can't grant in the same cycle
    // Cycle 0
    output logic                            lsu_dtlb_hit_o,   // sent in the same cycle as the request if translation hits in the DTLB
    output logic [CVA6Cfg.PPNW-1:0] lsu_dtlb_ppn_o,  // ppn (send same cycle as hit)
    output logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] lsu_dtlb_full_index_o,
    output northcape_types::task_id_t              lsu_current_task_o,
    output northcape_types::northcape_device_interpreted_restriction_t lsu_device_restriction_o,
    output logic lsu_is_non_cacheable_o,
    // Cycle 1
    output logic lsu_valid_o,  // translation is valid
    output logic [CVA6Cfg.PLEN-1:0] lsu_paddr_o,  // translated address
    output exception_t lsu_exception_o,  // address translation threw an exception
    // General control signals
    input riscv::priv_lvl_t priv_lvl_i,
    input riscv::priv_lvl_t ld_st_priv_lvl_i,
    input logic sum_i,
    input logic mxr_i,
    // input logic flag_mprv_i,
    input logic [CVA6Cfg.PPNW-1:0] satp_ppn_i,
    input logic [CVA6Cfg.ASID_WIDTH-1:0] asid_i,
    input logic [CVA6Cfg.ASID_WIDTH-1:0] asid_to_be_flushed_i,
    input logic [CVA6Cfg.VLEN-1:0] vaddr_to_be_flushed_i,
    input logic flush_tlb_i,
    // Performance counters
    output logic itlb_miss_o,
    output logic dtlb_miss_o,
    // To count Northcape's instruction MMU misses - PERF_COUNTERS
    output logic northcape_l1_instr_miss_o,
    // To count Northcape's data MMU misses - PERF_COUNTERS
    output logic northcape_l1_data_miss_o,
    // PTW memory interface
    input dcache_req_o_t req_port_i,
    output dcache_req_i_t req_port_o,
    // PMP
    input riscv::pmpcfg_t [15:0] pmpcfg_i,
    input logic [15:0][CVA6Cfg.PLEN-3:0] pmpaddr_i,

    // interface to capability resolver
    Axis5.TRANSMITTER axis_validate_request_instr,
    Axis5.TRANSMITTER axis_validate_request_data,
    Axis5.RECEIVER axis_validate_response_instr,
    Axis5.RECEIVER axis_validate_response_data,

    // cache flush needed?
    input logic northcape_cache_flush_i,

    // current CMT metadata from operations module
    NorthcapeCMTInterface.CONSUMER cmt_interface,

    // TODO remove - debug
    input northcape_types::task_id_t dbg_task_id_frontend,
    input logic dbg_task_id_frontend_valid,
    input northcape_types::task_id_t  dbg_task_id_id,
    input logic dbg_task_id_id_valid,
    input northcape_types::task_id_t dbg_task_id_issue,
    input logic dbg_task_id_issue_valid,

    input logic [CVA6Cfg.XLEN-1:0] dbg_predict_addr,
    input logic [9:0] dbg_predictions,
    input logic dbg_bp_valid,
    input logic [CVA6Cfg.XLEN-1:0] dbg_btb_update_addr,
    input logic dbg_btb_valid,
    input logic dbg_replay,
    input logic dbg_set_pc_commit,
    input northcape_types::task_id_t dbg_replay_task_id,
    // 12 bits
    input logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] dbg_ld_index,
    input logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] dbg_st_index,
    // 52 bits
    input logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0] dbg_ld_tag,
    input logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0] dbg_st_tag,
    input logic dbg_ld_req,
    input logic dbg_st_req,
    input logic dbg_ld_tag_val,
    input logic dbg_st_tag_val,
    input logic [3:0] dbg_state_load_unit_i,
    input logic dbg_page_offset_matches_i,
    input logic dbg_load_unit_gnt,
    input logic [CVA6Cfg.XLEN-1:0] dbg_ld_rdata,
    input logic [CVA6Cfg.XLEN-1:0] dbg_st_wdata,
    input logic dbg_ld_data_valid
);

  localparam type tlb_update_t = struct packed {
    logic                          valid;    // valid flag
    logic                          is_2M;    //
    logic                          is_1G;    //
    logic [27-1:0]                 vpn;      // VPN (39bits) = 27bits + 12bits offset
    logic [CVA6Cfg.ASID_WIDTH-1:0] asid;
    riscv::pte_t                   content;
  };

  logic                    iaccess_err;  // insufficient privilege to access this instruction page
  logic                    daccess_err;  // insufficient privilege to access this data page
  logic                    ptw_active;  // PTW is currently walking a page table
  logic                    walking_instr;  // PTW is walking because of an ITLB miss
  logic                    ptw_error;  // PTW threw an exception
  logic                    ptw_access_exception;  // PTW threw an access exception (PMPs)
  logic [CVA6Cfg.PLEN-1:0] ptw_bad_paddr;  // PTW PMP exception bad physical addr

  logic [CVA6Cfg.VLEN-1:0] update_vaddr;
  tlb_update_t update_ptw_itlb, update_ptw_dtlb;

  logic        itlb_lu_access;
  riscv::pte_t itlb_content;
  logic        itlb_is_2M;
  logic        itlb_is_1G;
  logic        itlb_lu_hit;

  logic        dtlb_lu_access;
  riscv::pte_t dtlb_content;
  logic        dtlb_is_2M;
  logic        dtlb_is_1G;
  logic        dtlb_lu_hit;

  // MMU <-> Northcape
  logic [CVA6Cfg.PLEN-1:0] itlb_address_out, northcape_instr_address_out;
  logic [CVA6Cfg.PLEN-1:0] dtlb_address_out, northcape_data_address_out_q, northcape_data_address_out_n, dtlb_address_out_q;
  logic itlb_translate_complete, northcape_instr_resolve_done, northcape_instr_resolve_error;
  logic dtlb_translate_complete, northcape_data_resolve_done_q, northcape_data_resolve_done_n, northcape_data_resolve_error, northcape_data_resolve_error_q;
  northcape_types::northcape_device_interpreted_restriction_t northcape_instr_device_specific_restriction, northcape_data_device_specific_restriction;
  northcape_types::task_id_t northcape_instr_active_task, northcape_data_active_task, northcape_instr_task_id_q, northcape_instr_task_id_irq_q;
  northcape_types::task_id_t northcape_current_task_id_irq; 
  northcape_types::task_id_t northcape_current_task_id_non_irq;
  northcape_types::task_id_t lsu_task_id_q;
  logic northcape_data_tlb_hit;
  logic northcape_instr_nc_out;
  logic northcape_instr_is_valid_scall;
  logic northcape_instr_is_valid_scall_s;

  logic [$clog2(CVA6Cfg.VLEN/8)-1:0] lsu_size_q, lsu_size_n;
  logic lsu_irq_q, lsu_irq_n;
  logic lsu_atomic_q, lsu_atomic_n;
  logic [CVA6Cfg.PPNW-1:0] dtlb_ppn;
  // indicate that the output address of the MMU does not match the input address
  logic northcape_data_mismatch, northcape_instr_mismatch;

  logic lsu_is_non_cacheable_d, lsu_is_non_cacheable_q;

  logic [2:0] ptw_dbg_state;

  logic northcape_is_subsystem_call;
  // debug signals
  logic dbg_cache_write;
  northcape_physical_address_t dbg_cache_write_phys_addr;
  segment_length_t dbg_cache_write_segment_length;
  logic [2:0] dbg_state;
  northcape_physical_address_t dbg_cache_read_phys_addr;
  segment_length_t dbg_cache_read_segment_length;

  logic cbo_misaligned_d, cbo_misaligned_q;
  logic [CVA6Cfg.VLEN-1:0] previous_instr_addr_q, previous_instr_addr_d;

  northcape_resolve_error_t instr_resolve_err_d, instr_resolve_err_q, data_resolve_err_d, data_resolve_err_q;


  // Assignments
  assign itlb_lu_access = icache_areq_i.fetch_req;
  assign dtlb_lu_access = lsu_req_i;


  tlb #(
      .CVA6Cfg     (CVA6Cfg),
      .tlb_update_t(tlb_update_t),
      .TLB_ENTRIES (INSTR_TLB_ENTRIES)
  ) i_itlb (
      .clk_i  (clk_i),
      .rst_ni (rst_ni),
      .flush_i(flush_tlb_i),

      .update_i(update_ptw_itlb),

      .lu_access_i          (itlb_lu_access),
      .lu_asid_i            (asid_i),
      .asid_to_be_flushed_i (asid_to_be_flushed_i),
      .vaddr_to_be_flushed_i(vaddr_to_be_flushed_i),
      .lu_vaddr_i           (icache_areq_i.fetch_vaddr),
      .lu_content_o         (itlb_content),

      .lu_is_2M_o(itlb_is_2M),
      .lu_is_1G_o(itlb_is_1G),
      .lu_hit_o  (itlb_lu_hit)
  );

  tlb #(
      .CVA6Cfg     (CVA6Cfg),
      .tlb_update_t(tlb_update_t),
      .TLB_ENTRIES (DATA_TLB_ENTRIES)
  ) i_dtlb (
      .clk_i  (clk_i),
      .rst_ni (rst_ni),
      .flush_i(flush_tlb_i),

      .update_i(update_ptw_dtlb),

      .lu_access_i          (dtlb_lu_access),
      .lu_asid_i            (asid_i),
      .asid_to_be_flushed_i (asid_to_be_flushed_i),
      .vaddr_to_be_flushed_i(vaddr_to_be_flushed_i),
      .lu_vaddr_i           (lsu_vaddr_i),
      .lu_content_o         (dtlb_content),

      .lu_is_2M_o(dtlb_is_2M),
      .lu_is_1G_o(dtlb_is_1G),
      .lu_hit_o  (dtlb_lu_hit)
  );


  ptw #(
      .CVA6Cfg   (CVA6Cfg),
      .dcache_req_i_t(dcache_req_i_t),
      .dcache_req_o_t(dcache_req_o_t),
      .tlb_update_t(tlb_update_t)
  ) i_ptw (
      .clk_i                 (clk_i),
      .rst_ni                (rst_ni),
      .ptw_active_o          (ptw_active),
      .walking_instr_o       (walking_instr),
      .ptw_error_o           (ptw_error),
      .ptw_access_exception_o(ptw_access_exception),
      .enable_translation_i  (enable_translation_i),

      .update_vaddr_o(update_vaddr),
      .itlb_update_o (update_ptw_itlb),
      .dtlb_update_o (update_ptw_dtlb),

      .itlb_access_i(itlb_lu_access),
      .itlb_hit_i   (itlb_lu_hit),
      .itlb_vaddr_i (icache_areq_i.fetch_vaddr),
      .itlb_task_i  (northcape_instr_active_task),
      .itlb_device_int_restriction_i(northcape_instr_device_specific_restriction),

      .dtlb_access_i(dtlb_lu_access),
      .dtlb_hit_i   (dtlb_lu_hit),
      .dtlb_vaddr_i (lsu_vaddr_i),
      .dtlb_task_i  (northcape_data_active_task),
      .dtlb_device_int_restriction_i(northcape_data_device_specific_restriction),

      .req_port_i (req_port_i),
      .req_port_o (req_port_o),
      .pmpcfg_i,
      .pmpaddr_i,
      .bad_paddr_o(ptw_bad_paddr),
      .dbg_state_o(ptw_dbg_state),
      .*
  );

  // ila_1 i_ila_1 (
  //     .clk(clk_i), // input wire clk
  //     .probe0({req_port_o.address_tag, req_port_o.address_index}),
  //     .probe1(req_port_o.data_req), // input wire [63:0]  probe1
  //     .probe2(req_port_i.data_gnt), // input wire [0:0]  probe2
  //     .probe3(req_port_i.data_rdata), // input wire [0:0]  probe3
  //     .probe4(req_port_i.data_rvalid), // input wire [0:0]  probe4
  //     .probe5(ptw_error), // input wire [1:0]  probe5
  //     .probe6(update_vaddr), // input wire [0:0]  probe6
  //     .probe7(update_ptw_itlb.valid), // input wire [0:0]  probe7
  //     .probe8(update_ptw_dtlb.valid), // input wire [0:0]  probe8
  //     .probe9(dtlb_lu_access), // input wire [0:0]  probe9
  //     .probe10(lsu_vaddr_i), // input wire [0:0]  probe10
  //     .probe11(dtlb_lu_hit), // input wire [0:0]  probe11
  //     .probe12(itlb_lu_access), // input wire [0:0]  probe12
  //     .probe13(icache_areq_i.fetch_vaddr), // input wire [0:0]  probe13
  //     .probe14(itlb_lu_hit) // input wire [0:0]  probe13
  // );

  //-----------------------
  // Instruction Interface
  //-----------------------
  logic match_any_execute_region;
  logic pmp_instr_allow;

  // The instruction interface is a simple request response interface
  always_comb begin : instr_interface
    // MMU disabled: just pass through
    itlb_translate_complete = icache_areq_i.fetch_req;
    previous_instr_addr_d = previous_instr_addr_q;
    
    if(icache_areq_i.fetch_task_id_overwrite_active)
    begin
      // need to use provided old value immediately in case of 0-cycle resolve
      icache_areq_o.task_id = icache_areq_i.fetch_task_id_overwrite;
    end
    else
    begin
      // always 1 cycle behind, i.e., value that the instruction MMU had before this instruction, i.e., task ID at which this was triggered
      icache_areq_o.task_id = icache_areq_i.fetch_irq ? northcape_instr_task_id_irq_q : northcape_instr_task_id_q;
    end
    icache_areq_o.is_non_cacheable = northcape_instr_nc_out;
    icache_areq_o.northcape_is_valid_scall = northcape_instr_is_valid_scall;
    icache_areq_o.northcape_is_valid_scall_s = northcape_instr_is_valid_scall_s;
    itlb_address_out  = icache_areq_i.fetch_vaddr[CVA6Cfg.PLEN-1:0]; // play through in case we disabled address translation
    // two potential exception sources:
    // 1. HPTW threw an exception -> signal with a page fault exception
    // 2. We got an access error because of insufficient permissions -> throw an access exception
    icache_areq_o.fetch_exception = '0;
    // Check whether we are allowed to access this memory region from a fetch perspective
    iaccess_err   = icache_areq_i.fetch_req && enable_translation_i
                                                 && (((priv_lvl_i == riscv::PRIV_LVL_U) && ~itlb_content.u)
                                                 || ((priv_lvl_i == riscv::PRIV_LVL_S) && itlb_content.u));
    
    icache_areq_o.task_id    = northcape_instr_active_task;
    icache_areq_o.device_interpreted_restriction = northcape_instr_device_specific_restriction;

    // MMU enabled: address from TLB, request delayed until hit. Error when TLB
    // hit and no access right or TLB hit and translated address not valid (e.g.
    // AXI decode error), or when PTW performs walk due to ITLB miss and raises
    // an error.
    if (enable_translation_i) begin
      // we work with SV39 or SV32, so if VM is enabled, check that all bits [CVA6Cfg.VLEN-1:CVA6Cfg.SV-1] are equal
      if (icache_areq_i.fetch_req && !((&icache_areq_i.fetch_vaddr[CVA6Cfg.VLEN-1:CVA6Cfg.SV-1]) == 1'b1 || (|icache_areq_i.fetch_vaddr[CVA6Cfg.VLEN-1:CVA6Cfg.SV-1]) == 1'b0)) begin
        icache_areq_o.fetch_exception.cause = riscv::INSTR_ACCESS_FAULT;
        icache_areq_o.fetch_exception.valid = 1'b1;
        if (CVA6Cfg.TvalEn)
          icache_areq_o.fetch_exception.tval = {
            {CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, icache_areq_i.fetch_vaddr
          };
      end

      itlb_translate_complete = 1'b0;

      // 4K page
      itlb_address_out = {itlb_content.ppn, icache_areq_i.fetch_vaddr[11:0]};
      // Mega page
      if (itlb_is_2M) begin
        itlb_address_out[20:12] = icache_areq_i.fetch_vaddr[20:12];
      end
      // Giga page
      if (itlb_is_1G) begin
        itlb_address_out[29:12] = icache_areq_i.fetch_vaddr[29:12];
      end

      // ---------
      // ITLB Hit
      // --------
      // if we hit the ITLB output the request signal immediately
      if (itlb_lu_hit) begin
        itlb_translate_complete = icache_areq_i.fetch_req;
        // we got an access error
        if (iaccess_err) begin
          // throw a page fault
          icache_areq_o.fetch_exception.cause = riscv::INSTR_PAGE_FAULT;
          icache_areq_o.fetch_exception.valid = 1'b1;
          if (CVA6Cfg.TvalEn)
            icache_areq_o.fetch_exception.tval = {
              {CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, icache_areq_i.fetch_vaddr
            };
        end else if (!pmp_instr_allow) begin
          icache_areq_o.fetch_exception.cause = riscv::INSTR_ACCESS_FAULT;
          icache_areq_o.fetch_exception.valid = 1'b1;
          if (CVA6Cfg.TvalEn)
            icache_areq_o.fetch_exception.tval = {
              {CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, icache_areq_i.fetch_vaddr
            };
        end
      end else
      // ---------
      // ITLB Miss
      // ---------
      // watch out for exceptions happening during walking the page table
      if (ptw_active && walking_instr) begin
        itlb_translate_complete = ptw_error | ptw_access_exception;
        if (ptw_error) begin
          icache_areq_o.fetch_exception.cause = riscv::INSTR_PAGE_FAULT;
          icache_areq_o.fetch_exception.valid = 1'b1;
          if (CVA6Cfg.TvalEn)
            icache_areq_o.fetch_exception.tval = {
              {CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, update_vaddr
            };
        end else begin
          icache_areq_o.fetch_exception.cause = riscv::INSTR_ACCESS_FAULT;
          icache_areq_o.fetch_exception.valid = 1'b1;
          if (CVA6Cfg.TvalEn)
            icache_areq_o.fetch_exception.tval = {
              {CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, update_vaddr
            };
        end
      end
    end
    else
    begin
      // skip MMU and talk to Northcape immediately
      itlb_translate_complete = icache_areq_i.fetch_req;
    end
    if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED && cmt_interface.reset_done)
    begin
      icache_areq_o.fetch_valid = icache_areq_i.fetch_req & northcape_instr_resolve_done;
      icache_areq_o.fetch_paddr = northcape_instr_address_out;
      if(northcape_instr_resolve_error)
      begin
        icache_areq_o.fetch_exception.cause = riscv::NORTHCAPE_BASE + instr_resolve_err_q;
        icache_areq_o.fetch_exception.valid = 1'b1;
        if (CVA6Cfg.TvalEn)
          /* provide PREVIOUS instruction address, i.e., where we jumped FROM - easier to debug */
          icache_areq_o.fetch_exception.tval = {
            {CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, previous_instr_addr_q
          };
      end
      else if(icache_areq_o.fetch_valid)
      begin
        previous_instr_addr_d = icache_areq_i.fetch_vaddr;
      end
    end
    else
    begin
      icache_areq_o.fetch_valid = itlb_translate_complete;
      icache_areq_o.fetch_paddr = itlb_address_out;
    end
    // if it didn't match any execute region throw an `Instruction Access Fault`
    // or: if we are not translating, check PMPs immediately on the paddr
    if ((!match_any_execute_region && !ptw_error && !(CVA6Cfg.NORTHCAPE_STAGE_ENABLED && cmt_interface.reset_done)) || (!enable_translation_i && !pmp_instr_allow && !(CVA6Cfg.NORTHCAPE_STAGE_ENABLED && cmt_interface.reset_done))) begin
      icache_areq_o.fetch_exception.cause = riscv::INSTR_ACCESS_FAULT;
      icache_areq_o.fetch_exception.valid = 1'b1;
      if (CVA6Cfg.TvalEn)
        icache_areq_o.fetch_exception.tval = {
          {CVA6Cfg.XLEN - CVA6Cfg.PLEN{1'b0}}, icache_areq_o.fetch_paddr
        };
    end
  end

  // check for execute flag on memory
  assign match_any_execute_region = config_pkg::is_inside_execute_regions(
      CVA6Cfg, {{64 - CVA6Cfg.PLEN{1'b0}}, itlb_address_out}
  );

  // assume non-compressed instruction
  localparam bit [2:0] NORTHCAPE_INSTRUCTION_SIZE_BYTES_CLOG2=2;

  // Northcape instruction MMU
  generate
    if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED)
    begin: gen_instr_nc_mmu
      localparam logic [CVA6Cfg.XLEN-1:0] expected_mtvec_table_size = 256;

      logic aux_fetch_err;

      always_comb begin: auxExceptionLogic
        mtvec_areq_o.fetch_exception = '0;

        if(aux_fetch_err)
        begin
          mtvec_areq_o.fetch_exception.valid = 1'b1;
          mtvec_areq_o.fetch_exception.cause = riscv::INSTR_ACCESS_FAULT;
          mtvec_areq_o.fetch_exception.tval  = mtvec_areq_i.fetch_vaddr;
        end
      end: auxExceptionLogic

      northcape_cva6_mmu
      #(
        .IS_EXECUTE(1'b1),
        .DEVICE_ID(CVA6Cfg.NORTHCAPE_MMU_INSTR_DEVICE_ID),
        .CAN_HANDLE_MISPREDICT(1'b0),
        .HAS_CACHE(CVA6Cfg.NORTHCAPE_MMU_ICACHE_SIZE != 0),
        .CACHE_SIZE(CVA6Cfg.NORTHCAPE_MMU_ICACHE_SIZE),
        .CACHE_IS_FULLY_ASSOCIATIVE(CVA6Cfg.NORTHCAPE_MMU_CACHE_FULL_ASSOC),
        .CBO_CACHELINE_WIDTH(CVA6Cfg.DCACHE_LINE_WIDTH)
      ) i_instr_nc_mmu(
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .data_address_i(icache_areq_i.fetch_vaddr),
        //on instruction side, never store
        .data_is_store_i(1'b0),
        .data_access_size_i(NORTHCAPE_INSTRUCTION_SIZE_BYTES_CLOG2),
        // only applicable for LSU
        .data_is_immediate_i(1'b0),
        .data_is_atomic_i(1'b0),
        .data_is_irq_i(icache_areq_i.fetch_irq),
        .data_is_valid_i(icache_areq_i.fetch_req),
        .data_is_branch_predict_i(1'b0),
        .data_is_mispredict_i(1'b0),
        .data_abort_i(1'b0),
        .data_is_correct_predict_i(1'b0),
        .task_id_overwrite_active_i(icache_areq_i.fetch_task_id_overwrite_active),
        .task_id_overwrite_i(icache_areq_i.fetch_task_id_overwrite),
        
        .translated_address_o(northcape_instr_address_out),
        .translation_error_o(northcape_instr_resolve_error),
        .translation_valid_o(northcape_instr_resolve_done),
        .translation_immediate_o(/* not needed */),
        .translation_requires_non_cacheable_o(northcape_instr_nc_out),
        .translation_is_subsystem_call_o(northcape_is_subsystem_call),
        .translation_is_subsystem_call_self_o(northcape_instr_is_valid_scall_s),
        .translation_cache_miss_event_o(northcape_l1_instr_miss_o),
        .translation_cbo_misaligned_o(/* not needed */),

        .current_task_id_irq_i('0),
        .current_task_id_non_irq_i('0),
        .is_subsystem_call_i(1'b0),

        // aux interface - mtvec
        .aux_addr_i(mtvec_areq_i.fetch_vaddr),
        .aux_expected_length_i(expected_mtvec_table_size),
        .aux_access_length_i(CVA6Cfg.XLEN / 8),
        .aux_access_type_i(READ_IRQ),
        .aux_check_task_id_i(NORTHCAPE_LOADER_TASK_TASK_ID),
        .aux_addr_valid_i(mtvec_areq_i.fetch_req),

        .aux_translated_addr_valid_o(mtvec_areq_o.fetch_valid),
        .aux_translated_addr_o(mtvec_areq_o.fetch_paddr),
        .aux_translated_addr_err_o(aux_fetch_err),

        .current_task_id_irq_o(northcape_current_task_id_irq),
        .current_task_id_non_irq_o(northcape_current_task_id_non_irq),
        .translation_device_specific_restriction_o(northcape_instr_device_specific_restriction),

        .axis_validate_request(axis_validate_request_instr),
        .axis_validate_response(axis_validate_response_instr),
        .cmt_interface(cmt_interface),
        .northcape_cache_flush_i(northcape_cache_flush_i),

        .final_error_o(instr_resolve_err_d),

        .dbg_cache_write_o(dbg_cache_write),
        .dbg_cache_write_phys_addr_o(dbg_cache_write_phys_addr),
        .dbg_cache_write_segment_length_o(dbg_cache_write_segment_length),
        .dbg_state_o(dbg_state),
        .dbg_cache_read_phys_addr_o(dbg_cache_read_phys_addr),
        .dbg_cache_read_segment_length_o(dbg_cache_read_segment_length)
      );
      assign northcape_instr_active_task = icache_areq_i.fetch_irq ? northcape_current_task_id_irq : northcape_current_task_id_non_irq;
      assign northcape_instr_mismatch = (northcape_instr_address_out != itlb_address_out);
      // subsystem call that CHANGES the task ID
      assign northcape_instr_is_valid_scall = northcape_is_subsystem_call;
    end: gen_instr_nc_mmu
    else
    begin: skip_instr_nc_mmu
      assign northcape_instr_address_out = itlb_address_out;
      assign northcape_instr_resolve_done = itlb_translate_complete;
      assign northcape_instr_resolve_error = 1'b0;
      assign northcape_instr_active_task = '0;
    end: skip_instr_nc_mmu

  endgenerate

  // Instruction fetch
  pmp #(
      .CVA6Cfg   (CVA6Cfg),
      .PLEN      (CVA6Cfg.PLEN),
      .PMP_LEN   (CVA6Cfg.PLEN - 2),
      .NR_ENTRIES(CVA6Cfg.NrPMPEntries)
  ) i_pmp_if (
      .addr_i       (itlb_address_out),
      .priv_lvl_i,
      // we will always execute on the instruction fetch port
      .access_type_i(riscv::ACCESS_EXEC),
      // Configuration
      .conf_addr_i  (pmpaddr_i),
      .conf_i       (pmpcfg_i),
      .allow_o      (pmp_instr_allow)
  );

  //-----------------------
  // Data Interface
  //-----------------------
  logic [CVA6Cfg.VLEN-1:0] lsu_vaddr_n, lsu_vaddr_q;
  riscv::pte_t dtlb_pte_n, dtlb_pte_q;
  exception_t misaligned_ex_n, misaligned_ex_q;
  logic lsu_req_n, lsu_req_q;
  logic lsu_is_store_n, lsu_is_store_q;
  logic dtlb_hit_n, dtlb_hit_q;
  logic dtlb_is_2M_n, dtlb_is_2M_q;
  logic dtlb_is_1G_n, dtlb_is_1G_q;

  // check if we need to do translation or if we are always ready (e.g.: we are not translating anything)
  assign  northcape_data_tlb_hit = (en_ld_st_translation_i) ? dtlb_hit_n : 1'b1;

  localparam int CACHE_INDEX_START = $clog2(CVA6Cfg.DCACHE_LINE_WIDTH / 8);

  // Wires to PMP checks
  riscv::pmp_access_t pmp_access_type;
  logic               pmp_data_allow;
  localparam PPNWMin = (CVA6Cfg.PPNW - 1 > 29) ? 29 : CVA6Cfg.PPNW - 1;
  int northcape_decoded_size, northcape_decoded_size_mask;
  // The data interface is simpler and only consists of a request/response interface
  always_comb begin : data_interface
    // save request and DTLB response
    lsu_vaddr_n = lsu_vaddr_i;
    lsu_req_n = lsu_req_i;
    lsu_size_n = lsu_req_i ? lsu_size_i : lsu_size_q;
    lsu_irq_n = lsu_req_i ? lsu_is_irq_i : lsu_irq_q;
    lsu_atomic_n = lsu_req_i ? lsu_is_atomic_i : lsu_atomic_q;
    misaligned_ex_n = misaligned_ex_i;
    dtlb_pte_n = dtlb_content;
    dtlb_hit_n = dtlb_lu_hit;
    lsu_is_store_n = lsu_is_store_i;
    dtlb_is_2M_n = dtlb_is_2M;
    dtlb_is_1G_n = dtlb_is_1G;

    dtlb_address_out = lsu_vaddr_q[CVA6Cfg.PLEN-1:0];
    dtlb_ppn = lsu_vaddr_n[CVA6Cfg.PLEN-1:12];
    dtlb_translate_complete = lsu_req_i;
    lsu_exception_o = misaligned_ex_q;
    pmp_access_type = lsu_is_store_q ? riscv::ACCESS_WRITE : riscv::ACCESS_READ;

    lsu_valid_o = lsu_req_q;

    if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED && cmt_interface.reset_done)
    begin
      lsu_valid_o = northcape_data_resolve_done_q;
    end

    // mute misaligned exceptions if there is no request otherwise they will throw accidental exceptions
    misaligned_ex_n.valid = misaligned_ex_i.valid & lsu_req_i;

    // Check if the User flag is set, then we may only access it in supervisor mode
    // if SUM is enabled
    daccess_err = en_ld_st_translation_i && ((ld_st_priv_lvl_i == riscv::PRIV_LVL_S && !sum_i && dtlb_pte_q.u) || // SUM is not set and we are trying to access a user page in supervisor mode
    (ld_st_priv_lvl_i == riscv::PRIV_LVL_U && !dtlb_pte_q.u));            // this is not a user page but we are in user mode and trying to access it
    // translation is enabled and no misaligned exception occurred
    if (en_ld_st_translation_i && !misaligned_ex_q.valid) begin
      lsu_valid_o = 1'b0;
      dtlb_translate_complete = 1'b0;
      
      
      // cycle 1 data - registers are current, new data might be from different transaction already
      dtlb_address_out = {dtlb_pte_q.ppn, lsu_vaddr_q[11:0]};
      dtlb_ppn = dtlb_content.ppn;
      // Mega page
      if (dtlb_is_2M_q) begin
        dtlb_address_out[20:12] = lsu_vaddr_q[20:12];
        dtlb_ppn[20:12] = lsu_vaddr_n[20:12];
      end
      // Giga page
      if (dtlb_is_1G_q) begin
        dtlb_address_out[PPNWMin:12] = lsu_vaddr_q[PPNWMin:12];
        dtlb_ppn[PPNWMin:12] = lsu_vaddr_n[PPNWMin:12];
      end

      // ---------
      // DTLB Hit
      // --------
      if (dtlb_hit_q && lsu_req_q) begin
        lsu_valid_o = 1'b1;
        // exception priority:
        // PAGE_FAULTS have higher priority than ACCESS_FAULTS
        // virtual memory based exceptions are PAGE_FAULTS
        // physical memory based exceptions are ACCESS_FAULTS (PMA/PMP)

        // this is a store
        if (lsu_is_store_q) begin
          // check if the page is write-able and we are not violating privileges
          // also check if the dirty flag is set
          if (!dtlb_pte_q.w || daccess_err || !dtlb_pte_q.d) begin
            lsu_exception_o.cause = riscv::STORE_PAGE_FAULT;
            lsu_exception_o.valid = 1'b1;
            if (CVA6Cfg.TvalEn)
              lsu_exception_o.tval = {
                {CVA6Cfg.XLEN - CVA6Cfg.VLEN{lsu_vaddr_q[CVA6Cfg.VLEN-1]}}, lsu_vaddr_q
              };
            // Check if any PMPs are violated
          end else if (!(CVA6Cfg.NORTHCAPE_STAGE_ENABLED && cmt_interface.reset_done) && !pmp_data_allow) begin
            lsu_exception_o.cause = riscv::ST_ACCESS_FAULT;
            lsu_exception_o.valid = 1'b1;
            if (CVA6Cfg.TvalEn)
              lsu_exception_o.tval = {
                {CVA6Cfg.XLEN - CVA6Cfg.VLEN{lsu_vaddr_q[CVA6Cfg.VLEN-1]}}, lsu_vaddr_q
              };
          end

          // this is a load
        end else begin
          // check for sufficient access privileges - throw a page fault if necessary
          if (daccess_err) begin
            lsu_exception_o.cause = riscv::LOAD_PAGE_FAULT;
            lsu_exception_o.valid = 1'b1;
            if (CVA6Cfg.TvalEn)
              lsu_exception_o.tval = {
                {CVA6Cfg.XLEN - CVA6Cfg.VLEN{lsu_vaddr_q[CVA6Cfg.VLEN-1]}}, lsu_vaddr_q
              };
            // Check if any PMPs are violated
          end else if (!(CVA6Cfg.NORTHCAPE_STAGE_ENABLED && cmt_interface.reset_done) && !pmp_data_allow) begin
            lsu_exception_o.cause = riscv::LD_ACCESS_FAULT;
            lsu_exception_o.valid = 1'b1;
            if (CVA6Cfg.TvalEn)
              lsu_exception_o.tval = {
                {CVA6Cfg.XLEN - CVA6Cfg.VLEN{lsu_vaddr_q[CVA6Cfg.VLEN-1]}}, lsu_vaddr_q
              };
          end
        end
      end else

      // ---------
      // DTLB Miss
      // ---------
      // watch out for exceptions
      if (ptw_active && !walking_instr) begin
        // page table walker threw an exception
        if (ptw_error) begin
          // an error makes the translation valid
          lsu_valid_o = 1'b1;
          // the page table walker can only throw page faults
          if (lsu_is_store_q) begin
            lsu_exception_o.cause = riscv::STORE_PAGE_FAULT;
            lsu_exception_o.valid = 1'b1;
            if (CVA6Cfg.TvalEn)
              lsu_exception_o.tval = {
                {CVA6Cfg.XLEN - CVA6Cfg.VLEN{lsu_vaddr_q[CVA6Cfg.VLEN-1]}}, update_vaddr
              };
          end else begin
            lsu_exception_o.cause = riscv::LOAD_PAGE_FAULT;
            lsu_exception_o.valid = 1'b1;
            if (CVA6Cfg.TvalEn)
              lsu_exception_o.tval = {
                {CVA6Cfg.XLEN - CVA6Cfg.VLEN{lsu_vaddr_q[CVA6Cfg.VLEN-1]}}, update_vaddr
              };
          end
        end

        if (ptw_access_exception) begin
          // an error makes the translation valid
          lsu_valid_o = 1'b1;
          // Any fault of the page table walk should be based of the original access type
          if (lsu_is_store_q) begin
            lsu_exception_o.cause = riscv::ST_ACCESS_FAULT;
            lsu_exception_o.valid = 1'b1;
            if (CVA6Cfg.TvalEn)
              lsu_exception_o.tval = {{CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, lsu_vaddr_n};
          end else begin
            lsu_exception_o.cause = riscv::LD_ACCESS_FAULT;
            lsu_exception_o.valid = 1'b1;
            if (CVA6Cfg.TvalEn)
              lsu_exception_o.tval = {{CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, lsu_vaddr_n};
          end
        end
      end
    end  // If translation is not enabled, check the paddr immediately against PMPs
    else if (!(CVA6Cfg.NORTHCAPE_STAGE_ENABLED && cmt_interface.reset_done) && lsu_req_q && !misaligned_ex_q.valid && !pmp_data_allow) begin
      if (lsu_is_store_q) begin
        lsu_exception_o.cause = riscv::ST_ACCESS_FAULT;
        lsu_exception_o.valid = 1'b1;
        if (CVA6Cfg.TvalEn)
          lsu_exception_o.tval = {{CVA6Cfg.XLEN - CVA6Cfg.PLEN{1'b0}}, lsu_paddr_o};
      end else begin
        lsu_exception_o.cause = riscv::LD_ACCESS_FAULT;
        lsu_exception_o.valid = 1'b1;
        if (CVA6Cfg.TvalEn)
          lsu_exception_o.tval = {{CVA6Cfg.XLEN - CVA6Cfg.PLEN{1'b0}}, lsu_paddr_o};
      end
    end

    northcape_decoded_size = 1<<lsu_size_q;
    northcape_decoded_size_mask = northcape_decoded_size-1;
    // exceptions are generated one cycle AFTER the hit signal was sent (together with the tag)
    if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED && cmt_interface.reset_done && northcape_data_resolve_error_q)
    begin
      lsu_exception_o.cause = riscv::NORTHCAPE_BASE + data_resolve_err_q;
      lsu_exception_o.valid = 1'b1;
      if (CVA6Cfg.TvalEn)
        lsu_exception_o.tval = {
          {CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, lsu_vaddr_q
        };
    end
    // check at the first output cycle where data is available, but the request is still up - input address might otherwise change
    else if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED && cmt_interface.reset_done && northcape_data_resolve_done_q && northcape_decoded_size != 32'd1 && (northcape_data_address_out_q & northcape_decoded_size_mask) != (lsu_vaddr_q & northcape_decoded_size_mask))
    begin
      lsu_exception_o.cause = lsu_is_store_q ? riscv::ST_ADDR_MISALIGNED : riscv::LD_ADDR_MISALIGNED;
      lsu_exception_o.valid = 1'b1;
      if (CVA6Cfg.TvalEn)
        // we provide the "physical" address here, to make clear(er) what is happening
        lsu_exception_o.tval = {
          {CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, northcape_data_address_out_q
        };
    end
    else if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED && cmt_interface.reset_done && northcape_data_resolve_done_q && lsu_is_cbo_i && cbo_misaligned_q)
    begin
      // overlaps into different cache line --> misaligned
      lsu_exception_o.cause = riscv::ST_ADDR_MISALIGNED;
      lsu_exception_o.valid = 1'b1;
      if (CVA6Cfg.TvalEn)
        // we provide the "physical" address here, to make clear(er) what is happening
        lsu_exception_o.tval = {
          {CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, northcape_data_address_out_q
        };
    end
  end

  // Load/store PMP check
  pmp #(
      .CVA6Cfg   (CVA6Cfg),
      .PLEN      (CVA6Cfg.PLEN),
      .PMP_LEN   (CVA6Cfg.PLEN - 2),
      .NR_ENTRIES(CVA6Cfg.NrPMPEntries)
  ) i_pmp_data (
      .addr_i       (dtlb_address_out),
      .priv_lvl_i   (ld_st_priv_lvl_i),
      .access_type_i(pmp_access_type),
      // Configuration
      .conf_addr_i  (pmpaddr_i),
      .conf_i       (pmpcfg_i),
      .allow_o      (pmp_data_allow)
  );

    // Northcape data MMU
  generate
    if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED)
    begin: gen_data_nc_mmu
      logic northcape_lsu_hit;
      northcape_cva6_mmu
      #(
        .IS_EXECUTE(1'b0),
        .DEVICE_ID(CVA6Cfg.NORTHCAPE_MMU_DATA_DEVICE_ID),
        .CAN_HANDLE_MISPREDICT(1'b0),
        .HAS_CACHE(CVA6Cfg.NORTHCAPE_MMU_DCACHE_SIZE != 0),
        .CACHE_SIZE(CVA6Cfg.NORTHCAPE_MMU_DCACHE_SIZE),
        .CACHE_IS_FULLY_ASSOCIATIVE(CVA6Cfg.NORTHCAPE_MMU_CACHE_FULL_ASSOC),
        .CBO_CACHELINE_WIDTH(CVA6Cfg.DCACHE_LINE_WIDTH)
      ) i_data_nc_mmu(
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .data_address_i(lsu_vaddr_n[CVA6Cfg.PLEN-1:0]),
        .data_is_store_i(lsu_is_store_n),
        .data_access_size_i(lsu_size_n),
        .data_is_immediate_i(1'b1),
        .data_is_atomic_i(lsu_atomic_n),
        .data_is_irq_i(lsu_irq_n),
        .data_is_valid_i(lsu_req_i),
        // ignored - only for instruction part
        .data_is_branch_predict_i(1'b0),
        .data_is_mispredict_i(1'b0),
        .data_abort_i(lsu_abort_i),
        .data_is_correct_predict_i(1'b0),
        .task_id_overwrite_active_i(1'b0),
        .task_id_overwrite_i('0),
        
        .translated_address_o(northcape_data_address_out_n),
        .translation_error_o(northcape_data_resolve_error),
        .translation_valid_o(northcape_data_resolve_done_n),
        .translation_immediate_o(northcape_lsu_hit),
        .translation_requires_non_cacheable_o(lsu_is_non_cacheable_d),
        .translation_device_specific_restriction_o(northcape_data_device_specific_restriction),
        .translation_is_subsystem_call_o(/* open */),
        .translation_is_subsystem_call_self_o(/* open */),
        .translation_cache_miss_event_o(northcape_l1_data_miss_o),
        .translation_cbo_misaligned_o(cbo_misaligned_d),

        .current_task_id_irq_i(lsu_task_id_i), // appropriately picked by instruction side for this instruction
        .current_task_id_non_irq_i(lsu_task_id_i), // appropriately picked by instruction side for this instruction
        .is_subsystem_call_i(northcape_is_subsystem_call),
        
        .current_task_id_irq_o(/* not needed */),
        .current_task_id_non_irq_o(/* not needed */),

        // aux interface - unused
        .aux_addr_i('0),
        .aux_expected_length_i('0),
        .aux_access_length_i('0),
        .aux_access_type_i(ACCESS_NONE),
        .aux_check_task_id_i('0),
        .aux_addr_valid_i(1'b0),

        .aux_translated_addr_o(),
        .aux_translated_addr_valid_o(),
        .aux_translated_addr_err_o(),

        .final_error_o(data_resolve_err_d),

        .axis_validate_request(axis_validate_request_data),
        .axis_validate_response(axis_validate_response_data),
        .cmt_interface(cmt_interface),
        .northcape_cache_flush_i(northcape_cache_flush_i),
        // currently unused
        .dbg_cache_write_o(),
        .dbg_cache_write_phys_addr_o(),
        .dbg_cache_write_segment_length_o(),
        .dbg_state_o(),
        .dbg_cache_read_phys_addr_o(),
        .dbg_cache_read_segment_length_o()
      );
      assign lsu_dtlb_hit_o = cmt_interface.reset_done ? northcape_lsu_hit : northcape_data_tlb_hit;
      // always computed from the physical address...
      assign lsu_dtlb_ppn_o = cmt_interface.reset_done ? northcape_data_address_out_n[CVA6Cfg.PLEN-1:12] : dtlb_ppn;
      // needs to be maintained for at least one more cycle
      assign lsu_dtlb_full_index_o = cmt_interface.reset_done ? (northcape_data_resolve_done_n ? northcape_data_address_out_n[CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] : northcape_data_address_out_q[CVA6Cfg.DCACHE_INDEX_WIDTH-1:0]) : (northcape_data_tlb_hit ? lsu_vaddr_n[CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] : lsu_vaddr_q[CVA6Cfg.DCACHE_INDEX_WIDTH-1:0]);
      // for load/store translation, we have an additional 1-cycle latency...
      assign lsu_paddr_o = cmt_interface.reset_done ? northcape_data_address_out_q : dtlb_address_out;
      // only valid for one cycle - need to hold it for the LSU after that
      assign northcape_data_active_task                              = dtlb_translate_complete ? lsu_task_id_i : lsu_task_id_q;
      // needs to be maintained across two cycles
      assign lsu_current_task_o = dtlb_translate_complete ? lsu_task_id_i : lsu_task_id_q;
      assign lsu_device_restriction_o = northcape_data_device_specific_restriction;

      assign northcape_data_mismatch = (northcape_data_address_out_n != dtlb_address_out);
      
      // "cycle 1" data - considered when the tag is available
      assign lsu_is_non_cacheable_o = lsu_is_non_cacheable_q;
    end: gen_data_nc_mmu
    else
    begin: skip_data_nc_mmu
      assign northcape_data_address_out_n = dtlb_address_out;
      assign northcape_data_resolve_done_n = dtlb_translate_complete;
      assign lsu_dtlb_full_index_o = dtlb_address_out[CVA6Cfg.DCACHE_INDEX_WIDTH-1:0];
      assign northcape_data_resolve_error = 1'b0;
      assign lsu_dtlb_hit_o = northcape_data_tlb_hit;
      assign lsu_dtlb_ppn_o = dtlb_ppn;
      assign lsu_paddr_o = northcape_data_address_out_n[CVA6Cfg.PLEN-1:0];

      assign northcape_data_active_task = '0;
      assign lsu_current_task_o = '0;
      assign lsu_device_restriction_o = '0;
      assign lsu_is_non_cacheable_o = 1'b0;
    end: skip_data_nc_mmu

  endgenerate

  // ----------
  // Registers
  // ----------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      lsu_vaddr_q     <= '0;
      lsu_req_q       <= '0;
      misaligned_ex_q <= '0;
      dtlb_pte_q      <= '0;
      dtlb_hit_q      <= '0;
      lsu_is_store_q  <= '0;
      dtlb_is_2M_q    <= '0;
      dtlb_is_1G_q    <= '0;
      if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED)
      begin
        lsu_size_q    <= '0;
        lsu_irq_q     <= 1'b0;
        lsu_atomic_q  <= 1'b0;
        northcape_instr_task_id_q <= '0;
        northcape_instr_task_id_irq_q <= '0;
        lsu_task_id_q <= '0;
        dtlb_address_out_q <= '0;
        northcape_data_resolve_error_q <= 1'b0;
        northcape_data_resolve_done_q <= 1'b0;
        northcape_data_address_out_q  <= '0;
        lsu_is_non_cacheable_q <= lsu_is_non_cacheable_d;
        cbo_misaligned_q <= 1'b0;
        previous_instr_addr_q <= '0;
        data_resolve_err_q <= NORTHCAPE_RESOLVE_NO_ERROR;
        instr_resolve_err_q <= NORTHCAPE_RESOLVE_NO_ERROR;
      end
    end else begin
      lsu_vaddr_q     <= lsu_vaddr_n;
      lsu_req_q       <= lsu_req_n;
      misaligned_ex_q <= misaligned_ex_n;
      dtlb_pte_q      <= dtlb_pte_n;
      dtlb_hit_q      <= dtlb_hit_n;
      lsu_is_store_q  <= lsu_is_store_n;
      dtlb_is_2M_q    <= dtlb_is_2M_n;
      dtlb_is_1G_q    <= dtlb_is_1G_n;
      if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED)
      begin
        lsu_size_q    <= lsu_size_n;
        lsu_irq_q     <= lsu_irq_n;
        lsu_atomic_q  <= lsu_atomic_n;
        northcape_instr_task_id_q <= northcape_current_task_id_non_irq;
        northcape_instr_task_id_irq_q <= northcape_current_task_id_irq;
        lsu_task_id_q <= lsu_current_task_o;
        dtlb_address_out_q <= dtlb_address_out;
        northcape_data_resolve_error_q <= northcape_data_resolve_error;
        northcape_data_resolve_done_q <= northcape_data_resolve_done_n;
        northcape_data_address_out_q  <= northcape_data_address_out_n;
        cbo_misaligned_q <= cbo_misaligned_d;
        previous_instr_addr_q <= previous_instr_addr_d;
        data_resolve_err_q <= data_resolve_err_d;
        instr_resolve_err_q <= instr_resolve_err_d;
      end
    end
  end

`ifdef CVA6_DEBUG
  northcape_cva6_ila ila(
    .clk(clk_i),
    .probe0(icache_areq_i.fetch_vaddr), // 64 bits
    .probe1(icache_areq_i.fetch_irq), // 1 bit
    .probe2({itlb_instr_resolve_done, northcape_instr_is_valid_scall, northcape_instr_is_valid_scall_s}), // 3 bit
    .probe3(northcape_instr_address_out), // 64 bits
    .probe4(northcape_instr_resolve_done), // 1 bit
    .probe5(northcape_instr_resolve_error), // 1 bit
    .probe6(northcape_instr_active_task), // 32 bit
    .probe7(northcape_data_active_task), // 32 bit
    .probe8(dtlb_data_address_out), // 64 bit
    .probe9(lsu_is_store_n), // 1 bit
    .probe10(lsu_size_n), // 3 bit
    .probe11(northcape_data_tlb_hit), // 1 bit
    .probe12(lsu_atomic_n), // 1 bit
    .probe13(lsu_irq_n), // 1 bit
    .probe14(northcape_data_address_out_n), // 64 bit
    .probe15(northcape_data_resolve_error), // 1 bit
    .probe16(northcape_data_resolve_done_n), // 1 bit
    .probe17(lsu_dtlb_full_index_o), // 12 bit
    .probe18(lsu_dtlb_ppn_o), // 52 bit
    .probe19(lsu_paddr_o), // 64 bit
    .probe20(lsu_req_i), // 1 bit
    .probe21(icache_areq_i.fetch_req), // 1 bit
    .probe22(lsu_vaddr_i), // 64 bit
    .probe23(icache_areq_i.fetch_task_id_overwrite_active), // 1 bit
    .probe24(icache_areq_i.fetch_task_id_overwrite), // 32 bit
    .probe25(icache_areq_o.task_id), // 32 bit
    .probe26(dbg_task_id_frontend), // 32 bit
    .probe27(dbg_task_id_frontend_valid), // 1 bit
    .probe28(dbg_task_id_id), // 32 bit
    .probe29(dbg_task_id_id_valid), // 1 bit
    .probe30(dbg_task_id_issue), // 32 bit
    .probe31(dbg_task_id_issue_valid), // 1 bit
    .probe32(dbg_predict_addr), // 64 bits
    .probe33(dbg_predictions), // 5 bits
    .probe34(dbg_bp_valid), // 1 bit
    .probe35(dbg_btb_update_addr), // 64 bit
    .probe36(dbg_btb_valid), // 1 bit
    .probe37(dbg_replay), // 1 bit
    .probe38(dbg_replay_task_id), // 32 bit
    .probe39(dbg_set_pc_commit), // 1 bit
    .probe40(dbg_ld_index), // 12 bit
    .probe41(dbg_st_index), // 12 bit
    .probe42(dbg_ld_tag), // 52 bit
    .probe43(dbg_st_tag), // 52 bit
    .probe44(dbg_ld_req), // 1 bit
    .probe45(dbg_st_req), // 1 bit
    .probe46(dbg_ld_tag_val), // 1 bit
    .probe47(dbg_st_tag_val), // 1 bit
    .probe48(dbg_state_load_unit_i), // 4 bit
    .probe49(dbg_page_offset_matches_i), // 1 bit
    .probe50(dbg_load_unit_gnt), // 1 bit
    .probe51(ptp_dbg_state), // 3 bit
    .probe52(dbg_ld_rdata), // 64 bit
    .probe53(dbg_st_wdata), // 64 bit
    .probe54(dbg_ld_data_valid), // 1 bit
    .probe55(dbg_cache_write), // 1 bit
    .probe56(dbg_cache_write_phys_addr), // 32 bit
    .probe57(dbg_cache_write_segment_length), // 32 bit
    .probe58(dbg_state), // 3 bits
    .probe59(dbg_cache_read_phys_addr), // 32 bit
    .probe60(dbg_cache_read_segment_length), // 32 bit
    .probe61(lsu_abort_i), // 1 bit
    .probe62(lsu_exception_o.valid),  // 1 bit
    .probe63(icache_areq_o.fetch_exception.valid)
  );
`endif

endmodule
