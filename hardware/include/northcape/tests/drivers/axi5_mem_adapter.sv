import northcape_sparse_mem_sim::*;
/**
 * Memory simulator - interfaces a simulation memory with an AXI slave port.
 */
module axi5_mem_adapter #(
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH   = -1,
    parameter AXI_USER_WIDTH = -1,

    parameter type MEM_TYPE = logic,

    localparam type INDEX_TYPE = logic [AXI_ADDR_WIDTH-1:0],
    localparam type DATA_TYPE  = logic [AXI_DATA_WIDTH-1:0]

) (
    input logic clk_i,
    input logic rst_ni,

    // this is used to simulate the CMT
    // in some cases, e.g., revocation, might mix writes to main memory and CMT on one interface
    // we ignore these writes - the hardware configuration normally makes sure that they cannot happen
    input logic ignore_write_i,

    Axi5.TO axi_slave,

    MEM_TYPE memory_i
);
  import axi5::*;
  import northcape_test::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam COMPONENT_NAME = "Axi5 Mem Adapter";


  logic in_read_transfer, last_in_read_transfer, in_write_transfer;

  // address that was requested for write
  INDEX_TYPE write_addr;

  // number of beats in read transfer
  axi_len_t read_beats, processed_read_beats;

  // queues with read/write data
  DATA_TYPE written_data[$];
  DATA_TYPE read_data[$];

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : ARChannelFFLogic
    if (rst_ni == 0) begin
      axi_slave.arready <= 0;
      read_beats <= 0;
      in_read_transfer <= 0;
    end else begin
      if (axi_slave.arvalid && !in_read_transfer) begin
        read_data  <= memory_i.read_mem(axi_slave.araddr, axi_slave.arlen + 1);
        read_beats <= axi_slave.arlen + 1;
        if (axi_slave.arburst != INCR) begin
          `uvm_fatal(COMPONENT_NAME, $sformatf(
                     "Unsupported AXI Read burst: %s!", axi_slave.arburst.name()));
        end
        axi_slave.arready <= 1;
        in_read_transfer  <= 1;
      end else begin
        axi_slave.arready <= 0;
        in_read_transfer <= in_read_transfer && !(axi_slave.rvalid && axi_slave.rready && axi_slave.rlast);
      end
    end
  end

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : AWChannelFFLogic
    if (rst_ni == 0) begin
      write_addr <= '0;
      axi_slave.awready <= 0;
      in_write_transfer <= 0;
    end else begin
      if (axi_slave.awvalid && !in_write_transfer) begin
        write_addr <= axi_slave.awaddr;
        if (axi_slave.awburst != INCR) begin
          `uvm_fatal(COMPONENT_NAME, $sformatf(
                     "Unsupported AXI Write burst: %s!", axi_slave.awburst.name()));
        end
        axi_slave.awready <= 1;
        in_write_transfer <= 1;
      end else begin
        axi_slave.awready <= 0;
        in_write_transfer <= in_write_transfer && !(axi_slave.bvalid && axi_slave.bready);
      end
    end
  end


  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : RChannelFFLogic
    if (rst_ni == 0) begin
      processed_read_beats <= 0;

      axi_slave.rdata <= '0;

      axi_slave.rvalid <= 0;
      axi_slave.rlast <= 0;
      axi_slave.rresp <= SLVERR;
      last_in_read_transfer <= 0;
    end else begin
      last_in_read_transfer <= in_read_transfer;
      if (in_read_transfer) begin
        automatic logic is_last;

        is_last = (processed_read_beats == read_beats - 1);
        axi_slave.rvalid <= !(axi_slave.rvalid && axi_slave.rready && axi_slave.rlast);
        if (axi_slave.rready || last_in_read_transfer === 1'b0) begin
          if (axi_slave.rvalid && axi_slave.rready && axi_slave.rlast) begin
            // no data left!
            axi_slave.rdata <= '0;
          end else begin
            // beat accepted or no data provided yet - get next data
            axi_slave.rdata <= read_data.pop_front();
          end
        end
        axi_slave.rlast <= is_last;
        axi_slave.rresp <= OKAY;

        processed_read_beats <= processed_read_beats + (axi_slave.rvalid && axi_slave.rready);

      end else begin
        axi_slave.rvalid <= 0;
        axi_slave.rlast <= 0;
        axi_slave.rresp <= SLVERR;
        processed_read_beats <= 0;
      end
    end
  end

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : WChannelFFLogic
    if (rst_ni == 0) begin
      axi_slave.wready <= 0;
    end else begin
      if (in_write_transfer) begin
        axi_slave.wready <= !(axi_slave.wvalid && axi_slave.wready && axi_slave.wlast);

        if (axi_slave.wvalid && axi_slave.wready) begin
          written_data.push_back(axi_slave.wdata);
        end
        if (axi_slave.wvalid && axi_slave.wready && axi_slave.wlast) begin
          automatic DATA_TYPE tmp[$];
          tmp = written_data;
          written_data = {};
          if (!ignore_write_i) begin
            memory_i.write_mem(write_addr, tmp);
          end
        end
      end else begin
        axi_slave.wready <= 0;
      end
    end
  end

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : BChannelFFLogic
    if (rst_ni == 0) begin
      axi_slave.bvalid <= 0;
    end else begin
      if (in_write_transfer) begin
        axi_slave.bvalid <= (axi_slave.wvalid && axi_slave.wready && axi_slave.wlast);
        axi_slave.bresp  <= OKAY;
      end else begin
        axi_slave.bvalid <= 0;
      end
    end
  end


endmodule
