// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
//
//
// Design Name:    Northcape register file
// Project Name:   Northcape
// Language:       SystemVerilog
//
// Description:    Register file wrapper for Northcape. Distinguishes an IRQ and a non-IRQ register file.
//

module northcape_regfile #(
    parameter config_pkg::cva6_cfg_t CVA6Cfg       = config_pkg::cva6_cfg_empty,
    parameter int unsigned           DATA_WIDTH    = 32,
    parameter int unsigned           NR_READ_PORTS = 2,
    parameter bit                    ZERO_REG_ZERO = 0,
    parameter bit                    EN_IRQ_REG    = 1, // if null, just ignore / zero-out all accesses during IRQ; otherwise, complete second register set for IRQ
    parameter bit                    SHIFT_REG_MASK = 0 // if 0, take low bits for uninit mask, otherwise, high bits
) (
    // clock and reset
    input  logic                                             clk_i,
    input  logic                                             rst_ni,
    // disable clock gates for testing
    input  logic                                             test_en_i,
    // read port
    input  logic [        NR_READ_PORTS-1:0][           4:0] raddr_i,
    output logic [        NR_READ_PORTS-1:0][DATA_WIDTH-1:0] rdata_o,
    // write port
    input  logic [CVA6Cfg.NrCommitPorts-1:0][           4:0] waddr_i,
    input  logic [CVA6Cfg.NrCommitPorts-1:0][DATA_WIDTH-1:0] wdata_i,
    input  logic [CVA6Cfg.NrCommitPorts-1:0]                 we_i,
    input  logic [CVA6Cfg.NrCommitPorts-1:0]                 wreg_mask_i, 
    input  logic [CVA6Cfg.NrCommitPorts-1:0]                 wirq_i,
    // do we want to use the IRQ or the non-IRQ register file?
    input logic                                              is_irq_i,
    //debug
    input logic [CVA6Cfg.VLEN-1:0]                           dbg_instr_pc_i
);

  logic [1:0][NR_READ_PORTS-1:0][DATA_WIDTH-1:0] rdata;
  logic [CVA6Cfg.NrCommitPorts-1:0] we_non_irq, we_irq;

  logic [EN_IRQ_REG:0] [31:0] uninit_mask_d, uninit_mask_q;

  if (CVA6Cfg.FpgaEn) begin : gen_fpga_regfile
    ariane_regfile_fpga #(
        .CVA6Cfg      (CVA6Cfg),
        .DATA_WIDTH   (DATA_WIDTH),
        .NR_READ_PORTS(NR_READ_PORTS),
        .ZERO_REG_ZERO(ZERO_REG_ZERO)
    ) i_ariane_regfile_fpga_no_irq (
        .test_en_i(1'b0),
        .raddr_i  (raddr_i),
        .rdata_o  (rdata[0]),
        .waddr_i  (waddr_i),
        .wdata_i  (wdata_i),
        .we_i     (we_non_irq),
        .*
    );


    if(EN_IRQ_REG) begin : gen_irq_regfile
        ariane_regfile_fpga #(
            .CVA6Cfg      (CVA6Cfg),
            .DATA_WIDTH   (DATA_WIDTH),
            .NR_READ_PORTS(NR_READ_PORTS),
            .ZERO_REG_ZERO(ZERO_REG_ZERO)
        ) i_ariane_regfile_fpga_irq (
            .test_en_i(1'b0),
            .raddr_i  (raddr_i),
            .rdata_o  (rdata[1]),
            .waddr_i  (waddr_i),
            .wdata_i  (wdata_i),
            .we_i     (we_irq),
            .*
        );
    end
    else
    begin : ignore_reg_accesses_during_irq
        // read always returns 0
        // write, address etc. ignored
        assign rdata[1] = '0;
        // unread i_we_non_Irq_unread(we_non_irq);
    end
  end else begin : gen_asic_regfile
    ariane_regfile #(
        .CVA6Cfg      (CVA6Cfg),
        .DATA_WIDTH   (DATA_WIDTH),
        .NR_READ_PORTS(NR_READ_PORTS),
        .ZERO_REG_ZERO(ZERO_REG_ZERO)
    ) i_ariane_regfile_no_irq (
        .test_en_i(1'b0),
        .raddr_i  (raddr_i),
        .rdata_o  (rdata[0]),
        .waddr_i  (waddr_i),
        .wdata_i  (wdata_i),
        .we_i     (we_non_irq),
        .*
    );

    if(EN_IRQ_REG) begin : gen_irq_regfile
        ariane_regfile #(
            .CVA6Cfg      (CVA6Cfg),
            .DATA_WIDTH   (DATA_WIDTH),
            .NR_READ_PORTS(NR_READ_PORTS),
            .ZERO_REG_ZERO(ZERO_REG_ZERO)
        ) i_ariane_regfile_irq (
            .test_en_i(1'b0),
            .raddr_i  (raddr_i),
            .rdata_o  (rdata[1]),
            .waddr_i  (waddr_i),
            .wdata_i  (wdata_i),
            .we_i     (we_irq),
            .*
        );
    end
    else
    begin : ignore_reg_accesses_during_irq
        // read always returns 0
        // write, address etc. ignored
        assign rdata[1] = '0;
        // unread i_we_non_Irq_unread(we_non_irq);
    end
  end

  always_comb begin: regMux
    uninit_mask_d = uninit_mask_q;

    for(int i = 0; i < CVA6Cfg.NrCommitPorts; i++)
    begin
        we_non_irq[i] = wirq_i[i] ? 1'b0 : we_i[i];
        we_irq[i] = wirq_i[i] ? we_i[i] : '0;
    end
    rdata_o = rdata[is_irq_i];

    for(int i = 0; i < NR_READ_PORTS; i++)
    begin
        if(uninit_mask_d[is_irq_i][raddr_i[i]])
        begin
            // uninitialized register - must read 0 to protect confidentiality
            rdata_o[i] = '0;
        end
    end
    for(int i = 0; i < CVA6Cfg.NrCommitPorts; i++)
    begin
        // write always 1 cycle delayed - check old value first
        if(we_i[i])
        begin
            // register was written - can be read again now
            uninit_mask_d[wirq_i[i]][waddr_i[i]] = 1'b0;
        end
    end
    for(int i = 0; i < CVA6Cfg.NrCommitPorts; i++)
    begin
        if(we_i[i] && wreg_mask_i[i])
        begin
            uninit_mask_d[wirq_i[i]] = SHIFT_REG_MASK ? (wdata_i[i] >> 32) : wdata_i[i];
        end
    end
  end: regMux

  generate
    if(CVA6Cfg.NORTHCAPE_REG_CLEAR_EXTENSION)
    begin: gen_uninit_mask
        always_ff @( posedge(clk_i), negedge(rst_ni) ) begin : uninitMaskReg
            if(!rst_ni)
            begin
                uninit_mask_q <= '0;
            end
            else
            begin
                uninit_mask_q <= uninit_mask_d;
            end
        end: uninitMaskReg
    end: gen_uninit_mask
    else
    begin: gen_no_unint_mask
        assign uninit_mask_q = '0;
    end: gen_no_unint_mask

  endgenerate

`ifdef CVA6_DEBUG
cva6_reg_ila i_ila(
    .clk(clk_i),
    .probe0(we_i), // 2 bits
    .probe1(wreg_mask_i), // 2 bits
    .probe2(uninit_mask_d[0]), // 32 bits
    .probe3(uninit_mask_d[1]), // 32 bits
    .probe4(waddr_i[0]), // 5 bits
    .probe5(waddr_i[1]), // 5 bits
    .probe6(wdata_i[0]), // 64 bits
    .probe7(wdata_i[1]), // 64 bits
    .probe8(rdata_o[0]), // 64 bits
    .probe9(rdata_o[1]), // 64 bits
    .probe10(rdata_o[2]), // 64 bits
    .probe11(raddr_i[0]), // 5 bits
    .probe12(raddr_i[1]), // 5 bits
    .probe13(raddr_i[2]), // 5 bits
    .probe14(wirq_i), // 2 bits
    .probe15(is_irq_i), // 1 bit
    .probe16(dbg_instr_pc_i) // 64 bit
);
`endif

endmodule
