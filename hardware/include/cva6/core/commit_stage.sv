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
// Date: 15.04.2017
// Description: Commits to the architectural state resulting from the scoreboard.


module commit_stage
  import ariane_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type exception_t = logic,
    parameter type scoreboard_entry_t = logic
) (
    // Subsystem Clock - SUBSYSTEM
    input logic clk_i,
    // Asynchronous reset active low - SUBSYSTEM
    input logic rst_ni,
    // Request to halt the core - CONTROLLER
    input logic halt_i,
    // request to flush dcache, also flush the pipeline - CACHE
    input logic flush_dcache_i,
    // TO_BE_COMPLETED - EX_STAGE
    output exception_t exception_o,
    // Mark the F state as dirty - CSR_REGFILE
    output logic dirty_fp_state_o,
    // TO_BE_COMPLETED - CSR_REGFILE
    input logic single_step_i,
    // The instruction we want to commit - ISSUE_STAGE
    input scoreboard_entry_t [CVA6Cfg.NrCommitPorts-1:0] commit_instr_i,
    // Acknowledge that we are indeed committing - ISSUE_STAGE
    output logic [CVA6Cfg.NrCommitPorts-1:0] commit_ack_o,
    // Acknowledge that we are indeed committing - CSR_REGFILE
    output logic [CVA6Cfg.NrCommitPorts-1:0] commit_macro_ack_o,
    // Register file write address - ISSUE_STAGE
    output logic [CVA6Cfg.NrCommitPorts-1:0][4:0] waddr_o,
    // Register file write data - ISSUE_STAGE
    output logic [CVA6Cfg.NrCommitPorts-1:0][CVA6Cfg.XLEN-1:0] wdata_o,
    // Does this write refer to the initialization mask? - ISSUE_STAGE
    output logic [CVA6Cfg.NrCommitPorts-1:0] wreg_mask_o,
    // Was this write commited during IRQ? - ISSUE_STAGE
    output logic [CVA6Cfg.NrCommitPorts-1:0] wirq_o,
    // Register file write enable - ISSUE_STAGE
    output logic [CVA6Cfg.NrCommitPorts-1:0] we_gpr_o,
    // Floating point register enable - ISSUE_STAGE
    output logic [CVA6Cfg.NrCommitPorts-1:0] we_fpr_o,
    // Result of AMO operation - CACHE
    input amo_resp_t amo_resp_i,
    // TO_BE_COMPLETED - FRONTEND_CSR_REGFILE
    output logic [CVA6Cfg.VLEN-1:0] pc_o,
    // commit PC valid - CONTROLLER
    output logic pc_commit_val_o,
    // Decoded CSR operation - CSR_REGFILE
    output fu_op csr_op_o,
    // Data to write to CSR - CSR_REGFILE
    output logic [CVA6Cfg.XLEN-1:0] csr_wdata_o,
    // Data to read from CSR - CSR_REGFILE
    input logic [CVA6Cfg.XLEN-1:0] csr_rdata_i,
    // Exception or interrupt occurred in CSR stage (the same as commit) - CSR_REGFILE
    input exception_t csr_exception_i,
    // Write the fflags CSR - CSR_REGFILE
    output logic csr_write_fflags_o,
    // Commit the pending store - EX_STAGE
    output logic commit_lsu_o,
    // Commit buffer of LSU is ready - EX_STAGE
    input logic commit_lsu_ready_i,
    // Transaction id of first commit port - ID_STAGE
    output logic [CVA6Cfg.TRANS_ID_BITS-1:0] commit_tran_id_o,
    // Valid AMO in commit stage - EX_STAGE
    output logic amo_valid_commit_o,
    // no store is pending - EX_STAGE
    input logic no_st_pending_i,
    // Commit the pending CSR instruction - EX_STAGE
    output logic commit_csr_o,
    // Flush I$ and pipeline - CONTROLLER
    output logic fence_i_o,
    // Flush D$ and pipeline - CONTROLLER
    output logic fence_o,
    // Request a pipeline flush - CONTROLLER
    output logic flush_commit_o,
    // Flush TLBs and pipeline - CONTROLLER
    output logic sfence_vma_o,
    output logic hfence_vvma_o,
    output logic hfence_gvma_o,
    // task ID on fence / other kind of replay - FRONTEND
    output northcape_types::task_id_t task_id_o
);
  import riscv::*;

  // ila_0 i_ila_commit (
  //     .clk(clk_i), // input wire clk
  //     .probe0(commit_instr_i[0].pc), // input wire [63:0]  probe0
  //     .probe1(commit_instr_i[1].pc), // input wire [63:0]  probe1
  //     .probe2(commit_instr_i[0].valid), // input wire [0:0]  probe2
  //     .probe3(commit_instr_i[1].valid), // input wire [0:0]  probe3
  //     .probe4(commit_ack_o[0]), // input wire [0:0]  probe4
  //     .probe5(commit_ack_o[0]), // input wire [0:0]  probe5
  //     .probe6(1'b0), // input wire [0:0]  probe6
  //     .probe7(1'b0), // input wire [0:0]  probe7
  //     .probe8(1'b0), // input wire [0:0]  probe8
  //     .probe9(1'b0) // input wire [0:0]  probe9
  // );

  // trigger exception if next instruction is NOT valid subsystem call target - used by scall, scalls
  // per-regime (IRQ, non-IRQ): could take an interrupt between scall and commiting the next instruction
  logic [1:0] exception_if_no_valid_scall_d, exception_if_no_valid_scall_q;
  logic [1:0] exception_if_no_valid_scall_s_d, exception_if_no_valid_scall_s_q;
  logic [1:0] exception_if_no_valid_scall_id_d, exception_if_no_valid_scall_id_q;
  northcape_types::task_id_t expected_task_id_d, expected_task_id_q;

  logic [CVA6Cfg.NrCommitPorts - 1 : 0] northcape_scall_exception;

  for (genvar i = 0; i < CVA6Cfg.NrCommitPorts; i++) begin : gen_waddr
    assign waddr_o[i] = commit_instr_i[i].rd[4:0];
  end

  assign pc_o = commit_instr_i[0].pc;
  /* only indicate valid when we are committing a single instruction to ensure correct pipeline behavior */
  assign pc_commit_val_o = commit_instr_i[0].valid && ~commit_instr_i[1].valid;
  assign task_id_o = commit_instr_i[0].task_id;
  // Dirty the FP state if we are committing anything related to the FPU
  always_comb begin : dirty_fp_state
    dirty_fp_state_o = 1'b0;
    for (int i = 0; i < CVA6Cfg.NrCommitPorts; i++) begin
      dirty_fp_state_o |= commit_ack_o[i] & ((commit_instr_i[i].fu inside {FPU, FPU_VEC} & CVA6Cfg.FpPresent & ariane_pkg::fd_changes_rd_state(commit_instr_i[i].op))
        || (CVA6Cfg.FpPresent && ariane_pkg::is_rd_fpr(
          commit_instr_i[i].op
      )));
      // Check if we issued a vector floating-point instruction to the accellerator
      dirty_fp_state_o |= commit_instr_i[i].fu == ACCEL && commit_instr_i[i].vfp;
    end
  end

  assign commit_tran_id_o = commit_instr_i[0].trans_id;

  logic instr_0_is_amo;
  logic [CVA6Cfg.NrCommitPorts-1:0] commit_macro_ack;
  assign instr_0_is_amo = is_amo(commit_instr_i[0].op);
  // -------------------
  // Commit Instruction
  // -------------------
  // write register file or commit instruction in LSU or CSR Buffer
  always_comb begin : commit
    automatic logic instr_1_did_commit;
    // default assignments
    commit_ack_o[0] = 1'b0;
    commit_macro_ack[0] = 1'b0;

    amo_valid_commit_o = 1'b0;

    exception_if_no_valid_scall_d = exception_if_no_valid_scall_q;
    exception_if_no_valid_scall_s_d = exception_if_no_valid_scall_s_q;
    exception_if_no_valid_scall_id_d = exception_if_no_valid_scall_id_q;
    expected_task_id_d = expected_task_id_q;
    northcape_scall_exception = '0;

    we_gpr_o[0] = 1'b0;
    we_fpr_o = '{default: 1'b0};
    commit_lsu_o = 1'b0;
    commit_csr_o = 1'b0;
    // amos will commit on port 0
    wdata_o[0] = (CVA6Cfg.RVA && amo_resp_i.ack) ? amo_resp_i.result[CVA6Cfg.XLEN-1:0] : commit_instr_i[0].result;
    wreg_mask_o = '0;
    wirq_o = '0;
    csr_op_o = ADD;  // this corresponds to a CSR NOP
    csr_wdata_o = {CVA6Cfg.XLEN{1'b0}};
    fence_i_o = 1'b0;
    fence_o = 1'b0;
    sfence_vma_o = 1'b0;
    hfence_vvma_o = 1'b0;
    hfence_gvma_o = 1'b0;
    csr_write_fflags_o = 1'b0;
    flush_commit_o = 1'b0;

    instr_1_did_commit = 1'b0;

    // we will not commit the instruction if we took an exception
    // and we do not commit the instruction if we requested a halt
    if (commit_instr_i[0].valid && !commit_instr_i[0].ex.valid && !halt_i) begin
      if (CVA6Cfg.RVZCMP && commit_instr_i[0].is_macro_instr && commit_instr_i[0].is_last_macro_instr)
        commit_macro_ack[0] = 1'b1;
      else commit_macro_ack[0] = 1'b0;
      // we can definitely write the register file
      // if the instruction is not committing anything the destination
      commit_ack_o[0] = 1'b1;
      if (CVA6Cfg.FpPresent && ariane_pkg::is_rd_fpr(commit_instr_i[0].op)) begin
        we_fpr_o[0] = 1'b1;
      end else begin
        we_gpr_o[0] = 1'b1;
      end
      // check whether the instruction we retire was a store
      if ((!CVA6Cfg.RVA && commit_instr_i[0].fu == STORE) || (CVA6Cfg.RVA && commit_instr_i[0].fu == STORE && !instr_0_is_amo)) begin
        // check if the LSU is ready to accept another commit entry (e.g.: a non-speculative store)
        if (commit_lsu_ready_i) begin
          commit_ack_o[0] = 1'b1;
          commit_lsu_o = 1'b1;
          // stall in case the store buffer is not able to accept anymore instructions
        end else begin
          commit_ack_o[0] = 1'b0;
        end
      end
      // ---------
      // FPU Flags
      // ---------
      if (CVA6Cfg.FpPresent) begin
        if (commit_instr_i[0].fu inside {FPU, FPU_VEC}) begin
          // write the CSR with potential exception flags from retiring floating point instruction
          csr_wdata_o = {{CVA6Cfg.XLEN - 5{1'b0}}, commit_instr_i[0].ex.cause[4:0]};
          csr_write_fflags_o = 1'b1;
          commit_ack_o[0] = 1'b1;
        end
      end
      // ---------
      // CSR Logic
      // ---------
      // check whether the instruction we retire was a CSR instruction and it did not
      // throw an exception
      if (commit_instr_i[0].fu == CSR) begin
        // write the CSR file
        csr_op_o    = commit_instr_i[0].op;
        csr_wdata_o = commit_instr_i[0].result;
        if (!csr_exception_i.valid) begin
          commit_csr_o = 1'b1;
          wdata_o[0] = csr_rdata_i;
          commit_ack_o[0] = 1'b1;
        end else begin
          commit_ack_o[0] = 1'b0;
          we_gpr_o[0] = 1'b0;
        end
      end
      // ------------------
      // SFENCE.VMA Logic
      // ------------------
      // sfence.vma is idempotent so we can safely re-execute it after returning
      // from interrupt service routine
      // check if this instruction was a SFENCE_VMA
      if (CVA6Cfg.RVS && commit_instr_i[0].op == SFENCE_VMA) begin
        // no store pending so we can flush the TLBs and pipeline
        sfence_vma_o = no_st_pending_i;
        // wait for the store buffer to drain until flushing the pipeline
        commit_ack_o[0] = no_st_pending_i;
      end
      // ------------------
      // HFENCE.VVMA Logic
      // ------------------
      // hfence.vvma is idempotent so we can safely re-execute it after returning
      // from interrupt service routine
      // check if this instruction was a HFENCE_VVMA
      if (CVA6Cfg.RVH && commit_instr_i[0].op == HFENCE_VVMA) begin
        // no store pending so we can flush the TLBs and pipeline
        hfence_vvma_o   = no_st_pending_i;
        // wait for the store buffer to drain until flushing the pipeline
        commit_ack_o[0] = no_st_pending_i;
      end
      // ------------------
      // HFENCE.GVMA Logic
      // ------------------
      // hfence.gvma is idempotent so we can safely re-execute it after returning
      // from interrupt service routine
      // check if this instruction was a HFENCE_GVMA
      if (CVA6Cfg.RVH && commit_instr_i[0].op == HFENCE_GVMA) begin
        // no store pending so we can flush the TLBs and pipeline
        hfence_gvma_o   = no_st_pending_i;
        // wait for the store buffer to drain until flushing the pipeline
        commit_ack_o[0] = no_st_pending_i;
      end
      // ------------------
      // FENCE.I Logic
      // ------------------
      // fence.i is idempotent so we can safely re-execute it after returning
      // from interrupt service routine
      // Fence synchronizes data and instruction streams. That means that we need to flush the private icache
      // and the private dcache. This is the most expensive instruction.
      if (commit_instr_i[0].op == FENCE_I || (flush_dcache_i && CVA6Cfg.DCacheType == config_pkg::WB && commit_instr_i[0].fu != STORE)) begin
        commit_ack_o[0] = no_st_pending_i;
        // tell the controller to flush the I$
        fence_i_o = no_st_pending_i;
      end
      // ------------------
      // FENCE Logic
      // ------------------
      // fence is idempotent so we can safely re-execute it after returning
      // from interrupt service routine
      if (commit_instr_i[0].op == FENCE) begin
        commit_ack_o[0] = no_st_pending_i;
        // tell the controller to flush the D$
        fence_o = no_st_pending_i;
      end
      // ------------------
      // AMO
      // ------------------
      if (CVA6Cfg.RVA && instr_0_is_amo) begin
        // AMO finished
        commit_ack_o[0] = amo_resp_i.ack;
        // flush the pipeline
        flush_commit_o = amo_resp_i.ack;
        amo_valid_commit_o = 1'b1;
        we_gpr_o[0] = amo_resp_i.ack;
      end

      instr_1_did_commit = 1'b1;
      // ------------------
      // Northcape accelerated Reg zero
      // ------------------
      if(CVA6Cfg.NORTHCAPE_REG_CLEAR_EXTENSION)
      begin
        wreg_mask_o[0] = commit_instr_i[0].op == REG_ZERO;
      end
      wirq_o[0] = commit_instr_i[0].is_irq;
    end

    // ------------------
    // Northcape subsystem call
    // ------------------
    /*
     * Clear the flag irregardless of exception.
     * Exception / interrupt handler will ensure we can only go here again or we do not return at all.
     */
    if(CVA6Cfg.NORTHCAPE_SCALL_EXTENSION && commit_instr_i[0].valid && !halt_i)
    begin
      // check case
      if(exception_if_no_valid_scall_d[commit_instr_i[0].is_irq])
      begin
        northcape_scall_exception[0] = !commit_instr_i[0].northcape_is_valid_scall;
        // reset - next instruction can be whatever
        exception_if_no_valid_scall_d[commit_instr_i[0].is_irq] = 1'b0;
      end
      if(exception_if_no_valid_scall_s_d[commit_instr_i[0].is_irq])
      begin
        northcape_scall_exception[0] = !commit_instr_i[0].northcape_is_valid_scall_s;
        // reset - next instruction can be whatever
        exception_if_no_valid_scall_s_d[commit_instr_i[0].is_irq] = 1'b0;
      end

      if(exception_if_no_valid_scall_id_d[commit_instr_i[0].is_irq])
      begin
        northcape_scall_exception[0] = !commit_instr_i[0].northcape_is_valid_scall;
        northcape_scall_exception[0] |= commit_instr_i[0].task_id != expected_task_id_d;
        // reset - next instruction can be whatever
        exception_if_no_valid_scall_id_d[commit_instr_i[0].is_irq] = 1'b0;
      end

      // set case - could theoretically IMMEDIATELY do next subsytem call, so might have to re-set the exception flags again
      // however, only want to set this in case the instruction actually commited - if we repeat the instruction later, might otherwise blow up on us
      if(commit_instr_i[0].op == JALR && commit_instr_i[0].scall_type inside {ariane_pkg::SKADI_SCALL, ariane_pkg::SKADI_SCALL_S, ariane_pkg::SKADI_SCALL_ID} && !northcape_scall_exception[0] && instr_1_did_commit)
      begin
        exception_if_no_valid_scall_d[commit_instr_i[0].is_irq] = commit_instr_i[0].scall_type == ariane_pkg::SKADI_SCALL;
        exception_if_no_valid_scall_s_d[commit_instr_i[0].is_irq] = commit_instr_i[0].scall_type == ariane_pkg::SKADI_SCALL_S;
        exception_if_no_valid_scall_id_d[commit_instr_i[0].is_irq] = commit_instr_i[0].scall_type == ariane_pkg::SKADI_SCALL_ID;
        // expected task ID is second register parameter (R-type) -> moved to "result" in ex stage
        expected_task_id_d = commit_instr_i[0].result[31:0];
      end
    end

    if (CVA6Cfg.NrCommitPorts > 1) begin

      commit_ack_o[1] = 1'b0;
      we_gpr_o[1]     = 1'b0;
      wdata_o[1]      = commit_instr_i[1].result;

      // -----------------
      // Commit Port 2
      // -----------------
      // check if the second instruction can be committed as well and the first wasn't a CSR instruction
      // also if we are in single step mode don't retire the second instruction
      if (commit_ack_o[0] && commit_instr_i[1].valid
                                && !halt_i
                                && !(commit_instr_i[0].fu inside {CSR})
                                && !flush_dcache_i
                                && !instr_0_is_amo
                                && !single_step_i) begin
        /* 
         * we check and handle/discard the flag IRREGARDLESS of exception when we would otherwise take the instruction
         * Northcape's interrupt/exception handling guarantees that we will either do a different subsytem call into handler and NOT return here
         * or that we return to this exact point when the interrupt/exception has been handled
         */
        if(CVA6Cfg.NORTHCAPE_SCALL_EXTENSION && !commit_instr_i[1].ex.valid
                                       && (commit_instr_i[1].fu inside {ALU, LOAD, CTRL_FLOW, MULT, FPU, FPU_VEC}))
        begin
          // check case
          if(exception_if_no_valid_scall_d[commit_instr_i[1].is_irq])
          begin
            northcape_scall_exception[1] = !commit_instr_i[1].northcape_is_valid_scall;
          end
          if(exception_if_no_valid_scall_s_d[commit_instr_i[1].is_irq])
          begin
            northcape_scall_exception[1] = !commit_instr_i[1].northcape_is_valid_scall_s;
          end
          if(exception_if_no_valid_scall_id_d[commit_instr_i[1].is_irq])
          begin
            northcape_scall_exception[1] = !commit_instr_i[1].northcape_is_valid_scall;
            northcape_scall_exception[1] |= commit_instr_i[1].task_id != expected_task_id_d;
          end
        end

        // only if the first instruction didn't throw an exception and this instruction won't throw an exception
        // and the functional unit is of type ALU, LOAD, CTRL_FLOW, MULT, FPU or FPU_VEC
        if (!exception_o.valid && !commit_instr_i[1].ex.valid
                                       && (commit_instr_i[1].fu inside {ALU, LOAD, CTRL_FLOW, MULT, FPU, FPU_VEC}
                                       && !northcape_scall_exception[1])) begin
          
          if(commit_instr_i[1].op == JALR && commit_instr_i[1].scall_type inside {ariane_pkg::SKADI_SCALL, ariane_pkg::SKADI_SCALL_S, ariane_pkg::SKADI_SCALL_ID} && !northcape_scall_exception[1])
          begin
            // set case - could theoretically IMMEDIATELY do next subsytem call, so might have to re-set the exception flags again
            exception_if_no_valid_scall_d[commit_instr_i[1].is_irq] = commit_instr_i[1].scall_type == ariane_pkg::SKADI_SCALL;
            exception_if_no_valid_scall_s_d[commit_instr_i[1].is_irq] = commit_instr_i[1].scall_type == ariane_pkg::SKADI_SCALL_S;
            exception_if_no_valid_scall_id_d[commit_instr_i[1].is_irq] = commit_instr_i[1].scall_type == ariane_pkg::SKADI_SCALL_ID;
            // expected task ID is second register parameter (R-type)
            expected_task_id_d = commit_instr_i[1].result[31:0];
          end
          else
          begin
            // no subsystem call and instruction committed - reset
            // reset - next instruction can be whatever
            exception_if_no_valid_scall_d[commit_instr_i[1].is_irq] = 1'b0;
            exception_if_no_valid_scall_s_d[commit_instr_i[1].is_irq] = 1'b0;
            exception_if_no_valid_scall_id_d[commit_instr_i[1].is_irq] = 1'b0;
          end

          if (CVA6Cfg.FpPresent && ariane_pkg::is_rd_fpr(commit_instr_i[1].op)) we_fpr_o[1] = 1'b1;
          else we_gpr_o[1] = 1'b1;

          if (commit_instr_i[1].is_macro_instr && commit_instr_i[1].is_last_macro_instr)
            commit_macro_ack[1] = 1'b1;
          else commit_macro_ack[1] = 1'b0;

          commit_ack_o[1] = 1'b1;

          // additionally check if we are retiring an FPU instruction because we need to make sure that we write all
          // exception flags
          if (CVA6Cfg.FpPresent && commit_instr_i[1].fu inside {FPU, FPU_VEC}) begin
            if (csr_write_fflags_o)
              csr_wdata_o = {
                {CVA6Cfg.XLEN - 5{1'b0}},
                (commit_instr_i[0].ex.cause[4:0] | commit_instr_i[1].ex.cause[4:0])
              };
            else csr_wdata_o = {{CVA6Cfg.XLEN - 5{1'b0}}, commit_instr_i[1].ex.cause[4:0]};

            csr_write_fflags_o = 1'b1;
          end

          // ------------------
          // Northcape accelerated Reg zero
          // ------------------
          if(CVA6Cfg.NORTHCAPE_REG_CLEAR_EXTENSION)
          begin
            wreg_mask_o[1] = commit_instr_i[1].op == REG_ZERO;
          end
          wirq_o[1] = commit_instr_i[1].is_irq;
        end
      end
    end
    if (CVA6Cfg.RVZCMP) begin
      if (CVA6Cfg.NrCommitPorts > 1)
        commit_macro_ack_o = (commit_instr_i[0].is_macro_instr || commit_instr_i[1].is_macro_instr) ? commit_macro_ack : commit_ack_o;
      else
        commit_macro_ack_o = (commit_instr_i[0].is_macro_instr) ? commit_macro_ack : commit_ack_o;
    end else commit_macro_ack_o = commit_ack_o;
  end

  // -----------------------------
  // Exception & Interrupt Logic
  // -----------------------------
  // here we know for sure that we are taking the exception
  always_comb begin : exception_handling
    // Multiple simultaneous interrupts and traps at the same privilege level are handled in the following decreasing
    // priority order: external interrupts, software interrupts, timer interrupts, then finally any synchronous traps. (1.10 p.30)
    // interrupts are correctly prioritized in the CSR reg file, exceptions are prioritized here
    exception_o.valid = 1'b0;
    exception_o.cause = '0;
    exception_o.tval  = '0;
    exception_o.tval2 = '0;
    exception_o.tinst = '0;
    exception_o.gva   = 1'b0;

    // we need a valid instruction in the commit stage
    if (commit_instr_i[0].valid) begin
      // ------------------------
      // check for Northcape CSR exception
      // ------------------------
      if(CVA6Cfg.NORTHCAPE_SCALL_EXTENSION && northcape_scall_exception[0])
      begin
        exception_o.valid = 1'b1;
        exception_o.cause = riscv::NORTHCAPE_BASE + northcape_types::NORTHCAPE_RESOLVE_ERROR_INVALID_SCALL_TARGET;
        exception_o.tval = commit_instr_i[0].pc;
      end
      // ------------------------
      // check for CSR exception
      // ------------------------
      if (csr_exception_i.valid) begin
        exception_o      = csr_exception_i;
        // if no earlier exception happened the commit instruction will still contain
        // the instruction bits from the ID stage. If a earlier exception happened we don't care
        // as we will overwrite it anyway in the next IF bl
        exception_o.tval = commit_instr_i[0].ex.tval;
        if (CVA6Cfg.RVH) begin
          exception_o.tinst = commit_instr_i[0].ex.tinst;
          exception_o.tval2 = commit_instr_i[0].ex.tval2;
          exception_o.gva   = commit_instr_i[0].ex.gva;
        end
      end
      // ------------------------
      // Earlier Exceptions
      // ------------------------
      // but we give precedence to exceptions which happened earlier e.g.: instruction page
      // faults for example
      if (commit_instr_i[0].ex.valid) begin
        exception_o = commit_instr_i[0].ex;
      end
    end
    // Don't take any exceptions iff:
    // - If we halted the processor
    if (halt_i) begin
      exception_o.valid = 1'b0;
    end
  end

  generate
    if(CVA6Cfg.NORTHCAPE_SCALL_EXTENSION)
    begin: gen_scall_exception_reg
      always_ff @(posedge(clk_i), negedge(rst_ni))
      begin: scall_ff
        if(!rst_ni)
        begin
          exception_if_no_valid_scall_q <= 2'b0;
          exception_if_no_valid_scall_s_q <= 2'b0;
          exception_if_no_valid_scall_id_q <= 2'b0;
          expected_task_id_q <= '0;
        end
        else
        begin
          exception_if_no_valid_scall_q <= exception_if_no_valid_scall_d;
          exception_if_no_valid_scall_s_q <= exception_if_no_valid_scall_s_d;
          exception_if_no_valid_scall_id_q <= exception_if_no_valid_scall_id_d;
          expected_task_id_q <= expected_task_id_d;
        end
      end: scall_ff
    end: gen_scall_exception_reg
    else
    begin: no_scall_exception_reg
      assign exception_if_no_valid_scall_q = 2'b0;
      assign exception_if_no_valid_scall_s_q = 2'b0;
    end: no_scall_exception_reg

  endgenerate
endmodule
