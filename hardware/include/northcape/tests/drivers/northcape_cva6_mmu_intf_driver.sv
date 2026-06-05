/**
  * Simulates an AXI5 LITE Master and checks soundness of the bus protocol.
  * Given a NorthcapeRegInterfaceTransaction, also verifies that the response data matches what was expected and performs the indicated write.
  */

package northcape_cva6_mmu_intf_driver;

  import northcape_types::*;
  import northcape_test::*;
  import axi5::*;
  import northcape_cva6_mmu_transaction::NorthcapeCVA6MMUInterfaceTransaction;
  import northcape_cva6_mmu_transaction::NorthcapeCVA6MMUInterfaceResultTransaction;

  import uvm_pkg::*;
  `include "uvm_macros.svh"


  class automatic NorthcapeCVA6IntfDriver #(
      parameter device_id_t INSTR_CHAN_DEVICE_ID = -1,
      parameter device_id_t DATA_CHAN_DEVICE_ID = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter string INTERFACE_NAME = ""
  ) extends uvm_driver #(NorthcapeCVA6MMUInterfaceTransaction #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .INSTR_CHAN_DEVICE_ID(INSTR_CHAN_DEVICE_ID),
      .DATA_CHAN_DEVICE_ID(DATA_CHAN_DEVICE_ID)
  ));

    typedef virtual NorthcapeCva6MMUInterface #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) northcape_cva6_mmu_intf_t;

    northcape_cva6_mmu_intf_t intf;

    typedef NorthcapeCVA6MMUInterfaceTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .INSTR_CHAN_DEVICE_ID(INSTR_CHAN_DEVICE_ID),
        .DATA_CHAN_DEVICE_ID(DATA_CHAN_DEVICE_ID)
    ) transaction_t;

    typedef NorthcapeCVA6MMUInterfaceResultTransaction#(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)) ret_t;

    localparam COMPONENT_NAME = "CVA6 MMU Interface Driver";

    uvm_analysis_port #(ret_t) ap;

    function new(northcape_cva6_mmu_intf_t intf, string name = "", uvm_component parent);
      super.new(name, parent);
      this.intf = intf;
    endfunction

    function void build_phase(uvm_phase phase);
      ap = new("result_port", this);
    endfunction : build_phase

    bit got_result;

    task check_result(bit is_before_predict_end);
      if (intf.input_clocking.translation_valid && !got_result) begin
        ret_t ret = new("CVA6 MMU response");
        // collect outputs
        ret.task_id_irq = intf.input_clocking.task_id_irq;
        ret.task_id_non_irq = intf.input_clocking.task_id_non_irq;
        ret.translated_address = intf.input_clocking.translated_address;
        ret.translation_error = intf.input_clocking.translation_error;
        ret.translation_valid = intf.input_clocking.translation_valid;
        ret.translation_hit = intf.input_clocking.translation_hit;
        ret.translation_requires_non_cacheable  = intf.input_clocking.translation_requires_non_cacheable;
        ret.translation_device_interpreted = intf.translation_device_interpreted;
        ret.is_before_predict_end = is_before_predict_end;
        ret.is_subsystem_call = intf.is_subsystem_call;
        ret.is_subsystem_call_self = intf.is_subsystem_call_self;

        ap.write(ret);
        got_result = 1'b1;
        // do not request second translation
        intf.input_clocking.data_is_valid <= 1'b0;
      end
    endtask

    task drive_branch_predict(input transaction_t transaction);
      // cva6 will sometimes announce a mispredict when a branch was missed in instruction scan
      // i.e., the MMU will see mispredicts without preceding branch_predict's
      if (transaction.branch_predict || transaction.branch_mispredict) begin
        check_result(1'b1);
        repeat (transaction.predict_cycles) begin
          @(intf.input_clocking);
          check_result(1'b1);
        end
        intf.input_clocking.data_is_mispredict <= transaction.branch_mispredict;
        intf.input_clocking.data_is_correct_predict <= !transaction.branch_mispredict;
      end
    endtask

    task do_one_test(input transaction_t transaction);
      intf.input_clocking.data_address            <= transaction.data_address;
      intf.input_clocking.data_is_store           <= transaction.data_is_store;
      intf.input_clocking.data_access_size        <= transaction.data_access_size;
      intf.input_clocking.data_is_immediate       <= transaction.data_is_immediate;
      intf.input_clocking.data_is_irq             <= transaction.data_is_irq;
      intf.input_clocking.data_is_atomic          <= transaction.data_is_atomic;
      intf.input_clocking.data_is_branch_predict  <= transaction.branch_predict;
      // CANNOT be in the same cycle
      intf.input_clocking.data_is_mispredict      <= 1'b0;
      intf.input_clocking.data_is_correct_predict <= 1'b0;

      intf.input_clocking.data_is_valid           <= 1'b1;

      `uvm_info(COMPONENT_NAME, "Set outputs for MMU!", UVM_HIGH);

      got_result = 1'b0;
      drive_branch_predict(transaction);

      if (!got_result) begin
        @(intf.input_clocking iff intf.input_clocking.translation_valid);
        check_result(1'b0);
        if (!got_result) begin
          `uvm_error(COMPONENT_NAME, "Did not get result!");
        end
      end


      `uvm_info(COMPONENT_NAME, "Got inputs from MMU!", UVM_HIGH);



      intf.input_clocking.data_is_valid <= 1'b0;
      // time for validate driver to reset itself
      @(intf.input_clocking);

    endtask

    task run_phase(uvm_phase phase);
      transaction_t transaction;

      phase.raise_objection(this);

      intf.input_clocking.data_is_valid <= 1'b0;

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

endpackage : northcape_cva6_mmu_intf_driver
