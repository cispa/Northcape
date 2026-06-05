`include "northcape_xilinx_wrapper.vh"

import axi5::*;

/**
  * A simple (optionally malicious) DMA.
  */
module northcape_confused_deputy_dma #(
    // AXI parameters
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_LITE_ADDR_WIDTH = -1,
    parameter AXI_LITE_DATA_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,

    // backdoor parameters :evil:
    parameter logic ENABLE_BACKDOOR = 1,
    parameter logic [AXI_DATA_WIDTH - 1 : 0] BACKDOOR_WRITE_ADDRESS = 64'hfacecafe,
    parameter logic [AXI_DATA_WIDTH - 1 : 0] BACKDOOR_WRITE_WORD = 64'hfeedbeef,
    parameter logic [AXI_DATA_WIDTH / 8 - 1 : 0] BACKDOOR_WRITE_MASK = 8'hfe,

    parameter logic [AXI_DATA_WIDTH - 1 : 0] BACKDOOR_TRIGGER_ADDRESS = 64'hdecade00,
    parameter logic [AXI_DATA_WIDTH - 1 : 0] BACKDOOR_TRIGGER_ADDRESS_MASK = 64'hffffffffffffff00

) (
    input logic clk_i,
    input logic rst_ni,

    // AXI LITE interface for registers
    Axi5Lite axi_slave,

    // AXI Master Interface 
    Axi5 axi_master
);

  //===================================
  // Declarations
  //===================================

  typedef enum {
    IDLE,
    SETUP_READ,
    SETUP_WRITE,
    READ_WORD,
    WRITE_WORD,
    GET_RESPONSE,
    BACKDOOR_SETUP_WRITE,
    BACKDOOR_DO_WRITE
  } dma_state_t;

  dma_state_t current_dma_state, next_dma_state;

  logic transfer_status_ready_out;
  logic transfer_status_running;

  logic [AXI_DATA_WIDTH-1:0] transfer_start_addr;
  logic [AXI_DATA_WIDTH-1:0] transfer_dest_addr;
  logic [AXI_DATA_WIDTH-1:0] transfer_length;
  logic transfer_start;


  localparam NUM_REGS = 4;

  NorthcapeRegInterfaceIO #(
      .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
      .NUM_REGS(NUM_REGS)
  ) reg_interface (
      .clk_i(clk_i)
  );

  // conservative: writes can be merged, but transaction needs to make it to final destination
  localparam axi_cache_t transaction_cache_type = 4'b0010;

  // used to ensure ordering of read and write transaction for the same transfer
  logic [AXI_ID_WIDTH  - 1 : 0] current_transaction_id;

  logic [AXI_DATA_WIDTH-1:0] word_buffer;
  logic is_last_transfer;

  axi_resp_t last_response_read, last_response_write;

  logic read_error;

  logic backdoor_executed, backdoor_match;

`ifdef NORTHCAPE_TEST_COVERAGE
  covergroup confused_deputy_dma_covergroup @(posedge (clk_i));
    coverpoint current_dma_state;

    cov_dst_addr: coverpoint transfer_dest_addr[2:0] {
      bins offset_zero = {3'h0};
      bins offset_one = {3'h1};
      bins offset_two = {3'h2};
      bins offset_three = {3'h3};
      bins offset_four = {3'h4};
      bins offset_five = {3'h5};
      bins offset_six = {3'h6};
      bins offset_seven = {3'h7};
    }

    coverpoint transfer_length;
    coverpoint current_transaction_id;
    coverpoint last_response_read;
    coverpoint last_response_write;
    coverpoint read_error;
    coverpoint backdoor_executed;
    coverpoint backdoor_match;
  endgroup

  confused_deputy_dma_covergroup cov_group;

  initial begin
    cov_group = new;
  end
`endif

  //===================================
  // MMIO Interface
  //===================================


  northcape_reg_interface #(
      .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
      .NUM_REGS(NUM_REGS)
  ) i_northcape_reg_interface (
      .s_axi(axi_slave),
      .reg_intf(reg_interface)
  );

  //===================================
  // Sequential logic
  //===================================

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : currentDMAStateFFLogic
    if (rst_ni == 0) begin
      current_dma_state <= IDLE;
    end else begin
      current_dma_state <= next_dma_state;
    end
  end : currentDMAStateFFLogic

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : axiInterfaceFFLogic
    if (rst_ni == 0) begin
      static logic [31:0] size_full_precision = $clog2(AXI_DATA_WIDTH / 8);
      axi_master.arid <= '0;
      axi_master.araddr <= '0;
      axi_master.arlen <= '0;
      axi_master.arsize <= size_full_precision[2:0];
      axi_master.arburst <= INCR;
      axi_master.arlock <= 0;
      axi_master.arcache <= transaction_cache_type;
      // unprivileged, data access
      axi_master.arprot <= '0;
      // unused / don't care
      axi_master.arqos <= '0;
      axi_master.arregion <= '0;
      axi_master.aruser <= '0;
      axi_master.arvalid <= 0;

      axi_master.awid <= '0;
      axi_master.awaddr <= '0;
      axi_master.awlen <= '0;
      axi_master.awsize <= size_full_precision[2:0];
      axi_master.awburst <= INCR;
      axi_master.awlock <= 0;
      axi_master.awcache <= transaction_cache_type;
      // unprivileged, data access
      axi_master.awprot <= '0;
      // unused / don't care
      axi_master.awqos <= '0;
      axi_master.awregion <= '0;
      axi_master.awuser <= '0;

      axi_master.rready <= 0;

      axi_master.wid <= '0;
      axi_master.wdata <= '0;
      // default: all valid
      axi_master.wstrb <= '1;
      axi_master.wlast <= 0;
      axi_master.wuser <= '0;
      axi_master.wvalid <= 0;

      axi_master.bready <= 0;

      // unused
      axi_master.atop_type <= ATOMIC_NONE;
      axi_master.atop_subtype <= '0;

      word_buffer <= '0;
      is_last_transfer <= 0;

      read_error <= 0;

      backdoor_executed <= 0;
      backdoor_match <= 0;
    end else begin
      logic [63:0] len_full_prec;

      len_full_prec = transfer_length / (1 << axi_master.arsize);
      // axi lenght starts from 0 for 1 transfer
      if ((transfer_length % (AXI_DATA_WIDTH / 8) == 0) && transfer_length != '0) begin
        len_full_prec = len_full_prec - 1;
      end

      unique case (current_dma_state)
        SETUP_READ: begin
          axi_master.arid <= current_transaction_id;
          axi_master.araddr <= transfer_start_addr;
          // size bytes per transfer and one transfer added implicitly
          axi_master.arlen <= len_full_prec[7:0];
          axi_master.arvalid <= !axi_master.arvalid || !axi_master.arready;

          if((transfer_start_addr & BACKDOOR_TRIGGER_ADDRESS_MASK) == (BACKDOOR_TRIGGER_ADDRESS & BACKDOOR_TRIGGER_ADDRESS_MASK))
                begin
            backdoor_match <= 1;
          end else begin
            backdoor_match <= 0;
          end

        end
        SETUP_WRITE: begin
          axi_master.awid <= current_transaction_id;
          axi_master.awaddr <= transfer_dest_addr;
          axi_master.awlen <= len_full_prec[7:0];
          axi_master.awvalid <= !axi_master.awvalid || !axi_master.awready;
        end
        READ_WORD: begin
          axi_master.rready <= !axi_master.rvalid || !axi_master.rready;
          word_buffer <= axi_master.rdata;
          is_last_transfer <= axi_master.rlast;

          read_error <= (axi_master.rresp != OKAY && axi_master.rresp != EXOKAY);
        end
        WRITE_WORD: begin
          axi_master.wvalid <= !axi_master.wvalid || !axi_master.wready;
          axi_master.wdata <= word_buffer;
          axi_master.wlast <= is_last_transfer;
          axi_master.wid <= current_transaction_id;
          if (is_last_transfer && transfer_length % (AXI_DATA_WIDTH / 8) != 0) begin
            // need to mask out bits over the end of the transfer
            logic [AXI_DATA_WIDTH / 8 - 1 : 0] last_strobe;
            logic [AXI_DATA_WIDTH - 1 : 0] bytes_last_strobe;

            bytes_last_strobe = transfer_length % (AXI_DATA_WIDTH / 8);
            last_strobe = bytes_last_strobe[AXI_DATA_WIDTH/8-1 : 0];
            last_strobe = (1 << last_strobe) - 1;

            axi_master.wstrb <= read_error ? '0 : last_strobe;
          end else if (read_error) begin
            axi_master.wstrb <= '0;
          end else begin
            axi_master.wstrb <= '1;
          end
        end
        GET_RESPONSE: begin
          axi_master.bready <= !axi_master.bvalid || !axi_master.bready;
        end
        BACKDOOR_SETUP_WRITE: begin
          axi_master.awid <= current_transaction_id;
          axi_master.awaddr <= BACKDOOR_WRITE_ADDRESS;
          axi_master.awlen <= 0;
          axi_master.awvalid <= !axi_master.awvalid || !axi_master.awready;
        end
        BACKDOOR_DO_WRITE: begin
          axi_master.wvalid <= !axi_master.wvalid || !axi_master.wready;
          axi_master.wdata <= BACKDOOR_WRITE_WORD;
          axi_master.wlast <= 1;
          axi_master.wstrb <= BACKDOOR_WRITE_MASK;
          axi_master.wid <= current_transaction_id;

          // should never be executed twice
          backdoor_executed <= 1;
        end
        default: begin
          axi_master.arvalid <= 0;
          axi_master.awvalid <= 0;
          axi_master.rready  <= 0;
          axi_master.wvalid  <= 0;
          axi_master.bready  <= 0;

          is_last_transfer   <= 0;
        end
      endcase

    end
  end : axiInterfaceFFLogic

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : currentTransactionIDFFLogic
    if (rst_ni == 0) begin
      current_transaction_id <= '0;
    end else begin
      if (current_dma_state == GET_RESPONSE && next_dma_state == IDLE) begin
        current_transaction_id <= current_transaction_id + 1;
      end
    end

  end : currentTransactionIDFFLogic

  always_ff @(posedge (clk_i), negedge (rst_ni)) begin : currentTransactionResultFFLogic
    if (rst_ni == 0) begin
      last_response_read  <= OKAY;
      last_response_write <= OKAY;
    end else begin
      if (current_dma_state == READ_WORD && axi_master.rvalid) begin
        last_response_read <= axi_master.rresp;
      end else if (current_dma_state == GET_RESPONSE && axi_master.bvalid) begin
        last_response_write <= axi_master.bresp;
      end
        else if(current_dma_state == IDLE && axi_slave.araddr == '0 && axi_slave.arvalid && axi_slave.arready)
        begin
        // status has been read - can clear responses
        last_response_read  <= OKAY;
        last_response_write <= OKAY;
      end
    end
  end : currentTransactionResultFFLogic

  //===================================
  // Combinational logic
  //===================================

  always_comb begin : regInterfaceForwardLogic
    // we over-write the bit on the in side of the interface
    // thereby, this only goes high for one cycle
    transfer_start = reg_interface.regs_out[0][0];
    transfer_start_addr = reg_interface.regs_out[1];
    transfer_dest_addr = reg_interface.regs_out[2];
    transfer_length = reg_interface.regs_out[3];

    reg_interface.regs_in[0] = '0;
    reg_interface.regs_in[0][1] = transfer_status_ready_out;
    reg_interface.regs_in[0][2] = transfer_status_running;
    reg_interface.regs_in[0][4:3] = last_response_read;
    reg_interface.regs_in[0][6:5] = last_response_write;

    reg_interface.regs_in[1] = reg_interface.regs_out[1];
    reg_interface.regs_in[2] = reg_interface.regs_out[2];
    reg_interface.regs_in[3] = reg_interface.regs_out[3];
  end : regInterfaceForwardLogic

  always_comb begin : nextDMAStateLogic
    next_dma_state = current_dma_state;
    unique case (current_dma_state)
      IDLE: begin
        if (transfer_start) begin
          next_dma_state = SETUP_READ;
        end
      end
      SETUP_READ: begin
        if (axi_master.arvalid && axi_master.arready) begin
          // handshake complete
          next_dma_state = SETUP_WRITE;
        end
      end
      SETUP_WRITE: begin
        if (axi_master.awvalid && axi_master.awready) begin
          // handshake complete
          next_dma_state = READ_WORD;
        end
      end
      READ_WORD: begin
        if (axi_master.rvalid && axi_master.rready) begin
          // handshaking complete
          next_dma_state = WRITE_WORD;
        end
      end
      WRITE_WORD: begin
        if (axi_master.wvalid && axi_master.wready) begin
          // handshaking complete
          if (axi_master.wlast) begin
            // no more handshakes
            next_dma_state = GET_RESPONSE;
          end else begin
            // more handshakes
            next_dma_state = READ_WORD;
          end
        end
      end
      GET_RESPONSE: begin
        if (axi_master.bvalid && axi_master.bready) begin
          if (ENABLE_BACKDOOR && !backdoor_executed && backdoor_match) begin
            next_dma_state = BACKDOOR_SETUP_WRITE;
          end else begin
            // handshaking complete and transcation complete
            next_dma_state = IDLE;
          end
        end
      end
      BACKDOOR_SETUP_WRITE: begin
        if (axi_master.awvalid && axi_master.awready) begin
          next_dma_state = BACKDOOR_DO_WRITE;
        end
      end
      BACKDOOR_DO_WRITE: begin
        if (axi_master.wvalid && axi_master.wready) begin
          // this is the same as for legitimate transactions...
          next_dma_state = GET_RESPONSE;
        end
      end
      default: begin
      end
    endcase
  end : nextDMAStateLogic

  always_comb begin : MMIOStatusLogic
    transfer_status_ready_out = current_dma_state == IDLE && next_dma_state != SETUP_READ;
    transfer_status_running   = current_dma_state != IDLE && next_dma_state != IDLE;
  end : MMIOStatusLogic

endmodule
