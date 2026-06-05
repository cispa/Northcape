/**
  * Wrapper around QARMA-64 implementation.
  */
localparam BLOCK_SIZE_BITS = 64;

`default_nettype wire

interface Qarma64CBCInterface (
    input logic clk_i,
    input logic rst_ni
);

  logic cbc_start;
  logic cbc_done;

  logic [BLOCK_SIZE_BITS-1:0] cbc_block_in;
  logic [BLOCK_SIZE_BITS-1:0] cbc_tweak;

  logic [BLOCK_SIZE_BITS*2-1:0] cbc_key;

  logic [BLOCK_SIZE_BITS-1:0] cbc_tag;

  modport QARMA(
      input clk_i,
      input rst_ni,
      input cbc_start,
      output cbc_done,

      input cbc_block_in,
      input cbc_tweak,
      input cbc_key,
      output cbc_tag
  );
endinterface


module qarma64Wrapper (
    Qarma64CBCInterface.QARMA intf
);

  logic [BLOCK_SIZE_BITS - 1 : 0] current_tag_in_q, current_tag_in_d;
  logic clk_i, rst_ni;
  logic reset_sync_q, reset_sync_d;
  logic ready_out;

  assign clk_i = intf.clk_i;
  assign rst_ni = intf.rst_ni;

  assign intf.cbc_done = ready_out && !reset_sync_q && !intf.cbc_start;


  Qarma64 i_block_cipher (
      .clk(clk_i),
      .reset_n(!reset_sync_q),
      .in(intf.cbc_block_in),
      .tweak(intf.cbc_tweak),
      .key(intf.cbc_key),
      .out(intf.cbc_tag),
      .ready(ready_out)
  );

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : currentTagFF
    if (rst_ni == 0) begin
      reset_sync_q <= 1;
    end else begin
      reset_sync_q <= reset_sync_d;
    end
  end : currentTagFF

  always_comb begin : resetLogic
    unique case (intf.cbc_start)
      1: begin
        reset_sync_d = 1;
      end
      default: begin
        reset_sync_d = intf.cbc_done;
      end
    endcase
  end : resetLogic
endmodule

module qarma64CBC (
    Qarma64CBCInterface.QARMA intf
);

  Qarma64CBCInterface qarma_intf_inner (
      .clk_i (intf.clk_i),
      .rst_ni(intf.rst_ni)
  );

  qarma64Wrapper i_wrapper (qarma_intf_inner);

  logic [BLOCK_SIZE_BITS - 1 : 0] current_tag_in_q, current_tag_in_d;
  logic clk_i, rst_ni;

  // control is simply forwarded
  assign qarma_intf_inner.cbc_start = intf.cbc_start;
  assign qarma_intf_inner.cbc_tweak = intf.cbc_tweak;
  assign qarma_intf_inner.cbc_key = intf.cbc_key;

  assign intf.cbc_tag = qarma_intf_inner.cbc_tag;
  assign intf.cbc_done = qarma_intf_inner.cbc_done;

  // xor-ed with last block
  assign qarma_intf_inner.cbc_block_in = current_tag_in_q ^ intf.cbc_block_in;

  assign clk_i = intf.clk_i;
  assign rst_ni = intf.rst_ni;


  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : currentTagFF
    if (rst_ni == 0) begin
      current_tag_in_q <= '0;
    end else begin
      current_tag_in_q <= current_tag_in_d;
    end
  end : currentTagFF

  always_comb begin : currentTagLogic
    unique case (intf.cbc_start)
      1: begin
        // reset to zero
        current_tag_in_d = '0;
      end
      default: begin
        current_tag_in_d = intf.cbc_tag;
      end
    endcase
  end : currentTagLogic
endmodule
