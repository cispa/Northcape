/**
  * Testbench for directed and regression testing of the dummy capability resolver component.
  */
package northcape_reg_interface_randomized_test;
  import northcape_reg_interface_transaction::*;
  import northcape_reg_interface_agent::NorthcapeRegInterfaceAgent;
  import northcape_generic_env::*;
  import northcape_generator::NorthcapeGenerator;
  import northcape_reg_interface_test_constants::*;

  import uvm_pkg::*;

  `include "uvm_macros.svh"
  `include "northcape_uvm_test_wrapper.svh"


  localparam test_num = 1024;
  localparam string COMPONENT_NAME = "Northcape Reg Interface Randomized Test";

  
  typedef NorthcapeRegInterfaceAgent#(
    .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .NUM_REGS(NUM_REGS),

    .TRANSACTIONS_QUEUE_NAME_AGENT(REGISTER_INTERFACE_TRANSACTION_QUEUE_NAME),
    .REG_INTERFACE_NAME(REGISTER_INTERFACE_NAME_REG_INTERFACE),
    .MMIO_INTERFACE_NAME(REGISTER_INTERFACE_NAME_MMIO_INTERFACE)
  ) agent_t;

  typedef NorthcapeRegInterfaceTransaction#(
    .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .NUM_REGS(NUM_REGS)
  ) transaction_t;

  typedef NorthcapeGenericEnv#(
    .AGENT_TYPE(agent_t),
    .RESET_INTERFACE_NAME(REGISTER_INTERFACE_RESET_INTERFACE_NAME)
  ) env_t;

  typedef NorthcapeGenerator#(transaction_t) generator_t;
  


  function automatic void do_randomized_test();
    transaction_t randomized_test;
    uvm_queue#(transaction_t) queue;

    randomized_test = generator_t::generate_transaction_ephemeral();

    assert(uvm_config_db#(uvm_queue#(transaction_t))::get(null,"",REGISTER_INTERFACE_TRANSACTION_QUEUE_NAME,queue));

    `uvm_info(COMPONENT_NAME,"I have pushed a randomized test!",UVM_DEBUG);
    
    queue.push_back(randomized_test);
  endfunction

  `NORTHCAPE_UVM_TEST(register_interface_randomized_test,env_t)
    for(int unsigned i = 0; i < test_num; i++)
    begin
      $display("Info: Test repetition %d of %d",i+1,test_num);
      do_randomized_test();
    end
  `NORTHCAPE_UVM_TEST_END

endpackage
