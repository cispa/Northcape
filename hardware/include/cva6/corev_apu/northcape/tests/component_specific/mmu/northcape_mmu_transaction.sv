/**
 * Transaction via the Northcape MMU.
 */
package northcape_mmu_transaction;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi5::*;
  import northcape_types::*;
  import northcape_test::*;
  import northcape_mmu_common::NorthcapeMMUCommon;


  localparam MAX_CMT_SIZE_CLOG2 = $clog2(16384);

  /**
     * Sequence item that holds all data needed for an MMU transaction.
     */
  class automatic NorthcapeMMUTransaction #(
      parameter device_id_t READ_CHAN_DEVICE_ID = -1,
      parameter device_id_t WRITE_CHAN_DEVICE_ID = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = 1,
      parameter AXI_ID_WIDTH = -1,
      parameter AXI_USER_WIDTH = -1,
      parameter CHECK_CMT_OVERLAP = 1
  ) extends uvm_sequence_item;

    localparam ACCEPT_AXI_WRAP_BURSTS = 1;
    localparam COMPONENT_NAME = "Northcape MMU Transaction";

    // depends on some parameters
    `include "northcape_mmu_definitions.svh"

    typedef NorthcapeMMUCommon#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .ACCEPT_AXI_WRAP_BURSTS(ACCEPT_AXI_WRAP_BURSTS),
        .IS_WRITE_CHAN(1'b0)
    ) northcape_mmu_common_t;


    Axi5DelayGenerator delay_gen;

    rand axi_test_request_type_t axi_request_type;

    // 1 for invalid, 0 for valid access
    // randc: will cycle through 0 and 1 repeatedly
    rand bit invalid_access;

    // only defined for READ
    // 1: fetching an instruction --> indicated in user bits of the AXI bus, need X permission
    // 0: fetching data --> indicated in user bits of AXI bus, need R permission
    rand bit instruction_fetch;

    // only defined for READ
    // 1: is in IRQ context --> need to validate restrictions against IRQ task ID
    // 0: is not in IRQ context --> need to validate restrictions against non-IRQ task ID
    rand bit is_irq;

    // bounds of capability metadata table
    rand northcape_physical_address_t cmt_base_addr;
    rand int unsigned cmt_size_clog2;

    constraint cmt_is_not_too_big {cmt_size_clog2 <= MAX_CMT_SIZE_CLOG2;}

    // capability token in the request
    rand bit [AXI_ADDR_WIDTH-1:0] capability_token;

    // translated physical address
    rand segment_base_addr_t physical_address;

    rand axi_len_t test_len;

    // most transfers are 1-byte (especially CPU)
    constraint len_mostly_zero {
      test_len dist {
        0 :/ 5  // 5 times more likely than other values
      };
    }

    rand axi_burst_t burst_type;

    constraint burst_type_mostly_incr {
      burst_type dist {
        INCR :/ 5
      };
    }
    rand axi_size_t test_size;

    constraint size_mostly_bus_size {
      test_size dist {
        $clog2(AXI_DATA_WIDTH / 8) :/ 5
      };
    }

    rand bit test_lock;
    rand axi_cache_t test_cache;
    rand axi_prot_t test_prot;
    rand axi_qos_t test_qos;
    rand axi_region_t test_region;

    constraint valid_burst_types_only {
      burst_type != BURST_RESERVED;
`ifdef NORTHCAPE_MMU_NO_AXI_WRAP
      burst_type != WRAP;
`endif
    }

    constraint burst_size_possible_for_bus_width {(1 << test_size) <= AXI_DATA_WIDTH / 8;}

    // these constraints help the randomizer to achieve valid bounds check
    constraint shift_only_allowed_for_zero_length_transactions {
      if (invalid_access == 0 && physical_address % AXI_DATA_WIDTH / 8 != 0) {
        // part of the bounds-check conditions, to help Vivado find workable solutions faster
        test_len == 0 && burst_type != WRAP;
      }
    }
    ;

    constraint capability_token_plus_size_must_stay_in_byte_lane {
      if (invalid_access == 0) {
        capability_token % (AXI_DATA_WIDTH / 8) + 1 << test_size <= AXI_DATA_WIDTH / 8;
      }
    }

    rand bit [AXI_ID_WIDTH-1:0] test_id;

    bit [AXI_USER_WIDTH-1:0] test_user_in;

    // (write only) test_len many words to be written
    bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] write_data;

    bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH/8-1:0] write_strobes;


    // (atomic write / read) data response
    bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] response_data;


    // (write only) type of atomic transfer
    rand axi5_atop_t atomic_type;

    // read / write response
    rand axi_resp_t expected_response, given_response;

    constraint expected_response_matches_request {
      (invalid_access == 1) -> expected_response == DECERR;
      (invalid_access == 0) -> expected_response == given_response;
      // easier to read if we do not use DECERR for failure and normal scenarios
      (invalid_access == 0) -> given_response != DECERR;
    }

    // (write only) test_len many words to be written
    bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] expected_write_data;


    bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH/8-1:0] expected_write_strobes;

    // (atomic write / read) expected data response
    bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] expected_data;

    rand axis_validate_response_tdata_t resolver_response;
    axis_validate_request_tdata_t resolver_expected_request;


    // regressions: specific scenarios that failed in hardware and are unlikely to appear in random testing
    // force ready high before valid
    rand bit regression_ready_before_valid;
    // keep arvalid/awvalid after a ready, accepting a second transaction
    rand bit regression_keep_valid_high;

    function int unsigned get_bytes_in_burst();
      return northcape_mmu_common_t::getBytesInBurst(test_size, burst_type, test_len,
                                                     capability_token, 1 << test_size);
    endfunction

    // MMU has "self preservation mode": it refuses all accesses that resolve into the CMT
    function bit call_overlaps_cmt();
      bit [AXI_ADDR_WIDTH-1:0] request_start_addr;
      int unsigned bytes_in_burst;

      bytes_in_burst = get_bytes_in_burst();

      request_start_addr =
          64'(capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(capability_token)) +
          (burst_type == WRAP ?
           axi5_address_calculations#(AXI_ADDR_WIDTH)::axi5_wrapped_burst_get_start_address(
           test_len, test_size, {32'h0, resolver_response.address}) : resolver_response.address);

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Request start %x request end %x cmt start %x cmt end %x",
                request_start_addr,
                request_start_addr + bytes_in_burst,
                cmt_base_addr,
                cmt_base_addr + 64'(1 << cmt_size_clog2) * $bits(
                    northcape_cmt_entry_t
                ) / 8
                ), UVM_DEBUG);


      return northcape_mmu_common_t::resolved_address_overlaps_cmt(
          cmt_base_addr, cmt_size_clog2, request_start_addr, bytes_in_burst
      );

    endfunction

    function bit [AXI_ADDR_WIDTH-1:0] get_cmt_end();
      return 64'(cmt_base_addr) + (1 << 64'(cmt_size_clog2)) * ($bits(northcape_cmt_entry_t) / 8);
    endfunction

    constraint transaction_fits_in_addr_space {
      get_cmt_end() <= 64'h00000000ffffffff;
      capability_accessors #(AXI_ADDR_WIDTH)::capability_get_offset(
          capability_token
      ) + 64'(physical_address) + 64'(resolver_response.segment_length) <= 64'h00000000ffffffff;
    }

    constraint access_into_cmt_is_invalid {
      (CHECK_CMT_OVERLAP == 1 && invalid_access == 0) -> call_overlaps_cmt() == 0;
    }

    /* verilator lint_off CONSTRAINTIGN */
    constraint expected_response_matches_response_given {
      // post_randomize will add masks
      expected_data == response_data;
      expected_write_strobes == write_strobes;
    }
    ;
    /* verilator lint_on CONSTRAINTIGN */

    constraint invalid_access_for_wrap_bursts_with_invalid_length {
      if (burst_type == WRAP) {
        // MMU only accepts allowed lenghts for Wrap bursts
        if (test_len != 1 && test_len != 3 && test_len != 7 && test_len != 15) {
          invalid_access == 1;
        }
      }
    }

    rand northcape_restriction_type_t resolver_response_restriction;

    function void randomize_arrays();
      // TODO verilator is not currently capable of randomizing arrays..
      for (int i = 0; i < AXI5_MAX_BURST_LEN; i++) begin
        int unsigned rnd = $urandom();
        write_data[i] = {32'h0, $urandom()} + ({32'h0, $urandom()} << 32);
        expected_write_data[i] = write_data[i];

        write_strobes[i] = rnd[AXI_DATA_WIDTH/8-1:0];
        expected_write_strobes[i] = write_strobes[i];

        response_data[i] = {32'h0, $urandom()} + ({32'h0, $urandom()} << 32);
        expected_data[i] = response_data[i];
      end
    endfunction

    function void recompute_masks();
      northcape_physical_address_t start_addr, initial_address;
      // masks are too complicated / inefficient for constraints
      bit [AXI_DATA_WIDTH-1:0] burst_mask_read;
      bit [AXI_DATA_WIDTH/8 - 1 : 0] burst_mask_write;

      initial_address = resolver_response.address + capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(
          capability_token);

      start_addr = initial_address;

      randomize_arrays();

      for (int i = 0; i < test_len + 1; i++) begin
        bit [$clog2(AXI_DATA_WIDTH)-1:0] shift_out_write, shift_out_read;

        burst_mask_write = northcape_mmu_common_t::get_per_byte_mask_for_addr(
            start_addr,
            resolver_response.address,
            resolver_response.address + resolver_response.segment_length
        );
        burst_mask_read =
            northcape_axi_masks#(AXI_DATA_WIDTH, AXI_DATA_WIDTH)::stretchMask(burst_mask_write);


        // shift in different directions: one for slave->master, one for master->slave
        shift_out_write = AXI_ADDR_WIDTH / 8 - resolver_response.address % (AXI_ADDR_WIDTH / 8);
        shift_out_read = resolver_response.address % (AXI_ADDR_WIDTH / 8);


        start_addr =
            northcape_mmu_common_t::get_next_addr(burst_type, start_addr, test_len, test_size);
        // read data and strobes need to be masked to prevent leaks and shifted to where the slave/master expects them
        // for read data, we mask first and shift then; for write data/strobes, we mask first and shift then - mask applies to master side of MMU
        expected_data[i] = response_data[i] & burst_mask_read;
        expected_data[i] = northcape_mmu_common_t::shift_data(expected_data[i], shift_out_read);

        expected_write_strobes[i] =
            northcape_mmu_common_t::shift_strobes(write_strobes[i], shift_out_write);
        expected_write_strobes[i] = expected_write_strobes[i] & burst_mask_write;
        // write data need to be shifted to where the master expects them
        // no masking necessary, as strobes control what is actually written
        expected_write_data[i] =
            northcape_mmu_common_t::shift_data(expected_write_data[i], shift_out_write);

        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Test computed my read masks for transfer %d with capability token %x current physical address %x initial physical address %x segment start address %x segment length %d size %d: read mask %x write mask %x shift out read %d shift out write %d",
                  i,
                  capability_token,
                  start_addr,
                  initial_address,
                  resolver_response.address,
                  resolver_response.segment_length,
                  test_size,
                  burst_mask_read,
                  burst_mask_write,
                  shift_out_read,
                  shift_out_write
                  ), UVM_DEBUG);
      end
    endfunction

    // task ID persists between requests
    // thus, we need to account for it when generating test cases
    static task_id_t current_task_id = NORTHCAPE_LOADER_TASK_TASK_ID;

    function void post_randomize();

      `uvm_info(COMPONENT_NAME, $sformatf("Starting post_randomize for token %x", capability_token),
                UVM_DEBUG);

      if (invalid_access == 0) begin
        // TODO for some reason, the Vivado solver cannot figure this out as a constraint
        resolver_response.address = physical_address;

        if(current_task_id != resolver_response.restriction.task_restriction.task_id && resolver_response_restriction == NORTHCAPE_RESTRICTIONS_SET_TASK_ID)
        begin
          // first request into set-task-id capability needs 0 offset
          // could otherwise jump over parts of the code
          if (capability_accessors#(AXI_ADDR_WIDTH)::capability_set_offset(
                  capability_token, 0
              ) != 1) begin
            `uvm_warning(COMPONENT_NAME, "Could not fix the offset!");
          end
          current_task_id = resolver_response.restriction.task_restriction.task_id;
        end

        physical_address = physical_address + capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(
            capability_token);
      end

      resolver_expected_request.flags.is_recursion = 1'b0;
      resolver_expected_request.flags.reserved = '0;
      resolver_expected_request.original_address = '0;
      resolver_expected_request.original_segment_length = '0;
      resolver_expected_request.original_permission_tid_match = 1'b0;
      resolver_expected_request.original_permissions = '0;

      resolver_expected_request.address =
          capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(capability_token);
      resolver_expected_request.tag =
          capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(capability_token);

      if (axi_request_type == AXI_TEST_WRITE) begin
        // never indicates execute, but does indicate IRQ
        test_user_in = {is_irq, 1'b0};
      end

      if (axi_request_type == AXI_TEST_READ) begin

        if (instruction_fetch) begin
          resolver_expected_request.access_type = is_irq ? EXECUTE_IRQ : EXECUTE;
          test_user_in = {is_irq, 1'b1};
        end else begin
          resolver_expected_request.access_type = is_irq ? READ_IRQ : READ;
          test_user_in = {is_irq, 1'b0};
        end

      end
            else if(axi_request_type == AXI_TEST_WRITE && atomic_type.atop_type != ATOMIC_NONE && atomic_type.atop_type != ATOMIC_STORE)
            begin
        resolver_expected_request.access_type = is_irq ? READ_WRITE_IRQ : READ_WRITE;
      end else begin
        resolver_expected_request.access_type = is_irq ? WRITE_IRQ : WRITE;
      end

      if (invalid_access == 0) begin
        recompute_masks();
      end else begin
        expected_data = '0;
        if (instruction_fetch && axi_request_type == AXI_TEST_READ) begin
          // ebreak instructions on error
          for (int i = 0; i <= test_len; i++) begin
            expected_data[i] = northcape_mmu_common_t::INSTRUCTION_FETCH_ERROR_RESP;
          end
          expected_response = OKAY;
        end else begin
          // all-zeros and error response
          expected_response = DECERR;
        end
      end

      if (invalid_access == 0) begin
        if (CHECK_CMT_OVERLAP == 1 && call_overlaps_cmt()) begin
          `uvm_fatal(COMPONENT_NAME, "Call overlaps CMT when the constraint should prevent this!");
        end
      end

      resolver_response.restriction_type = resolver_response_restriction;

      // TODO Vivado sometimes does not evaluate the check_bounds constraint
      if (invalid_access == 1'b0 && check_bounds_after_randomize() != 1'b1) begin
        `uvm_warning(COMPONENT_NAME, "Post-randomized valid transaction is suddenly invalid!");
      end

      if (invalid_access == 1'b1 && check_bounds_after_randomize() != 1'b0) begin
        `uvm_warning(COMPONENT_NAME, "Post-randomized invalid transaction is suddenly valid!");
      end

    endfunction
    // physical_address becomes start_address after randomize()
    function bit check_bounds_after_randomize();
      `uvm_info(COMPONENT_NAME, $sformatf(
                "Checking bounds post-randomize for capability token %x!", capability_token),
                UVM_DEBUG);
      return northcape_mmu_common_t::checkBounds(
          get_bytes_in_burst(),
          capability_accessors#(AXI_ADDR_WIDTH)::capability_get_offset(
              capability_token
          ),
          resolver_response.segment_length,
          burst_type,
          physical_address,
          cmt_base_addr,
          cmt_size_clog2,
          test_len,
          (1 << test_size),
          resolver_response.address % AXI_ADDR_WIDTH / 8 != 0,
          .self_preservation_mode_active(1)
      );
    endfunction


    constraint resolver_response_should_match_expected_output {
      if (invalid_access == 0) {
        resolver_response.segment_length >= capability_accessors #(64)::capability_get_offset(
            capability_token
        ) + (test_len + 1) * (1 << test_size) || burst_type == WRAP;
      } else {
        resolver_response.segment_length == 0;
      }
    }
    ;

    constraint resolver_response_should_have_valid_restriction_type {
      if (invalid_access == 0) {
        resolver_response_restriction inside {NORTHCAPE_RESTRICTIONS_SET_TASK_ID, NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED};
      }
    }
    ;

    // TODO tooling bug: cannot move the repeating invocation into a helper function; if I do, it is not evaluated all the time when capability_token changes
    constraint bounds_check_must_be_ok_for_valid_access_and_not_ok_for_invalid_access {
      if (invalid_access == 0) {
        northcape_mmu_common_t::checkBounds(
            get_bytes_in_burst(),
            capability_accessors #(AXI_ADDR_WIDTH)::capability_get_offset(
                capability_token
            ),
            resolver_response.segment_length,
            burst_type,
            physical_address + capability_accessors #(AXI_ADDR_WIDTH)::capability_get_offset(
                capability_token
            ),
            cmt_base_addr,
            cmt_size_clog2,
            test_len,
            (1 << test_size),
            physical_address % AXI_ADDR_WIDTH / 8 != 0,
            .self_preservation_mode_active(1)
        ) == 1;
      }

      if (invalid_access == 1) {
        northcape_mmu_common_t::checkBounds(
            get_bytes_in_burst(),
            capability_accessors #(AXI_ADDR_WIDTH)::capability_get_offset(
                capability_token
            ),
            resolver_response.segment_length,
            burst_type,
            physical_address + capability_accessors #(AXI_ADDR_WIDTH)::capability_get_offset(
                capability_token
            ),
            cmt_base_addr,
            cmt_size_clog2,
            test_len,
            (1 << test_size),
            physical_address % AXI_ADDR_WIDTH / 8 != 0,
            .self_preservation_mode_active(1)
        ) == 0;
      }
    }

    // the segment cannot wrap the end of the 32-bit physical address space
    constraint resolver_response_addr_and_segment_length_should_never_wrap {
      64'(physical_address) + 64'(resolver_response.segment_length) <= 64'h00000000ffffffff;
    }
    ;



    function new(string name = "");
      super.new(name);
      delay_gen = new();
    endfunction

    typedef NorthcapeMMUTransaction#(
        .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
        .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),
        .CHECK_CMT_OVERLAP(CHECK_CMT_OVERLAP)
    ) my_type_t;

    function void do_copy(uvm_object rhs);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      delay_gen = other_transaction.delay_gen;
      axi_request_type = other_transaction.axi_request_type;
      invalid_access = other_transaction.invalid_access;
      cmt_base_addr = other_transaction.cmt_base_addr;
      cmt_size_clog2 = other_transaction.cmt_size_clog2;
      capability_token = other_transaction.capability_token;
      physical_address = other_transaction.physical_address;
      test_len = other_transaction.test_len;
      burst_type = other_transaction.burst_type;
      test_size = other_transaction.test_size;
      test_lock = other_transaction.test_lock;
      test_cache = other_transaction.test_cache;
      test_prot = other_transaction.test_prot;
      test_qos = other_transaction.test_qos;
      test_region = other_transaction.test_region;
      test_id = other_transaction.test_id;
      test_user_in = other_transaction.test_user_in;
      write_data = other_transaction.write_data;
      write_strobes = other_transaction.write_strobes;
      response_data = other_transaction.response_data;

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Copying atomic type %s", other_transaction.atomic_type.atop_type.name()),
                UVM_DEBUG);

      atomic_type = other_transaction.atomic_type;
      expected_response = other_transaction.expected_response;
      given_response = other_transaction.expected_response;
      expected_write_data = other_transaction.expected_write_data;
      expected_write_strobes = other_transaction.expected_write_strobes;
      expected_data = other_transaction.expected_data;
      resolver_response = other_transaction.resolver_response;
      resolver_response_restriction = other_transaction.resolver_response_restriction;
      resolver_expected_request = other_transaction.resolver_expected_request;

      regression_ready_before_valid = other_transaction.regression_ready_before_valid;
      regression_keep_valid_high = other_transaction.regression_keep_valid_high;

      instruction_fetch = other_transaction.instruction_fetch;
      is_irq = other_transaction.is_irq;
    endfunction : do_copy

    function string print_expected_strobes();
      string ret;

      ret = "";
      for (int i = 0; i < AXI5_MAX_BURST_LEN; i++) begin
        ret = {
          ret,
          $sformatf(
              "regression_test.expected_write_strobes[%d]=%s;\n",
              i,
              $sformatf(
                  "%p", expected_write_strobes[i]
              )
          )
        };
      end


      return ret;
    endfunction

    function string print_expected_wr_data();
      string ret;

      ret = "";
      for (int i = 0; i < AXI5_MAX_BURST_LEN; i++) begin
        ret = {
          ret,
          $sformatf(
              "regression_test.expected_write_data[%d]=%s;\n",
              i,
              $sformatf(
                  "%p", expected_write_data[i]
              )
          )
        };
      end


      return ret;
    endfunction

    function string print_expected_rd_data();
      string ret;

      ret = "";
      for (int i = 0; i < AXI5_MAX_BURST_LEN; i++) begin
        ret = {
          ret,
          $sformatf("regression_test.expected_data[%d]=%s;\n", i, $sformatf("%p", expected_data[i]))
        };
      end


      return ret;
    endfunction

    function string print_given_strobes();
      string ret;

      ret = "";
      for (int i = 0; i < AXI5_MAX_BURST_LEN; i++) begin
        ret = {
          ret,
          $sformatf("regression_test.write_strobes[%d]=%s;\n", i, $sformatf("%p", write_strobes[i]))
        };
      end


      return ret;
    endfunction

    function string print_given_wr_data();
      string ret;

      ret = "";
      for (int i = 0; i < AXI5_MAX_BURST_LEN; i++) begin
        ret = {
          ret, $sformatf("regression_test.write_data[%d]=%s;\n", i, $sformatf("%p", write_data[i]))
        };
      end


      return ret;
    endfunction

    function string print_given_rd_data();
      string ret;

      ret = "";
      for (int i = 0; i < AXI5_MAX_BURST_LEN; i++) begin
        ret = {
          ret,
          $sformatf("regression_test.response_data[%d]=%s;\n", i, $sformatf("%p", response_data[i]))
        };
      end


      return ret;
    endfunction

    function string convert2string();
      string s;

      s = "";

      s = {
        s,
        $sformatf("/* ==========================Test Request Begin=========================== */\n")
      };
      s = {
        s,
        $sformatf(
            "automatic NorthcapeMMUScoreboard#(.AXI_DATA_WIDTH(%d), .AXI_ID_WIDTH(%d), .AXI_USER_WIDTH(%d)) regression_test;\n",
            AXI_DATA_WIDTH,
            AXI_ID_WIDTH,
            AXI_USER_WIDTH
        )
      };
      s = {s, $sformatf("regression_test=new;\n")};

      s = {s, $sformatf("regression_test.axi_request_type=%s;\n", axi_request_type.name())};
      s = {s, $sformatf("regression_test.invalid_access=1'b%b;\n", invalid_access)};
      s = {
        s,
        $sformatf(
            "regression_test.capability_token=%d'h%x;\n", $bits(capability_token), capability_token
        )
      };
      s = {
        s,
        $sformatf(
            "regression_test.physical_address=%d'h%x;\n", $bits(physical_address), physical_address
        )
      };
      s = {s, $sformatf("regression_test.test_len=%d;\n", test_len)};
      s = {s, $sformatf("regression_test.burst_type=%s;\n", burst_type.name())};
      s = {s, $sformatf("regression_test.test_size=%d;\n", test_size)};
      s = {s, $sformatf("regression_test.test_lock=%d;\n", test_lock)};
      s = {s, $sformatf("regression_test.test_cache=%d;\n", test_cache)};
      s = {s, $sformatf("regression_test.test_prot=%d;\n", test_prot)};
      s = {s, $sformatf("regression_test.test_qos=%d;\n", test_qos)};
      s = {s, $sformatf("regression_test.test_region=%d;\n", test_region)};
      s = {s, $sformatf("regression_test.test_id=64'h%x;\n", test_id)};

      s = {s, print_given_wr_data()};
      s = {s, print_given_strobes()};
      s = {s, print_given_rd_data()};

      s = {
        s, $sformatf("regression_test.atomic_type.atop_type=%s;\n", atomic_type.atop_type.name())
      };
      s = {
        s, $sformatf("regression_test.atomic_type.atop_subtype=%d;\n", atomic_type.atop_subtype)
      };

      s = {s, $sformatf("regression_test.expected_response=%s;\n", expected_response.name())};
      s = {s, $sformatf("regression_test.given_response=%s;\n", given_response.name())};

      s = {s, print_expected_wr_data()};
      s = {s, print_expected_strobes()};
      s = {s, print_expected_rd_data()};

      s = {
        s,
        $sformatf(
            "regression_test.resolver_response.address=%d'h%x;\n",
            $bits(
                resolver_response.address
            ),
            resolver_response.address
        )
      };
      s = {
        s,
        $sformatf(
            "regression_test.resolver_response.segment_length=%d'h%x;\n",
            $bits(
                resolver_response.segment_length
            ),
            resolver_response.segment_length
        )
      };

      s = {
        s,
        $sformatf(
            "regression_test.resolver_expected_request.tag=%d;\n", resolver_expected_request.tag
        )
      };
      s = {
        s,
        $sformatf(
            "regression_test.resolver_expected_request.address=%d'h%x;\n",
            $bits(
                resolver_expected_request.address
            ),
            resolver_expected_request.address
        )
      };
      s = {
        s,
        $sformatf(
            "regression_test.resolver_expected_request.access_type=%s;\n",
            resolver_expected_request.access_type.name()
        )
      };

`ifdef INCLUDE_DELAYS_IN_TRANSACTION_PRINT
      s = {
        s,
        $sformatf(
            "regression_test.delay_gen.ar_channel_valids=%s;\n",
            $sformatf(
                "%p", delay_gen.ar_channel_valids
            )
        )
      };
      s = {
        s,
        $sformatf(
            "regression_test.delay_gen.ar_channel_readys=%s;\n",
            $sformatf(
                "%p", delay_gen.ar_channel_readys
            )
        )
      };
      s = {
        s,
        $sformatf(
            "regression_test.delay_gen.aw_channel_valids=%s;\n",
            $sformatf(
                "%p", delay_gen.aw_channel_valids
            )
        )
      };
      s = {
        s,
        $sformatf(
            "regression_test.delay_gen.aw_channel_readys=%s;\n",
            $sformatf(
                "%p", delay_gen.aw_channel_readys
            )
        )
      };
      s = {
        s,
        $sformatf(
            "regression_test.delay_gen.r_channel_valids=%s;\n",
            $sformatf(
                "%p", delay_gen.r_channel_valids
            )
        )
      };
      s = {
        s,
        $sformatf(
            "regression_test.delay_gen.r_channel_readys=%s;\n",
            $sformatf(
                "%p", delay_gen.r_channel_readys
            )
        )
      };
      s = {
        s,
        $sformatf(
            "regression_test.delay_gen.w_channel_valids=%s;\n",
            $sformatf(
                "%p", delay_gen.w_channel_valids
            )
        )
      };
      s = {
        s,
        $sformatf(
            "regression_test.delay_gen.w_channel_readys=%s;\n",
            $sformatf(
                "%p", delay_gen.w_channel_readys
            )
        )
      };
      s = {
        s,
        $sformatf(
            "regression_test.delay_gen.b_channel_valids=%s;\n",
            $sformatf(
                "%p", delay_gen.b_channel_valids
            )
        )
      };
      s = {
        s,
        $sformatf(
            "regression_test.delay_gen.b_channel_readys=%s;\n",
            $sformatf(
                "%p", delay_gen.b_channel_readys
            )
        )
      };
      s = {
        s,
        $sformatf(
            "regression_test.delay_gen.axis_channel_valids=%s;\n",
            $sformatf(
                "%p", delay_gen.axis_channel_valids
            )
        )
      };
      s = {
        s,
        $sformatf(
            "regression_test.delay_gen.axis_channel_readys=%s;\n",
            $sformatf(
                "%p", delay_gen.axis_channel_readys
            )
        )
      };
`endif

      s = {
        s,
        $sformatf(
            "regression_test.regression_ready_before_valid=%b;\n", regression_ready_before_valid
        )
      };
      s = {
        s, $sformatf("regression_test.regression_keep_valid_high=%b;\n", regression_keep_valid_high)
      };

      s = {s, $sformatf("regression_test.instruction_fetch=%b;\n", instruction_fetch)};
      s = {s, $sformatf("regression_test.is_irq=%b;\n", is_irq)};
      s = {
        s, $sformatf("/* ==========================Test Request End=========================== */")
      };

      return s;
    endfunction : convert2string


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

      return delay_gen == other_transaction.delay_gen &&
                axi_request_type == other_transaction.axi_request_type &&
                invalid_access == other_transaction.invalid_access &&
                cmt_base_addr == other_transaction.cmt_base_addr &&
                cmt_size_clog2 == other_transaction.cmt_size_clog2 &&
                capability_token == other_transaction.capability_token &&
                physical_address == other_transaction.physical_address &&
                test_len == other_transaction.test_len &&
                burst_type == other_transaction.burst_type &&
                test_size == other_transaction.test_size &&
                test_lock == other_transaction.test_lock &&
                test_cache == other_transaction.test_cache &&
                test_prot == other_transaction.test_prot &&
                test_qos == other_transaction.test_qos &&
                test_region == other_transaction.test_region &&
                test_id == other_transaction.test_id &&
                test_user_in == other_transaction.test_user_in &&
                write_data == other_transaction.write_data &&
                write_strobes == other_transaction.write_strobes &&
                response_data == other_transaction.response_data &&
                atomic_type == other_transaction.atomic_type &&
                expected_response == other_transaction.expected_response &&
                given_response == other_transaction.expected_response &&
                expected_write_data == other_transaction.expected_write_data &&
                expected_write_strobes == other_transaction.expected_write_strobes &&
                expected_data == other_transaction.expected_data &&
                resolver_response == other_transaction.resolver_response &&
                resolver_response_restriction == other_transaction.resolver_response_restriction &&
                resolver_expected_request == other_transaction.resolver_expected_request &&

                regression_ready_before_valid == other_transaction.regression_ready_before_valid &&
                regression_keep_valid_high == other_transaction.regression_keep_valid_high &&
                instruction_fetch == other_transaction.instruction_fetch && 
                is_irq == other_transaction.is_irq;

    endfunction : do_compare

  endclass


  /**
     * Sequence item that goes to the slave side of the MMU's AXI bus.
     */
  class NorthcapeMMUTransactionSlave #(
      parameter device_id_t READ_CHAN_DEVICE_ID = -1,
      parameter device_id_t WRITE_CHAN_DEVICE_ID = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = 1,
      parameter AXI_ID_WIDTH = -1,
      parameter AXI_USER_WIDTH = -1,
      parameter CHECK_CMT_OVERLAP = 1
  ) extends NorthcapeMMUTransaction #(
      .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
      .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .CHECK_CMT_OVERLAP(CHECK_CMT_OVERLAP)
  ) implements INorthcapeAXITransactionSlaveSide#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  );

    function new(string name = "");
      super.new(name);
    endfunction

    virtual function axi_test_request_type_t get_axi_request_type();
      return axi_request_type;
    endfunction


    virtual function bit [AXI_ADDR_WIDTH-1:0] get_slave_axi_addr();
      return capability_token;
    endfunction

    virtual function axi_len_t get_test_len();
      return test_len;
    endfunction

    virtual function axi_burst_t get_burst_type();
      return burst_type;
    endfunction
    virtual function axi_size_t get_test_size();
      return test_size;
    endfunction
    virtual function bit get_test_lock();
      return test_lock;
    endfunction

    virtual function axi_cache_t get_test_cache();
      return test_cache;
    endfunction

    virtual function axi_prot_t get_test_prot();
      return test_prot;
    endfunction

    virtual function axi_qos_t get_test_qos();
      return test_qos;
    endfunction

    virtual function axi_region_t get_test_region();
      return test_region;
    endfunction

    virtual function bit [AXI_ID_WIDTH-1:0] get_test_id();
      return test_id;
    endfunction

    virtual function bit [AXI_USER_WIDTH-1:0] get_test_user();
      return test_user_in;
    endfunction

    virtual function bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] get_write_data();
      return write_data;
    endfunction

    virtual function bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH/8-1:0] get_slave_write_strobes();
      return write_strobes;
    endfunction

    virtual function axi5_atop_t get_atomic_type();
      return atomic_type;
    endfunction

    virtual function bit get_regression_ready_before_valid();
      return regression_ready_before_valid;
    endfunction

    virtual function bit get_regression_keep_valid_high();
      return regression_keep_valid_high;
    endfunction

    virtual function bit generate_random_delay(axi_test_delay_type delay_type);
      return delay_gen.generate_random_delay(delay_type);
    endfunction

  endclass

  /**
     * Sequence item that goes to the master side of the MMU's AXI bus.
     */
  class NorthcapeMMUTransactionMaster #(
      parameter device_id_t READ_CHAN_DEVICE_ID = -1,
      parameter device_id_t WRITE_CHAN_DEVICE_ID = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = 1,
      parameter AXI_ID_WIDTH = -1,
      parameter AXI_USER_WIDTH = -1,
      parameter CHECK_CMT_OVERLAP = 1
  ) extends NorthcapeMMUTransaction #(
      .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
      .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .CHECK_CMT_OVERLAP(CHECK_CMT_OVERLAP)
  ) implements INorthcapeAXITransactionMasterSide#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  );

    function new(string name = "");
      super.new(name);
    endfunction

    virtual function axi_test_request_type_t get_axi_request_type();
      return axi_request_type;
    endfunction

    virtual function axi_len_t get_test_len();
      return test_len;
    endfunction


    virtual function bit [AXI_ID_WIDTH-1:0] get_test_id();
      return test_id;
    endfunction

    virtual function bit [AXI_USER_WIDTH-1:0] get_test_user();
      // TODO not used?
      return '0;
    endfunction

    virtual function bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] get_response_data();
      return response_data;
    endfunction

    virtual function axi_resp_t get_given_response();
      return given_response;
    endfunction

    virtual function bit get_regression_ready_before_valid();
      return regression_ready_before_valid;
    endfunction

    virtual function bit get_regression_keep_valid_high();
      return regression_keep_valid_high;
    endfunction

    virtual function bit generate_random_delay(axi_test_delay_type delay_type);
      return delay_gen.generate_random_delay(delay_type);
    endfunction

    virtual function axi_atop_t get_atomic_type();
      `uvm_info(COMPONENT_NAME, $sformatf("Returning atomic type %s", atomic_type.atop_type.name()),
                UVM_DEBUG);
      return atomic_type.atop_type;
    endfunction

    virtual function string to_string();
      return convert2string();
    endfunction

  endclass

  /**
     * Sequence item that goes to the capability resolver interfaces of the MMU.
     */
  class NorthcapeMMUTransactionResolver #(
      parameter device_id_t READ_CHAN_DEVICE_ID = -1,
      parameter device_id_t WRITE_CHAN_DEVICE_ID = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = 1,
      parameter AXI_ID_WIDTH = -1,
      parameter AXI_USER_WIDTH = -1,
      parameter CHECK_CMT_OVERLAP = 1
  ) extends NorthcapeMMUTransaction #(
      .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
      .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .CHECK_CMT_OVERLAP(CHECK_CMT_OVERLAP)
  ) implements INorthcapeCapabilityResolverTransaction;

    function new(string name = "");
      super.new(name);
    endfunction

    virtual function axi_test_request_type_t get_axi_request_type();
      return axi_request_type;
    endfunction

    virtual function axis_validate_request_tdata_t get_resolver_expected_request();
      return resolver_expected_request;
    endfunction

    virtual function axis_validate_response_tdata_t get_resolver_response();
      return resolver_response;
    endfunction


  endclass
endpackage
