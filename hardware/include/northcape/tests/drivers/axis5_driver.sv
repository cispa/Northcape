/**
  * Drivers for AXI 5 Stream interface.
  */

package northcape_axis5_driver;

  import northcape_types::*;
  import northcape_test::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  /**
  * Simulates an AXI Stream transmitter and checks soundness of the bus protocol.
  */
  class automatic Axis5TransmitterDriver #(
      parameter AXIS_TDATA_WIDTH = -1,
      parameter AXIS_TID_WIDTH   = -1,
      parameter AXIS_TDEST_WIDTH = -1,
      parameter AXIS_TUSER_WIDTH = -1,

      parameter string INTERFACE_NAME = "",

      parameter type SEQUENCE_ITEM_TYPE = logic
  ) extends uvm_driver #(SEQUENCE_ITEM_TYPE);
    typedef virtual Axis5Test #(
        .AXIS_TDATA_WIDTH(AXIS_TDATA_WIDTH),
        .AXIS_TID_WIDTH  (AXIS_TID_WIDTH),
        .AXIS_TDEST_WIDTH(AXIS_TDEST_WIDTH),
        .AXIS_TUSER_WIDTH(AXIS_TUSER_WIDTH)
    ) transmitter_intf_t;

    typedef IAxis5TransmitterTransaction#(
        .AXIS_TDATA_WIDTH(AXIS_TDATA_WIDTH),
        .AXIS_TID_WIDTH  (AXIS_TID_WIDTH),
        .AXIS_TDEST_WIDTH(AXIS_TDEST_WIDTH),
        .AXIS_TUSER_WIDTH(AXIS_TUSER_WIDTH)
    ) transaction_t;

    localparam COMPONENT_NAME = "AXIS Transmitter Driver";

    transmitter_intf_t transmitter_intf;


    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction


    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(transmitter_intf_t)::get(
              null, "", INTERFACE_NAME, transmitter_intf
          )) begin
        `uvm_fatal(COMPONENT_NAME, "Could not get interface!");
      end

    endfunction

    task run_phase(uvm_phase phase);
      transaction_t transaction;
      int unsigned  wait_cycles;

      wait_cycles = 0;


      transmitter_intf.transmitter_clocking.tvalid <= 0;

      forever begin : driverTransaction
        seq_item_port.get_next_item(transaction);

        phase.raise_objection(this);

        `uvm_info(COMPONENT_NAME, "Requesting validation", UVM_DEBUG);

        @(transmitter_intf.transmitter_clocking);

        transmitter_intf.transmitter_clocking.tdata <= transaction.get_transmitter_tdata();
        transmitter_intf.transmitter_clocking.tstrb <= transaction.get_transmitter_tstrb();
        transmitter_intf.transmitter_clocking.tkeep <= transaction.get_transmitter_tkeep();
        // for now, only used for / expected to support single-cycle transfers
        transmitter_intf.transmitter_clocking.tlast <= 1;
        transmitter_intf.transmitter_clocking.tid <= transaction.get_transmitter_tid();
        transmitter_intf.transmitter_clocking.tdest <= transaction.get_transmitter_tdest();
        transmitter_intf.transmitter_clocking.tuser <= transaction.get_transmitter_tuser();
        // unused
        transmitter_intf.transmitter_clocking.twakeup <= 1;

        transmitter_intf.transmitter_clocking.tvalid <= 1;

        do begin
          @(transmitter_intf.transmitter_clocking);

          wait_cycles++;
        end while (!transmitter_intf.transmitter_clocking.tready);

        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Validation completed after %d cycles with tdata %x",
                  wait_cycles,
                  transaction.get_transmitter_tdata()
                  ), UVM_DEBUG);


        transmitter_intf.transmitter_clocking.tvalid <= 0;

        seq_item_port.item_done();

        phase.drop_objection(this);

      end : driverTransaction

    endtask

  endclass

  /**
  * Simulates an AXI Stream receiver and checks soundness of the bus protocol.
  */
  class automatic Axis5ReceiverMonitor #(
      parameter AXIS_TDATA_WIDTH = -1,
      parameter AXIS_TID_WIDTH   = -1,
      parameter AXIS_TDEST_WIDTH = -1,
      parameter AXIS_TUSER_WIDTH = -1,

      parameter string INTERFACE_NAME = ""
  ) extends uvm_monitor;

    typedef virtual Axis5Test #(
        .AXIS_TDATA_WIDTH(AXIS_TDATA_WIDTH),
        .AXIS_TID_WIDTH  (AXIS_TID_WIDTH),
        .AXIS_TDEST_WIDTH(AXIS_TDEST_WIDTH),
        .AXIS_TUSER_WIDTH(AXIS_TUSER_WIDTH)
    ) receiver_intf_t;
    receiver_intf_t receiver_intf;

    typedef AxisGenericResultTransaction#(
        .AXIS_TDATA_WIDTH(AXIS_TDATA_WIDTH),
        .AXIS_TID_WIDTH  (AXIS_TID_WIDTH),
        .AXIS_TDEST_WIDTH(AXIS_TDEST_WIDTH),
        .AXIS_TUSER_WIDTH(AXIS_TUSER_WIDTH)
    ) ret_t;

    uvm_analysis_port #(ret_t) ap;

    localparam string COMPONENT_NAME = "Axis 5 Receiver Monitor";

    function new(string name = "", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(receiver_intf_t)::get(null, "", INTERFACE_NAME, receiver_intf)) begin
        `uvm_fatal(COMPONENT_NAME, "Could not get interface!");
      end

      ap = new("result_port", this);

    endfunction

    task run_phase(uvm_phase phase);
      receiver_intf.receiver_clocking.tready <= 1;

      forever begin : driverTransaction
        @(receiver_intf.receiver_clocking);

        if (receiver_intf.receiver_clocking.tvalid) begin
          ret_t ret;

          phase.raise_objection(this);
          ret = new("return transaction");

          ret.tdata = receiver_intf.receiver_clocking.tdata;
          ret.tid = receiver_intf.receiver_clocking.tid;
          ret.tuser = receiver_intf.receiver_clocking.tuser;
          ret.tdest = receiver_intf.receiver_clocking.tdest;
          ret.tstrb = receiver_intf.receiver_clocking.tstrb;
          ret.tkeep = receiver_intf.receiver_clocking.tkeep;

          ap.write(ret);

          phase.drop_objection(this);
        end


      end : driverTransaction
    endtask
  endclass

endpackage : northcape_axis5_driver
