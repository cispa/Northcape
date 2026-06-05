/**
  * Cache store buffer - accepts incoming Ops write transactions in one cycle, allowing ops to resume before write commits.
  * Detects read-after-write hazards, stalling the missunit to ensure consistency if needed.
  */
module northcape_capability_cache_store_buffer #(
    parameter int STORE_BUFFER_SIZE = -1,
    parameter bit DEBUG_ILA = 1'b0
) (
    input logic clk_i,
    input logic rst_ni,

    // write interface
    input northcape_types::capability_id_t write_capability_id_i,
    input northcape_types::northcape_cmt_entry_t write_capability_i,
    input logic write_capability_id_valid_i,
    output logic write_accepted_o,

    // hazard interface
    input northcape_types::capability_id_t missunit_capability_id_i,
    output logic store_buffer_hazard_o,

    // read interface
    output northcape_types::capability_id_t write_capability_id_o,
    output northcape_types::northcape_cmt_entry_t write_cmt_entry_o,
    output logic write_valid_o,
    input write_commit_i
);
  import northcape_types::*;

  //===================================
  // declarations and static assignments
  //===================================

  localparam int ROUNDED_NUMBER_ENTRIES = 2 ** ($clog2(STORE_BUFFER_SIZE));
  localparam int NUMBER_BITS_IN_BUFFER_SIZE = $clog2(STORE_BUFFER_SIZE);

  typedef struct packed {
    capability_id_t cap_id;
    logic valid;
  } capability_id_entry_t;

  capability_id_entry_t [ROUNDED_NUMBER_ENTRIES-1:0] capability_sram_d, capability_sram_q;

  logic [NUMBER_BITS_IN_BUFFER_SIZE-1:0] capability_sram_rd_ptr_d, capability_sram_rd_ptr_q;
  logic [NUMBER_BITS_IN_BUFFER_SIZE-1:0] capability_sram_wr_ptr_d, capability_sram_wr_ptr_q;

  NorthcapeFifoInterface #(
      .FIFO_DATA_WIDTH($bits(northcape_cmt_entry_t))
  ) i_fifo_interface (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  // buffer for "large" data (CMT entries)
  northcape_fifo #(
      .FIFO_DATA_WIDTH  ($bits(northcape_cmt_entry_t)),
      .FIFO_DEPTH_CLOG_2($clog2(STORE_BUFFER_SIZE))
  ) i_cmt_buffer (
      .fifo_interface(i_fifo_interface)
  );

  //===================================
  // sequential logic
  //===================================
  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : capabilitySRAMQ
    if (!rst_ni) begin
      capability_sram_q <= '0;
      capability_sram_rd_ptr_q <= '0;
      capability_sram_wr_ptr_q <= '0;
    end else begin
      capability_sram_q <= capability_sram_d;
      capability_sram_rd_ptr_q <= capability_sram_rd_ptr_d;
      capability_sram_wr_ptr_q <= capability_sram_wr_ptr_d;
    end
  end : capabilitySRAMQ



  //===================================
  // combinational logic
  //===================================

  always_comb begin : hazardLogic
    store_buffer_hazard_o = 1'b0;
    for (int i = 0; i < ROUNDED_NUMBER_ENTRIES; i++) begin
      store_buffer_hazard_o |= capability_sram_d[i].valid && capability_sram_d[i].cap_id == missunit_capability_id_i;
    end
  end : hazardLogic

  always_comb begin : capabilitySRAMUpdateLogic
    // default assignments
    capability_sram_d = capability_sram_q;
    capability_sram_rd_ptr_d = capability_sram_rd_ptr_q;
    capability_sram_wr_ptr_d = capability_sram_wr_ptr_q;

    // there is no overflow logic, as we use the empty/full logic of the existing FIFO
    if (!i_fifo_interface.is_full && write_capability_id_valid_i) begin
      capability_sram_d[capability_sram_wr_ptr_d].valid  = 1'b1;
      capability_sram_d[capability_sram_wr_ptr_d].cap_id = write_capability_id_i;
      capability_sram_wr_ptr_d++;
    end

    if (!i_fifo_interface.is_empty && write_commit_i) begin
      capability_sram_d[capability_sram_rd_ptr_d].valid = 1'b0;
      capability_sram_rd_ptr_d++;
    end
  end : capabilitySRAMUpdateLogic

  always_comb begin : writeSideLogic
    i_fifo_interface.enable_wr = 1'b0;
    i_fifo_interface.wr_data = '0;
    write_accepted_o = 1'b0;

    if (!i_fifo_interface.is_full) begin
      i_fifo_interface.enable_wr = write_capability_id_valid_i;
      i_fifo_interface.wr_data = write_capability_i;
      write_accepted_o = write_capability_id_valid_i;
    end
  end : writeSideLogic

  always_comb begin : readSideLogic
    i_fifo_interface.enable_rd = 1'b0;
    write_valid_o = 1'b0;

    write_cmt_entry_o = '0;
    write_capability_id_o = '0;

    if (!i_fifo_interface.is_empty) begin
      write_cmt_entry_o = i_fifo_interface.rd_data;
      write_valid_o = 1'b1;
      i_fifo_interface.enable_rd = write_commit_i;
      write_capability_id_o = capability_sram_d[capability_sram_rd_ptr_q].cap_id;
    end
  end : readSideLogic

  // debug
  generate
    if (DEBUG_ILA) begin : gen_debug_ila
      store_buffer_ila i_ila (
          .clk(clk_i),
          .probe0(write_capability_id_i),  // 38 bits
          .probe1(write_capability_id_valid_i),  // 1 bit
          .probe2(i_fifo_interface.is_full),  // 1 bit
          .probe3(write_accepted_o),  // 1 bit
          .probe4(i_fifo_interface.is_empty),  // 1 bit
          .probe5(write_valid_o),  // 1 bit
          .probe6(write_capability_id_o),  // 38 bits
          .probe7(write_commit_i)  // 1 bit
      );
    end : gen_debug_ila
  endgenerate


endmodule
