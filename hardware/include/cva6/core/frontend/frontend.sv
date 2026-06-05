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
// Date: 08.02.2018
// Description: Ariane Instruction Fetch Frontend
//
// This module interfaces with the instruction cache, handles control
// change request from the back-end and does branch prediction.

module frontend
  import ariane_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type icache_areq_t = logic,
    parameter type icache_arsp_t = logic,
    parameter type bp_resolve_t = logic,
    parameter type fetch_entry_t = logic,
    parameter type icache_dreq_t = logic,
    parameter type icache_drsp_t = logic,
    parameter type interrupts_t = logic,
    parameter type dcache_req_i_t = logic,
    parameter type dcache_req_o_t = logic,
    parameter interrupts_t INTERRUPTS = '0
) (
    // Subsystem Clock - SUBSYSTEM
    input logic clk_i,
    // Asynchronous reset active low - SUBSYSTEM
    input logic rst_ni,
    // Next PC when reset - SUBSYSTEM
    input logic [CVA6Cfg.VLEN-1:0] boot_addr_i,
    // Flush branch prediction - CSR
    input logic flush_bp_i,
    // Flush requested by FENCE, mis-predict and exception - CONTROLLER
    input logic flush_i,
    // Halt requested by WFI and Accelerate port - CONTROLLER
    input logic halt_i,
    // Halt frontend - CONTROLLER (in the case of fence_i to avoid fetching an old instruction)
    input logic halt_frontend_i,
    // Set COMMIT PC as next PC requested by FENCE, CSR side-effect and Accelerate port - CONTROLLER
    input logic set_pc_commit_i,
    // COMMIT PC - COMMIT
    input logic [CVA6Cfg.VLEN-1:0] pc_commit_i,
    // COMMIT task ID - COMMIT
    input northcape_types::task_id_t task_id_commit_i,
    // Exception event - COMMIT
    input logic ex_valid_i,
    // Exception cause - COMMIT
    input logic [CVA6Cfg.XLEN-1:0] ex_cause_i,
    // Mispredict event and next PC - EXECUTE
    input bp_resolve_t resolved_branch_i,
    // Return from exception event - CSR
    input logic eret_i,
    // Next PC when returning from exception - CSR
    input logic [CVA6Cfg.VLEN-1:0] epc_i,
    // Next PC when jumping into exception - CSR
    input logic [CVA6Cfg.VLEN-1:0] trap_vector_base_i,
    // Are we in ISR table mode? If so, trap_vector_base contains an address, not an instruction - CSR
    input logic trap_vector_mode_table_i,
    // Debug event - CSR
    input logic set_debug_pc_i,
    // dynamically relocated base for the debug module
    input logic [CVA6Cfg.VLEN-1:0] debug_offset_i,
    // Debug mode state - CSR
    input logic debug_mode_i,
    // Handshake between CACHE and FRONTEND (fetch) - CACHES
    output icache_dreq_t icache_dreq_o,
    // Handshake between CACHE and FRONTEND (fetch) - CACHES
    input icache_drsp_t icache_dreq_i,
    // Handshake's data between fetch and decode - ID_STAGE
    output fetch_entry_t [ariane_pkg::SUPERSCALAR:0] fetch_entry_o,
    // Handshake's valid between fetch and decode - ID_STAGE
    output logic [ariane_pkg::SUPERSCALAR:0] fetch_entry_valid_o,
    // Handshake's ready between fetch and decode - ID_STAGE
    input logic [ariane_pkg::SUPERSCALAR:0] fetch_entry_ready_i,
    // Northcape-specific timer base
    input logic [CVA6Cfg.XLEN-1:0] northcape_mtimer_base_i,
    // Handshake between DCACHE and FRONTEND (ISR table) - CACHES
    output dcache_req_i_t dcache_req_port_o,
    input dcache_req_o_t dcache_req_port_i,
    /* Is northcape enabled? */
    input logic northcape_enabled_i,
    // MTVEC translation interface - Northcape
    output icache_arsp_t mtvec_areq_o,
    input icache_areq_t mtvec_areq_i,

    // TODO remove - debug
    output logic [CVA6Cfg.XLEN-1:0] dbg_predict_addr,
    output logic [9:0] dbg_predictions,
    output logic dbg_bp_valid,
    output logic [CVA6Cfg.XLEN-1:0] dbg_btb_update_addr,
    output logic dbg_btb_valid,
    output logic dbg_replay,
    output northcape_types::task_id_t dbg_replay_task_id
);

  localparam type bht_update_t = struct packed {
    logic                    valid;
    logic [CVA6Cfg.VLEN-1:0] pc;     // update at PC
    logic                    taken;
  };

  localparam type btb_prediction_t = struct packed {
    logic                    valid;
    logic [CVA6Cfg.VLEN-1:0] target_address;
  };

  localparam type btb_update_t = struct packed {
    logic                    valid;
    logic [CVA6Cfg.VLEN-1:0] pc;              // update at PC
    logic [CVA6Cfg.VLEN-1:0] target_address;
  };

  localparam type ras_t = struct packed {
    logic                    valid;
    logic [CVA6Cfg.VLEN-1:0] ra;
  };

  // Instruction Cache Registers, from I$
  logic                            [    CVA6Cfg.FETCH_WIDTH-1:0] icache_data_q;
  logic                                                          icache_valid_q;
  ariane_pkg::frontend_exception_t                               icache_ex_valid_q;
  logic                            [           CVA6Cfg.VLEN-1:0] icache_vaddr_q;
  logic                            [          CVA6Cfg.GPLEN-1:0] icache_gpaddr_q;
  logic                            [                       31:0] icache_tinst_q;
  logic                                                          icache_gva_q;
  northcape_types::task_id_t                                     icache_task_id_q;
  logic                                                          icache_is_valid_scall_q;
  logic                                                          icache_is_valid_scall_s_q;
  logic                                                          instr_queue_ready;
  logic                            [CVA6Cfg.INSTR_PER_FETCH-1:0] instr_queue_consumed;
  // upper-most branch-prediction from last cycle
  btb_prediction_t                                               btb_q;
  bht_prediction_t                                               bht_q;
  // instruction fetch is ready
  logic                                                          if_ready;
  logic [CVA6Cfg.VLEN-1:0] npc_d, npc_q;  // next PC

  // indicates whether we come out of reset (then we need to load boot_addr_i)
  logic                                       npc_rst_load_q;

  logic                                       replay;
  logic [                   CVA6Cfg.VLEN-1:0] replay_addr;
  northcape_types::task_id_t                  replay_task_id_d, replay_task_id_q, queue_task_id;
  logic                                       replay_task_id_active_d, replay_task_id_active_q;
  northcape_types::task_id_t                  task_id_realigner;
  logic                                       valid_scall_realigner;
  logic                                       valid_scall_s_realigner;

  // shift amount
  logic [$clog2(CVA6Cfg.INSTR_PER_FETCH)-1:0] shamt;
  // address will always be 16 bit aligned, make this explicit here
  if (CVA6Cfg.RVC) begin : gen_shamt
    assign shamt = icache_dreq_i.vaddr[$clog2(CVA6Cfg.INSTR_PER_FETCH):1];
  end else begin
    assign shamt = 1'b0;
  end

  // -----------------------
  // Ctrl Flow Speculation
  // -----------------------
  // RVI ctrl flow prediction
  logic [CVA6Cfg.INSTR_PER_FETCH-1:0] rvi_return, rvi_call, rvi_branch, rvi_jalr, rvi_jump, return_from_irq;
  logic [CVA6Cfg.INSTR_PER_FETCH-1:0][CVA6Cfg.VLEN-1:0] rvi_imm;
  // RVC branching
  logic [CVA6Cfg.INSTR_PER_FETCH-1:0] rvc_branch, rvc_jump, rvc_jr, rvc_return, rvc_jalr, rvc_call;
  logic            [CVA6Cfg.INSTR_PER_FETCH-1:0][CVA6Cfg.VLEN-1:0] rvc_imm;
  // re-aligned instruction and address (coming from cache - combinationally)
  logic            [CVA6Cfg.INSTR_PER_FETCH-1:0][            31:0] instr;
  logic            [CVA6Cfg.INSTR_PER_FETCH-1:0][CVA6Cfg.VLEN-1:0] addr;
  logic            [CVA6Cfg.INSTR_PER_FETCH-1:0]                   instruction_valid;
  // BHT, BTB and RAS prediction
  bht_prediction_t [CVA6Cfg.INSTR_PER_FETCH-1:0]                   bht_prediction;
  btb_prediction_t [CVA6Cfg.INSTR_PER_FETCH-1:0]                   btb_prediction;
  bht_prediction_t [CVA6Cfg.INSTR_PER_FETCH-1:0]                   bht_prediction_shifted;
  btb_prediction_t [CVA6Cfg.INSTR_PER_FETCH-1:0]                   btb_prediction_shifted;
  ras_t                                                            ras_predict;
  logic            [           CVA6Cfg.VLEN-1:0]                   vpc_btb;

  // branch-predict update
  logic                                                            is_mispredict;
  logic ras_push, ras_pop;
  logic [           CVA6Cfg.VLEN-1:0] ras_update;

  // Instruction FIFO
  logic [           CVA6Cfg.VLEN-1:0] predict_address;
  cf_t  [CVA6Cfg.INSTR_PER_FETCH-1:0] cf_type;
  logic [CVA6Cfg.INSTR_PER_FETCH-1:0] taken_rvi_cf;
  logic [CVA6Cfg.INSTR_PER_FETCH-1:0] taken_rvc_cf;

  logic                               serving_unaligned;
  // Re-align instructions
  instr_realign #(
      .CVA6Cfg(CVA6Cfg)
  ) i_instr_realign (
      .clk_i              (clk_i),
      .rst_ni             (rst_ni),
      .flush_i            (icache_dreq_o.kill_s2),
      .valid_i            (icache_valid_q),
      .serving_unaligned_o(serving_unaligned),
      .address_i          (icache_vaddr_q),
      .task_id_i          (icache_task_id_q),
      .valid_scall_i      (icache_is_valid_scall_q),
      .valid_scall_s_i    (icache_is_valid_scall_s_q),
      .data_i             (icache_data_q),
      .valid_o            (instruction_valid),
      .addr_o             (addr),
      .instr_o            (instr),
      .valid_scall_o      (valid_scall_realigner),
      .valid_scall_s_o    (valid_scall_s_realigner),
      .task_id_o          (task_id_realigner)
  );

  assign icache_dreq_o.dbg_vaddr_out = fetch_entry_o[0].address;
  assign icache_dreq_o.dbg_instr_out = fetch_entry_o[0].instruction;
  assign icache_dreq_o.dbg_instr_queue_addr_in = addr[0];
  assign icache_dreq_o.dbg_frontend_vaddr = icache_vaddr_q;
  assign icache_dreq_o.dbg_flush = flush_i;
  assign icache_dreq_o.dbg_fetch_entry_valid = fetch_entry_valid_o;
  // --------------------
  // Branch Prediction
  // --------------------
  // select the right branch prediction result
  // in case we are serving an unaligned instruction in instr[0] we need to take
  // the prediction we saved from the previous fetch
  if (CVA6Cfg.RVC) begin : gen_btb_prediction_shifted
    assign bht_prediction_shifted[0] = (serving_unaligned) ? bht_q : bht_prediction[addr[0][$clog2(
        CVA6Cfg.INSTR_PER_FETCH
    ):1]];
    assign btb_prediction_shifted[0] = (serving_unaligned) ? btb_q : btb_prediction[addr[0][$clog2(
        CVA6Cfg.INSTR_PER_FETCH
    ):1]];

    // for all other predictions we can use the generated address to index
    // into the branch prediction data structures
    for (genvar i = 1; i < CVA6Cfg.INSTR_PER_FETCH; i++) begin : gen_prediction_address
      assign bht_prediction_shifted[i] = bht_prediction[addr[i][$clog2(CVA6Cfg.INSTR_PER_FETCH):1]];
      assign btb_prediction_shifted[i] = btb_prediction[addr[i][$clog2(CVA6Cfg.INSTR_PER_FETCH):1]];
    end
  end else begin
    assign bht_prediction_shifted[0] = (serving_unaligned) ? bht_q : bht_prediction[addr[0][1]];
    assign btb_prediction_shifted[0] = (serving_unaligned) ? btb_q : btb_prediction[addr[0][1]];
  end
  ;

  // for the return address stack it doens't matter as we have the
  // address of the call/return already
  logic bp_valid;

  logic [CVA6Cfg.INSTR_PER_FETCH-1:0] is_branch;
  logic [CVA6Cfg.INSTR_PER_FETCH-1:0] is_call;
  logic [CVA6Cfg.INSTR_PER_FETCH-1:0] is_jump;
  logic [CVA6Cfg.INSTR_PER_FETCH-1:0] is_return;
  logic [CVA6Cfg.INSTR_PER_FETCH-1:0] is_jalr;

  for (genvar i = 0; i < CVA6Cfg.INSTR_PER_FETCH; i++) begin
    // branch history table -> BHT
    assign is_branch[i] = instruction_valid[i] & (rvi_branch[i] | rvc_branch[i]);
    // function calls -> RAS
    assign is_call[i] = instruction_valid[i] & (rvi_call[i] | rvc_call[i]);
    // function return -> RAS
    assign is_return[i] = instruction_valid[i] & (rvi_return[i] | rvc_return[i]);
    // unconditional jumps with known target -> immediately resolved
    assign is_jump[i] = instruction_valid[i] & (rvi_jump[i] | rvc_jump[i]);
    // unconditional jumps with unknown target -> BTB
    assign is_jalr[i] = instruction_valid[i] & ~is_return[i] & (rvi_jalr[i] | rvc_jalr[i] | rvc_jr[i]);
  end

  // taken/not taken
  always_comb begin
    taken_rvi_cf = '0;
    taken_rvc_cf = '0;
    predict_address = '0;

    for (int i = 0; i < CVA6Cfg.INSTR_PER_FETCH; i++) cf_type[i] = ariane_pkg::NoCF;

    ras_push = 1'b0;
    ras_pop = 1'b0;
    ras_update = '0;

    // lower most prediction gets precedence
    for (int i = CVA6Cfg.INSTR_PER_FETCH - 1; i >= 0; i--) begin
      unique case ({
        is_branch[i], is_return[i], is_jump[i], is_jalr[i]
      })
        4'b0000: ;  // regular instruction e.g.: no branch
        // unconditional jump to register, we need the BTB to resolve this
        4'b0001: begin
          ras_pop  = 1'b0;
          ras_push = 1'b0;
          if (CVA6Cfg.BTBEntries && btb_prediction_shifted[i].valid) begin
            predict_address = btb_prediction_shifted[i].target_address;
            cf_type[i] = ariane_pkg::JumpR;
          end
        end
        // its an unconditional jump to an immediate
        4'b0010: begin
          ras_pop = 1'b0;
          ras_push = 1'b0;
          taken_rvi_cf[i] = rvi_jump[i];
          taken_rvc_cf[i] = rvc_jump[i];
          cf_type[i] = ariane_pkg::Jump;
        end
        // return
        4'b0100: begin
          // make sure to only alter the RAS if we actually consumed the instruction
          ras_pop = ras_predict.valid & instr_queue_consumed[i];
          ras_push = 1'b0;
          predict_address = ras_predict.ra;
          cf_type[i] = ariane_pkg::Return;
        end
        // branch prediction
        4'b1000: begin
          ras_pop  = 1'b0;
          ras_push = 1'b0;
          // if we have a valid dynamic prediction use it
          if (bht_prediction_shifted[i].valid) begin
            taken_rvi_cf[i] = rvi_branch[i] & bht_prediction_shifted[i].taken;
            taken_rvc_cf[i] = rvc_branch[i] & bht_prediction_shifted[i].taken;
            // otherwise default to static prediction
          end else begin
            // set if immediate is negative - static prediction
            taken_rvi_cf[i] = rvi_branch[i] & rvi_imm[i][CVA6Cfg.VLEN-1];
            taken_rvc_cf[i] = rvc_branch[i] & rvc_imm[i][CVA6Cfg.VLEN-1];
          end
          if (taken_rvi_cf[i] || taken_rvc_cf[i]) begin
            cf_type[i] = ariane_pkg::Branch;
          end
        end
        default: ;
        // default: $error("Decoded more than one control flow");
      endcase
      // if this instruction, in addition, is a call, save the resulting address
      // but only if we actually consumed the address
      if (is_call[i]) begin
        ras_push   = instr_queue_consumed[i];
        ras_update = addr[i] + (rvc_call[i] ? 2 : 4);
      end
      // calculate the jump target address
      if (taken_rvc_cf[i] || taken_rvi_cf[i]) begin
        predict_address = addr[i] + (taken_rvc_cf[i] ? rvc_imm[i] : rvi_imm[i]);
      end
    end
  end
  // or reduce struct
  always_comb begin
    bp_valid = 1'b0;
    // BP cannot be valid if we have a return instruction and the RAS is not giving a valid address
    // Check that we encountered a control flow and that for a return the RAS
    // contains a valid prediction.
    for (int i = 0; i < CVA6Cfg.INSTR_PER_FETCH; i++)
    bp_valid |= ((cf_type[i] != NoCF & cf_type[i] != Return) | ((cf_type[i] == Return) & ras_predict.valid));
  end
  assign is_mispredict = resolved_branch_i.valid & resolved_branch_i.is_mispredict;

  // Cache interface
  assign if_ready = icache_dreq_i.ready & instr_queue_ready & ~halt_frontend_i;
  // We need to flush the cache pipeline if:
  // 1. We mispredicted
  // 2. Want to flush the whole processor front-end
  // 3. Need to replay an instruction because the fetch-fifo was full
  assign icache_dreq_o.kill_s1 = is_mispredict | flush_i | replay;
  // if we have a valid branch-prediction we need to only kill the last cache request
  // also if we killed the first stage we also need to kill the second stage (inclusive flush)
  assign icache_dreq_o.kill_s2 = icache_dreq_o.kill_s1 | bp_valid;

  // Update Control Flow Predictions
  bht_update_t bht_update;
  btb_update_t btb_update;

  // assert on branch, deassert when resolved
  logic speculative_q, speculative_d;
  assign speculative_d = (speculative_q && !resolved_branch_i.valid || |is_branch || |is_return || |is_jalr) && !flush_i;
  assign icache_dreq_o.spec = speculative_d;
  // branches should not trigger subsystem calls - no need to check here
  assign bht_update.valid = resolved_branch_i.valid
                                & (resolved_branch_i.cf_type == ariane_pkg::Branch);
  assign bht_update.pc = resolved_branch_i.pc;
  assign bht_update.taken = resolved_branch_i.is_taken;
  // only update mispredicted branches e.g. no returns from the RAS
  // no speculative subsystem calls - fetch has side effects!
  // all subsystem calls have offset 0, but not all capabilities with offset 0 are subsystem calls
  // still, non-subsystem calls with offset 0 basically do not occur
  // so this is a simple strategy that prevents us from doing subsystem calls speculatively
  // overwriting the control flow type takes care of both the bp_valid below and the instruction queue
  assign btb_update.valid = resolved_branch_i.valid
                                & resolved_branch_i.is_mispredict
                                & (resolved_branch_i.cf_type == ariane_pkg::JumpR)
                                & !(CVA6Cfg.NORTHCAPE_STAGE_ENABLED && northcape_types::capability_accessors#(64)::capability_get_offset(resolved_branch_i.target_address) == 32'h0);
  assign btb_update.pc = resolved_branch_i.pc;
  assign btb_update.target_address = resolved_branch_i.target_address;

  assign dbg_predict_addr = predict_address;
  assign dbg_predictions = {is_branch[1], is_call[1], is_return[1], is_jump[1], is_jalr[1], is_branch[0], is_call[0], is_return[0], is_jump[0], is_jalr[0]};
  assign dbg_bp_valid = bp_valid;
  assign dbg_btb_update_addr = resolved_branch_i.pc;
  assign dbg_btb_valid = btb_update.valid;
  assign dbg_replay_task_id = replay_task_id_d;
  assign dbg_replay = replay;

  //----------------------
  // IRQ tracking logic
  //----------------------

  logic in_irq_n, in_irq_q;

  generate
    if(CVA6Cfg.SUPPORT_NON_STANDARD_TABLE_ISR_MODE) begin: trackIRQ
      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          in_irq_q <= 1'b0;
        end 
        else
        begin
          in_irq_q <= in_irq_n;
        end
      end
    end: trackIRQ
    else begin: skipIRQ
      assign in_irq_q = 1'b0;
    end: skipIRQ
  endgenerate

  always_comb begin: compute_next_irq_state
    in_irq_n = in_irq_q;
    /*
     * Conditions for "irq" flag:
     * - not an exception (handled synchronously)
     * - not a pipeline mispredict (will take later)
     * - not a timer interrupt, if timer interrupts excluded from IRQ logic
     * - Northcape's timer IRQ mode enabled
     */
    if(ex_valid_i && !set_pc_commit_i && !(CVA6Cfg.DebugEn && set_debug_pc_i) && !(CVA6Cfg.DO_NOT_INDICATE_IRQ_ON_TIMER && ex_cause_i inside {INTERRUPTS.S_TIMER, INTERRUPTS.M_TIMER}) && !(CVA6Cfg.DO_NOT_INDICATE_IRQ_ON_EXCEPTION && ex_cause_i[CVA6Cfg.XLEN-1] == 1'b0) && trap_vector_mode_table_i)
    begin
      // transition INTO IRQ
      in_irq_n = 1'b1;
    end

    // we are returning from the interrupt
    if(eret_i)
    begin
      in_irq_n = 1'b0;
    end
  end

  //---------------------
  // ISR table logic
  //---------------------

  typedef enum logic[2:0] { ISR_TABLE_RESOLVED, ISR_TABLE_WAIT_TRANSLATION, ISR_TABLE_RESOLVE_WAIT_GNT, ISR_TABLE_RESOLVE_SEND_TAG, ISR_TABLE_RESOLVE_WAIT_DATA } isr_table_resolution_state_t;

  isr_table_resolution_state_t isr_table_resolution_state_q, isr_table_resolution_state_n;
  logic [CVA6Cfg.XLEN-1:0] isr_base_n;

  // static for dcache request
  assign dcache_req_port_o.data_wdata = '0;
  assign dcache_req_port_o.data_wuser = '0;
  assign dcache_req_port_o.data_we = '0;
  assign dcache_req_port_o.is_non_cacheable = 1'b0;
  assign dcache_req_port_o.cbo_op = ariane_pkg::CBO_NONE;
  // not applicable
  assign dcache_req_port_o.task_id = '0;
  assign dcache_req_port_o.device_interpreted_restriction = '0;
  assign dcache_req_port_o.data_id = '0;
  // always 8-bit by design
  assign dcache_req_port_o.data_size = 2'b11;
  assign dcache_req_port_o.data_be = 8'b1111_1111;
  assign dcache_req_port_o.kill_req = 1'b0;

  generate
    if(CVA6Cfg.SUPPORT_NON_STANDARD_TABLE_ISR_MODE)
    begin: isrTableModeFSM
      always_ff @(posedge(clk_i), negedge(rst_ni)) begin: haveResolvedISRBaseQFF
        if(rst_ni == 1'b0)
        begin
          // never start with ISR
          isr_table_resolution_state_q <= ISR_TABLE_RESOLVED;
        end
        else
        begin
          isr_table_resolution_state_q <= isr_table_resolution_state_n;
        end
      end: haveResolvedISRBaseQFF
    end: isrTableModeFSM
    else
    begin: noTableSupport
      assign isr_table_resolution_state_q = ISR_TABLE_RESOLVED;
    end: noTableSupport
  endgenerate

  // -------------------
  // Next PC
  // -------------------
  // next PC (NPC) can come from (in order of precedence):
  // 0. Default assignment/replay instruction
  // 1. Branch Predict taken
  // 2. Control flow change request (misprediction)
  // 3. Return from environment call
  // 4. Exception/Interrupt
  // 5. Pipeline Flush because of CSR side effects
  // Mis-predict handling is a little bit different
  // select PC a.k.a PC Gen
  always_comb begin : npc_select
    automatic logic [CVA6Cfg.VLEN-1:0] fetch_address;
    // Gate ICache requests and NPC updates during fence.i
    icache_dreq_o.req = instr_queue_ready & ~halt_frontend_i;
    icache_dreq_o.is_irq = in_irq_q;
    icache_dreq_o.fetch_task_id_overwrite_active = replay_task_id_active_q;
    icache_dreq_o.fetch_task_id_overwrite = replay_task_id_q;
    isr_table_resolution_state_n = isr_table_resolution_state_q;

    dcache_req_port_o.address_index = '0;
    dcache_req_port_o.address_tag = '0;
    dcache_req_port_o.data_req = 1'b0;
    dcache_req_port_o.tag_valid = 1'b0;
    dcache_req_port_o.is_irq = 1'b0;

    replay_task_id_active_d = replay_task_id_active_q;
    replay_task_id_d = replay_task_id_q;

    mtvec_areq_o.fetch_req = 1'b0;
    mtvec_areq_o.fetch_irq = 1'b0;
    mtvec_areq_o.fetch_vaddr = '0;
    mtvec_areq_o.fetch_task_id_overwrite = '0;
    mtvec_areq_o.fetch_task_id_overwrite_active = 1'b0;

    isr_base_n = '0;

    // check whether we come out of reset
    // this is a workaround. some tools have issues
    // having boot_addr_i in the asynchronous
    // reset assignment to npc_q, even though
    // boot_addr_i will be assigned a constant
    // on the top-level.
    if (npc_rst_load_q) begin
      npc_d         = boot_addr_i;
      fetch_address = boot_addr_i;
    end else begin
      fetch_address = npc_q;
      // keep stable by default
      npc_d         = npc_q;

      // maintain task ID reset until completed icache handshake
      if(replay_task_id_active_q)
      begin
        replay_task_id_active_d = !(icache_dreq_o.req && icache_dreq_i.ready);
      end

    end
    // 0. Branch Prediction
    if (bp_valid && isr_table_resolution_state_q == ISR_TABLE_RESOLVED) begin
      fetch_address = predict_address;
      npc_d = predict_address;
    end
    // 1. Default assignment
    if (if_ready && isr_table_resolution_state_q == ISR_TABLE_RESOLVED) begin
      npc_d = {
        fetch_address[CVA6Cfg.VLEN-1:CVA6Cfg.FETCH_ALIGN_BITS] + 1, {CVA6Cfg.FETCH_ALIGN_BITS{1'b0}}
      };
    end
    // 2. Replay instruction fetch
    if (replay) begin
      npc_d = replay_addr;
      // make sure that replay will use the same task ID - current instruction could overwrite it
      replay_task_id_active_d = 1'b1;
      // capture task ID from replay / instruction queue
      replay_task_id_d = queue_task_id;
    end
    // 3. Control flow change request
    if (is_mispredict) begin
      npc_d = resolved_branch_i.target_address;
      // overwrite replay
      replay_task_id_active_d = 1'b0;
    end
    // 4. Return from environment call
    if (eret_i) begin
      // overwrite replay
      replay_task_id_active_d = 1'b0;
      npc_d = epc_i;
    end
    // 5. Exception/Interrupt
    if (ex_valid_i) begin
      // overwrite replay
      // we will (very likely) do a subsystem call here
      replay_task_id_active_d = 1'b0;
      
      npc_d = trap_vector_base_i;
      // if we are in table mode, we need to make one request to get the ISR handler's base address
      // we can then set the PC there

      // debug is also technically an exception
      // but handling differs - instead of jumping into ISR table, we jump into the debug module
      // thus, no need to go into table resolution
      // same treatment when encountering an exception in debug mode - the CSR provides us with the address of the exception handler in the debug module
      // if we did, we would deadlock the frontend or execute the wrong instruction
      isr_table_resolution_state_n = (trap_vector_mode_table_i && (!CVA6Cfg.DebugEn || (!set_debug_pc_i && !debug_mode_i))) ? ISR_TABLE_WAIT_TRANSLATION : ISR_TABLE_RESOLVED;

      if(trap_vector_mode_table_i && CVA6Cfg.DO_NOT_INDICATE_IRQ_ON_TIMER && ex_cause_i inside {INTERRUPTS.S_TIMER, INTERRUPTS.M_TIMER})
      begin
        // unconditionally use the per-hart CSR - MUST have been set by the subsystem
        // only applicable with Northcape - we cannot into Linux otherwise :-(
        npc_d = northcape_mtimer_base_i;
        isr_table_resolution_state_n = ISR_TABLE_RESOLVED;
      end

      // for debug: need to wait for instruction queue, do not treat as interrupt
      if(isr_table_resolution_state_n == ISR_TABLE_WAIT_TRANSLATION)
      begin
        // no valid address at the moment
        icache_dreq_o.req = 1'b0;
      end
    end
    // 6. Pipeline Flush because of CSR side effects
    // On a pipeline flush start fetching from the next address
    // of the instruction in the commit stage
    // we either came here from a flush request of a CSR instruction or AMO,
    // so as CSR or AMO instructions do not exist in a compressed form
    // we can unconditionally do PC + 4 here
    // or if the commit stage is halted, just take the current pc of the
    // instruction in the commit stage
    // TODO(zarubaf) This adder can at least be merged with the one in the csr_regfile stage
    if (set_pc_commit_i) begin
      // overwrite replay - (may) need to reset replay's task ID
      replay_task_id_active_d = 1'b1;
      replay_task_id_d = task_id_commit_i;
      npc_d = pc_commit_i + (halt_i ? '0 : {{CVA6Cfg.VLEN - 3{1'b0}}, 3'b100});
      icache_dreq_o.is_irq = in_irq_q && isr_table_resolution_state_n == ISR_TABLE_RESOLVED;
    end
    // 7. Debug
    // enter debug on a hard-coded base-address
    if (CVA6Cfg.DebugEn && set_debug_pc_i)
    begin
      // overwrite replay
      replay_task_id_active_d = 1'b0;
      npc_d = debug_offset_i + CVA6Cfg.DmBaseAddress[CVA6Cfg.VLEN-1:0] + CVA6Cfg.HaltAddress[CVA6Cfg.VLEN-1:0];
      // debug not treated as IRQ in this context
      icache_dreq_o.is_irq = 1'b0;
    end

    unique case(isr_table_resolution_state_q)
      ISR_TABLE_WAIT_TRANSLATION:
      begin
        // no valid address at the moment
        icache_dreq_o.req = 1'b0;

        mtvec_areq_o.fetch_req = 1'b1;
        mtvec_areq_o.fetch_irq = 1'b0;
        // we parked the trap vector in this register
        mtvec_areq_o.fetch_vaddr = npc_q;
        mtvec_areq_o.fetch_task_id_overwrite = '0;
        mtvec_areq_o.fetch_task_id_overwrite_active = 1'b0;
        if(mtvec_areq_i.fetch_valid)
        begin
          if(mtvec_areq_i.fetch_exception.valid == 1'b0)
          begin
            // TODO if fetch exception, stay here, try again, hope for someone to fix this asynchronously (ops / other device / ...)
            npc_d = mtvec_areq_i.fetch_paddr;
            isr_table_resolution_state_n = ISR_TABLE_RESOLVE_WAIT_GNT;
          end
        end
      end
      ISR_TABLE_RESOLVE_WAIT_GNT:
      begin
        // no valid address at the moment
        icache_dreq_o.req = 1'b0;
        
        // we temporarily saved the trap base in npc_q
        dcache_req_port_o.address_index = npc_q[CVA6Cfg.DCACHE_INDEX_WIDTH-1:0];
        dcache_req_port_o.address_tag = npc_q[CVA6Cfg.DCACHE_TAG_WIDTH     +
                                              CVA6Cfg.DCACHE_INDEX_WIDTH-1 :
                                              CVA6Cfg.DCACHE_INDEX_WIDTH];
        // can unconditionally do the request
        dcache_req_port_o.data_req = 1'b1;
        // if configured, timer IRQs never constitute IRQs in the sense of Northcape
        dcache_req_port_o.is_irq = in_irq_q;

        if(dcache_req_port_i.data_gnt)
        begin
          isr_table_resolution_state_n = ISR_TABLE_RESOLVE_SEND_TAG;
        end
        
        npc_d = fetch_address;
        
      end
      ISR_TABLE_RESOLVE_SEND_TAG:
      begin
        // no valid address at the moment
        icache_dreq_o.req = 1'b0;

        // we temporarily saved the trap base in npc_q
        dcache_req_port_o.address_index = npc_q[CVA6Cfg.DCACHE_INDEX_WIDTH-1:0];
        dcache_req_port_o.address_tag = npc_q[CVA6Cfg.DCACHE_TAG_WIDTH     +
                                              CVA6Cfg.DCACHE_INDEX_WIDTH-1 :
                                              CVA6Cfg.DCACHE_INDEX_WIDTH];
        // can unconditionally do the request
        dcache_req_port_o.tag_valid = 1'b1;
        // if configured, timer IRQs never constitute IRQs in the sense of Northcape
        dcache_req_port_o.is_irq = in_irq_q;

        isr_table_resolution_state_n = ISR_TABLE_RESOLVE_WAIT_DATA;

        isr_base_n = dcache_req_port_i.data_rdata;

        if(dcache_req_port_i.data_rvalid)
        begin
          isr_table_resolution_state_n = ISR_TABLE_RESOLVED;
          // fetch the data we just got
          fetch_address = isr_base_n;
          npc_d = fetch_address;
          // can start fetching immediately
          icache_dreq_o.req = instr_queue_ready & ~halt_frontend_i;
          if(if_ready)
          begin
            // the cache was able to immediately accept our request for the first bytes of the ISR
            // starting from the next cycle, we can request the following instruction
            // otherwise, risk repeating instructions
            npc_d = {
              fetch_address[CVA6Cfg.VLEN-1:CVA6Cfg.FETCH_ALIGN_BITS] + 1, {CVA6Cfg.FETCH_ALIGN_BITS{1'b0}}
            };
          end
        end
        

      end
      ISR_TABLE_RESOLVE_WAIT_DATA:
      begin
        // no valid address at the moment
        icache_dreq_o.req = 1'b0;
        
        isr_table_resolution_state_n = ISR_TABLE_RESOLVE_WAIT_DATA;

        isr_base_n = dcache_req_port_i.data_rdata;

        if(dcache_req_port_i.data_rvalid)
        begin
          isr_table_resolution_state_n = ISR_TABLE_RESOLVED;
          // fetch the data we just got
          fetch_address = isr_base_n;
          npc_d = fetch_address;
          // can start fetching immediately
          icache_dreq_o.req = instr_queue_ready & ~halt_frontend_i;
          if(if_ready)
          begin
            // the cache was able to immediately accept our request for the first bytes of the ISR
            // starting from the next cycle, we can request the following instruction
            // otherwise, risk repeating instructions
            npc_d = {
              fetch_address[CVA6Cfg.VLEN-1:CVA6Cfg.FETCH_ALIGN_BITS] + 1, {CVA6Cfg.FETCH_ALIGN_BITS{1'b0}}
            };
          end
        end
        
      end
      default:
      begin
      end
    endcase
    
    icache_dreq_o.vaddr = fetch_address;
  end

  logic [CVA6Cfg.FETCH_WIDTH-1:0] icache_data;
  // re-align the cache line
  assign icache_data = icache_dreq_i.data >> {shamt, 4'b0};

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      npc_rst_load_q    <= 1'b1;
      npc_q             <= '0;
      speculative_q     <= '0;
      icache_data_q     <= '0;
      icache_valid_q    <= 1'b0;
      icache_vaddr_q    <= 'b0;
      icache_gpaddr_q   <= 'b0;
      icache_tinst_q    <= 'b0;
      icache_gva_q      <= 1'b0;
      icache_ex_valid_q <= ariane_pkg::FE_NONE;
      btb_q             <= '0;
      bht_q             <= '0;
      if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED)
      begin
        icache_task_id_q<= '0;
        replay_task_id_q<= '0;
        replay_task_id_active_q <= 1'b0;
        if(CVA6Cfg.NORTHCAPE_SCALL_EXTENSION)
        begin
          icache_is_valid_scall_q <= 1'b0;
          icache_is_valid_scall_s_q <= 1'b0;
        end
      end
    end else begin
      npc_rst_load_q <= 1'b0;
      npc_q          <= npc_d;
      speculative_q  <= speculative_d;
      icache_valid_q <= icache_dreq_i.valid && isr_table_resolution_state_q == ISR_TABLE_RESOLVED;
      if (icache_dreq_i.valid && isr_table_resolution_state_q == ISR_TABLE_RESOLVED) begin
        icache_data_q  <= icache_data;
        icache_vaddr_q <= icache_dreq_i.vaddr;
        if (CVA6Cfg.RVH) begin
          icache_gpaddr_q <= icache_dreq_i.ex.tval2[CVA6Cfg.GPLEN-1:0];
          icache_tinst_q  <= icache_dreq_i.ex.tinst;
          icache_gva_q    <= icache_dreq_i.ex.gva;
        end else begin
          icache_gpaddr_q <= 'b0;
          icache_tinst_q  <= 'b0;
          icache_gva_q    <= 1'b0;
        end

        if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED)
        begin
          icache_task_id_q  <= icache_dreq_i.task_id;
          if(CVA6Cfg.NORTHCAPE_SCALL_EXTENSION)
          begin
            icache_is_valid_scall_q <= icache_dreq_i.northcape_is_valid_scall;
            icache_is_valid_scall_s_q <= icache_dreq_i.northcape_is_valid_scall_s;
          end
        end

        // Map the only three exceptions which can occur in the frontend to a two bit enum
        if (CVA6Cfg.MmuPresent && icache_dreq_i.ex.cause == riscv::INSTR_GUEST_PAGE_FAULT) begin
          icache_ex_valid_q <= ariane_pkg::FE_INSTR_GUEST_PAGE_FAULT;
        end else if (CVA6Cfg.MmuPresent && icache_dreq_i.ex.cause == riscv::INSTR_PAGE_FAULT) begin
          icache_ex_valid_q <= ariane_pkg::FE_INSTR_PAGE_FAULT;
        end else if (icache_dreq_i.ex.cause == riscv::INSTR_ACCESS_FAULT) begin
          icache_ex_valid_q <= ariane_pkg::FE_INSTR_ACCESS_FAULT;
        end else begin
          if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED && northcape_enabled_i)
          begin
            /* transition into IRQ regime, but no change of task ID -> could be task ID hijacking attack */
            if(in_irq_n && ~in_irq_q && ~icache_dreq_i.northcape_is_valid_scall_s)
            begin
              icache_ex_valid_q <= ariane_pkg::FE_INSTR_ACCESS_FAULT;
            end
            else
            begin
              icache_ex_valid_q <= ariane_pkg::FE_NONE;
            end
          end
          else
          begin
            icache_ex_valid_q <= ariane_pkg::FE_NONE;
          end
        end
        // save the uppermost prediction
        btb_q <= btb_prediction[CVA6Cfg.INSTR_PER_FETCH-1];
        bht_q <= bht_prediction[CVA6Cfg.INSTR_PER_FETCH-1];
      end
      if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED)
      begin
        if(replay_task_id_active_d)
        begin
          replay_task_id_q  <= replay_task_id_d;
        end
        else
        begin
          replay_task_id_q  <= replay_task_id_q;
        end
        replay_task_id_active_q <= replay_task_id_active_d;
      end
    end
  end

  if (CVA6Cfg.RASDepth == 0) begin
    assign ras_predict = '0;
  end else begin : ras_gen
    ras #(
        .CVA6Cfg(CVA6Cfg),
        .ras_t  (ras_t),
        .DEPTH  (CVA6Cfg.RASDepth)
    ) i_ras (
        .clk_i,
        .rst_ni,
        .flush_bp_i(flush_bp_i),
        .push_i(ras_push),
        .pop_i(ras_pop),
        .data_i(ras_update),
        .data_o(ras_predict)
    );
  end

  //For FPGA, BTB is implemented in read synchronous BRAM
  //while for ASIC, BTB is implemented in D flip-flop
  //and can be read at the same cycle.
  assign vpc_btb = (CVA6Cfg.FpgaEn) ? icache_dreq_i.vaddr : icache_vaddr_q;

  if (CVA6Cfg.BTBEntries == 0) begin
    assign btb_prediction = '0;
  end else begin : btb_gen
    btb #(
        .CVA6Cfg   (CVA6Cfg),
        .btb_update_t(btb_update_t),
        .btb_prediction_t(btb_prediction_t),
        .NR_ENTRIES(CVA6Cfg.BTBEntries)
    ) i_btb (
        .clk_i,
        .rst_ni,
        .flush_bp_i      (flush_bp_i),
        .debug_mode_i,
        .vpc_i           (vpc_btb),
        .btb_update_i    (btb_update),
        .btb_prediction_o(btb_prediction)
    );
  end

  if (CVA6Cfg.BHTEntries == 0) begin
    assign bht_prediction = '0;
  end else begin : bht_gen
    bht #(
        .CVA6Cfg   (CVA6Cfg),
        .bht_update_t(bht_update_t),
        .NR_ENTRIES(CVA6Cfg.BHTEntries)
    ) i_bht (
        .clk_i,
        .rst_ni,
        .flush_bp_i      (flush_bp_i),
        .debug_mode_i,
        .vpc_i           (icache_vaddr_q),
        .bht_update_i    (bht_update),
        .bht_prediction_o(bht_prediction)
    );
  end

  // we need to inspect up to CVA6Cfg.INSTR_PER_FETCH instructions for branches
  // and jumps
  for (genvar i = 0; i < CVA6Cfg.INSTR_PER_FETCH; i++) begin : gen_instr_scan
    instr_scan #(
        .CVA6Cfg(CVA6Cfg)
    ) i_instr_scan (
        .instr_i     (instr[i]),
        .rvi_return_o(rvi_return[i]),
        .rvi_call_o  (rvi_call[i]),
        .rvi_branch_o(rvi_branch[i]),
        .rvi_jalr_o  (rvi_jalr[i]),
        .rvi_jump_o  (rvi_jump[i]),
        .rvi_imm_o   (rvi_imm[i]),
        .rvc_branch_o(rvc_branch[i]),
        .rvc_jump_o  (rvc_jump[i]),
        .rvc_jr_o    (rvc_jr[i]),
        .rvc_return_o(rvc_return[i]),
        .rvc_jalr_o  (rvc_jalr[i]),
        .rvc_call_o  (rvc_call[i]),
        .rvc_imm_o   (rvc_imm[i]),
        .return_from_irq_o(return_from_irq[i])
    );
  end

  instr_queue #(
      .CVA6Cfg(CVA6Cfg),
      .fetch_entry_t(fetch_entry_t)
  ) i_instr_queue (
      .clk_i              (clk_i),
      .rst_ni             (rst_ni),
      .flush_i            (flush_i),
      .instr_i            (instr),                 // from re-aligner
      .addr_i             (addr),                  // from re-aligner
      .exception_i        (icache_ex_valid_q),     // from I$
      .exception_addr_i   (icache_vaddr_q),
      .exception_gpaddr_i (icache_gpaddr_q),
      .exception_tinst_i  (icache_tinst_q),
      .exception_gva_i    (icache_gva_q),
      .predict_address_i  (predict_address),
      .cf_type_i          (cf_type),
      .valid_i            (instruction_valid),     // from re-aligner
      .consumed_o         (instr_queue_consumed),
      .ready_o            (instr_queue_ready),
      .replay_o           (replay),
      .replay_addr_o      (replay_addr),
      .replay_task_id_o   (queue_task_id),
      .fetch_entry_o      (fetch_entry_o),         // to back-end
      .fetch_entry_valid_o(fetch_entry_valid_o),   // to back-end
      .fetch_entry_ready_i(fetch_entry_ready_i),    // to back-end
      .is_irq_i           (in_irq_n),
      .task_id_i          (task_id_realigner),
      .valid_scall_i      (valid_scall_realigner),
      .valid_scall_s_i    (valid_scall_s_realigner)
  );

  // pragma translate_off
`ifndef VERILATOR
  initial begin
    assert (CVA6Cfg.FETCH_WIDTH == 32 || CVA6Cfg.FETCH_WIDTH == 64)
    else $fatal(1, "[frontend] fetch width != not supported");
  end
`endif
  // pragma translate_on
endmodule
