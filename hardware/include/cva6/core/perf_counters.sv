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
// Date: 06.10.2017
// Description: Performance counters


module perf_counters
  import ariane_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type bp_resolve_t = logic,
    parameter type dcache_req_i_t = logic,
    parameter type dcache_req_o_t = logic,
    parameter type exception_t = logic,
    parameter type icache_dreq_t = logic,
    parameter type scoreboard_entry_t = logic,
    parameter int unsigned NumPorts = 3  // number of miss ports
) (
    input logic clk_i,
    input logic rst_ni,
    input logic debug_mode_i,  // debug mode
    // SRAM like interface
    input logic [11:0] addr_i,  // read/write address (up to 6 counters possible)
    input logic we_i,  // write enable
    input logic [CVA6Cfg.XLEN-1:0] data_i,  // data to write
    output logic [CVA6Cfg.XLEN-1:0] data_o,  // data to read
    // from commit stage
    input  scoreboard_entry_t [CVA6Cfg.NrCommitPorts-1:0] commit_instr_i,     // the instruction we want to commit
    input  logic [CVA6Cfg.NrCommitPorts-1:0]              commit_ack_i,       // acknowledge that we are indeed committing
    // from L1 caches
    input logic l1_icache_miss_i,
    input logic l1_dcache_miss_i,
    // from MMU
    input logic itlb_miss_i,
    input logic dtlb_miss_i,
    // from issue stage
    input logic sb_full_i,
    // from frontend
    input logic if_empty_i,
    // from PC Gen
    input exception_t ex_i,
    input logic eret_i,
    input bp_resolve_t resolved_branch_i,
    // from Northcape L1
    input logic northcape_l1_data_miss_i,
    input logic northcape_l1_instr_miss_i,
    // from Northcape L2
    input logic northcape_l2_resolver_miss_i,
    input logic northcape_l2_resolver_spec_fail_i,
    input logic northcape_l2_ops_miss_i,
    input logic northcape_cache_missunit_stall_i,
    input logic northcape_ops_write_stall_i,
    // from icache - extra 1-cycle delay due to Northcape
    input logic northcape_delay_i,
    // for newly added events
    input exception_t branch_exceptions_i,  //Branch exceptions->execute unit-> branch_exception_o
    input icache_dreq_t l1_icache_access_i,
    input dcache_req_i_t [2:0] l1_dcache_access_i,
    input  logic [NumPorts-1:0][CVA6Cfg.DCACHE_SET_ASSOC-1:0]miss_vld_bits_i,  //For Cache eviction (3ports-LOAD,STORE,PTW)
    input logic i_tlb_flush_i,
    input logic stall_issue_i,  //stall-read operands
    input logic [31:0] mcountinhibit_i
);

  typedef logic [11:0] csr_addr_t;

  logic [63:0] generic_counter_d[MHPMCounterNum:1];
  logic [63:0] generic_counter_q[MHPMCounterNum:1];

  //internal signal to keep track of exception
  logic read_access_exception, update_access_exception;

  logic events[MHPMCounterNum:1];
  //internal signal for  MUX select line input
  logic [4:0] mhpmevent_d[MHPMCounterNum:1];
  logic [4:0] mhpmevent_q[MHPMCounterNum:1];
  // internal signal to detect event on multiple commit ports
  logic [CVA6Cfg.NrCommitPorts-1:0] load_event;
  logic [CVA6Cfg.NrCommitPorts-1:0] store_event;
  logic [CVA6Cfg.NrCommitPorts-1:0] branch_event;
  logic [CVA6Cfg.NrCommitPorts-1:0] call_event;
  logic [CVA6Cfg.NrCommitPorts-1:0] return_event;
  logic [CVA6Cfg.NrCommitPorts-1:0] int_event;
  logic [CVA6Cfg.NrCommitPorts-1:0] fp_event;

  // extra pipelining to break critical path with Northcape
  logic l1_icache_miss_q;
  logic l1_dcache_miss_q;
  logic itlb_miss_q;
  logic dtlb_miss_q;
  logic load_event_q;
  logic store_event_q;
  logic exception_q;
  logic eret_q;
  logic branch_event_q;
  logic branch_mispredict_q;
  logic branch_exception_q;
  logic call_event_q;
  logic return_event_q;
  logic sb_full_q;
  logic if_empty_q;
  logic icache_access_q;
  logic dcache_access_q;
  logic dcache_eviction_q;
  logic itlb_flush_q;
  logic int_event_q;
  logic fp_event_q;
  logic stall_issue_q;
  logic northcape_l1_instr_miss_q;
  logic northcape_l1_data_miss_q;
  logic northcape_l2_resolver_miss_q;
  logic northcape_l2_ops_miss_q;
  logic northcape_cache_missunit_stall_q;
  logic northcape_ops_write_stall_q;
  logic northcape_l2_resolver_spec_fail_q;
  logic northcape_delay_q;

  //Multiplexer
  always_comb begin : Mux
    events[MHPMCounterNum:1] = '{default: 0};
    load_event = '{default: 0};
    store_event = '{default: 0};
    branch_event = '{default: 0};
    call_event = '{default: 0};
    return_event = '{default: 0};
    int_event = '{default: 0};
    fp_event = '{default: 0};

    for (int unsigned j = 0; j < CVA6Cfg.NrCommitPorts; j++) begin
      load_event[j] = commit_ack_i[j] & (commit_instr_i[j].fu == LOAD);
      store_event[j] = commit_ack_i[j] & (commit_instr_i[j].fu == STORE);
      branch_event[j] = commit_ack_i[j] & (commit_instr_i[j].fu == CTRL_FLOW);
      call_event[j] = commit_ack_i[j] & (commit_instr_i[j].fu == CTRL_FLOW && (commit_instr_i[j].op == ADD || commit_instr_i[j].op == JALR) && (commit_instr_i[j].rd == 'd1 || commit_instr_i[j].rd == 'd5));
      return_event[j] = commit_ack_i[j] & (commit_instr_i[j].op == JALR && commit_instr_i[j].rd == 'd0);
      int_event[j] = commit_ack_i[j] & (commit_instr_i[j].fu == ALU || commit_instr_i[j].fu == MULT);
      fp_event[j] = commit_ack_i[j] & (commit_instr_i[j].fu == FPU || commit_instr_i[j].fu == FPU_VEC);
    end

    for (int unsigned i = 1; i <= MHPMCounterNum; i++) begin
      case (mhpmevent_q[i])
        5'b00000: events[i] = 0;
        5'b00001: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? l1_icache_miss_q : l1_icache_miss_i;  //L1 I-Cache misses
        5'b00010: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? l1_dcache_miss_q : l1_dcache_miss_i;  //L1 D-Cache misses
        5'b00011: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? itlb_miss_q : itlb_miss_i;  //ITLB misses
        5'b00100: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? dtlb_miss_q : dtlb_miss_i;  //DTLB misses
        5'b00101: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? load_event_q : |load_event;  //Load accesses
        5'b00110: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? store_event_q : |store_event;  //Store accesses
        5'b00111: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? exception_q : ex_i.valid;  //Exceptions
        5'b01000: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? eret_q : eret_i;  //Exception handler returns
        5'b01001: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? branch_event_q : |branch_event;  // Branch instructions
        5'b01010:
        events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? branch_mispredict_q : resolved_branch_i.valid && resolved_branch_i.is_mispredict;//Branch mispredicts
        5'b01011: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? branch_exception_q : branch_exceptions_i.valid;  //Branch exceptions
        // The standard software calling convention uses register x1 to hold the return address on a call
        // the unconditional jump is decoded as ADD op
        5'b01100: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? call_event_q : |call_event;  //Call
        5'b01101: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? return_event_q : |return_event;  //Return
        5'b01110: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? sb_full_q : sb_full_i;  //MSB Full
        5'b01111: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? if_empty_q : if_empty_i;  //Instruction fetch Empty
        5'b10000: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? icache_access_q : l1_icache_access_i.req;  //L1 I-Cache accesses
        5'b10001:
        events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? dcache_access_q : l1_dcache_access_i[0].data_req || l1_dcache_access_i[1].data_req || l1_dcache_access_i[2].data_req;//L1 D-Cache accesses
        5'b10010:
        events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? dcache_eviction_q : (l1_dcache_miss_i && miss_vld_bits_i[0] == 8'hFF) || (l1_dcache_miss_i && miss_vld_bits_i[1] == 8'hFF) || (l1_dcache_miss_i && miss_vld_bits_i[2] == 8'hFF);//eviction
        5'b10011: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? itlb_flush_q : i_tlb_flush_i;  //I-TLB flush
        5'b10100: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? int_event_q : |int_event;  //Integer instructions
        5'b10101: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? fp_event_q : |fp_event;  //Floating Point Instructions
        5'b10110: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? stall_issue_q : stall_issue_i;  //Pipeline bubbles
        5'b10111: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? northcape_l1_instr_miss_q : northcape_l1_instr_miss_i;  //Northcape cva6 instruction MMU misses
        5'b11000: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? northcape_l1_data_miss_q : northcape_l1_data_miss_i;  //Northcape cva6 data MMU misses
        5'b11001: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? northcape_l2_resolver_miss_q : northcape_l2_resolver_miss_i;  //Northcape cache misses (resolver port)
        5'b11010: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? northcape_l2_ops_miss_q : northcape_l2_ops_miss_i;  //Northcape cache misses (ops port)
        5'b11011: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? northcape_delay_q : northcape_delay_i ; // Northcape caused 1-cycle extra delay in icache
        5'b11100: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? northcape_cache_missunit_stall_q : northcape_cache_missunit_stall_i; // Northcape stalled the resolver waiting for ops to commit
        5'b11101: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? northcape_ops_write_stall_q : northcape_ops_write_stall_i; // An ops write was stalled due to lack of write buffer space
        5'b11110: events[i] = CVA6Cfg.NORTHCAPE_STAGE_ENABLED ? northcape_l2_resolver_spec_fail_q : northcape_l2_resolver_spec_fail_i; // The Northcape l2 TLB had to be flushed completely due to a speculation failure
        default: events[i] = 0;
      endcase
    end

  end

  always_comb begin : generic_counter
    generic_counter_d = generic_counter_q;
    data_o = 'b0;
    mhpmevent_d = mhpmevent_q;
    read_access_exception = 1'b0;
    update_access_exception = 1'b0;

    // Increment the non-inhibited counters with active events
    for (int unsigned i = 1; i <= 6; i++) begin
      if ((!debug_mode_i) && (!we_i)) begin
        if ((events[i]) == 1 && (!mcountinhibit_i[i+2])) begin
          generic_counter_d[i] = generic_counter_q[i] + 1'b1;
        end
      end
    end

    //Read
    if( (addr_i >= csr_addr_t'(riscv::CSR_MHPM_COUNTER_3)) && (addr_i < ( csr_addr_t'(riscv::CSR_MHPM_COUNTER_3) + MHPMCounterNum)) ) begin
      if (riscv::XLEN == 32) begin
        data_o = generic_counter_q[addr_i-riscv::CSR_MHPM_COUNTER_3+1][31:0];
      end else begin
        data_o = generic_counter_q[addr_i-riscv::CSR_MHPM_COUNTER_3+1];
      end
    end else if( (addr_i >= csr_addr_t'(riscv::CSR_MHPM_COUNTER_3H)) && (addr_i < ( csr_addr_t'(riscv::CSR_MHPM_COUNTER_3H) + MHPMCounterNum)) ) begin
      if (riscv::XLEN == 32) begin
        data_o = generic_counter_q[addr_i-riscv::CSR_MHPM_COUNTER_3H+1][63:32];
      end else begin
        read_access_exception = 1'b1;
      end
    end else if( (addr_i >= csr_addr_t'(riscv::CSR_MHPM_EVENT_3)) && (addr_i < (csr_addr_t'(riscv::CSR_MHPM_EVENT_3) + MHPMCounterNum)) ) begin
      data_o = mhpmevent_q[addr_i-riscv::CSR_MHPM_EVENT_3+1];
    end else if( (addr_i >= csr_addr_t'(riscv::CSR_HPM_COUNTER_3)) && (addr_i < (csr_addr_t'(riscv::CSR_HPM_COUNTER_3) + MHPMCounterNum)) ) begin
      if (riscv::XLEN == 32) begin
        data_o = generic_counter_q[addr_i-riscv::CSR_HPM_COUNTER_3+1][31:0];
      end else begin
        data_o = generic_counter_q[addr_i-riscv::CSR_HPM_COUNTER_3+1];
      end
    end else if( (addr_i > csr_addr_t'(riscv::CSR_HPM_COUNTER_3H)) && (addr_i < (csr_addr_t'(riscv::CSR_HPM_COUNTER_3H) + MHPMCounterNum)) ) begin
      if (riscv::XLEN == 32) begin
        data_o = generic_counter_q[addr_i-riscv::CSR_MHPM_COUNTER_3H+1][63:32];
      end else begin
        read_access_exception = 1'b1;
      end
    end

    //Write
    if (we_i) begin
      if( (addr_i >= csr_addr_t'(riscv::CSR_MHPM_COUNTER_3)) && (addr_i < (csr_addr_t'(riscv::CSR_MHPM_COUNTER_3) + MHPMCounterNum)) ) begin
        if (riscv::XLEN == 32) begin
          generic_counter_d[addr_i-riscv::CSR_MHPM_COUNTER_3+1][31:0] = data_i;
        end else begin
          generic_counter_d[addr_i-riscv::CSR_MHPM_COUNTER_3+1] = data_i;
        end
      end else if( (addr_i >= csr_addr_t'(riscv::CSR_MHPM_COUNTER_3H)) && (addr_i < (csr_addr_t'(riscv::CSR_MHPM_COUNTER_3H) + MHPMCounterNum)) ) begin
        if (riscv::XLEN == 32) begin
          generic_counter_d[addr_i-riscv::CSR_MHPM_COUNTER_3H+1][63:32] = data_i;
        end else begin
          update_access_exception = 1'b1;
        end
      end else if( (addr_i >= csr_addr_t'(riscv::CSR_MHPM_EVENT_3)) && (addr_i < csr_addr_t'(riscv::CSR_MHPM_EVENT_3) + MHPMCounterNum) ) begin
        mhpmevent_d[addr_i-riscv::CSR_MHPM_EVENT_3+1] = data_i;
      end
    end
  end

  //Registers
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      generic_counter_q <= '{default: 0};
      mhpmevent_q       <= '{default: 0};
      if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED)
      begin
        l1_icache_miss_q <= 1'b0;
        l1_dcache_miss_q <= 1'b0;
        itlb_miss_q <= 1'b0;
        dtlb_miss_q <= 1'b0;
        load_event_q <= 1'b0;
        store_event_q <= 1'b0;
        exception_q <= 1'b0;
        eret_q <= 1'b0;
        branch_event_q <= 1'b0;
        branch_mispredict_q <= 1'b0;
        branch_exception_q <= 1'b0;
        call_event_q <= 1'b0;
        return_event_q <= 1'b0;
        sb_full_q <= 1'b0;
        if_empty_q <= 1'b0;
        icache_access_q <= 1'b0;
        dcache_access_q <= 1'b0;
        dcache_eviction_q <= 1'b0;
        itlb_flush_q <= 1'b0;
        int_event_q <= 1'b0;
        fp_event_q <= 1'b0;
        stall_issue_q <= 1'b0;
        northcape_l1_instr_miss_q <= 1'b0;
        northcape_l1_data_miss_q <= 1'b0;
        northcape_l2_resolver_miss_q <= 1'b0;
        northcape_l2_ops_miss_q <= 1'b0;
        northcape_cache_missunit_stall_q <= 1'b0;
        northcape_ops_write_stall_q <= 1'b0;
        northcape_l2_resolver_spec_fail_q <= 1'b0;
        northcape_delay_q <= 1'b0;
      end
    end else begin
      generic_counter_q <= generic_counter_d;
      mhpmevent_q       <= mhpmevent_d;
      if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED)
      begin
        l1_icache_miss_q <= l1_icache_miss_i;
        l1_dcache_miss_q <= l1_dcache_miss_i;
        itlb_miss_q <= itlb_miss_i;
        dtlb_miss_q <= dtlb_miss_i;
        load_event_q <= |load_event;
        store_event_q <= |store_event;
        exception_q <= ex_i.valid;
        eret_q <= eret_i;
        branch_event_q <= |branch_event;
        branch_mispredict_q <= resolved_branch_i.valid && resolved_branch_i.is_mispredict;
        branch_exception_q <= branch_exceptions_i.valid;
        call_event_q <= |call_event;
        return_event_q <= |return_event;
        sb_full_q <= sb_full_i;
        if_empty_q <= if_empty_i;
        icache_access_q <= l1_icache_access_i.req;
        dcache_access_q <= l1_dcache_access_i[0].data_req || l1_dcache_access_i[1].data_req || l1_dcache_access_i[2].data_req;
        dcache_eviction_q <= (l1_dcache_miss_i && miss_vld_bits_i[0] == 8'hFF) || (l1_dcache_miss_i && miss_vld_bits_i[1] == 8'hFF) || (l1_dcache_miss_i && miss_vld_bits_i[2] == 8'hFF);
        itlb_flush_q <= i_tlb_flush_i;
        int_event_q <= |int_event;
        fp_event_q <= |fp_event;
        stall_issue_q <= stall_issue_i;
        northcape_l1_instr_miss_q <= northcape_l1_instr_miss_i;
        northcape_l1_data_miss_q <= northcape_l1_data_miss_i;
        northcape_l2_resolver_miss_q <= northcape_l2_resolver_miss_i;
        northcape_l2_ops_miss_q <= northcape_l2_ops_miss_i;
        northcape_cache_missunit_stall_q <= northcape_cache_missunit_stall_i;
        northcape_ops_write_stall_q <= northcape_ops_write_stall_i;
        northcape_l2_resolver_spec_fail_q <= northcape_l2_resolver_spec_fail_i;
        northcape_delay_q <= northcape_delay_i;
      end
    end
  end

endmodule
