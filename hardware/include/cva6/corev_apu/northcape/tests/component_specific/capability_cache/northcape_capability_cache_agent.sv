/**
  * Agent for Northcape Capability Cache
  */
package northcape_capability_cache_agent;

  import axi5::*;
  import northcape_test::*;
  import northcape_types::*;
  import northcape_capability_cache_scoreboard::NorthcapeCapabilityCacheScoreboard;
  import northcape_capability_cache_transaction::*;
  import northcape_sequence::NorthcapeDirectSequence;
  import northcape_sequence::NorthcapeSingleSequence;
  import northcape_generic_checker::*;

  import northcape_capability_cache_driver::*;
  import northcape_capability_cache_common::*;


  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class automatic NorthcapeCapabilityCacheAgentConfig #(
      parameter AXI_ADDR_WIDTH = -1,

      parameter HASH_TYPE = -1,

      parameter bit [AXI_ADDR_WIDTH-1:0] INITIAL_CMT_BASE = -1,
      parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1
  );
    typedef virtual NorthcapeCMTInterface #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ).TEST_CONSUMER cmt_interface_t;

    typedef virtual NorthcapeCapabilityCacheInterfaceResolverTest resolver_interface_t;
    typedef virtual NorthcapeCapabilityCacheInterfaceOpsTest ops_interface_t;

    logic [AXI_ADDR_WIDTH-1:0] initial_cmt_base;
    int unsigned initial_cmt_size_clog2;

    resolver_interface_t resolver_interface;
    ops_interface_t ops_interface;

    virtual northcape_test_reset reset_intf;

    cmt_interface_t cmt_intf;



    function new(cmt_interface_t cmt_intf, logic [AXI_ADDR_WIDTH-1:0] initial_cmt_base,
                 int unsigned initial_cmt_size_clog2, resolver_interface_t resolver_interface,
                 ops_interface_t ops_interface, virtual northcape_test_reset reset_intf);

      this.initial_cmt_base = initial_cmt_base;
      this.initial_cmt_size_clog2 = initial_cmt_size_clog2;

      this.resolver_interface = resolver_interface;
      this.ops_interface = ops_interface;

      this.reset_intf = reset_intf;

      this.cmt_intf = cmt_intf;
    endfunction

  endclass


  class automatic NorthcapeCapabilityCacheAgent #(
      parameter AXI_ADDR_WIDTH = -1,

      parameter HASH_TYPE = -1,

      parameter bit [AXI_ADDR_WIDTH-1:0] INITIAL_CMT_BASE = -1,
      parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1,


      parameter string CAPABILITY_CACHE_AGENT_CONFIG_NAME = "",
      parameter string TRANSACTIONS_QUEUE_NAME_AGENT = ""
  ) extends uvm_agent;

    function new(string name = "", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    typedef NorthcapeCapabilityCacheTransaction transaction_t;


    typedef virtual NorthcapeCMTInterface #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ).TEST_CONSUMER cmt_interface_t;




    logic [AXI_ADDR_WIDTH-1:0] initial_cmt_base;
    int unsigned initial_cmt_size_clog2;
    // TODO tooling bug - Vivado does not allow me to typedef here
    virtual NorthcapeCapabilityCacheInterfaceResolverTest resolver_interface;
    virtual NorthcapeCapabilityCacheInterfaceOpsTest ops_interface;

    cmt_interface_t cmt_intf;

    virtual northcape_test_reset reset_intf;

    localparam string COMPONENT_NAME = "Northcape Capability Cache Agent";

    localparam string TRANSACTIONS_QUEUE_NAME_SCOREBOARD = "capability_cache_transactions_scoreboard";

    typedef NorthcapeDirectSequence#(
        .TRANSACTION_TYPE(transaction_t),
        .TRANSACTION_QUEUE_NAME(TRANSACTIONS_QUEUE_NAME_SCOREBOARD)
    ) scoreboard_sequence_t;

    typedef NorthcapeSingleSequence#(
        .TRANSACTION_TYPE(NorthcapeCapabilityCacheResolverTransaction)
    ) resolver_sequence_t;

    typedef NorthcapeSingleSequence#(
        .TRANSACTION_TYPE(NorthcapeCapabilityCacheOpsTransaction)
    ) ops_sequence_t;
    // sequence is always 1:1 between sequencer and driver
    scoreboard_sequence_t sequence_scoreboard;
    uvm_sequencer #(transaction_t) sequencer_scoreboard;

    typedef NorthcapeCapabilityCacheScoreboard#(
        .TRANSACTIONS_QUEUE_NAME_SCOREBOARD(TRANSACTIONS_QUEUE_NAME_SCOREBOARD)
    ) scoreboard_t;
    scoreboard_t scoreboard;

    typedef uvm_sequencer#(NorthcapeCapabilityCacheResolverTransaction) resolver_sequencer_t;
    typedef uvm_sequencer#(NorthcapeCapabilityCacheOpsTransaction) ops_sequencer_t;

    resolver_sequencer_t sequencer_resolver;
    ops_sequencer_t sequencer_ops;

    // actual checking is implemented with the transactions
    // generic checker implements this in a uniform way
    NorthcapeGenericChecker generic_checker;



    typedef NorthcapeCapabilityCacheAgentConfig#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),

        .HASH_TYPE(HASH_TYPE),

        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) agent_config_t;

    NorthcapeCapabilityCacheResolverDriver resolver_driver;
    NorthcapeCapabilityCacheOpsDriver ops_driver;


    function void build_phase(uvm_phase phase);

      agent_config_t agent_config;


      `uvm_info(COMPONENT_NAME, $sformatf(
                "Retrieving Capability Cache Agent Config of type %s name %s into config DB!",
                $typename(
                    agent_config
                ),
                CAPABILITY_CACHE_AGENT_CONFIG_NAME
                ), UVM_DEBUG);

      if (!uvm_config_db#(agent_config_t)::get(
              this, "", CAPABILITY_CACHE_AGENT_CONFIG_NAME, agent_config
          )) begin
        `uvm_fatal(COMPONENT_NAME, "Failed to get config object!");
      end

      this.initial_cmt_base = agent_config.initial_cmt_base;
      this.initial_cmt_size_clog2 = agent_config.initial_cmt_size_clog2;
      this.ops_interface = agent_config.ops_interface;
      this.resolver_interface = agent_config.resolver_interface;
      this.cmt_intf = agent_config.cmt_intf;
      this.reset_intf = agent_config.reset_intf;


      this.scoreboard = new("scoreboard", this);
      this.sequence_scoreboard = new("scoreboard_sequence");
      this.sequencer_scoreboard = new("scoreboard_sequencer", this);

      this.generic_checker = new("checker", this);

      this.resolver_driver = new(this.resolver_interface, "Resolver driver", this);
      this.ops_driver = new(this.ops_interface, "Ops driver", this);

      this.sequencer_resolver = new("Resolver sequencer", this);
      this.sequencer_ops = new("Ops sequencer", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      scoreboard.transaction_port.connect(sequencer_scoreboard.seq_item_export);

      scoreboard.checker_port.connect(generic_checker.analysis_export);

      resolver_driver.ap.connect(scoreboard.resolver_result_fifo.analysis_export);
      resolver_driver.seq_item_port.connect(sequencer_resolver.seq_item_export);

      ops_driver.ap.connect(scoreboard.ops_result_fifo.analysis_export);
      ops_driver.seq_item_port.connect(sequencer_ops.seq_item_export);
    endfunction

    task handle_one_transaction(transaction_t current_transaction);
      resolver_sequence_t resolver_sequence;
      ops_sequence_t ops_sequence;

      `uvm_info(COMPONENT_NAME, $sformatf("Got transaction %s", current_transaction.convert2string()
                ), UVM_DEBUG);

      if (current_transaction.active_port == NORTHCAPE_CAP_CACHE_RESOLVER) begin
        resolver_sequence = new("Resolver sequence");
        resolver_sequence.transaction = current_transaction.to_resolver_transaction();
        resolver_sequence.start(sequencer_resolver);
      end else begin
        ops_sequence = new("Ops sequence");
        ops_sequence.transaction = current_transaction.to_ops_transaction();
        ops_sequence.start(sequencer_ops);
      end

    endtask

    task run_phase(uvm_phase phase);
      transaction_t current_transaction, next_transaction;
      uvm_queue #(transaction_t) transactions, transactions_scoreboard;
      int unsigned test_id;

      phase.raise_objection(this);

      `uvm_info(COMPONENT_NAME, "Agent reset phase start!", UVM_MEDIUM);

      reset_intf.reset_clocking.resetn <= 0;
      @(reset_intf.reset_clocking);
      @(reset_intf.reset_clocking);

      reset_intf.reset_clocking.resetn <= 1;
      @(reset_intf.reset_clocking);
      @(reset_intf.reset_clocking);



      `uvm_info(COMPONENT_NAME, "Agent reset phase complete!", UVM_MEDIUM);


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

      while (transactions.size() > 0) begin : transactionForward
        current_transaction = transactions.pop_front();
        next_transaction = null;

        if (transactions.size() > 0) begin
          next_transaction = transactions.get(0);
        end

        if(next_transaction && next_transaction.active_port != current_transaction.active_port)
        begin
          // need to remove it so it is not doubly executed
          next_transaction = transactions.pop_front();
          // can dispatch two transactions in parallel
          // ops needs to be given to scoreboard first so read predicts correctly
          if (next_transaction.active_port != NORTHCAPE_CAP_CACHE_RESOLVER) begin
            transaction_t tmp = next_transaction;
            next_transaction = current_transaction;
            current_transaction = tmp;
          end

          transactions_scoreboard.push_back(current_transaction);
          transactions_scoreboard.push_back(next_transaction);
          // can be issued in parallel
          fork
            handle_one_transaction(current_transaction);
            handle_one_transaction(next_transaction);
          join
        end else begin
          transactions_scoreboard.push_back(current_transaction);
          // single transaction
          handle_one_transaction(current_transaction);
          // only count once
          next_transaction = null;
        end

        `uvm_info(COMPONENT_NAME, "Starting scoreboard sequence!", UVM_HIGH);
        sequence_scoreboard.start(sequencer_scoreboard);

        test_id++;
        `uvm_info(COMPONENT_NAME, $sformatf("Finished transaction %d", test_id), UVM_MEDIUM);

        if (next_transaction) begin
          test_id++;
          `uvm_info(COMPONENT_NAME, $sformatf("Finished transaction %d (double issue)", test_id),
                    UVM_MEDIUM);
        end

      end : transactionForward

      phase.drop_objection(this);


    endtask
  endclass


endpackage
