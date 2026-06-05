/**
 * Agent for Northcape MMU verification.
 */
package northcape_cva6_mmu_agent;
  import northcape_test::*;
  import northcape_cva6_mmu_transaction::*;
  import northcape_generator::*;
  import northcape_types::device_id_t;
  import uvm_pkg::*;
  import northcape_cva6_mmu_scoreboard::NorthcapeCVA6MMUScoreboard;
  import northcape_cva6_mmu_intf_driver::NorthcapeCVA6IntfDriver;


  import northcape_sequence::NorthcapeDirectSequence;
  import northcape_generic_checker::*;


  `include "uvm_macros.svh"

  class automatic NorthcapeCVA6MMUAgentConfig #(
      parameter device_id_t INSTR_CHAN_DEVICE_ID = -1,
      parameter device_id_t DATA_CHAN_DEVICE_ID = -1,
      parameter AXI_ADDR_WIDTH = -1
  );


    typedef mailbox#(INorthcapeCapabilityResolverTransaction) resolver_mailbox_t;

    typedef NorthcapeCVA6MMUTransaction#(
        .INSTR_CHAN_DEVICE_ID(INSTR_CHAN_DEVICE_ID),
        .DATA_CHAN_DEVICE_ID(DATA_CHAN_DEVICE_ID),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) transaction_t;
    typedef NorthcapeGenerator#(transaction_t) generator_t;

    typedef virtual NorthcapeCMTInterface #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ).TEST_PRODUCER cmt_interface_t;

    typedef uvm_analysis_port#(AxisValidateResultTransaction) resolver_analysis_port_t;

    typedef virtual NorthcapeCva6MMUInterface #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ).CVA6 mmu_interface_t;

    mmu_interface_t execute_interface, data_interface;

    resolver_mailbox_t validate_requests_instr;
    resolver_mailbox_t validate_requests_data;
    cmt_interface_t cmt_interface;

    resolver_analysis_port_t instr_resolver_analysis_port;
    resolver_analysis_port_t data_resolver_analysis_port;

    function new(input mmu_interface_t execute_interface, input mmu_interface_t data_interface,
                 input resolver_mailbox_t validate_requests_instr,
                 input resolver_mailbox_t validate_requests_data, cmt_interface_t cmt_interface,
                 input resolver_analysis_port_t instr_resolver_analysis_port,
                 data_resolver_analysis_port);
      this.execute_interface = execute_interface;
      this.data_interface = data_interface;
      this.validate_requests_instr = validate_requests_instr;
      this.validate_requests_data = validate_requests_data;


      this.instr_resolver_analysis_port = instr_resolver_analysis_port;
      this.data_resolver_analysis_port = data_resolver_analysis_port;

      this.cmt_interface = cmt_interface;
    endfunction

  endclass


  class automatic NorthcapeCVA6MMUAgent #(
      parameter device_id_t INSTR_CHAN_DEVICE_ID = -1,
      parameter device_id_t DATA_CHAN_DEVICE_ID = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter string MMU_AGENT_CONFIG_NAME = "",
      parameter string TRANSACTIONS_QUEUE_NAME_AGENT = ""
  ) extends uvm_agent;

    localparam COMPONENT_NAME = "CVA6 MMU Agent";


    typedef mailbox#(INorthcapeCapabilityResolverTransaction) resolver_mailbox_t;
    typedef NorthcapeCVA6MMUInterfaceResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) result_transaction_t;

    typedef NorthcapeCVA6MMUTransaction#(
        .INSTR_CHAN_DEVICE_ID(INSTR_CHAN_DEVICE_ID),
        .DATA_CHAN_DEVICE_ID(DATA_CHAN_DEVICE_ID),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) transaction_t;
    typedef NorthcapeGenerator#(transaction_t) generator_t;

    typedef virtual NorthcapeCMTInterface #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ).TEST_PRODUCER cmt_interface_t;

    typedef NorthcapeCVA6MMUAgentConfig#(
        .INSTR_CHAN_DEVICE_ID(INSTR_CHAN_DEVICE_ID),
        .DATA_CHAN_DEVICE_ID(DATA_CHAN_DEVICE_ID),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) agent_config_t;

    typedef NorthcapeCVA6MMUScoreboard#(
        .INSTR_CHAN_DEVICE_ID(INSTR_CHAN_DEVICE_ID),
        .DATA_CHAN_DEVICE_ID(DATA_CHAN_DEVICE_ID),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) scoreboard_t;

    typedef NorthcapeCVA6IntfDriver#(
        .INSTR_CHAN_DEVICE_ID(INSTR_CHAN_DEVICE_ID),
        .DATA_CHAN_DEVICE_ID(DATA_CHAN_DEVICE_ID),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) cva6_intf_driver_t;

    typedef NorthcapeCVA6MMUInterfaceTransaction#(
        .INSTR_CHAN_DEVICE_ID(INSTR_CHAN_DEVICE_ID),
        .DATA_CHAN_DEVICE_ID(DATA_CHAN_DEVICE_ID),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) driver_transaction_t;

    typedef uvm_sequencer#(driver_transaction_t) intf_sequencer_t;

    typedef uvm_analysis_port#(AxisValidateResultTransaction) resolver_analysis_port_t;
    typedef uvm_analysis_port#(result_transaction_t) intf_deriver_analysis_port_t;

    typedef virtual NorthcapeCva6MMUInterface #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ).CVA6 mmu_interface_t;


    localparam string TRANSACTIONS_QUEUE_NAME_SCOREBOARD = "cva6_mmu_transactions_scoreboard";
    localparam string TRANSACTIONS_QUEUE_NAME_DRIVER_INSTR = "cva6_mmu_transactions_instr";
    localparam string TRANSACTIONS_QUEUE_NAME_DRIVER_DATA = "cva6_mmu_transactions_data";

    typedef NorthcapeDirectSequence#(
        .TRANSACTION_TYPE(transaction_t),
        .TRANSACTION_QUEUE_NAME(TRANSACTIONS_QUEUE_NAME_SCOREBOARD)
    ) scoreboard_sequence_t;

    typedef NorthcapeDirectSequence#(
        .TRANSACTION_TYPE(driver_transaction_t),
        .TRANSACTION_QUEUE_NAME(TRANSACTIONS_QUEUE_NAME_DRIVER_INSTR)
    ) instr_driver_sequence_t;

    typedef NorthcapeDirectSequence#(
        .TRANSACTION_TYPE(driver_transaction_t),
        .TRANSACTION_QUEUE_NAME(TRANSACTIONS_QUEUE_NAME_DRIVER_DATA)
    ) data_driver_sequence_t;

    instr_driver_sequence_t sequence_instr_driver;
    data_driver_sequence_t sequence_data_driver;

    // sequence is always 1:1 between sequencer and driver
    scoreboard_sequence_t sequence_scoreboard;
    uvm_sequencer #(transaction_t) sequencer_scoreboard;

    scoreboard_t scoreboard;

    transaction_t current_transaction;

    cva6_intf_driver_t instr_driver, data_driver;
    intf_sequencer_t instr_sequencer, data_sequencer;

    resolver_mailbox_t validate_requests_instr;
    resolver_mailbox_t validate_requests_data;

    mmu_interface_t instr_interface, data_interface;

    uvm_queue #(transaction_t) transactions;

    cmt_interface_t cmt_interface;

    resolver_analysis_port_t instr_resolver_analysis_port;
    resolver_analysis_port_t data_resolver_analysis_port;

    // actual checking is implemented with the transactions
    // generic checker implements this in a uniform way
    NorthcapeGenericChecker generic_checker;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);

      agent_config_t agent_config;

      if (!uvm_config_db#(agent_config_t)::get(this, "", MMU_AGENT_CONFIG_NAME, agent_config)) begin
        `uvm_fatal(COMPONENT_NAME, "Failed to get config object!");
      end

      this.instr_interface = agent_config.execute_interface;
      this.data_interface = agent_config.data_interface;
      this.validate_requests_instr = agent_config.validate_requests_instr;
      this.validate_requests_data = agent_config.validate_requests_data;

      this.instr_resolver_analysis_port = agent_config.instr_resolver_analysis_port;
      this.data_resolver_analysis_port = agent_config.data_resolver_analysis_port;

      this.cmt_interface = agent_config.cmt_interface;


      this.scoreboard = new("scoreboard", this);
      this.sequence_scoreboard = new("scoreboard_sequence");
      this.sequence_instr_driver = new("instr_driver_sequence");
      this.sequence_data_driver = new("data_driver_sequence");
      this.sequencer_scoreboard = new("scoreboard_sequencer", this);

      this.generic_checker = new("checker", this);

      this.instr_driver = new(this.instr_interface, "Instruction driver", this);
      this.data_driver = new(this.data_interface, "Data driver", this);
      this.instr_sequencer = new("Instruction Sequencer", this);
      this.data_sequencer = new("Data Sequencer", this);

    endfunction

    function void connect_phase(uvm_phase phase);
      scoreboard.transaction_port.connect(sequencer_scoreboard.seq_item_export);

      instr_driver.ap.connect(scoreboard.intf_driver_result_fifo_instr.analysis_export);
      data_driver.ap.connect(scoreboard.intf_driver_result_fifo_data.analysis_export);

      instr_driver.seq_item_port.connect(instr_sequencer.seq_item_export);
      data_driver.seq_item_port.connect(data_sequencer.seq_item_export);

      instr_resolver_analysis_port.connect(scoreboard.resolver_result_fifo_instr.analysis_export);
      data_resolver_analysis_port.connect(scoreboard.resolver_result_fifo_data.analysis_export);

      scoreboard.checker_port.connect(generic_checker.analysis_export);
    endfunction

    task run_phase(uvm_phase phase);
      transaction_t transaction_scoreboard;
      transaction_t resolver_transaction;
      driver_transaction_t driver_transaction;
      int unsigned transaction_num;

      uvm_queue #(transaction_t) transactions, transactions_scoreboard;
      uvm_queue #(driver_transaction_t) transactions_instr_driver, transactions_data_driver;

      phase.raise_objection(this);

      // might only exist at run time
      if (!uvm_config_db#(uvm_queue#(transaction_t))::get(
              null, "", TRANSACTIONS_QUEUE_NAME_AGENT, transactions
          )) begin
        `uvm_fatal(COMPONENT_NAME, "Failed to get transactions object!");
      end

      transactions_scoreboard = new("Scoreboard transactions MMU");
      transactions_scoreboard.delete();

      transactions_instr_driver = new("Instr transactions");
      transactions_data_driver  = new("Data transactions");

      uvm_config_db#(uvm_queue#(transaction_t))::set(null, "", TRANSACTIONS_QUEUE_NAME_SCOREBOARD,
                                                     transactions_scoreboard);

      uvm_config_db#(uvm_queue#(driver_transaction_t))::set(
          null, "", TRANSACTIONS_QUEUE_NAME_DRIVER_INSTR, transactions_instr_driver);
      uvm_config_db#(uvm_queue#(driver_transaction_t))::set(
          null, "", TRANSACTIONS_QUEUE_NAME_DRIVER_DATA, transactions_data_driver);

      while (transactions.size() > 0) begin

        `uvm_info(COMPONENT_NAME, "Waiting for transaction in FIFO!", UVM_HIGH);
        current_transaction = transactions.pop_front();
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Got transaction from FIFO: %s", current_transaction.convert2string()), UVM_HIGH);


        transaction_scoreboard = new("Scoreboard transaction");
        transaction_scoreboard.do_copy(current_transaction);

        transactions_scoreboard.push_back(transaction_scoreboard);

        resolver_transaction = new("resolver_transaction");
        resolver_transaction.do_copy(current_transaction);

        driver_transaction = new("driver transaction");
        driver_transaction.do_copy(current_transaction);

        if (current_transaction.is_execute) begin
          transactions_instr_driver.push_back(driver_transaction);
        end else begin
          transactions_data_driver.push_back(driver_transaction);
        end


        if (cmt_interface) begin
          // in integration test, this is not used
          cmt_interface.test_producer_clocking.cmt_base <= current_transaction.cmt_base_addr;
          cmt_interface.test_producer_clocking.table_size_clog2 <= current_transaction.cmt_size_clog2;
        end

        if (current_transaction.is_execute) begin
          validate_requests_instr.put(resolver_transaction);
        end else begin
          validate_requests_data.put(resolver_transaction);
        end


        // sequence terminates when scoreboard has consumed the last item - by then, we know that the transaction has been processed
        fork
          begin
            `uvm_info(COMPONENT_NAME, "sb sequence start", UVM_HIGH);
            sequence_scoreboard.start(sequencer_scoreboard);
            `uvm_info(COMPONENT_NAME, "sb sequence end", UVM_HIGH);
          end
          begin
            if (current_transaction.is_execute) begin
              `uvm_info(COMPONENT_NAME, "instruction driver sequence start", UVM_HIGH);
              sequence_instr_driver.start(instr_sequencer);
            end else begin
              `uvm_info(COMPONENT_NAME, "data driver sequence start", UVM_HIGH);
              sequence_data_driver.start(data_sequencer);
            end
            `uvm_info(COMPONENT_NAME, "driver sequence end", UVM_HIGH);
          end
        join

        transaction_num++;
        `uvm_info(COMPONENT_NAME, $sformatf("Finished transaction %d", transaction_num),
                  UVM_MEDIUM);

      end

      phase.drop_objection(this);


    endtask

  endclass


endpackage
