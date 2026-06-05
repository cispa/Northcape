`include "uvm_macros.svh"
/**
  * Generic UVM environment.
  */
package northcape_generic_env;
  import uvm_pkg::*;
  import northcape_test::*;
  import northcape_types::*;
  import northcape_reset_agent::NorthcapeResetAgent;
  import "DPI-C" function void tpm_initialize();

  /**
     * Class that takes care of connecting and initializing UVM components used in the tests.
     * Also forwards the parameters.
     */
  class automatic NorthcapeGenericEnv #(
      parameter type AGENT_TYPE = logic,
      parameter string RESET_INTERFACE_NAME = ""
  ) extends uvm_env;

    typedef NorthcapeResetAgent#(.RESET_INTERFACE_NAME(RESET_INTERFACE_NAME)) reset_agent_t;


    AGENT_TYPE agent;
    reset_agent_t reset_agent;



    function void build_phase(uvm_phase phase);
      reset_agent = new("reset_agent", this);
      agent = new("test_agent", this);

    endfunction



    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction

  endclass

  /**
     * Class that takes care of connecting and initializing UVM components used in the tests.
     * Assumes provided agent does reset.
     */
  class automatic NorthcapeNoResetEnv #(
      parameter type AGENT_TYPE = logic
  ) extends uvm_env;


    AGENT_TYPE agent;



    function void build_phase(uvm_phase phase);
      agent = new("test_agent", this);
    endfunction



    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction

  endclass


  /**
      * Environment that does not do anything.
      * Useful it test completes in the actual test class.
      */
  class automatic NorthcapeDummyEnv extends uvm_env;
    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

endpackage
