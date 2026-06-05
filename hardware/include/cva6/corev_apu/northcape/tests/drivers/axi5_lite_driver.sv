/**
  * Simulates an AXI5 LITE Master and checks soundness of the bus protocol.
  * Given a NorthcapeRegInterfaceTransaction, also verifies that the response data matches what was expected and performs the indicated write.
  */

package northcape_axi5_lite_driver;

  import northcape_types::*;
  import northcape_test::*;
  import axi5::*;
  import northcape_reg_interface_transaction::NorthcapeRegInterfaceAxiLiteTransaction;

  import uvm_pkg::*;
  `include "uvm_macros.svh"


  class automatic Axi5LiteDriver #(
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter NUM_REGS = -1,
      parameter string INTERFACE_NAME = "axi_lite_interface"
  ) extends uvm_driver #(NorthcapeRegInterfaceAxiLiteTransaction #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
  ));

    typedef virtual Axi5Lite #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) axi_lite_interface_t;

    axi_lite_interface_t intf;

    typedef NorthcapeRegInterfaceAxiLiteTransaction#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) transaction_t;

    typedef AxiLiteResultTransaction#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) ret_t;

    localparam COMPONENT_NAME = "AXI Lite Driver";

    uvm_analysis_port #(ret_t) ap;

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(axi_lite_interface_t)::get(null, "", INTERFACE_NAME, intf)) begin
        `uvm_fatal(COMPONENT_NAME, $sformatf(
                   "Could not get interface by type %s name %s Addr width %d data width %d!",
                   $typename(
                       intf
                   ),
                   INTERFACE_NAME,
                   AXI_ADDR_WIDTH,
                   AXI_DATA_WIDTH
                   ));
      end

      ap = new("result_port", this);

    endfunction : build_phase

    task do_read_test(input transaction_t transaction);
      ret_t ret;

      ret = new("Read response");
      ret.request_type = AXI_TEST_READ;

      intf.transmitter_clocking.araddr  <= transaction.transaction_addr;
      intf.transmitter_clocking.arprot  <= transaction.transaction_prot;
      intf.transmitter_clocking.arvalid <= 1'b1;
      intf.transmitter_clocking.rready  <= 1'b1;

      @(intf.transmitter_clocking iff intf.transmitter_clocking.arready)

        intf.transmitter_clocking.arvalid <= 1'b0;
      intf.transmitter_clocking.araddr <= '0;
      intf.transmitter_clocking.arprot <= '0;

      if (!intf.transmitter_clocking.rvalid) begin
        @(intf.transmitter_clocking iff intf.transmitter_clocking.rvalid);
      end

      ret.read_data = intf.transmitter_clocking.rdata;
      ret.response  = intf.transmitter_clocking.rresp;

      ap.write(ret);

      intf.transmitter_clocking.rready <= 1'b0;
      @(intf.transmitter_clocking);

    endtask

    task do_write_test(input transaction_t transaction);
      ret_t ret;
      bit   have_wvalid;

      have_wvalid = 0;

      ret = new("Write response");
      ret.request_type = AXI_TEST_WRITE;

      intf.transmitter_clocking.awaddr  <= transaction.transaction_addr;
      intf.transmitter_clocking.awprot  <= transaction.transaction_prot;
      intf.transmitter_clocking.awvalid <= 1'b1;

      if (transaction.aw_w_at_same_time) begin
        intf.transmitter_clocking.wdata  <= transaction.transaction_data;
        intf.transmitter_clocking.wstrb  <= transaction.transaction_write_strobe;
        intf.transmitter_clocking.wvalid <= 1'b1;
        have_wvalid = 1;
      end else begin
        intf.transmitter_clocking.wvalid <= 1'b0;
      end

      @(intf.transmitter_clocking iff intf.transmitter_clocking.awready);
      intf.transmitter_clocking.awvalid <= 1'b0;
      // reset signals, so the DUT does not use them WHEN IT SHOULD NOT (looking at you, capability ops!)
      intf.transmitter_clocking.awaddr  <= '0;
      intf.transmitter_clocking.awprot  <= '0;

      if (!have_wvalid) begin

        intf.transmitter_clocking.wdata  <= transaction.transaction_data;
        intf.transmitter_clocking.wstrb  <= transaction.transaction_write_strobe;
        intf.transmitter_clocking.wvalid <= 1'b1;
        @(intf.transmitter_clocking);
        have_wvalid = 1;
      end

      if (!(have_wvalid && intf.transmitter_clocking.wready)) begin

        @(intf.transmitter_clocking iff (have_wvalid && intf.transmitter_clocking.wready));
      end




      intf.transmitter_clocking.wdata  <= '0;
      intf.transmitter_clocking.wstrb  <= '0;

      intf.transmitter_clocking.wvalid <= 1'b0;

      intf.transmitter_clocking.bready <= 1'b1;

      if (!intf.transmitter_clocking.bvalid) begin
        @(intf.transmitter_clocking iff intf.transmitter_clocking.bvalid);
      end else begin
        @(intf.transmitter_clocking);
      end

      ret.response = intf.transmitter_clocking.bresp;

      ap.write(ret);

      intf.transmitter_clocking.bready <= 1'b0;

      @(intf.transmitter_clocking);
    endtask

    task run_phase(uvm_phase phase);
      transaction_t transaction;

      forever begin
        seq_item_port.get_next_item(transaction);

        phase.raise_objection(this);

        if (transaction.transaction_type == AXI_TEST_READ) begin
          do_read_test(.transaction(transaction));
        end else begin
          do_write_test(.transaction(transaction));
        end

        seq_item_port.item_done();

        phase.drop_objection(this);
      end

    endtask


  endclass

endpackage : northcape_axi5_lite_driver
