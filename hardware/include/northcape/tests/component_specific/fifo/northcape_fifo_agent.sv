/**
 * Agent for Northcape FIFO verification.
 */
package northcape_fifo_agent;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class automatic NorthcapeFifoAgent #(
      parameter FIFO_DATA_WIDTH   = -1,
      parameter FIFO_DEPTH_CLOG_2 = -1,

      parameter string FIFO_INTERFACE_NAME = ""
  ) extends uvm_agent;
    typedef logic [FIFO_DATA_WIDTH-1:0] fifo_entry_t;

    typedef virtual NorthcapeFifoInterfaceTest #(.FIFO_DATA_WIDTH(FIFO_DATA_WIDTH)) fifo_intf_t;

    fifo_intf_t fifo_intf;

    fifo_entry_t wr_data, rd_data;

    logic enable_wr;
    logic enable_rd;

    localparam TEST_ITERATIONS = (1 << 20);

    localparam string COMPONENT_NAME = "Northcape FIFO Agent";

    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(fifo_intf_t)::get(null, "", FIFO_INTERFACE_NAME, fifo_intf)) begin
        `uvm_fatal(COMPONENT_NAME, "Could not get FIFO interface!");
      end
    endfunction

    task run_phase(uvm_phase phase);
      fifo_entry_t golden_sample[$:(1<<FIFO_DEPTH_CLOG_2)-1];
      bit do_read;
      bit do_write;
      int unsigned rnd;

      phase.raise_objection(this);

      for (int i = 0; i < TEST_ITERATIONS; i++) begin
        rnd = $urandom();
        do_read = rnd[0];
        do_write = rnd[1];

        fifo_intf.fifo_clocking.wr_data <= rnd;

        `uvm_info(COMPONENT_NAME, $sformatf("Test %d of %d", (i + 1), TEST_ITERATIONS), UVM_MEDIUM);

        if (fifo_intf.fifo_clocking.is_empty != (golden_sample.size() == 0)) begin
          `uvm_error(COMPONENT_NAME, $sformatf(
                     "Empty disagreement - FIFO empty %b golden sample empty %b",
                     fifo_intf.fifo_clocking.is_empty,
                     golden_sample.size() == 0
                     ));
        end
        if(fifo_intf.fifo_clocking.is_full != (golden_sample.size() == (1<<FIFO_DEPTH_CLOG_2)-1))
                begin
          `uvm_error(COMPONENT_NAME, $sformatf(
                     "Full disagreement - FIFO full %b golden sample full %b",
                     fifo_intf.fifo_clocking.is_full,
                     golden_sample.size() == (1 << FIFO_DEPTH_CLOG_2) - 1
                     ));
        end

        if (do_read && !fifo_intf.fifo_clocking.is_empty) begin
          bit [FIFO_DATA_WIDTH-1:0] sample_data;
          fifo_intf.fifo_clocking.enable_rd <= 1;

          sample_data = golden_sample.pop_front();

          if (fifo_intf.fifo_clocking.rd_data !== sample_data) begin
            `uvm_error(
                COMPONENT_NAME, $sformatf(
                "Expected rd data %x but got %x", sample_data, fifo_intf.fifo_clocking.rd_data));
          end
        end

        if (do_write && !fifo_intf.fifo_clocking.is_full) begin
          fifo_intf.fifo_clocking.enable_wr <= 1;

          golden_sample.push_back(rnd);
        end

        @(fifo_intf.fifo_clocking);

        // we sample the outputs BEFORE the clock cycle
        // hence, need to make sure at least one clock has passed
        // at the same time, cannot leak the write signal
        fifo_intf.fifo_clocking.enable_wr <= 0;
        fifo_intf.fifo_clocking.enable_rd <= 0;

        // 1-cycle latency
        @(fifo_intf.fifo_clocking);
        @(fifo_intf.fifo_clocking);

        @(fifo_intf.fifo_clocking);
      end

      phase.drop_objection(this);
    endtask

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

endpackage
