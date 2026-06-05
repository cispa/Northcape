/**
  * Testbench for randomized testing of the capability resolver component.
  */
package northcape_capability_resolver_randomized_test;
  
  import northcape_capability_resolver_test_constants::*;
  import northcape_capability_resolver_transaction::*;
  import northcape_capability_resolver_agent::*;
  import northcape_generator::NorthcapeGenerator;
  import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
  import northcape_test::*;
  import northcape_types::*;
  import axi5::*;
  import northcape_generic_env::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "northcape_uvm_test_wrapper.svh"

  typedef NorthcapeCapabilityResolverTransaction#(
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),

    .AXIS_REQUEST_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH),
    .AXIS_REQUEST_TID_WIDTH(AXIS_VALIDATE_REQUEST_TID_WIDTH),
    .AXIS_REQUEST_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
    .AXIS_REQUEST_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH),

    .AXIS_RESPONSE_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH),
    .AXIS_RESPONSE_TID_WIDTH(AXIS_VALIDATE_RESPONSE_TID_WIDTH),
    .AXIS_RESPONSE_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH),
    .AXIS_RESPONSE_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH)
  ) transaction_t;

  typedef NorthcapeCapabilityResolverAgent#(
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),

    .AXIS_REQUEST_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH),
    .AXIS_REQUEST_TID_WIDTH(AXIS_VALIDATE_REQUEST_TID_WIDTH),
    .AXIS_REQUEST_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH),
    .AXIS_REQUEST_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH),

    .AXIS_RESPONSE_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH),
    .AXIS_RESPONSE_TID_WIDTH(AXIS_VALIDATE_RESPONSE_TID_WIDTH),
    .AXIS_RESPONSE_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH),
    .AXIS_RESPONSE_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH),

    .TRANSACTIONS_QUEUE_NAME_AGENT(CAPABILITY_RESOLVER_TRANSACTION_QUEUE_NAME)
  ) agent_t;

  typedef NorthcapeGenericEnv#(
    .AGENT_TYPE(agent_t),
    .RESET_INTERFACE_NAME(CAPABILITY_RESOLVER_RESET_INTERFACE_NAME)
  ) env_t;

  typedef NorthcapeGenerator#(transaction_t) generator_t;

  localparam COMPONENT_NAME = "Northcape Capability Resolver Randomized Test";

  localparam TEST_REPETITIONS = 16384;

  function automatic void do_randomized_test();
    transaction_t randomized_test;
    uvm_queue#(transaction_t) queue;

    randomized_test = generator_t::generate_transaction_ephemeral();

    assert(uvm_config_db#(uvm_queue#(transaction_t))::get(null,"",CAPABILITY_RESOLVER_TRANSACTION_QUEUE_NAME,queue));

    `uvm_info(COMPONENT_NAME,$sformatf("I have pushed a randomized test of type %s",randomized_test.test_type.name()),UVM_DEBUG);
    
    queue.push_back(randomized_test);

  endfunction
  
  `NORTHCAPE_UVM_TEST(capability_resolver_randomized_test,env_t)
  begin
    for(int i = 0; i < TEST_REPETITIONS; i++)
    begin
      $display("Test repetition %d of %d!",(i+1),TEST_REPETITIONS);
      do_randomized_test();
    end
  end
  `NORTHCAPE_UVM_TEST_END

endpackage
