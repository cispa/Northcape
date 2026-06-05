/**
  * Test class that predicts capability resolver transactions and output.
  */
package northcape_capability_resolver_scoreboard;
  import axi5::*;
  import northcape_capability_resolver_common::*;
  import northcape_types::*;
  import northcape_test::*;
  import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
  import northcape_capability_resolver_common::NorthcapeCapabilityResolverHash;
  import northcape_generic_checker::NorthcapeGenericCheckerCompItem;
  import northcape_capability_resolver_transaction::*;

  import northcape_cmt_parser_pkg::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class automatic NorthcapeCapabilityResolverScoreboard #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      parameter AXIS_REQUEST_TDATA_WIDTH = -1,
      parameter AXIS_REQUEST_TID_WIDTH   = -1,
      parameter AXIS_REQUEST_TDEST_WIDTH = -1,
      parameter AXIS_REQUEST_TUSER_WIDTH = -1,

      // parameters for AXIs response interface (output of the resolver)
      parameter AXIS_RESPONSE_TDATA_WIDTH = -1,
      parameter AXIS_RESPONSE_TID_WIDTH   = -1,
      parameter AXIS_RESPONSE_TDEST_WIDTH = -1,
      parameter AXIS_RESPONSE_TUSER_WIDTH = -1
  ) extends uvm_scoreboard;

    typedef Axi5MasterDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) master_result_t;

    typedef AxisGenericResultTransaction#(
        .AXIS_TDATA_WIDTH(AXIS_RESPONSE_TDATA_WIDTH),
        .AXIS_TID_WIDTH  (AXIS_RESPONSE_TID_WIDTH),
        .AXIS_TDEST_WIDTH(AXIS_RESPONSE_TDEST_WIDTH),
        .AXIS_TUSER_WIDTH(AXIS_RESPONSE_TUSER_WIDTH)
    ) validate_response_t;

    typedef NorthcapeCapabilityResolverTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXIS_REQUEST_TDATA_WIDTH(AXIS_REQUEST_TDATA_WIDTH),
        .AXIS_REQUEST_TID_WIDTH  (AXIS_REQUEST_TID_WIDTH),
        .AXIS_REQUEST_TDEST_WIDTH(AXIS_REQUEST_TDEST_WIDTH),
        .AXIS_REQUEST_TUSER_WIDTH(AXIS_REQUEST_TUSER_WIDTH),

        .AXIS_RESPONSE_TDATA_WIDTH(AXIS_RESPONSE_TDATA_WIDTH),
        .AXIS_RESPONSE_TID_WIDTH  (AXIS_RESPONSE_TID_WIDTH),
        .AXIS_RESPONSE_TDEST_WIDTH(AXIS_RESPONSE_TDEST_WIDTH),
        .AXIS_RESPONSE_TUSER_WIDTH(AXIS_RESPONSE_TUSER_WIDTH)
    ) transaction_t;


    localparam COMPONENT_NAME = "Northcape Capability Resolver Scoreboard";

    uvm_tlm_analysis_fifo #(master_result_t) master_result_fifo;
    uvm_tlm_analysis_fifo #(validate_response_t) resolver_response_fifo;

    // connected to our checker
    uvm_analysis_port #(NorthcapeGenericCheckerCompItem) checker_port;

    uvm_seq_item_pull_port #(transaction_t, transaction_t) transaction_port;


    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      master_result_fifo = new("master_result_fifo", this);
      resolver_response_fifo = new("resolver_response_fifo", this);

      transaction_port = new("scoreboard_transaction_port", this);

      checker_port = new("checker_port", this);
    endfunction : build_phase

    function master_result_t predict_master_result(const ref transaction_t transaction,
                                                   int unsigned result_num);
      master_result_t ret;

      ret = new("master_result");

      unique case (transaction.test_type)
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_VALIDATION_ERROR, NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_ROOT_CAPABILITY,NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_DIRECT_CAPABILITY,NORTHCAPE_CAPABILITY_RESOLVER_TEST_BUS_ERROR: begin
          ret.addr = transaction.entries[0].get_entry_addr(transaction.table_size_clog_2);
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_INVALID_ENTRY, NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_INDIRECT_CAPABILITY,NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_OK, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_FAIL, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_FRONT, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_BACK, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_FRONT, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_BACK, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_CHILD, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE_CHILD, NORTHCAPE_CAPABILITY_RESOLVER_TEST_REVOCATION_CAPABILITY: begin
          ret.addr = transaction.entries[result_num].get_entry_addr(transaction.table_size_clog_2);
        end
        default: begin
          `uvm_fatal(COMPONENT_NAME, "Not supported!");
        end
      endcase

      // designed to be possible in burst of one
      ret.len = 0;

      ret.burst = INCR;
      ret.size = $clog2($bits(transaction.entries[0].get_entry()) / 8);

      /**
              * Default from here, not necessary
              */
      ret.lock = 0;
      ret.cache = '0;
      ret.prot = '0;
      ret.qos = '0;
      ret.region = '0;
      ret.id = '0;
      ret.user = '0;

      return ret;
    endfunction

    function void set_restrictions(const ref northcape_cmt_entry_t entry,
                                   ref axis_validate_response_tdata_t tdata);
      tdata.restriction_type = entry.restrictions.restriction_type;
      tdata.restriction = entry.restrictions.body;
    endfunction

    function validate_response_t predict_resolver_response(const ref transaction_t transaction);
      validate_response_t ret;
      axis_validate_response_tdata_t tdata;
      cmt_parser_verdict_t parser_verdict;

      tdata.error_code = NORTHCAPE_RESOLVE_NO_ERROR;
      parser_verdict = northcape_cmt_parser::entry_matches_validate_request(
          transaction.entries[0].get_entry(),
          capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
              transaction.capability_tokens[0]
          ),
          capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(
              transaction.capability_tokens[0]
          ),
          ACCESS_DERIVE_RECURSION,  /* hard-coded for initial check */
          transaction.request_device_id,
          transaction.request_task_id,
          '0
      );
      if (parser_verdict inside {CMT_ENTRY_MATCH, CMT_ENTRY_RECURSE}) begin
        /* second check AFTER full recursion */
        parser_verdict = northcape_cmt_parser::entry_matches_validate_request(
            transaction.entries[0].get_entry(),
            capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(
                transaction.capability_tokens[0]
            ),
            capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(
                transaction.capability_tokens[0]
            ),
            transaction.access_type,
            transaction.request_device_id,
            transaction.request_task_id,
            '0
        );
      end

      `uvm_info(COMPONENT_NAME, $sformatf("Parser verdict %s", parser_verdict.name()), UVM_HIGH);

      ret = new("validate_response");

      unique case (transaction.test_type)
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_ROOT_CAPABILITY,NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_DIRECT_CAPABILITY: begin
          tdata.address = transaction.entries[0].get_entry().location.physical_location.base;
          tdata.segment_length = transaction.entries[0].get_entry().location.physical_location.length;
          set_restrictions(transaction.entries[0].get_entry(), tdata);
          tdata.permissions = transaction.entries[0].get_entry().permissions;
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_OK_INDIRECT_CAPABILITY: begin
          // this is always dictated by the first indirect capability, which is the most restrictive
          tdata.address = transaction.entries[0].get_entry().location.indirect_location.effective_base;
          tdata.segment_length = transaction.entries[0].get_entry().location.indirect_location.length;
          set_restrictions(transaction.entries[0].get_entry(), tdata);
          tdata.permissions = transaction.entries[0].get_entry().permissions;
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_INVALID_ENTRY: begin
          tdata.address = '0;
          tdata.segment_length = '0;
          tdata.restriction = '0;
          tdata.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
          tdata.permissions = '0;
          tdata.error_code = NORTHCAPE_RESOLVE_ERROR_CAP_TYPE;
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_FAIL: begin
          tdata.address = '0;
          tdata.segment_length = '0;
          tdata.restriction = '0;
          tdata.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
          tdata.permissions = '0;
          tdata.error_code = NORTHCAPE_RESOLVE_ERROR_LOCKED;
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_BUS_ERROR: begin
          tdata.address = '0;
          tdata.segment_length = '0;
          tdata.restriction = '0;
          tdata.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
          tdata.permissions = '0;
          tdata.error_code = NORTHCAPE_RESOLVE_ERROR_BUS;
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_REVOCATION_CAPABILITY: begin
          tdata.address = '0;
          tdata.segment_length = '0;
          tdata.restriction = '0;
          tdata.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
          tdata.permissions = '0;
          tdata.error_code = NORTHCAPE_RESOLVE_ERROR_RESTRICTIONS;
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_VALIDATION_ERROR: begin
          tdata.address = '0;
          tdata.segment_length = '0;
          tdata.restriction = '0;
          tdata.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
          tdata.permissions = '0;
          unique case (parser_verdict)
            CMT_ENTRY_FAIL_TAG: tdata.error_code = NORTHCAPE_RESOLVE_ERROR_TAG;
            CMT_ENTRY_FAIL_PERMISSIONS: tdata.error_code = NORTHCAPE_RESOLVE_ERROR_PERMISSIONS;
            CMT_ENTRY_FAIL_RESTRICTIONS: tdata.error_code = NORTHCAPE_RESOLVE_ERROR_RESTRICTIONS;
            CMT_ENTRY_FAIL_CAP_TYPE: tdata.error_code = NORTHCAPE_RESOLVE_ERROR_CAP_TYPE;
            CMT_ENTRY_FAIL_LOCKED: tdata.error_code = NORTHCAPE_RESOLVE_ERROR_LOCKED;
            default: begin
              `uvm_fatal(COMPONENT_NAME, "Unknown / no failure for validation error!");
            end
          endcase
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_FRONT, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_BACK, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_FRONT, NORTHCAPE_CAPABILITY_RESOLVER_TEST_PARENT_OUT_OF_BOUNDS_LOCKED_BACK:
        begin
          tdata.address = '0;
          tdata.segment_length = '0;
          tdata.restriction = '0;
          tdata.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
          tdata.permissions = '0;
          tdata.error_code = NORTHCAPE_RESOLVE_ERROR_BOUNDS;
        end
        NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCKED_OK, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_CHILD, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE, NORTHCAPE_CAPABILITY_RESOLVER_TEST_LOCK_HOLDER_RECURSIVE_CHILD: begin
          bit found_entry;

          found_entry = 1'b0;

          set_restrictions(transaction.entries[0].get_entry(), tdata);
          tdata.permissions = transaction.entries[0].get_entry().permissions;

          // lock holder does not have base/length info, so the first / most restrictive entry wins
          for (int i = 0; i < transaction.entries.size(); i++) begin
            if (transaction.entries[i].get_entry().capability_type == NORTHCAPE_CMT_DIRECT) begin
              tdata.address = transaction.entries[i].get_entry().location.physical_location.base;
              tdata.segment_length = transaction.entries[i].get_entry().location.physical_location.length;
              found_entry = 1'b1;
              break;
            end
            if (transaction.entries[i].get_entry().capability_type == NORTHCAPE_CMT_INDIRECT) begin
              tdata.address = transaction.entries[i].get_entry().location.indirect_location.effective_base;
              tdata.segment_length = transaction.entries[i].get_entry().location.indirect_location.length;
              found_entry = 1'b1;
              break;
            end
          end

          if (found_entry == 1'b0) begin
            `uvm_fatal(COMPONENT_NAME, "Could not determine return address for lock holder!");
          end
        end
        default: begin
          `uvm_fatal(COMPONENT_NAME, "Not supported!");
        end
      endcase

      ret.tdata = tdata;
      ret.tdest = transaction.request_device_id;
      ret.tstrb = '1;
      ret.tkeep = '1;
      ret.tid   = '0;
      ret.tuser = '0;

      return ret;
    endfunction

    task run_phase(uvm_phase phase);
      transaction_t current_transaction;
      master_result_t predicted_master_result, real_master_result;
      validate_response_t predicted_validate_response, real_validate_response;
      int unsigned transaction_num;

      transaction_num = 0;

      forever begin : checkOneTransaction

        `uvm_info(COMPONENT_NAME, "Waiting for transaction from FIFO!", UVM_DEBUG);
        transaction_port.get_next_item(current_transaction);
        `uvm_info(COMPONENT_NAME, "Got transaction from FIFO!", UVM_DEBUG);

        phase.raise_objection(this);

        for (int unsigned i = 0; i < current_transaction.entries.size(); i++) begin
          `uvm_info(COMPONENT_NAME, $sformatf("Waiting for transaction %d", i), UVM_HIGH);
          predicted_master_result = predict_master_result(current_transaction, i);
          master_result_fifo.get(real_master_result);
          checker_port.write(NorthcapeGenericCheckerCompItem::new(
                             real_master_result, predicted_master_result));
        end

        predicted_validate_response = predict_resolver_response(current_transaction);
        `uvm_info(COMPONENT_NAME, "Waiting for resolver response from FIFO!", UVM_DEBUG);
        resolver_response_fifo.get(real_validate_response);
        `uvm_info(COMPONENT_NAME, "Got resolver response from FIFO!", UVM_DEBUG);
        checker_port.write(NorthcapeGenericCheckerCompItem::new(
                           real_validate_response, predicted_validate_response));

        transaction_port.item_done();

        transaction_num++;

        `uvm_info(COMPONENT_NAME, $sformatf("I have completed transaction %d!", transaction_num),
                  UVM_MEDIUM);

        phase.drop_objection(this);

      end : checkOneTransaction

    endtask

  endclass

endpackage
