/**
 * Agent for the Northcape Register Interface.
 */
package northcape_reg_interface_agent;
  import northcape_reg_interface_transaction::*;
  import northcape_reg_interface_scoreboard::*;
  import northcape_axi5_lite_driver::*;
  import northcape_reg_interface_driver::*;
  import northcape_test::*;
  import northcape_generator::NorthcapeGenerator;
  import northcape_generic_checker::NorthcapeGenericChecker;
  import northcape_sequence::*;

  import uvm_pkg::*;

  `include "uvm_macros.svh"



  class automatic NorthcapeRegInterfaceAgent #(
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter NUM_REGS = -1,


      parameter string TRANSACTIONS_QUEUE_NAME_AGENT = "",

      parameter string REG_INTERFACE_NAME  = "",
      parameter string MMIO_INTERFACE_NAME = ""
  ) extends uvm_agent;

    typedef NorthcapeRegInterfaceTransaction#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .NUM_REGS(NUM_REGS)
    ) transaction_t;


    typedef NorthcapeRegInterfaceScoreboard#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .NUM_REGS(NUM_REGS)
    ) scoreboard_t;

    typedef Axi5LiteDriver#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .NUM_REGS(NUM_REGS),
        .INTERFACE_NAME(MMIO_INTERFACE_NAME)
    ) mmio_driver_t;

    typedef NorthcapeRegInterfaceDriver#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .NUM_REGS(NUM_REGS),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .INTERFACE_NAME(REG_INTERFACE_NAME)
    ) reg_driver_t;

    typedef NorthcapeRegInterfaceMonitor#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .NUM_REGS(NUM_REGS),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .INTERFACE_NAME(REG_INTERFACE_NAME)
    ) reg_monitor_t;

    typedef virtual Axi5Lite #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ).TEST axi_intf_t;

    typedef virtual NorthcapeRegInterfaceIO #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .NUM_REGS(NUM_REGS)
    ).TEST reg_intf_t;

    typedef NorthcapeRegInterfaceAxiLiteTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) mmio_transaction_t;

    typedef uvm_sequencer#(mmio_transaction_t) mmio_sequencer_t;

    typedef NorthcapeGenerator#(transaction_t) gen_t;

    localparam COMPONENT_NAME = "Northcape Register Interface Agent";

    axi_intf_t axi_intf;
    reg_intf_t reg_intf;

    scoreboard_t scoreboard;

    mmio_driver_t mmio_driver;
    reg_driver_t reg_driver;
    reg_monitor_t reg_monitor;

    NorthcapeGenericChecker generic_checker;

    localparam string TRANSACTIONS_QUEUE_NAME_SCOREBOARD = "reg_interface_transactions_scoreboard";
    typedef NorthcapeDirectSequence#(
        .TRANSACTION_TYPE(transaction_t),
        .TRANSACTION_QUEUE_NAME(TRANSACTIONS_QUEUE_NAME_SCOREBOARD)
    ) scoreboard_sequence_t;

    localparam string TRANSACTIONS_QUEUE_NAME_MMIO = "reg_interface_transactions_mmio";
    typedef NorthcapeDirectSequence#(
        .TRANSACTION_TYPE(mmio_transaction_t),
        .TRANSACTION_QUEUE_NAME(TRANSACTIONS_QUEUE_NAME_MMIO)
    ) mmio_sequence_t;

    localparam string TRANSACTIONS_QUEUE_NAME_REG = "reg_interface_transactions_reg";
    typedef NorthcapeDirectSequence#(
        .TRANSACTION_TYPE(transaction_t),
        .TRANSACTION_QUEUE_NAME(TRANSACTIONS_QUEUE_NAME_REG)
    ) reg_sequence_t;
    typedef uvm_sequencer#(transaction_t) reg_sequencer_t;

    // sequence is always 1:1 between sequencer and driver
    scoreboard_sequence_t sequence_scoreboard;
    uvm_sequencer #(transaction_t) sequencer_scoreboard;

    mmio_sequence_t sequence_mmio;
    mmio_sequencer_t sequencer_mmio;

    reg_sequence_t sequence_reg;
    reg_sequencer_t sequencer_reg;

    function new(string name = "", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      this.scoreboard = new("scoreboard", this);
      this.mmio_driver = new("MMIO driver", this);

      this.reg_driver = new("Reg driver", this);
      this.reg_monitor = new("Reg monitor", this);


      this.generic_checker = new("DMA generic checker", this);

      this.sequence_scoreboard = new("scoreboard_sequence");
      this.sequencer_scoreboard = new("scoreboard_sequencer", this);

      this.sequence_mmio = new("MMIO sequence");
      this.sequencer_mmio = new("MMIO sequencer", this);

      this.sequence_reg = new("Reg sequence");
      this.sequencer_reg = new("Reg sequencer", this);
    endfunction : build_phase

    function void connect_phase(uvm_phase phase);
      scoreboard.transaction_port.connect(sequencer_scoreboard.seq_item_export);

      mmio_driver.seq_item_port.connect(sequencer_mmio.seq_item_export);
      mmio_driver.ap.connect(scoreboard.mmio_result_fifo.analysis_export);

      reg_driver.seq_item_port.connect(sequencer_reg.seq_item_export);

      reg_monitor.ap.connect(scoreboard.reg_result_fifo.analysis_export);

      scoreboard.checker_port.connect(generic_checker.analysis_export);
    endfunction

    task run_phase(uvm_phase phase);
      transaction_t current_transaction;
      uvm_queue #(transaction_t) transactions, transactions_scoreboard, transactions_reg;
      uvm_queue #(mmio_transaction_t) transactions_mmio;
      int unsigned transaction_num;

      phase.raise_objection(this);

      `uvm_info(COMPONENT_NAME, "Agent run phase start", UVM_MEDIUM);


      // might only exist at run time
      if (!uvm_config_db#(uvm_queue#(transaction_t))::get(
              null, "", TRANSACTIONS_QUEUE_NAME_AGENT, transactions
          )) begin
        `uvm_fatal(COMPONENT_NAME, "Failed to get transactions object!");
      end

      transactions_scoreboard = new("Scoreboard transactions");

      transactions_mmio = new("MMIO transactions");

      transactions_reg = new("Reg transactions");

      uvm_config_db#(uvm_queue#(transaction_t))::set(null, "", TRANSACTIONS_QUEUE_NAME_SCOREBOARD,
                                                     transactions_scoreboard);

      uvm_config_db#(uvm_queue#(mmio_transaction_t))::set(null, "", TRANSACTIONS_QUEUE_NAME_MMIO,
                                                          transactions_mmio);

      uvm_config_db#(uvm_queue#(transaction_t))::set(null, "", TRANSACTIONS_QUEUE_NAME_REG,
                                                     transactions_reg);

      while (transactions.size() > 0) begin
        current_transaction = transactions.pop_front();

        `uvm_info(COMPONENT_NAME, "Pushing MMIO and scoreboard transactions", UVM_DEBUG);

        transactions_mmio.push_back(current_transaction.axi_lite_transaction);

        transactions_scoreboard.push_back(current_transaction);

        if (current_transaction.axi_lite_transaction.transaction_type == AXI_TEST_READ) begin
          // need to change input data for read first...
          transactions_reg.push_back(current_transaction);

          `uvm_info(COMPONENT_NAME, "Running Reg sequence", UVM_DEBUG);
          sequence_reg.start(sequencer_reg);
        end

        `uvm_info(COMPONENT_NAME, "Running MMIO sequence", UVM_DEBUG);

        sequence_mmio.start(sequencer_mmio);

        `uvm_info(COMPONENT_NAME, "Getting results from monitor", UVM_DEBUG);

        reg_monitor.get_current_values();

        `uvm_info(COMPONENT_NAME, "Running MMIO sequence", UVM_DEBUG);

        sequence_scoreboard.start(sequencer_scoreboard);

        transaction_num++;


        `uvm_info(COMPONENT_NAME, $sformatf("Finished transaction %d", transaction_num),
                  UVM_MEDIUM);
      end


      phase.drop_objection(this);

    endtask

  endclass
endpackage
