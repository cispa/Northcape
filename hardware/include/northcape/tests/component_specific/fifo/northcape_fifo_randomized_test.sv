/**
 * UVM Test for Northcape FIFO verification.
 */
package northcape_fifo_randomized_test;

  import northcape_fifo_test_constants::*;
  import uvm_pkg::*;
  import northcape_generic_env::NorthcapeGenericEnv;

  import northcape_fifo_agent::NorthcapeFifoAgent;

  `include "uvm_macros.svh"
  `include "northcape_uvm_test_wrapper.svh"

  typedef NorthcapeFifoAgent#(
      .FIFO_DATA_WIDTH(FIFO_DATA_WIDTH),
      .FIFO_DEPTH_CLOG_2(FIFO_DEPTH_CLOG_2),
      .FIFO_INTERFACE_NAME(FIFO_INTERFACE_NAME)
  ) agent_t;

  typedef NorthcapeGenericEnv#(
      .AGENT_TYPE(agent_t),
      .RESET_INTERFACE_NAME(FIFO_RESET_INTERFACE_NAME)
  ) env_t;

  `NORTHCAPE_UVM_TEST(fifo_randomized_test, env_t)
  // agent does test in its own run phase
  `NORTHCAPE_UVM_TEST_END

endpackage
