
/**
  * Agent, i.e., test orchestrator for DMA.
  */

package northcape_confused_deputy_dma_agent;

  import northcape_types::*;
  import northcape_test::*;
  import axi5::*;
  import northcape_confused_deputy_dma_scoreboard::*;
  import northcape_reg_interface_transaction::*;
  import northcape_axi5_lite_driver::*;
  import northcape_confused_deputy_dma_transaction::*;
  import northcape_confused_deputy_dma_sequence::*;
  import northcape_reg_interface_transaction::NorthcapeRegInterfaceAxiLiteTransaction;
  import northcape_generic_checker::NorthcapeGenericChecker;
  import northcape_sequence::NorthcapeDirectSequence;

  import uvm_pkg::*;

  `include "uvm_macros.svh"

  /**
  * DMA agent.
  */
  class NorthcapeConfusedDeputyDMATestAgent #(
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_LITE_ADDR_WIDTH = -1,
      parameter AXI_LITE_DATA_WIDTH = -1,
      parameter AXI_ID_WIDTH = -1,
      parameter AXI_USER_WIDTH = -1,

      parameter logic [AXI_DATA_WIDTH - 1 : 0] evil_mode_address = 64'hfacecafe,
      parameter logic [AXI_DATA_WIDTH - 1 : 0] evil_mode_write = 64'hfeedbeef,
      parameter logic [AXI_DATA_WIDTH / 8 - 1 : 0] evil_mode_write_mask = 8'hfe,

      parameter logic [AXI_DATA_WIDTH - 1 : 0] evil_mode_trigger_address = 64'hdecade00,
      parameter logic [AXI_DATA_WIDTH - 1 : 0] evil_mode_trigger_address_mask = 64'hffffffffffffff00,


      parameter string TRANSACTIONS_QUEUE_NAME_AGENT = ""
  ) extends uvm_agent;

    localparam COMPONENT_NAME = "DMA Agent";

    typedef NorthcapeDMAScoreboard#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH)
    ) scoreboard_t;

    typedef NorthcapeDMATransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) transaction_t;



    typedef NorthcapeRegInterfaceAxiLiteTransaction#(
        .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH)
    ) axi_lite_transaction_t;

    typedef Axi5LiteDriver#(
        .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH)
    ) axi_lite_driver_t;

    typedef INorthcapeAXITransactionMasterSide#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) axi_transaction_t;

    int unsigned test_id;
    mailbox #(axi_transaction_t) requests_in_master_read, requests_in_master_write;


    scoreboard_t scoreboard;
    axi_lite_driver_t mmio_driver;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    typedef uvm_sequencer#(NorthcapeRegInterfaceAxiLiteTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    )) mmio_sequencer_t;

    NorthcapeDMAStartSequence #(
        .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH)
    ) sequence_start;

    NorthcapeDMAStopSequence #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) sequence_stop;

    mmio_sequencer_t sequencer_mmio;

    NorthcapeGenericChecker generic_checker;

    localparam string TRANSACTIONS_QUEUE_NAME_SCOREBOARD = "dma_transactions_scoreboard";
    typedef NorthcapeDirectSequence#(
        .TRANSACTION_TYPE(transaction_t),
        .TRANSACTION_QUEUE_NAME(TRANSACTIONS_QUEUE_NAME_SCOREBOARD)
    ) scoreboard_sequence_t;

    // sequence is always 1:1 between sequencer and driver
    scoreboard_sequence_t sequence_scoreboard;
    uvm_sequencer #(transaction_t) sequencer_scoreboard;

    typedef INorthcapeAXITransactionMasterSide#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) mailbox_transaction_t;

    typedef uvm_analysis_port#(Axi5MasterDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    )) master_analysis_port_t;

    master_analysis_port_t master_analysis_port_read, master_analysis_port_write;

    function void build_phase(uvm_phase phase);
      this.scoreboard = new("scoreboard", this);
      this.mmio_driver = new("MMIO driver", this);

      this.sequence_stop = new("stop_sequence");

      this.sequencer_mmio = new("MMIO Sequencer", this);

      this.generic_checker = new("DMA generic checker", this);

      this.sequence_scoreboard = new("scoreboard_sequence");
      this.sequencer_scoreboard = new("scoreboard_sequencer", this);

      assert (uvm_config_db#(mailbox#(mailbox_transaction_t))::get(
          null, "", "dma_mailbox_read", requests_in_master_read
      ));
      assert (uvm_config_db#(mailbox#(mailbox_transaction_t))::get(
          null, "", "dma_mailbox_write", requests_in_master_write
      ));

      assert (uvm_config_db#(master_analysis_port_t)::get(
          null, "", "dma_master_analysis_port_read", master_analysis_port_read
      ));
      assert (uvm_config_db#(master_analysis_port_t)::get(
          null, "", "dma_master_analysis_port_write", master_analysis_port_write
      ));
    endfunction : build_phase

    function void connect_phase(uvm_phase phase);
      scoreboard.transaction_port.connect(sequencer_scoreboard.seq_item_export);
      master_analysis_port_read.connect(scoreboard.master_result_fifo_read.analysis_export);
      master_analysis_port_write.connect(scoreboard.master_result_fifo_write.analysis_export);

      scoreboard.checker_port.connect(generic_checker.analysis_export);

      mmio_driver.ap.connect(scoreboard.mmio_result_fifo.analysis_export);
      mmio_driver.seq_item_port.connect(sequencer_mmio.seq_item_export);
    endfunction

    typedef NorthcapeDMATransactionMasterSideRead#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) read_transaction_t;

    typedef NorthcapeDMATransactionMasterSideWrite#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) write_transaction_t;

    function write_transaction_t generate_backdoor_transaction();
      write_transaction_t ret;

      ret = new("backdoor_write");

      ret.source_addr = '0;
      ret.dst_addr = evil_mode_address;
      ret.axi_transfer_len = 0;
      ret.data = evil_mode_write;
      ret.write_response = OKAY;

      return ret;
    endfunction

    bit backdoor_write_seen;

    task run_phase(uvm_phase phase);
      transaction_t current_transaction;
      uvm_queue #(transaction_t) transactions, transactions_scoreboard;

      backdoor_write_seen = 0;

      phase.raise_objection(this);

      `uvm_info(COMPONENT_NAME, "Agent run phase start", UVM_MEDIUM);

      // might only exist at run time
      if (!uvm_config_db#(uvm_queue#(transaction_t))::get(
              null, "", TRANSACTIONS_QUEUE_NAME_AGENT, transactions
          )) begin
        `uvm_fatal(COMPONENT_NAME, "Failed to get transactions object!");
      end

      transactions_scoreboard = new("Scoreboard transactions");

      uvm_config_db#(uvm_queue#(transaction_t))::set(null, "", TRANSACTIONS_QUEUE_NAME_SCOREBOARD,
                                                     transactions_scoreboard);

      while (transactions.size() > 0) begin
        read_transaction_t  read_transaction;
        write_transaction_t write_transaction;

        read_transaction = new("read_transaction");
        write_transaction = new("write_transaction");

        current_transaction = transactions.pop_front();

        // due to the scoreboard waiting for the last check sequence,
        // we need to feed the scoreboard transactions one-by-one
        transactions_scoreboard.push_back(current_transaction);

        read_transaction.do_copy(current_transaction);
        write_transaction.do_copy(current_transaction);

        requests_in_master_read.put(read_transaction);
        requests_in_master_write.put(write_transaction);

        if((current_transaction.source_addr & evil_mode_trigger_address_mask) == (evil_mode_trigger_address & evil_mode_trigger_address_mask))
            begin
          if (backdoor_write_seen) begin
            `uvm_info(COMPONENT_NAME, "Not expecting backdoor write as already seen!", UVM_MEDIUM);
          end else begin
            `uvm_info(COMPONENT_NAME, "Expecting backdoor write!", UVM_MEDIUM);
            requests_in_master_write.put(generate_backdoor_transaction());
            backdoor_write_seen = 1;
          end
        end

        current_transaction.test_id = test_id++;


        sequence_start = new(
            "start_sequence",
            current_transaction.source_addr,
            current_transaction.dst_addr,
            current_transaction.axi_transfer_len
        );

        `uvm_info(COMPONENT_NAME, "Starting sequence initialized!", UVM_HIGH);
        sequence_start.start(sequencer_mmio);
        `uvm_info(COMPONENT_NAME, "Starting sequence done!", UVM_HIGH);

        `uvm_info(COMPONENT_NAME, "Scoreboard sequence initialized!", UVM_HIGH);
        sequence_scoreboard.start(sequencer_scoreboard);
        `uvm_info(COMPONENT_NAME, "Scoreboard sequence done!", UVM_HIGH);

        `uvm_info(COMPONENT_NAME, "Stopping sequence initialized!", UVM_HIGH);
        sequence_stop.start(sequencer_mmio);
        `uvm_info(COMPONENT_NAME, "Stopping sequence done!", UVM_HIGH);

        `uvm_info(COMPONENT_NAME, $sformatf("Finished transaction %d", test_id), UVM_MEDIUM);
      end

      phase.drop_objection(this);
    endtask

  endclass

endpackage : northcape_confused_deputy_dma_agent
