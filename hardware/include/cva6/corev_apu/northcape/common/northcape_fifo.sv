/**
  * Simple synchronous FIFO with first-word fallthrough and associated interface.
  */

interface NorthcapeFifoInterface #(
    parameter FIFO_DATA_WIDTH = -1
) (
    input logic clk_i,
    input logic rst_ni
);
  logic enable_rd;
  logic enable_wr;

  logic is_empty;
  logic is_full;

  logic [FIFO_DATA_WIDTH-1:0] rd_data;
  logic [FIFO_DATA_WIDTH-1:0] wr_data;

  modport FIFO(
      input clk_i, rst_ni, enable_rd, enable_wr, wr_data,
      output rd_data, is_empty, is_full
  );
  modport FIFO_USER(input clk_i, rd_data, is_empty, is_full, output enable_rd, enable_wr, wr_data);


endinterface
/* Same as the above, but with a clocking. Used to work around a tooling bug in Vivado. */
interface NorthcapeFifoInterfaceTest #(
    parameter FIFO_DATA_WIDTH = -1
) (
    input logic clk_i,
    input logic rst_ni
);
  logic enable_rd;
  logic enable_wr;

  logic is_empty;
  logic is_full;

  logic [FIFO_DATA_WIDTH-1:0] rd_data;
  logic [FIFO_DATA_WIDTH-1:0] wr_data;

`ifndef VERILATOR
  // rst_ni not used through clocking
  clocking fifo_clocking @(posedge (clk_i));
    output enable_rd;
    output enable_wr;

    input is_empty;
    input is_full;

    input rd_data;
    output wr_data;
  endclocking
  modport TEST(clocking fifo_clocking);
`endif
  modport FIFO(
      input clk_i, rst_ni, enable_rd, enable_wr, wr_data,
      output rd_data, is_empty, is_full
  );
  modport FIFO_USER(input clk_i, rd_data, is_empty, is_full, output enable_rd, enable_wr, wr_data);


endinterface

module northcape_fifo #(
    parameter FIFO_DATA_WIDTH   = -1,
    parameter FIFO_DEPTH_CLOG_2 = -1
) (
    NorthcapeFifoInterface.FIFO fifo_interface
);
  localparam FIFO_DEPTH = 1 << FIFO_DEPTH_CLOG_2;

  logic [FIFO_DATA_WIDTH-1:0] fifo_in, fifo_out;

  logic [FIFO_DEPTH_CLOG_2-1:0] read_pointer_q, write_pointer_q, read_pointer_d, write_pointer_d;

  logic empty, full;

  northcape_sram_dport #(
      .DATA_WIDTH  (FIFO_DATA_WIDTH),
      .DATA_DEPTH  (FIFO_DEPTH),
      .INIT_TO_ZERO(1'b0),
      .WRITE_FIRST (1'b0)
  ) i_sram_dport (
      .clk_i(fifo_interface.clk_i),
      // A port used for write only
      .a_wdata_i(fifo_in),
      .a_wenable_i(fifo_interface.enable_wr),
      .a_rdata_o(  /*open*/),
      .a_addr_i(write_pointer_q),
      .a_enable_i(fifo_interface.enable_wr),

      // B port used for read only
      .b_wdata_i('0),
      .b_wenable_i(1'b0),
      .b_rdata_o(fifo_out),
      // we must use the NEXT read pointer
      // in case we are reading / consuming the input in this cycle, we would otherwise return the old data one last time
      .b_addr_i(read_pointer_d),
      .b_enable_i(1'b1)
  );

  always_comb begin : emptyFullLogic
    automatic logic [FIFO_DEPTH_CLOG_2-1:0] tmp;
    // force overflow
    tmp = write_pointer_q + 1;

    // consider the following scenarios:
    // no read, no write - empty if read and write pointer in the same spot (e.g., after reset)
    // read, no write - empty if in the NEXT cycle, read will catch up to write -> have to assign now, will otherwise be indicated too late
    // no read, write -> write data needs 1-2 cycles to go through FIFO and output. If FIFO was not empty, need only 1 cycle and will likely keep empty down.
    // If FIFO was empty, will need the same 2 cycles for empty to catch up
    // read and write -> In case where the FIFO is empty or has one word, we will indicate 0 for one extra cycle. Otherwise, only 1 cycle latency.
    empty = (read_pointer_q + fifo_interface.enable_rd == write_pointer_q);
    full = (tmp == read_pointer_q);

    fifo_interface.is_full = full;
  end

  always_comb begin : pointerLogic
    // underflow protection has to use current (not future) values - otherwise, might not advance on last read
    read_pointer_d  = read_pointer_q + (fifo_interface.enable_rd && (read_pointer_q != write_pointer_q));
    write_pointer_d = write_pointer_q + (fifo_interface.enable_wr && !full);
  end

  always_ff @(posedge (fifo_interface.clk_i), negedge (fifo_interface.rst_ni)) begin : fifoFFs
    if (fifo_interface.rst_ni == 0) begin
      read_pointer_q <= '0;
      write_pointer_q <= '0;
      fifo_interface.is_empty <= 1'b1;
    end else begin
      read_pointer_q <= read_pointer_d;
      write_pointer_q <= write_pointer_d;
      fifo_interface.is_empty <= empty;
    end
  end

  assign fifo_interface.rd_data = fifo_out;
  assign fifo_in = fifo_interface.wr_data;
`ifndef ASIC
  property fifo_not_empty_and_full;
    @(posedge fifo_interface.clk_i)
        disable iff (fifo_interface.rst_ni === 0)
        !(fifo_interface.is_full === 1'b1 && fifo_interface.is_empty === 1'b1);
  endproperty

  assert property (fifo_not_empty_and_full);
`endif

endmodule
