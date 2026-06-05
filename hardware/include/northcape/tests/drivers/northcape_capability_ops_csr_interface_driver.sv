/**
  * Driver for Northcape Capability Ops CSR interface.
  * Simulates a CSR module
  */
package northcape_capability_ops_csr_interface_driver;

  import northcape_types::*;
  import northcape_test::*;
  import axi5::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class automatic NorthcapeCapabilityOpsCSRInterfaceTransaction extends uvm_sequence_item;
    localparam COMPONENT_NAME = "Northcape Capability Ops CSR Interface Transaction";

    northcape_cap_ops_rcsr_req_t request;

    function new(string name = "");
      super.new(name);
    endfunction

    function void do_copy(uvm_object rhs);
      NorthcapeCapabilityOpsCSRInterfaceTransaction other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      request = other_transaction.request;

    endfunction

    function string convert2string;
      return $sformatf(
          "Request valid %b request type %s register number %d register new value %x device ID %x task ID %x is IRQ %b",
          request.req_valid,
          request.req_type.name(),
          request.reg_num,
          request.reg_new_val,
          request.device_id,
          request.task_id,
          request.is_irq
      );

    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      NorthcapeCapabilityOpsCSRInterfaceTransaction other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      return request == other_transaction.request;
    endfunction

  endclass

  class automatic NorthcapeCapabilityOpsCSRInterfaceResultTransaction extends uvm_sequence_item;
    localparam COMPONENT_NAME = "Northcape Capability Ops CSR Interface Result Transaction";

    northcape_cap_ops_rcsr_resp_t response;

    function new(northcape_cap_ops_rcsr_resp_t response, string name = "");
      super.new(name);
      this.response = response;
    endfunction

    function void do_copy(uvm_object rhs);
      NorthcapeCapabilityOpsCSRInterfaceResultTransaction other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      response = other_transaction.response;

    endfunction

    function string convert2string;
      return $sformatf("Request OK %b old register value %x", response.ok, response.reg_old_val);

    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      NorthcapeCapabilityOpsCSRInterfaceResultTransaction other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      if (response.ok != other_transaction.response.ok) begin
        `uvm_error(COMPONENT_NAME, "OK does not match!");
        return 1'b0;
      end

      if (response.reg_old_val != other_transaction.response.reg_old_val) begin
        `uvm_error(COMPONENT_NAME, "Returned register value does not match!");
        return 1'b0;
      end

      return 1'b1;
    endfunction

  endclass

  class automatic NorthcapeCapabilityOpsCSRInterfaceDriver #(
      parameter string INTERFACE_NAME = "csr_interface"
  ) extends uvm_driver #(NorthcapeCapabilityOpsCSRInterfaceTransaction);

    typedef virtual NorthcapeCapabilityOpsCsrIntf csr_intf_t;


    csr_intf_t intf;

    typedef NorthcapeCapabilityOpsCSRInterfaceTransaction transaction_t;

    typedef NorthcapeCapabilityOpsCSRInterfaceResultTransaction ret_t;

    localparam COMPONENT_NAME = "AXI Lite Driver";

    uvm_analysis_port #(ret_t) ap;

    function new(string name = "", csr_intf_t intf, uvm_component parent);
      super.new(name, parent);
      this.intf = intf;
    endfunction

    function void build_phase(uvm_phase phase);

      ap = new("result_port", this);

    endfunction : build_phase




    task run_phase(uvm_phase phase);
      transaction_t transaction;
      ret_t ret;

      intf.csr_clocking.request <= '0;

      forever begin
        seq_item_port.get_next_item(transaction);

        phase.raise_objection(this);

        intf.csr_clocking.request <= transaction.request;
        @(intf.csr_clocking);
        intf.csr_clocking.request <= '0;
        ret = new(intf.csr_clocking.response);
        ap.write(ret);


        seq_item_port.item_done();

        phase.drop_objection(this);
      end

    endtask


  endclass

endpackage : northcape_capability_ops_csr_interface_driver
