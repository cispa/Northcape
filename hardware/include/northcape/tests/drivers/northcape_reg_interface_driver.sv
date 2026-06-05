
/**
  * Drivers for Northcape Register Interface.
  */
package northcape_reg_interface_driver;

  import northcape_test::*;
  import northcape_reg_interface_transaction::NorthcapeRegInterfaceTransaction;

  import uvm_pkg::*;

  /**
  * Generates input for register interface's registers (for read transactions).
  */
  class automatic NorthcapeRegInterfaceDriver #(
      parameter NUM_REGS = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,

      parameter string INTERFACE_NAME = ""
  ) extends uvm_driver #(NorthcapeRegInterfaceTransaction #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .NUM_REGS(NUM_REGS)
  ));
    typedef virtual NorthcapeRegInterfaceIO #(
        .NUM_REGS(NUM_REGS),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) reg_intf_t;

    typedef NorthcapeRegInterfaceTransaction#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .NUM_REGS(NUM_REGS)
    ) transaction_t;

    reg_intf_t reg_intf;

    localparam string COMPONENT_NAME = "Northcape Reg Interface Driver";

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(reg_intf_t)::get(null, "", INTERFACE_NAME, reg_intf)) begin
        `uvm_fatal(COMPONENT_NAME, "Could not get interface!");
      end

    endfunction

    task run_phase(uvm_phase phase);
      int unsigned  reg_index;
      transaction_t transaction;

      forever begin : driverTransaction
        seq_item_port.get_next_item(transaction);

        phase.raise_objection(this);

        reg_index = transaction.get_reg_index();

        reg_intf.test_regs_clocking.regs_in <= transaction.transaction_regs_in;

        if (transaction.axi_lite_transaction.transaction_type == AXI_TEST_READ) begin
          reg_intf.test_regs_clocking.regs_in[reg_index] <= transaction.axi_lite_transaction.transaction_data;
        end

        @(reg_intf.test_regs_clocking);


        seq_item_port.item_done();

        phase.drop_objection(this);
      end : driverTransaction
    endtask
  endclass

  /**
 * Reads output of the register interface (for write transactions).
 */
  class automatic NorthcapeRegInterfaceMonitor #(
      parameter NUM_REGS = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter string INTERFACE_NAME = ""
  ) extends uvm_monitor;

    typedef virtual NorthcapeRegInterfaceIO #(
        .NUM_REGS(NUM_REGS),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) reg_intf_t;
    typedef RegInterfaceResultTransaction#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .NUM_REGS(NUM_REGS)
    ) ret_t;

    reg_intf_t reg_intf;

    localparam string COMPONENT_NAME = "Northcape Reg Interface Monitor";


    uvm_analysis_port #(ret_t) ap;

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(reg_intf_t)::get(null, "", INTERFACE_NAME, reg_intf)) begin
        `uvm_fatal(COMPONENT_NAME, "Could not get interface!");
      end

      ap = new("result port", this);
    endfunction

    protected bit record_next_transaction;

    function void get_current_values();
      record_next_transaction = 1;
    endfunction

    task run_phase(uvm_phase phase);
      forever begin : Monitor

        if (record_next_transaction) begin
          ret_t ret;

          phase.raise_objection(this);

          record_next_transaction = 0;

          ret = new("result");
          ret.current_data = reg_intf.test_regs_clocking.regs_out;

          ap.write(ret);

          phase.drop_objection(this);

        end

        @(reg_intf.test_regs_clocking);
      end : Monitor
    endtask
  endclass

endpackage : northcape_reg_interface_driver
