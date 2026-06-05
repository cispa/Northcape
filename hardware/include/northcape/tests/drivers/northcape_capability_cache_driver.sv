/**
  * Drivers for Northcape capability cache ports (ops and resolver).
  */
package northcape_capability_cache_driver;
  import northcape_types::*;
  import northcape_test::*;
  import northcape_capability_cache_common::*;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class NorthcapeCapabilityCacheResolverTransaction extends uvm_sequence_item;
    capability_id_t  request_capability_id;
    capability_tag_t capability_tag;
    logic            request_cache_flush;
    logic            request_close_speculation_window;
    logic            request_is_recursion;

    function new(string name = "");
      super.new(name);
    endfunction

    function capability_id_t get_resolver_request_capability_id();
      return request_capability_id;
    endfunction
    function capability_tag_t get_resolver_request_capability_tag();
      return capability_tag;
    endfunction
    function logic get_resolver_request_cache_flush();
      return request_cache_flush;
    endfunction
    function logic get_request_close_speculation_window();
      return request_close_speculation_window;
    endfunction
    function logic get_resolver_request_is_recursion();
      return request_is_recursion;
    endfunction
  endclass

  class NorthcapeCapabilityCacheOpsTransaction extends uvm_sequence_item;
    capability_id_t request_capability_id;
    capability_tag_t capability_tag;
    logic is_write;
    northcape_cmt_entry_t write_cmt_entry;
    logic write_request_flush;
    logic request_is_uncacheable;

    function new(string name = "");
      super.new(name);
    endfunction

    virtual function capability_id_t get_ops_request_capability_id();

      return request_capability_id;
    endfunction
    virtual function capability_tag_t get_ops_request_capability_tag();
      return capability_tag;
    endfunction
    virtual function logic get_ops_is_write();
      return is_write;
    endfunction
    virtual function northcape_cmt_entry_t get_ops_write_cmt_entry();
      return write_cmt_entry;
    endfunction
    virtual function logic get_ops_is_flush();
      return write_request_flush;
    endfunction
    virtual function logic get_ops_is_uncacheable();
      return request_is_uncacheable;
    endfunction
  endclass

  class NorthcapeCapabilityCacheResultTransaction extends uvm_sequence_item;

    logic response_err;
    northcape_cmt_entry_t response_entry;

    function new(string name = "");
      super.new(name);
    endfunction

    typedef NorthcapeCapabilityCacheResultTransaction my_type_t;

    function void do_copy(uvm_object rhs);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      response_err   = other_transaction.response_err;
      response_entry = other_transaction.response_entry;
    endfunction

    function string convert2string();
      return $sformatf("Response error %b response entry %x", response_err, response_entry);
    endfunction

    localparam COMPONENT_NAME = "Slave Driver Result Transaction";

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      if (response_err !== other_transaction.response_err) begin
        `uvm_error(COMPONENT_NAME, "response error does not match!");
        return 0;
      end

      if (response_entry !== other_transaction.response_entry) begin
        `uvm_error(COMPONENT_NAME, "response CMT entry does not match!");
        return 0;
      end

      return 1;
    endfunction

  endclass


  class automatic NorthcapeCapabilityCacheResolverDriver extends uvm_driver #(NorthcapeCapabilityCacheResolverTransaction);
    /* TODO tooling bug Vivado crashes when I typedef this */
    virtual NorthcapeCapabilityCacheInterfaceResolverTest intf;

    typedef NorthcapeCapabilityCacheResolverTransaction transaction_t;

    typedef NorthcapeCapabilityCacheResultTransaction ret_t;

    localparam COMPONENT_NAME = "Northcape Cache Resolver Interface Driver";

    uvm_analysis_port #(ret_t) ap;

    function new(virtual NorthcapeCapabilityCacheInterfaceResolverTest intf, string name = "",
                 uvm_component parent);
      super.new(name, parent);
      this.intf = intf;
    endfunction

    function void build_phase(uvm_phase phase);
      ap = new("result_port", this);
    endfunction : build_phase

    task do_one_test(input transaction_t transaction);
      ret_t ret = new("Cache resolver response");
      intf.test_resolver_clocking.request_valid <= 1'b1;
      intf.test_resolver_clocking.response_ready <= 1'b1;
      intf.test_resolver_clocking.request_capability_id    <= transaction.get_resolver_request_capability_id();
      intf.test_resolver_clocking.request_capability_tag   <= transaction.get_resolver_request_capability_tag();
      intf.test_resolver_clocking.request_is_recursion     <= transaction.get_resolver_request_is_recursion();

      `uvm_info(COMPONENT_NAME, "Set outputs for resolver!", UVM_HIGH);

      @(intf.test_resolver_clocking iff intf.test_resolver_clocking.response_valid);
      intf.test_resolver_clocking.request_valid <= 1'b0;

      ret.response_err   = intf.test_resolver_clocking.response_err;
      ret.response_entry = intf.test_resolver_clocking.response_cmt_entry;

      if (transaction.get_resolver_request_cache_flush()) begin
        // flush occurs in same cycle as giving the response
        intf.test_resolver_clocking.request_cache_flush <= 1'b1;
        @(intf.test_resolver_clocking);
        intf.test_resolver_clocking.request_cache_flush <= 1'b0;
      end else if (transaction.get_request_close_speculation_window()) begin
        // end of speculation occurs in same cycle as giving the response
        intf.test_resolver_clocking.request_close_speculation_window <= 1'b1;
        @(intf.test_resolver_clocking);
        intf.test_resolver_clocking.request_close_speculation_window <= 1'b0;
      end

      `uvm_info(COMPONENT_NAME, "Resolver is done!", UVM_HIGH);

      ap.write(ret);

    endtask

    task run_phase(uvm_phase phase);
      transaction_t transaction;

      phase.raise_objection(this);

      intf.test_resolver_clocking.request_valid <= 1'b0;
      intf.test_resolver_clocking.request_cache_flush <= 1'b0;
      intf.test_resolver_clocking.request_close_speculation_window <= 1'b0;

      phase.drop_objection(this);

      forever begin
        seq_item_port.get_next_item(transaction);

        phase.raise_objection(this);

        do_one_test(transaction);

        seq_item_port.item_done();

        phase.drop_objection(this);
      end

    endtask
  endclass


  class automatic NorthcapeCapabilityCacheOpsDriver extends uvm_driver #(NorthcapeCapabilityCacheOpsTransaction);
    /* TODO tooling bug Vivado crashes when I typedef this */
    virtual NorthcapeCapabilityCacheInterfaceOpsTest intf;

    typedef NorthcapeCapabilityCacheOpsTransaction transaction_t;

    typedef NorthcapeCapabilityCacheResultTransaction ret_t;

    localparam COMPONENT_NAME = "Northcape Cache Ops Interface Driver";

    uvm_analysis_port #(ret_t) ap;

    function new(virtual NorthcapeCapabilityCacheInterfaceOpsTest intf, string name = "",
                 uvm_component parent);
      super.new(name, parent);
      this.intf = intf;
    endfunction

    function void build_phase(uvm_phase phase);
      ap = new("result_port", this);
    endfunction : build_phase

    task do_one_test(input transaction_t transaction);
      ret_t ret = new("Cache ops response");

      // shared signals
      intf.test_ops_clocking.request_valid <= 1'b1;
      intf.test_ops_clocking.request_capability_id <= transaction.get_ops_request_capability_id();
      intf.test_ops_clocking.request_capability_tag <= transaction.get_ops_request_capability_tag();
      intf.test_ops_clocking.is_write <= transaction.get_ops_is_write();
      intf.test_ops_clocking.request_is_uncacheable <= transaction.get_ops_is_uncacheable();

      if (transaction.get_ops_is_write()) begin
        // write
        intf.test_ops_clocking.write_request_capability <= transaction.get_ops_write_cmt_entry();
        intf.test_ops_clocking.write_request_flush <= transaction.get_ops_is_flush();

        ret.response_entry = '0;
      end

      @(intf.test_ops_clocking iff intf.test_ops_clocking.response_valid);

      ret.response_err = intf.test_ops_clocking.response_err;

      if (!transaction.get_ops_is_write()) begin
        ret.response_entry = intf.test_ops_clocking.response_cmt_entry;
      end

      `uvm_info(COMPONENT_NAME, "Set outputs for ops!", UVM_HIGH);

      intf.test_ops_clocking.request_valid <= 1'b0;


      `uvm_info(COMPONENT_NAME, "Ops is done!", UVM_HIGH);

      ap.write(ret);
    endtask

    task run_phase(uvm_phase phase);
      transaction_t transaction;

      phase.raise_objection(this);

      intf.test_ops_clocking.request_valid <= 1'b0;

      phase.drop_objection(this);

      forever begin
        seq_item_port.get_next_item(transaction);

        phase.raise_objection(this);

        do_one_test(transaction);

        seq_item_port.item_done();

        phase.drop_objection(this);
      end

    endtask

  endclass

endpackage
