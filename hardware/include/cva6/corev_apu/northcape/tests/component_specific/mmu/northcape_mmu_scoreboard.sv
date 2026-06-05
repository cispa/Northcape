/**
  * Data structures for predicting Northcape MMU transactions.
  */

package northcape_mmu_scoreboard;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi5::*;
  import northcape_types::*;
  import northcape_test::*;


  import northcape_mmu_transaction::*;
  import northcape_generic_checker::*;

  /**
 * Holds all provided and expected data for a transaction involving the MMU: data on the slave and master interfaces as well as the expected request/response to/from the operations module.
 * Used by the slave, master and resolver simulators.
 */
  class automatic NorthcapeMMUScoreboard #(
      parameter device_id_t READ_CHAN_DEVICE_ID = -1,
      parameter device_id_t WRITE_CHAN_DEVICE_ID = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH = -1,
      parameter AXI_USER_WIDTH = -1,
      parameter CHECK_RESOLVER_RESULT = 1,
      parameter CHECK_CMT_OVERLAP = 1
  ) extends uvm_scoreboard;

    localparam string COMPONENT_NAME = "MMU Scoreboard";

    typedef Axi5SlaveDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) slave_result_t;

    typedef Axi5MasterDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) master_result_t;

    typedef AxisValidateResultTransaction resolver_result_t;

    typedef NorthcapeMMUTransaction#(
        .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
        .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .CHECK_CMT_OVERLAP(CHECK_CMT_OVERLAP)
    ) transaction_t;

    // connected to analysis ports coming FROM the drivers
    uvm_tlm_analysis_fifo #(slave_result_t) slave_result_fifo;
    uvm_tlm_analysis_fifo #(master_result_t) master_result_fifo;
    uvm_tlm_analysis_fifo #(resolver_result_t) resolver_result_fifo_read;
    uvm_tlm_analysis_fifo #(resolver_result_t) resolver_result_fifo_write;

    // connected to our checker
    uvm_analysis_port #(NorthcapeGenericCheckerCompItem) checker_port;

    uvm_seq_item_pull_port #(transaction_t, transaction_t) transaction_port;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      current_task_id_irq = '0;
      current_task_id_non_irq = '0;
    endfunction

    function void build_phase(uvm_phase phase);
      slave_result_fifo = new("slave_result_fifo", this);
      master_result_fifo = new("master_result_fifo", this);
      resolver_result_fifo_read = new("resolver_result_fifo_read", this);
      resolver_result_fifo_write = new("resolver_result_fifo_write", this);
      transaction_port = new("scoreboard_transaction_port", this);

      checker_port = new("checker_port", this);
    endfunction : build_phase

    function logic [AXI_USER_WIDTH-1:0] compute_expected_slave_user_bits(
        const ref transaction_t transaction);
      return '0;
    endfunction

    function slave_result_t predict_slave_result(const ref transaction_t transaction);
      slave_result_t ret;
      ret = new("predicted_result_slave");

      unique case (transaction.axi_request_type)
        AXI_TEST_READ: begin
          for (int i = 0; i < transaction.test_len + 1; i++) begin
            ret.read_data[i] = transaction.expected_data[i];
          end
          ret.resp = transaction.expected_response;
          ret.data_len = transaction.test_len;
          ret.id = transaction.test_id;
          ret.user = compute_expected_slave_user_bits(transaction);
        end
        AXI_TEST_WRITE: begin
          if(transaction.atomic_type.atop_type != ATOMIC_NONE && transaction.atomic_type.atop_type != ATOMIC_STORE)
                begin
            for (int i = 0; i < transaction.test_len + 1; i++) begin
              ret.read_data[i] = transaction.expected_data[i];
            end
            ret.data_len = transaction.test_len;
          end
          ret.resp = transaction.expected_response;
          ret.id   = transaction.test_id;
          ret.user = compute_expected_slave_user_bits(transaction);
        end
        default: begin
          `uvm_fatal(COMPONENT_NAME, "Unknown request type!");
        end
      endcase

      return ret;
    endfunction : predict_slave_result

    task_id_t current_task_id_irq, current_task_id_non_irq;

    function logic [AXI_USER_WIDTH-1:0] compute_expected_master_user_bits(
        const ref transaction_t transaction);
      northcape_axi_user_t ret;

      ret = '0;

      if(transaction.resolver_response.restriction_type == NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED)
      begin
        ret.device_interpreted_restriction = transaction.resolver_response.restriction.device_interpreted_bits;
      end

      ret.current_device_id = ((transaction.axi_request_type == AXI_TEST_READ) ? READ_CHAN_DEVICE_ID : WRITE_CHAN_DEVICE_ID) >> 1;
      ret.current_task_id = transaction.is_irq ? current_task_id_irq : current_task_id_non_irq;

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Expecting master user bits %x based on restriction type %s device interpreted bits %x device id %d task id %d in IRQ context %b",
                ret,
                transaction.resolver_response.restriction_type.name(),
                transaction.resolver_response.restriction.device_interpreted_bits,
                ret.current_device_id,
                ret.current_task_id,
                transaction.is_irq
                ), UVM_DEBUG);

      return ret;
    endfunction

    function master_result_t predict_master_result(const ref transaction_t transaction);
      master_result_t ret;
      ret = new("predicted_result_master");

      ret.request_type = transaction.axi_request_type;
      ret.addr = transaction.physical_address;
      ret.len = transaction.test_len;
      ret.burst = transaction.burst_type;
      ret.size = transaction.test_size;
      ret.lock = transaction.test_lock;
      ret.cache = transaction.test_cache;
      ret.prot = transaction.test_prot;
      ret.qos = transaction.test_qos;
      ret.region = transaction.test_region;
      ret.id = transaction.test_id;
      ret.user = compute_expected_master_user_bits(transaction);

      unique case (transaction.axi_request_type)
        AXI_TEST_READ: begin
          // common attributes suffice
        end
        AXI_TEST_WRITE: begin
          ret.atop = transaction.atomic_type;
          for (int i = 0; i < ret.len + 1; i++) begin
            ret.write_data[i] = transaction.expected_write_data[i];
            ret.write_strobes[i] = transaction.expected_write_strobes[i];
          end
          ret.wid   = transaction.test_id;
          // TODO this is not properly distinguished on write
          ret.wuser = transaction.test_user_in;
        end
        default: begin
          `uvm_fatal(COMPONENT_NAME, "Unknown request type!");
        end
      endcase

      return ret;
    endfunction : predict_master_result

    function resolver_result_t predict_resolver_result(const ref transaction_t transaction);
      resolver_result_t ret;
      ret = new("predicted_result_resolver");

      ret.request_data = transaction.resolver_expected_request;

      return ret;
    endfunction : predict_resolver_result

    task run_phase(uvm_phase phase);
      transaction_t current_transaction;
      slave_result_t predicted_slave_result, real_slave_result;
      master_result_t predicted_master_result, real_master_result;
      resolver_result_t predicted_resolver_result, real_resolver_result;
      int unsigned transaction_num;
      bit subsystem_call = 1'b0;
      task_id_t old_task_id;

      transaction_num = 0;


      // we keep requesting new item until the sequence is complete
      // we assume that whoever created the sequence holds an objection
      // such that the test does not end prematurely
      forever begin

        `uvm_info(COMPONENT_NAME, "Waiting for transaction from FIFO!", UVM_HIGH);
        transaction_port.get_next_item(current_transaction);
        `uvm_info(COMPONENT_NAME, "Got transaction from FIFO!", UVM_HIGH);

        if(current_transaction.axi_request_type == AXI_TEST_READ && current_transaction.instruction_fetch && current_transaction.is_irq)
        begin
          // we are either already in IRQ context or about to jump into IRQ context
          // either way, need to validate against IRQ task ID
          old_task_id = current_task_id_irq;
        end else begin
          // validate against IRQ/non-IRQ task ID, depending on which context the instruction is in
          old_task_id = current_transaction.is_irq ? current_task_id_irq : current_task_id_non_irq;
        end

        if(current_transaction.axi_request_type == AXI_TEST_READ && current_transaction.instruction_fetch)
        begin
          // subsystem call
          // update task ID if needed
          // we also need to start indicating who we are immediately
          if(current_transaction.resolver_response.restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID)
          begin
            `uvm_info(COMPONENT_NAME, $sformatf(
                      "Encountered X-only transaction (is irq: %b)- switching task ID from %d to %d!",
                      current_transaction.is_irq,
                      old_task_id,
                      current_transaction.resolver_response.restriction.task_restriction.task_id
                      ), UVM_DEBUG);
            if(old_task_id != current_transaction.resolver_response.restriction.task_restriction.task_id && capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(
                    current_transaction.capability_token
                ) != '0) begin
              // MMU ignores indicated offset (only) on first execute call to set-task-ID capability
              // this prevents caller from skipping over part of the code
              `uvm_warning(COMPONENT_NAME,
                           "Set-task-ID transaction with non-zero offset - expecting refusal!");
              current_transaction.invalid_access = 1'b1;
            end else if (current_transaction.invalid_access == 1'b0) begin
              if (current_transaction.is_irq) begin
                current_task_id_irq = current_transaction.resolver_response.restriction.task_restriction.task_id;
                subsystem_call = (current_task_id_irq != old_task_id);
              end else begin
                // after iret
                current_task_id_non_irq = current_transaction.resolver_response.restriction.task_restriction.task_id;
                subsystem_call = (current_task_id_non_irq != old_task_id);
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

        // when we are doing a subsystem call, the initial request cannot yet have the new task id
        // we expect to continue to see the old one
        // otherwise, expect current task ID
        if (!subsystem_call) begin
          current_transaction.resolver_expected_request.task_id = current_transaction.is_irq ? current_task_id_irq : current_task_id_non_irq;
        end else begin
          current_transaction.resolver_expected_request.task_id = old_task_id;
        end

        // we do not know how many transactions will come
        // but we do not want the test to end while we are checking one
        phase.raise_objection(this);

        predicted_slave_result = predict_slave_result(current_transaction);

        slave_result_fifo.get(real_slave_result);

        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_slave_result, predicted_slave_result));

        if (!current_transaction.invalid_access) begin
          // invalid accesses are never forwarded to master
          predicted_master_result = predict_master_result(current_transaction);
          master_result_fifo.get(real_master_result);
          checker_port.write(NorthcapeGenericCheckerCompItem::new(
                             real_master_result, predicted_master_result));
        end

        if (CHECK_RESOLVER_RESULT) begin
          if (current_transaction.axi_request_type == AXI_TEST_READ) begin
            resolver_result_fifo_read.get(real_resolver_result);
          end else begin
            resolver_result_fifo_write.get(real_resolver_result);
          end
          predicted_resolver_result = predict_resolver_result(current_transaction);
          `uvm_info(COMPONENT_NAME, $sformatf(
                    "Got resolver result %s expected %s",
                    real_resolver_result.convert2string(),
                    predicted_resolver_result.convert2string()
                    ), UVM_DEBUG);
          checker_port.write(NorthcapeGenericCheckerCompItem::new(
                             real_resolver_result, predicted_resolver_result));
        end

        transaction_port.item_done();

        phase.drop_objection(this);

        transaction_num++;

        `uvm_info(COMPONENT_NAME, $sformatf("I have completed transaction %d!", transaction_num),
                  UVM_MEDIUM);

      end
    endtask

  endclass

endpackage : northcape_mmu_scoreboard
