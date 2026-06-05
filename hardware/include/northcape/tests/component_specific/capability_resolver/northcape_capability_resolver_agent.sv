

/**
  * Agent, i.e., test orchestrator for DMA.
  */

package northcape_capability_resolver_agent;

  import northcape_types::*;
  import northcape_test::*;
  import axi5::*;
  import northcape_generator::NorthcapeGenerator;
  import northcape_capability_resolver_scoreboard::NorthcapeCapabilityResolverScoreboard;
  import northcape_capability_resolver_transaction::*;
  import northcape_axis5_driver::*;
  import northcape_sequence::NorthcapeDirectSequence;
  import northcape_generic_checker::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  /**
 * Holds all configuration used in the capability resolver agent.
 */
  class NorthcapeCapabilityResolverAgentConfig #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      // parameters for AXIs request interface (input of the resolver)
      parameter AXIS_REQUEST_TDATA_WIDTH = -1,
      parameter AXIS_REQUEST_TID_WIDTH   = -1,
      parameter AXIS_REQUEST_TDEST_WIDTH = -1,
      parameter AXIS_REQUEST_TUSER_WIDTH = -1,

      // parameters for AXIs response interface (output of the resolver)
      parameter AXIS_RESPONSE_TDATA_WIDTH = -1,
      parameter AXIS_RESPONSE_TID_WIDTH   = -1,
      parameter AXIS_RESPONSE_TDEST_WIDTH = -1,
      parameter AXIS_RESPONSE_TUSER_WIDTH = -1
  );
    typedef INorthcapeAXITransactionMasterSide#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) axi_master_transaction_t;

    typedef virtual Axis5Test #(
        .AXIS_TDATA_WIDTH(AXIS_REQUEST_TDATA_WIDTH),
        .AXIS_TID_WIDTH  (AXIS_REQUEST_TID_WIDTH),
        .AXIS_TDEST_WIDTH(AXIS_REQUEST_TDEST_WIDTH),
        .AXIS_TUSER_WIDTH(AXIS_REQUEST_TUSER_WIDTH)
    ) axis5_request_t;

    typedef virtual Axis5Test #(
        .AXIS_TDATA_WIDTH(AXIS_RESPONSE_TDATA_WIDTH),
        .AXIS_TID_WIDTH  (AXIS_RESPONSE_TID_WIDTH),
        .AXIS_TDEST_WIDTH(AXIS_RESPONSE_TDEST_WIDTH),
        .AXIS_TUSER_WIDTH(AXIS_RESPONSE_TUSER_WIDTH)
    ) axis5_response_t;

    typedef uvm_analysis_port#(Axi5MasterDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    )) master_analysis_port_t;

    typedef virtual NorthcapeCMTInterface #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ).TEST_PRODUCER cmt_interface_t;

    axis5_request_t request;
    axis5_response_t response;

    cmt_interface_t cmt_intf;

    mailbox #(axi_master_transaction_t) requests_in_master;

    master_analysis_port_t master_analysis_port;


    function new(cmt_interface_t cmt_intf, axis5_request_t request, axis5_response_t response,
                 mailbox#(axi_master_transaction_t) requests_in_master,
                 master_analysis_port_t master_analysis_port);
      this.requests_in_master = requests_in_master;
      this.request = request;
      this.response = response;
      this.cmt_intf = cmt_intf;
      this.master_analysis_port = master_analysis_port;
    endfunction

  endclass

  /**
  * Capability Resolver agent.
  */
  class NorthcapeCapabilityResolverAgent #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      // parameters for AXIs request interface (input of the resolver)
      parameter AXIS_REQUEST_TDATA_WIDTH = -1,
      parameter AXIS_REQUEST_TID_WIDTH   = -1,
      parameter AXIS_REQUEST_TDEST_WIDTH = -1,
      parameter AXIS_REQUEST_TUSER_WIDTH = -1,

      // parameters for AXIs response interface (output of the resolver)
      parameter AXIS_RESPONSE_TDATA_WIDTH = -1,
      parameter AXIS_RESPONSE_TID_WIDTH   = -1,
      parameter AXIS_RESPONSE_TDEST_WIDTH = -1,
      parameter AXIS_RESPONSE_TUSER_WIDTH = -1,

      parameter string TRANSACTIONS_QUEUE_NAME_AGENT = ""
  ) extends uvm_agent;
    typedef NorthcapeCapabilityResolverTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXIS_REQUEST_TDATA_WIDTH(AXIS_REQUEST_TDATA_WIDTH),
        .AXIS_REQUEST_TID_WIDTH  (AXIS_REQUEST_TID_WIDTH),
        .AXIS_REQUEST_TDEST_WIDTH(AXIS_REQUEST_TDEST_WIDTH),
        .AXIS_REQUEST_TUSER_WIDTH(AXIS_REQUEST_TUSER_WIDTH),

        .AXIS_RESPONSE_TDATA_WIDTH(AXIS_RESPONSE_TDATA_WIDTH),
        .AXIS_RESPONSE_TID_WIDTH  (AXIS_RESPONSE_TID_WIDTH),
        .AXIS_RESPONSE_TDEST_WIDTH(AXIS_RESPONSE_TDEST_WIDTH),
        .AXIS_RESPONSE_TUSER_WIDTH(AXIS_RESPONSE_TUSER_WIDTH)
    ) transaction_t;

    localparam string COMPONENT_NAME = "Northcape Capability Resolver Agent";

    typedef NorthcapeCapabilityResolverTransactionAxiMaster#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXIS_REQUEST_TDATA_WIDTH(AXIS_REQUEST_TDATA_WIDTH),
        .AXIS_REQUEST_TID_WIDTH  (AXIS_REQUEST_TID_WIDTH),
        .AXIS_REQUEST_TDEST_WIDTH(AXIS_REQUEST_TDEST_WIDTH),
        .AXIS_REQUEST_TUSER_WIDTH(AXIS_REQUEST_TUSER_WIDTH),

        .AXIS_RESPONSE_TDATA_WIDTH(AXIS_RESPONSE_TDATA_WIDTH),
        .AXIS_RESPONSE_TID_WIDTH  (AXIS_RESPONSE_TID_WIDTH),
        .AXIS_RESPONSE_TDEST_WIDTH(AXIS_RESPONSE_TDEST_WIDTH),
        .AXIS_RESPONSE_TUSER_WIDTH(AXIS_RESPONSE_TUSER_WIDTH)
    ) axi_transaction_t;

    typedef NorthcapeCapabilityResolverTransactionAxisTransmitter#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXIS_REQUEST_TDATA_WIDTH(AXIS_REQUEST_TDATA_WIDTH),
        .AXIS_REQUEST_TID_WIDTH  (AXIS_REQUEST_TID_WIDTH),
        .AXIS_REQUEST_TDEST_WIDTH(AXIS_REQUEST_TDEST_WIDTH),
        .AXIS_REQUEST_TUSER_WIDTH(AXIS_REQUEST_TUSER_WIDTH),

        .AXIS_RESPONSE_TDATA_WIDTH(AXIS_RESPONSE_TDATA_WIDTH),
        .AXIS_RESPONSE_TID_WIDTH  (AXIS_RESPONSE_TID_WIDTH),
        .AXIS_RESPONSE_TDEST_WIDTH(AXIS_RESPONSE_TDEST_WIDTH),
        .AXIS_RESPONSE_TUSER_WIDTH(AXIS_RESPONSE_TUSER_WIDTH)
    ) axis_transaction_t;

    typedef NorthcapeCapabilityResolverAgentConfig#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),

        .AXIS_REQUEST_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH),
        .AXIS_REQUEST_TID_WIDTH  (AXIS_VALIDATE_REQUEST_TID_WIDTH),
        .AXIS_REQUEST_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
        .AXIS_REQUEST_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH),

        .AXIS_RESPONSE_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH),
        .AXIS_RESPONSE_TID_WIDTH  (AXIS_VALIDATE_RESPONSE_TID_WIDTH),
        .AXIS_RESPONSE_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH),
        .AXIS_RESPONSE_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH)
    ) agent_config_t;

    typedef NorthcapeCapabilityResolverScoreboard#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),

        .AXIS_REQUEST_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH),
        .AXIS_REQUEST_TID_WIDTH  (AXIS_VALIDATE_REQUEST_TID_WIDTH),
        .AXIS_REQUEST_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
        .AXIS_REQUEST_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH),

        .AXIS_RESPONSE_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH),
        .AXIS_RESPONSE_TID_WIDTH  (AXIS_VALIDATE_RESPONSE_TID_WIDTH),
        .AXIS_RESPONSE_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH),
        .AXIS_RESPONSE_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH)
    ) scoreboard_t;

    typedef INorthcapeAXITransactionMasterSide#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) axi_master_transaction_t;

    typedef virtual Axis5Test #(
        .AXIS_TDATA_WIDTH(AXIS_REQUEST_TDATA_WIDTH),
        .AXIS_TID_WIDTH  (AXIS_REQUEST_TID_WIDTH),
        .AXIS_TDEST_WIDTH(AXIS_REQUEST_TDEST_WIDTH),
        .AXIS_TUSER_WIDTH(AXIS_REQUEST_TUSER_WIDTH)
    ) axis5_request_t;

    typedef virtual Axis5Test #(
        .AXIS_TDATA_WIDTH(AXIS_RESPONSE_TDATA_WIDTH),
        .AXIS_TID_WIDTH  (AXIS_RESPONSE_TID_WIDTH),
        .AXIS_TDEST_WIDTH(AXIS_RESPONSE_TDEST_WIDTH),
        .AXIS_TUSER_WIDTH(AXIS_RESPONSE_TUSER_WIDTH)
    ) axis5_response_t;

    scoreboard_t scoreboard;

    localparam string AXIS_TRANSMIT_INTERFACE_NAME = "capability_resolver_axis_transmit_interface";
    localparam string AXIS_RECEIVE_INTERFACE_NAME = "capability_resolver_axis_receive_interface";

    typedef Axis5TransmitterDriver#(
        .AXIS_TDATA_WIDTH(AXIS_REQUEST_TDATA_WIDTH),
        .AXIS_TID_WIDTH  (AXIS_REQUEST_TID_WIDTH),
        .AXIS_TDEST_WIDTH(AXIS_REQUEST_TDEST_WIDTH),
        .AXIS_TUSER_WIDTH(AXIS_REQUEST_TUSER_WIDTH),

        .INTERFACE_NAME(AXIS_TRANSMIT_INTERFACE_NAME),
        .SEQUENCE_ITEM_TYPE(axis_transaction_t)
    ) axis_request_driver_t;

    axis_request_driver_t request_driver;

    typedef Axis5ReceiverMonitor#(
        .AXIS_TDATA_WIDTH(AXIS_RESPONSE_TDATA_WIDTH),
        .AXIS_TID_WIDTH  (AXIS_RESPONSE_TID_WIDTH),
        .AXIS_TDEST_WIDTH(AXIS_RESPONSE_TDEST_WIDTH),
        .AXIS_TUSER_WIDTH(AXIS_RESPONSE_TUSER_WIDTH),

        .INTERFACE_NAME(AXIS_RECEIVE_INTERFACE_NAME)
    ) axis_response_monitor_t;

    axis_response_monitor_t response_monitor;

    typedef uvm_analysis_port#(Axi5MasterDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    )) master_analysis_port_t;

    typedef virtual NorthcapeCMTInterface #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ).TEST_PRODUCER cmt_interface_t;

    int unsigned test_id;

    axis5_request_t request;
    axis5_response_t response;

    cmt_interface_t cmt_intf;

    mailbox #(axi_master_transaction_t) requests_in_master;

    master_analysis_port_t master_analysis_port;

    localparam string TRANSACTIONS_QUEUE_NAME_SCOREBOARD = "capability_resolver_transactions_scoreboard";
    localparam string TRANSACTIONS_QUEUE_NAME_AXIS = "capability_resolver_transactions_axis";

    typedef NorthcapeDirectSequence#(
        .TRANSACTION_TYPE(transaction_t),
        .TRANSACTION_QUEUE_NAME(TRANSACTIONS_QUEUE_NAME_SCOREBOARD)
    ) scoreboard_sequence_t;

    typedef NorthcapeDirectSequence#(
        .TRANSACTION_TYPE(axis_transaction_t),
        .TRANSACTION_QUEUE_NAME(TRANSACTIONS_QUEUE_NAME_AXIS)
    ) axis_sequence_t;

    // sequence is always 1:1 between sequencer and driver
    scoreboard_sequence_t sequence_scoreboard;
    uvm_sequencer #(transaction_t) sequencer_scoreboard;

    axis_sequence_t sequence_axis;
    uvm_sequencer #(axis_transaction_t) sequencer_axis;

    uvm_queue #(transaction_t) transactions;

    // actual checking is implemented with the transactions
    // generic checker implements this in a uniform way
    NorthcapeGenericChecker generic_checker;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);

      agent_config_t agent_config;

      if (!uvm_config_db#(agent_config_t)::get(
              this, "", "capability_resolver_agent_config", agent_config
          )) begin
        `uvm_fatal(COMPONENT_NAME, "Failed to get config object!");
      end

      this.requests_in_master = agent_config.requests_in_master;
      this.request = agent_config.request;
      this.response = agent_config.response;
      this.cmt_intf = agent_config.cmt_intf;
      this.master_analysis_port = agent_config.master_analysis_port;


      this.scoreboard = new("scoreboard", this);
      this.sequence_scoreboard = new("scoreboard_sequence");
      this.sequencer_scoreboard = new("scoreboard_sequencer", this);


      this.sequence_axis = new("axis_sequence");
      this.sequencer_axis = new("axis_sequencer", this);

      this.generic_checker = new("checker", this);

      this.request_driver = new("request_driver", this);
      this.response_monitor = new("response_monitor", this);

      uvm_config_db#(axis5_request_t)::set(null, "", AXIS_TRANSMIT_INTERFACE_NAME, request);
      uvm_config_db#(axis5_response_t)::set(null, "", AXIS_RECEIVE_INTERFACE_NAME, response);

      assert (uvm_config_db#(master_analysis_port_t)::get(
          null, "", "capability_resolver_master_analysis_port", master_analysis_port
      ));
    endfunction

    function void connect_phase(uvm_phase phase);
      scoreboard.transaction_port.connect(sequencer_scoreboard.seq_item_export);
      request_driver.seq_item_port.connect(sequencer_axis.seq_item_export);
      master_analysis_port.connect(scoreboard.master_result_fifo.analysis_export);

      response_monitor.ap.connect(scoreboard.resolver_response_fifo.analysis_export);


      scoreboard.checker_port.connect(generic_checker.analysis_export);
    endfunction


    task automatic run_phase(uvm_phase phase);
      transaction_t current_transaction;
      uvm_queue #(transaction_t) transactions, transactions_scoreboard;
      uvm_queue #(axis_transaction_t) transactions_axis;
      axi_transaction_t master_transaction;
      axis_transaction_t axis_transaction;
      int unsigned test_id;

      phase.raise_objection(this);

      `uvm_info(COMPONENT_NAME, "Agent run phase start", UVM_MEDIUM);

      transactions_scoreboard = new("Scoreboard transactions");
      uvm_config_db#(uvm_queue#(transaction_t))::set(null, "", TRANSACTIONS_QUEUE_NAME_SCOREBOARD,
                                                     transactions_scoreboard);

      transactions_axis = new("Axis transactions");
      uvm_config_db#(uvm_queue#(axis_transaction_t))::set(null, "", TRANSACTIONS_QUEUE_NAME_AXIS,
                                                          transactions_axis);

      // might only exist at run time
      if (!uvm_config_db#(uvm_queue#(transaction_t))::get(
              null, "", TRANSACTIONS_QUEUE_NAME_AGENT, transactions
          )) begin
        `uvm_fatal(COMPONENT_NAME, "Failed to get transactions object!");
      end

      while (transactions.size() > 0) begin : transactionForward
        current_transaction = transactions.pop_front();

        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Got transaction from FIFO: %s", current_transaction.convert2string()),
                  UVM_DEBUG);

        cmt_intf.test_producer_clocking.cmt_base <= current_transaction.cmt_base_addr;
        cmt_intf.test_producer_clocking.table_size_clog2 <= current_transaction.table_size_clog_2;

        transactions_scoreboard.push_back(current_transaction);

        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Copying transaction %s type %s to master transaction",
                  current_transaction.convert2string(),
                  $typename(
                      current_transaction
                  )
                  ), UVM_DEBUG);


        for (int i = 0; i < current_transaction.entries.size(); i++) begin
          master_transaction = new("axi_master_transaction");
          master_transaction.do_copy(current_transaction);
          master_transaction.entry_number = i;

          requests_in_master.put(master_transaction);
        end

        `uvm_info(COMPONENT_NAME, "Copying to axis transaction", UVM_DEBUG);
        axis_transaction = new("axis_transaction");
        axis_transaction.do_copy(current_transaction);



        // master needs to retrieve request such that it does not accidentally accept
        @(posedge (request.clk_i));
        @(posedge (request.clk_i));

        @(posedge (request.clk_i));
        @(posedge (request.clk_i));

        transactions_axis.push_back(axis_transaction);


        `uvm_info(COMPONENT_NAME, "Starting Axis sequence!", UVM_HIGH);
        sequence_axis.start(sequencer_axis);

        `uvm_info(COMPONENT_NAME, "Starting scoreboard sequence!", UVM_HIGH);
        sequence_scoreboard.start(sequencer_scoreboard);

        test_id++;
        `uvm_info(COMPONENT_NAME, $sformatf("Finished transaction %d", test_id), UVM_MEDIUM);

      end : transactionForward

      phase.drop_objection(this);

    endtask

  endclass

endpackage : northcape_capability_resolver_agent
