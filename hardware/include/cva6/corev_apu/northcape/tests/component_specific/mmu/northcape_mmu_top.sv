
`include "uvm_macros.svh"

/**
  * Top-level module that has all of the wirings for testing the MMU.
  */
module northcape_mmu_top;
  import northcape_types::*;
  import northcape_test::*;
  import uvm_pkg::*;
  import northcape_mmu_agent::NorthcapeMMUAgentConfig;
  import uvm_test_discovery::test_northcape_discover_tests;
  import northcape_mmu_test_constants::*;

  typedef virtual northcape_test_reset reset_intf_t;

  logic clk_i;
  logic rst_ni;


  Axis5 #(
      .AXIS_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_REQUEST_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH)
  )
      axis_validate_request_read (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      axis_validate_request_write (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );
  Axis5 #(
      .AXIS_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH),
      .AXIS_TID_WIDTH  (AXIS_VALIDATE_RESPONSE_TID_WIDTH),
      .AXIS_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH),
      .AXIS_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH)
  )
      axis_validate_response_read (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      ),
      axis_validate_response_write (
          .clk_i (clk_i),
          .rst_ni(rst_ni)
      );

  // interface that goes to SLAVE port of MMU
  Axi5 #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) axi_in (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );


  // interface that goes to MASTER port of MMU
  Axi5 #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) axi_out (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  // CMT metadata from test / ops module
  NorthcapeCMTInterface #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) cmt_interface (.clk_i(clk_i));

  assign cmt_interface.reset_done = 1;

  // queue of slave test requests
  mailbox #(INorthcapeAXITransactionSlaveSide #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )) requests_in_slave;

  // queue of master test requests
  mailbox #(INorthcapeAXITransactionMasterSide #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )) requests_in_master;

  // queue of validate requests
  mailbox #(INorthcapeCapabilityResolverTransaction)
      validate_requests_read, validate_requests_write;

  initial begin
    requests_in_slave = new;
    requests_in_master = new;

    validate_requests_read = new;
    validate_requests_write = new;
  end

  northcape_test_clock_generator #(.CLOCK_PERIOD_NS(10)) clock_generator (.clk_i(clk_i));

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



  slave_analysis_port_t slave_analysis_port;
  master_analysis_port_t master_analysis_port;

  resolver_analysis_port_t read_resolver_analysis_port;
  resolver_analysis_port_t write_resolver_analysis_port;

  initial begin
    slave_analysis_port = new("slave_analysis_port", null);
    master_analysis_port = new("mmu_master_analysis_port", null);
    read_resolver_analysis_port = new("read_resolver_analysis_port", null);
    write_resolver_analysis_port = new("write_resolver_analysis_port", null);
  end

  axi5_slave_driver #(
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
  ) test_request_generator (
      .requests_in(requests_in_slave),

      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .axi_slave(axi_in),

      .ap_i(slave_analysis_port)
  );

  northcape_mmu #(
`ifdef NORTHCAPE_MMU_NO_AXI_WRAP
      .ACCEPT_AXI_WRAP_BURSTS(0),
`endif
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
      .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
      .DEVICE_INDICATES_EXECUTE(1'b1),
      .MMU_BYPASS_UNTIL_CMT_RESET_DONE_ENABLED(1'b1)
  ) my_northcape_mmu (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      // AXI Slave interface
      .axi_slave(axi_in),

      // AXI Master interface
      .axi_master(axi_out),

      .axis_validate_request_read  (axis_validate_request_read.TRANSMITTER),
      .axis_validate_response_read (axis_validate_response_read.RECEIVER),
      .axis_validate_request_write (axis_validate_request_write.TRANSMITTER),
      .axis_validate_response_write(axis_validate_response_write.RECEIVER),

      .cmt_interface(cmt_interface)
  );

  northcape_axis_validate_driver read_resolver (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .requests_in(validate_requests_read),

      .axis_validate_request (axis_validate_request_read.RECEIVER),
      .axis_validate_response(axis_validate_response_read.TRANSMITTER),

      .ap_i(read_resolver_analysis_port)
  );

  northcape_axis_validate_driver write_resolver (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .requests_in(validate_requests_write),

      .axis_validate_request (axis_validate_request_write.RECEIVER),
      .axis_validate_response(axis_validate_response_write.TRANSMITTER),

      .ap_i(write_resolver_analysis_port)
  );


  axi5_master_driver #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH)
  ) test_response_generator (
      .requests_in(requests_in_master),

      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .axi_master(axi_out),

      .ap_i(master_analysis_port)
  );

  typedef NorthcapeMMUAgentConfig#(
      .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
      .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .CHECK_CMT_OVERLAP(1)
  ) agent_config_t;

  northcape_test_reset reset_intf (.clk_i(clk_i));

  assign rst_ni = reset_intf.resetn;

  typedef NorthcapeMMUTransaction#(
      .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
      .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .CHECK_CMT_OVERLAP(1)
  ) transaction_t;

  initial begin
    automatic agent_config_t agent_config;
    automatic uvm_queue #(transaction_t) transactions;

    agent_config = new(
        requests_in_slave,
        requests_in_master,
        validate_requests_read,
        validate_requests_write,
        cmt_interface,
        slave_analysis_port,
        master_analysis_port,
        read_resolver_analysis_port,
        write_resolver_analysis_port
    );
    uvm_config_db#(agent_config_t)::set(null, "", MMU_AGENT_CONFIG_NAME, agent_config);

    uvm_config_db#(reset_intf_t)::set(null, "", MMU_RESET_INTERFACE_NAME, reset_intf);

    transactions = new("transaction_queue");

    transactions.delete();

    uvm_config_db#(uvm_queue#(transaction_t))::set(null, "", MMU_TRANSACTION_QUEUE_NAME,
                                                   transactions);
  end

endmodule
