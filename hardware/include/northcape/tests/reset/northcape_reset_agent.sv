/**
 * Agent for generic reset interface.
 */
package northcape_reset_agent;
  `include "uvm_macros.svh"

  import uvm_pkg::*;
  import northcape_test::*;

  class automatic NorthcapeResetAgent #(
      parameter string RESET_INTERFACE_NAME = ""
  ) extends uvm_agent;

    typedef virtual northcape_test_reset reset_intf_t;

    reset_intf_t reset_intf;

    function void build_phase(uvm_phase phase);
      assert (uvm_config_db#(reset_intf_t)::get(null, "", RESET_INTERFACE_NAME, reset_intf));
    endfunction

    task pre_reset_phase(uvm_phase phase);
      phase.raise_objection(this);
      reset_intf.reset_clocking.resetn <= 0;
      @(reset_intf.reset_clocking);
      @(reset_intf.reset_clocking);
      phase.drop_objection(this);
    endtask

    task reset_phase(uvm_phase phase);
      phase.raise_objection(this);
      reset_intf.reset_clocking.resetn <= 1;
      @(reset_intf.reset_clocking);
      @(reset_intf.reset_clocking);
      phase.drop_objection(this);
    endtask

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass


endpackage
