/**
 * Agent for Northcape MMU verification.
 */
package northcape_mmu_agent;
  import northcape_test::*;
  import northcape_mmu_transaction::*;
  import northcape_generator::*;
  import axi5::*;
  import northcape_types::device_id_t;
  import uvm_pkg::*;


  import northcape_mmu_scoreboard::NorthcapeMMUScoreboard;
  import northcape_sequence::NorthcapeDirectSequence;
  import northcape_generic_checker::*;

  `include "axi5_functional_coverage.svh"

  `include "uvm_macros.svh"

  class automatic NorthcapeMMUAgentConfig #(
      parameter device_id_t READ_CHAN_DEVICE_ID = -1,
      parameter device_id_t WRITE_CHAN_DEVICE_ID = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ID_WIDTH = -1,
      parameter AXI_USER_WIDTH = -1,
      parameter CHECK_CMT_OVERLAP = 1
  );


    typedef mailbox#(INorthcapeAXITransactionSlaveSide#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH)
    )) slave_mailbox_t;
    typedef mailbox#(INorthcapeAXITransactionMasterSide#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH)
    )) master_mailbox_t;
    typedef mailbox#(INorthcapeCapabilityResolverTransaction) resolver_mailbox_t;

    typedef NorthcapeMMUTransaction#(
        .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
        .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .CHECK_CMT_OVERLAP(CHECK_CMT_OVERLAP)
    ) transaction_t;
    typedef NorthcapeGenerator#(transaction_t) generator_t;

    typedef virtual NorthcapeCMTInterface #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ).TEST_PRODUCER cmt_interface_t;

    typedef uvm_analysis_port#(Axi5SlaveDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    )) slave_analysis_port_t;

    typedef uvm_analysis_port#(Axi5MasterDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    )) master_analysis_port_t;

    typedef uvm_analysis_port#(AxisValidateResultTransaction) resolver_analysis_port_t;

    slave_mailbox_t requests_in_slave;
    master_mailbox_t requests_in_master;
    resolver_mailbox_t validate_requests_read;
    resolver_mailbox_t validate_requests_write;
    cmt_interface_t cmt_interface;

    slave_analysis_port_t slave_analysis_port;
    master_analysis_port_t master_analysis_port;

    resolver_analysis_port_t read_resolver_analysis_port;
    resolver_analysis_port_t write_resolver_analysis_port;

    function new(input slave_mailbox_t requests_in_slave, input master_mailbox_t requests_in_master,
                 input resolver_mailbox_t validate_requests_read,
                 input resolver_mailbox_t validate_requests_write, cmt_interface_t cmt_interface,
                 input slave_analysis_port_t slave_analysis_port,
                 master_analysis_port_t master_analysis_port,
                 input resolver_analysis_port_t read_resolver_analysis_port,
                 write_resolver_analysis_port);
      this.requests_in_slave = requests_in_slave;
      this.requests_in_master = requests_in_master;
      this.validate_requests_read = validate_requests_read;
      this.validate_requests_write = validate_requests_write;

      this.slave_analysis_port = slave_analysis_port;
      this.master_analysis_port = master_analysis_port;
      this.read_resolver_analysis_port = read_resolver_analysis_port;
      this.write_resolver_analysis_port = write_resolver_analysis_port;

      this.cmt_interface = cmt_interface;
    endfunction

  endclass

  class automatic NorthcapeMMUAgent #(
      parameter device_id_t READ_CHAN_DEVICE_ID = -1,
      parameter device_id_t WRITE_CHAN_DEVICE_ID = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ID_WIDTH = -1,
      parameter AXI_USER_WIDTH = -1,
      parameter CHECK_RESOLVER_RESULT = 1,
      parameter string TRANSACTIONS_QUEUE_NAME_AGENT = "",
      parameter string MMU_AGENT_CONFIG_NAME = "",
      parameter CHECK_CMT_OVERLAP = 1
  ) extends uvm_agent;

    localparam COMPONENT_NAME = "MMU Agent";

    typedef mailbox#(INorthcapeAXITransactionSlaveSide#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH)
    )) slave_mailbox_t;
    typedef mailbox#(INorthcapeAXITransactionMasterSide#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH)
    )) master_mailbox_t;
    typedef mailbox#(INorthcapeCapabilityResolverTransaction) resolver_mailbox_t;

    typedef NorthcapeMMUTransaction#(
        .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
        .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .CHECK_CMT_OVERLAP(CHECK_CMT_OVERLAP)
    ) transaction_t;
    typedef NorthcapeGenerator#(transaction_t) generator_t;

    typedef virtual NorthcapeCMTInterface #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ).TEST_PRODUCER cmt_interface_t;

    typedef NorthcapeMMUAgentConfig#(
        .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
        .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .CHECK_CMT_OVERLAP(CHECK_CMT_OVERLAP)
    ) agent_config_t;

    typedef NorthcapeMMUScoreboard#(
        .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
        .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .CHECK_RESOLVER_RESULT(CHECK_RESOLVER_RESULT),
        .CHECK_CMT_OVERLAP(CHECK_CMT_OVERLAP)
    ) scoreboard_t;

    typedef uvm_analysis_port#(Axi5SlaveDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    )) slave_analysis_port_t;

    typedef uvm_analysis_port#(Axi5MasterDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    )) master_analysis_port_t;

    typedef uvm_analysis_port#(AxisValidateResultTransaction) resolver_analysis_port_t;


    localparam string TRANSACTIONS_QUEUE_NAME_SCOREBOARD = "mmu_transactions_scoreboard";

    typedef NorthcapeDirectSequence#(
        .TRANSACTION_TYPE(transaction_t),
        .TRANSACTION_QUEUE_NAME(TRANSACTIONS_QUEUE_NAME_SCOREBOARD)
    ) scoreboard_sequence_t;

    // sequence is always 1:1 between sequencer and driver
    scoreboard_sequence_t sequence_scoreboard;
    uvm_sequencer #(transaction_t) sequencer_scoreboard;

    scoreboard_t scoreboard;

    transaction_t current_transaction = generator_t::generate_transaction_ephemeral();

    `AXI5_TEST_DECLARE_COVERAGE_GROUP(current_transaction)

    slave_mailbox_t requests_in_slave;
    master_mailbox_t requests_in_master;
    resolver_mailbox_t validate_requests_read;
    resolver_mailbox_t validate_requests_write;

    uvm_queue #(transaction_t) transactions;

    cmt_interface_t cmt_interface;

    // analysis ports connect scoreboard with drivers' results
    // APs are defined in the top module
    slave_analysis_port_t slave_analysis_port;
    master_analysis_port_t master_analysis_port;

    resolver_analysis_port_t read_resolver_analysis_port;
    resolver_analysis_port_t write_resolver_analysis_port;

    // actual checking is implemented with the transactions
    // generic checker implements this in a uniform way
    NorthcapeGenericChecker generic_checker;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      `AXI5_TEST_INIT_COVERAGE_GROUP(current_transaction)
    endfunction

    function void build_phase(uvm_phase phase);

      agent_config_t agent_config;

      if (!uvm_config_db#(agent_config_t)::get(this, "", MMU_AGENT_CONFIG_NAME, agent_config)) begin
        `uvm_fatal(COMPONENT_NAME, "Failed to get config object!");
      end

      this.requests_in_slave = agent_config.requests_in_slave;
      this.requests_in_master = agent_config.requests_in_master;
      this.validate_requests_read = agent_config.validate_requests_read;
      this.validate_requests_write = agent_config.validate_requests_write;

      this.slave_analysis_port = agent_config.slave_analysis_port;
      this.master_analysis_port = agent_config.master_analysis_port;
      this.read_resolver_analysis_port = agent_config.read_resolver_analysis_port;
      this.write_resolver_analysis_port = agent_config.write_resolver_analysis_port;

      this.cmt_interface = agent_config.cmt_interface;


      this.scoreboard = new("scoreboard", this);
      this.sequence_scoreboard = new("scoreboard_sequence");
      this.sequencer_scoreboard = new("scoreboard_sequencer", this);

      this.generic_checker = new("checker", this);

    endfunction

    function void connect_phase(uvm_phase phase);
      scoreboard.transaction_port.connect(sequencer_scoreboard.seq_item_export);
      slave_analysis_port.connect(scoreboard.slave_result_fifo.analysis_export);
      master_analysis_port.connect(scoreboard.master_result_fifo.analysis_export);

      if (CHECK_RESOLVER_RESULT) begin
        read_resolver_analysis_port.connect(scoreboard.resolver_result_fifo_read.analysis_export);
        write_resolver_analysis_port.connect(scoreboard.resolver_result_fifo_write.analysis_export);
      end

      scoreboard.checker_port.connect(generic_checker.analysis_export);
    endfunction

    typedef NorthcapeMMUTransactionSlave#(
        .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
        .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .CHECK_CMT_OVERLAP(CHECK_CMT_OVERLAP)
    ) slave_transaction_t;

    typedef NorthcapeMMUTransactionMaster#(
        .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
        .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .CHECK_CMT_OVERLAP(CHECK_CMT_OVERLAP)
    ) master_transaction_t;

    typedef NorthcapeMMUTransactionResolver#(
        .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
        .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .CHECK_CMT_OVERLAP(CHECK_CMT_OVERLAP)
    ) resolver_transaction_t;

    // used to ensure that the ops module has completed creating the capability before we start using it
    semaphore mmu_transactions_available;
    semaphore mmu_finished;


    task run_phase(uvm_phase phase);
      slave_transaction_t slave_transaction;
      master_transaction_t master_transaction;
      resolver_transaction_t resolver_transaction;
      transaction_t transaction_scoreboard;
      int unsigned transaction_num;

      uvm_queue #(transaction_t) transactions, transactions_scoreboard;

      phase.raise_objection(this);

      // might only exist at run time
      if (!uvm_config_db#(uvm_queue#(transaction_t))::get(
              null, "", TRANSACTIONS_QUEUE_NAME_AGENT, transactions
          )) begin
        `uvm_fatal(COMPONENT_NAME, "Failed to get transactions object!");
      end

      transactions_scoreboard = new("Scoreboard transactions MMU");
      transactions_scoreboard.delete();

      uvm_config_db#(uvm_queue#(transaction_t))::set(null, "", TRANSACTIONS_QUEUE_NAME_SCOREBOARD,
                                                     transactions_scoreboard);

      // have to wait for integration agent to complete setup, generate a transaction for us
      if (mmu_transactions_available != null) begin
        `uvm_info(COMPONENT_NAME, "Waiting for lockstep sema", UVM_HIGH);
        mmu_transactions_available.get();
        `uvm_info(COMPONENT_NAME, "Lockstep sema triggered", UVM_HIGH);
      end

      while (transactions.size() > 0) begin

        `uvm_info(COMPONENT_NAME, "Waiting for transaction in FIFO!", UVM_HIGH);
        current_transaction = transactions.pop_front();
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Got transaction from FIFO: %s", current_transaction.convert2string()), UVM_HIGH);


        transaction_scoreboard = new("Scoreboard transaction");
        transaction_scoreboard.do_copy(current_transaction);

        transactions_scoreboard.push_back(transaction_scoreboard);

        if (transaction_scoreboard == null) begin
          `uvm_fatal(COMPONENT_NAME, "Could not clone transaction!");
        end

        slave_transaction = new("slave_transaction");
        master_transaction = new("master_transaction");
        resolver_transaction = new("resolver_transaction");

        slave_transaction.do_copy(current_transaction);
        master_transaction.do_copy(current_transaction);
        resolver_transaction.do_copy(current_transaction);


        if (cmt_interface) begin
          // in integration test, this is not used
          cmt_interface.test_producer_clocking.cmt_base <= current_transaction.cmt_base_addr;
          cmt_interface.test_producer_clocking.table_size_clog2 <= current_transaction.cmt_size_clog2;
        end

        if (current_transaction.call_overlaps_cmt()) begin
          `uvm_info(COMPONENT_NAME, "CMT overlaps!", UVM_DEBUG);
        end else begin
          `uvm_info(COMPONENT_NAME, "CMT cleared!", UVM_DEBUG);
        end

        if (current_transaction.axi_request_type == AXI_TEST_READ) begin
          if (validate_requests_read) begin
            validate_requests_read.put(resolver_transaction);
          end
        end else begin
          if (validate_requests_write) begin
            validate_requests_write.put(resolver_transaction);
          end
        end

        requests_in_slave.put(slave_transaction);

        if (current_transaction.invalid_access == 0) begin
          requests_in_master.put(master_transaction);
        end

        `AXI5_TEST_SAMPLE_COVERAGE_GROUP(current_transaction);

        // sequence terminates when scoreboard has consumed the last item - by then, we know that the transaction has been processed
        `uvm_info(COMPONENT_NAME, "sb sequence start", UVM_HIGH);
        sequence_scoreboard.start(sequencer_scoreboard);
        `uvm_info(COMPONENT_NAME, "sb sequence end", UVM_HIGH);

        if (mmu_finished != null) begin
          mmu_finished.put();
        end

        // have to wait for integration agent to complete setup, generate a transaction for us
        if (mmu_transactions_available != null) begin
          `uvm_info(COMPONENT_NAME, "Waiting for lockstep sema", UVM_HIGH);
          mmu_transactions_available.get();
          `uvm_info(COMPONENT_NAME, "Lockstep sema triggered", UVM_HIGH);
        end


        transaction_num++;
        `uvm_info(COMPONENT_NAME, $sformatf("Finished transaction %d", transaction_num),
                  UVM_MEDIUM);

      end

      phase.drop_objection(this);


    endtask

  endclass

endpackage
