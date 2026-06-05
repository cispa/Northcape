/**
  * Data structures for predicting Northcape MMU transactions.
  */

package northcape_cva6_mmu_scoreboard;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import northcape_types::*;
  import northcape_test::*;


  import northcape_cva6_mmu_transaction::*;
  import northcape_generic_checker::*;

  /**
 * Holds all provided and expected data for a transaction involving the MMU: data on the slave and master interfaces as well as the expected request/response to/from the operations module.
 * Used by the slave, master and resolver simulators.
 */
  class automatic NorthcapeCVA6MMUScoreboard #(
      parameter device_id_t INSTR_CHAN_DEVICE_ID = -1,
      parameter device_id_t DATA_CHAN_DEVICE_ID = -1,
      parameter AXI_ADDR_WIDTH = -1
  ) extends uvm_scoreboard;

    localparam string COMPONENT_NAME = "CVA6 MMU Scoreboard";


    typedef AxisValidateResultTransaction resolver_result_t;

    typedef NorthcapeCVA6MMUTransaction#(
        .INSTR_CHAN_DEVICE_ID(INSTR_CHAN_DEVICE_ID),
        .DATA_CHAN_DEVICE_ID(DATA_CHAN_DEVICE_ID),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) transaction_t;

    typedef NorthcapeCVA6MMUInterfaceResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) result_transaction_t;

    // connected to analysis ports coming FROM the drivers
    uvm_tlm_analysis_fifo #(result_transaction_t) intf_driver_result_fifo_instr;
    uvm_tlm_analysis_fifo #(result_transaction_t) intf_driver_result_fifo_data;

    uvm_tlm_analysis_fifo #(resolver_result_t) resolver_result_fifo_instr;
    uvm_tlm_analysis_fifo #(resolver_result_t) resolver_result_fifo_data;

    // connected to our checker
    uvm_analysis_port #(NorthcapeGenericCheckerCompItem) checker_port;

    uvm_seq_item_pull_port #(transaction_t, transaction_t) transaction_port;

    task_id_t current_task_id_irq, current_task_id_non_irq;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      current_task_id_irq = '0;
      current_task_id_non_irq = '0;
    endfunction

    function void build_phase(uvm_phase phase);
      intf_driver_result_fifo_instr = new("intf_driver_result_fifo_instr", this);
      intf_driver_result_fifo_data = new("intf_driver_result_fifo_data", this);

      resolver_result_fifo_instr = new("resolver_result_fifo_instr", this);
      resolver_result_fifo_data = new("resolver_result_fifo_data", this);
      transaction_port = new("scoreboard_transaction_port", this);

      checker_port = new("checker_port", this);
    endfunction : build_phase

    function result_transaction_t predict_resolution_result(
        transaction_t transaction, bit is_before_predict_end, bit is_subsystem_call,
        bit is_subsystem_call_self);
      result_transaction_t ret;

      ret = new;

      // always returned
      ret.translated_address = transaction.segment_base + capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(
          transaction.data_address);
      ret.translation_hit = 1'b1;
      ret.translation_valid = 1'b1;
      ret.translation_requires_non_cacheable = !transaction.is_cacheable_data;
      ret.task_id_irq = current_task_id_irq;
      ret.task_id_non_irq = current_task_id_non_irq;
      ret.translation_device_interpreted = '0;

      // task ID will be updated temporarily before mispredict and then be reset
      // however, this does NOT occur on error, as the entire request is ignored
      if(transaction.valid_test && is_before_predict_end && transaction.is_execute && transaction.restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID)
      begin
        if (transaction.data_is_irq) begin
          ret.task_id_irq = transaction.restriction_body.task_restriction.task_id;
        end else begin
          ret.task_id_non_irq = transaction.restriction_body.task_restriction.task_id;
        end
      end

      if (transaction.restriction_type == NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED) begin
        ret.translation_device_interpreted = transaction.restriction_body.device_interpreted_bits;
      end

      if (transaction.valid_test) begin
        ret.translation_error = 1'b0;
      end else begin
        ret.translation_error = 1'b1;
      end

      ret.is_subsystem_call = is_subsystem_call;
      ret.is_subsystem_call_self = is_subsystem_call_self;

      `uvm_info(COMPONENT_NAME, $sformatf("Expecting result %s", ret.convert2string()), UVM_HIGH);

      return ret;
    endfunction

    task run_phase(uvm_phase phase);
      transaction_t current_transaction;
      result_transaction_t predicted_result_transaction, real_result_transaction;
      resolver_result_t predicted_resolver_result, real_resolver_result;
      int unsigned transaction_num;
      bit subsystem_call = 1'b0;
      task_id_t old_task_id;
      bit is_subsystem_call, is_subsystem_call_self;

      transaction_num = 0;


      // we keep requesting new item until the sequence is complete
      // we assume that whoever created the sequence holds an objection
      // such that the test does not end prematurely
      forever begin
        is_subsystem_call = 1'b0;
        is_subsystem_call_self = 1'b0;

        `uvm_info(COMPONENT_NAME, "Waiting for transaction from FIFO!", UVM_HIGH);
        transaction_port.get_next_item(current_transaction);
        `uvm_info(COMPONENT_NAME, "Got transaction from FIFO!", UVM_HIGH);

        if (current_transaction.is_execute && current_transaction.data_is_irq) begin
          // we are either already in IRQ context or about to jump into IRQ context
          // either way, need to validate against IRQ task ID
          old_task_id = current_task_id_irq;
        end else begin
          // validate against IRQ/non-IRQ task ID, depending on which context the instruction is in
          old_task_id = current_transaction.data_is_irq ? current_task_id_irq : current_task_id_non_irq;
        end

        // when we are doing a subsystem call, the initial request cannot yet have the new task id
        // we expect to continue to see the old one
        // otherwise, expect current task ID
        current_transaction.task_id_irq = current_task_id_irq;
        current_transaction.task_id_non_irq = current_task_id_non_irq;

        // possibly, the transaction was randomized to not be valid but happens to be valid
        current_transaction.post_randomize();

        if (current_transaction.is_execute) begin
          // subsystem call
          // update task ID if needed
          // we also need to start indicating who we are immediately
          if (current_transaction.restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID) begin
            `uvm_info(COMPONENT_NAME, $sformatf(
                      "Encountered X-only transaction (is irq: %b)- switching task ID from %d to %d!",
                      current_transaction.data_is_irq,
                      old_task_id,
                      current_transaction.restriction_body.task_restriction.task_id
                      ), UVM_DEBUG);
            if(old_task_id != current_transaction.restriction_body.task_restriction.task_id && capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(
                    current_transaction.data_address
                ) != '0) begin
              // MMU ignores indicated offset (only) on first execute call to set-task-ID capability
              // this prevents caller from skipping over part of the code
              `uvm_warning(COMPONENT_NAME,
                           "Set-task-ID transaction with non-zero offset - expecting refusal!");
              current_transaction.valid_test = 1'b0;
            end else if (current_transaction.valid_test == 1'b1) begin
              // mispredict should roll back the changed task ID
              if(!current_transaction.branch_predict || !current_transaction.branch_mispredict)
              begin
                if (current_transaction.data_is_irq) begin
                  current_task_id_irq = current_transaction.restriction_body.task_restriction.task_id;
                  subsystem_call = (current_task_id_irq != old_task_id);
                end else begin
                  // after iret
                  current_task_id_non_irq = current_transaction.restriction_body.task_restriction.task_id;
                  subsystem_call = (current_task_id_non_irq != old_task_id);
                end
              end else begin
                `uvm_info(COMPONENT_NAME, "Assuming mispredict - not updating task ID!", UVM_HIGH);
              end
              // as the mispredict is fired AFTER the subsystem call, the MMU will indicate the flags
              `uvm_info(COMPONENT_NAME, $sformatf(
                        "Capability offset is %x for addr %x is subsystem call self %b is subsystem call %b",
                        capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(
                            current_transaction.data_address
                        ),
                        current_transaction.data_address,
                        is_subsystem_call_self,
                        is_subsystem_call
                        ), UVM_HIGH);
              if (capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(
                      current_transaction.data_address
                  ) == 0) begin
                is_subsystem_call_self = 1'b1;
                is_subsystem_call = (old_task_id != current_transaction.restriction_body.task_restriction.task_id);
                `uvm_info(COMPONENT_NAME, $sformatf(
                          "Is subsystem call self %b is subsystem call %b",
                          is_subsystem_call_self,
                          is_subsystem_call
                          ), UVM_HIGH);
              end
              if (subsystem_call) begin
                `uvm_info(COMPONENT_NAME, "Detected subsystem call!", UVM_HIGH);
              end
            end else begin
              `uvm_info(COMPONENT_NAME,
                        "Set-task-ID transaction with invalid access - not changing task ID!",
                        UVM_DEBUG);
            end
          end
        end

        // we do not know how many transactions will come
        // but we do not want the test to end while we are checking one
        phase.raise_objection(this);


        if (current_transaction.is_execute) begin
          `uvm_info(COMPONENT_NAME, "Waiting for instruction resolver!", UVM_DEBUG);
          resolver_result_fifo_instr.get(real_resolver_result);
        end else begin
          `uvm_info(COMPONENT_NAME, "Waiting for data resolver!", UVM_DEBUG);
          resolver_result_fifo_data.get(real_resolver_result);
        end
        predicted_resolver_result = new;
        predicted_resolver_result.request_data = current_transaction.get_resolver_expected_request();
        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Got resolver result %s expected %s",
                  real_resolver_result.convert2string(),
                  predicted_resolver_result.convert2string()
                  ), UVM_DEBUG);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_resolver_result, predicted_resolver_result));

        if (current_transaction.is_execute) begin
          `uvm_info(COMPONENT_NAME, "Waiting for instruction result!", UVM_DEBUG);
          intf_driver_result_fifo_instr.get(real_result_transaction);
        end else begin
          `uvm_info(COMPONENT_NAME, "Waiting for instruction data!", UVM_DEBUG);
          intf_driver_result_fifo_data.get(real_result_transaction);
        end
        predicted_result_transaction = predict_resolution_result(
            current_transaction,
            real_result_transaction.is_before_predict_end,
            is_subsystem_call,
            is_subsystem_call_self
        );

        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_result_transaction, predicted_result_transaction));

        `uvm_info(COMPONENT_NAME, "Got instruction result!", UVM_DEBUG);


        transaction_port.item_done();

        phase.drop_objection(this);

        transaction_num++;

        `uvm_info(COMPONENT_NAME, $sformatf("I have completed transaction %d!", transaction_num),
                  UVM_MEDIUM);

      end
    endtask

  endclass

endpackage : northcape_cva6_mmu_scoreboard
