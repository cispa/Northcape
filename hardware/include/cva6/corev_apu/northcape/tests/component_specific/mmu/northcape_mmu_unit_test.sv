
`include "northcape_uvm_test_wrapper.svh"

/**
  * Testbench for directed and regression testing of the MMU component.
  */
package northcape_mmu_unit_test;
  import northcape_mmu_common::NorthcapeMMUCommon;
  import northcape_mmu_transaction::*;
  import northcape_types::*;
  import northcape_test::*;
  import axi5::*;
  import uvm_pkg::*;
  import northcape_generic_env::NorthcapeGenericEnv;
  import northcape_generator::NorthcapeGenerator;
  import northcape_sequence::NorthcapeDirectSequence;
  import northcape_mmu_test_constants::*;

  localparam string COMPONENT_NAME = "MMU Unit Test";

  // attempts to read 16 bursts of 8 bytes each from capability 0xdeadbeef.
  // token is of type 0b01 (0-length offset)
  localparam valid_test_addr=64'h400000deadbeef00;
  // we need to be able to use the offset here, so we use a 16-bit-offset token
  localparam aligned_valid_test_addr=64'h8000deadbeef0000;
  localparam valid_test_segment_base=32'hdead0000;
  localparam valid_test_segment_length = 32'd128;
  // this is implicitly rounded up to 16
  localparam valid_test_len = 15;
  localparam valid_test_size = 3'b011;
  localparam axi_burst_t valid_test_burst = INCR;

  // bits default to 0

  localparam bit [AXI5_MAX_BURST_LEN-1:0][63:0] valid_test_data_fixed = {256{64'h0123456789ABCDEF}};
  logic [AXI5_MAX_BURST_LEN-1:0][7:0] valid_test_strobes = '0;

  // starts at end of the segment
  localparam overflow_test_addr=64'd128;

  // offset 14 into test data
  localparam burst_test_addr=64'h0e;

  localparam valid_test_cmt_start = 64'h00000000fffffff00;
  localparam valid_test_cmt_size_clog_2 = 4;

  localparam bit [AXI5_MAX_BURST_LEN-1:0][63:0] valid_test_data = {
    64'h0123456789ABCDEF,
    64'h23456789ABCDEF01,
    64'h456789ABCDEF0123,
    64'h6789ABCDEF012345,
    64'h89ABCDEF01234567,
    64'h9ABCDEF012345678,
    64'hABCDEF0123456789,
    64'hCDEF0123456789AB,
    64'hEF0123456789ABCD,
    64'hF0123456789ABCDE,
    64'h89ABCDEF23456701,
    64'hABCDEF4567890123,
    64'hCDEF6789ABCDEF45,
    64'hEF0123ABCDEF4567,
    64'hF0123456789ABC89,
    64'h0123456789ABCDEF
  };

  // this is for a narrow burst, 1 bytes out of 8 bytes, with a zero-byte offset
  localparam bit [AXI5_MAX_BURST_LEN-1:0][63:0] valid_test_data_narrow_zero_byte_offset_1_byte = {
    64'h0100000000000000,
    64'h0045000000000000,
    64'h0000890000000000,
    64'h000000CD00000000,
    64'h0000000001000000,
    64'h0000000000340000,
    64'h0000000000006700,
    64'h00000000000000AB,
    64'hEF00000000000000,
    64'h0012000000000000,
    64'h0000CD0000000000,
    64'h0000004500000000,
    64'h00000000AB000000,
    64'h0000000000EF0000,
    64'h000000000000BC00,
    64'h00000000000000EF
  };

  localparam bit[AXI5_MAX_BURST_LEN-1:0][7:0] valid_test_strobes_narrow_zero_byte_offset_1_byte = {
    8'b10000000,
    8'b01000000,
    8'b00100000,
    8'b00010000,
    8'b00001000,
    8'b00000100,
    8'b00000010,
    8'b00000001,
    8'b10000000,
    8'b01000000,
    8'b00100000,
    8'b00010000,
    8'b00001000,
    8'b00000100,
    8'b00000010,
    8'b00000001
  };

  // this is for a narrow burst, 4 bytes out of 8 bytes, with a zero-byte offset
  // i.e., just pass-through the test data
  localparam bit [AXI5_MAX_BURST_LEN-1:0][63:0] valid_test_data_narrow_four_byte_offset_4_bytes = valid_test_data;

  // test data barrel-shifted by four left
  // only one-beat transfers allowed
  localparam bit [63:0] valid_test_data_narrow_four_byte_offset_4_bytes_shift_left_4 = 64'h89ABCDEF01234567;

  localparam bit [AXI5_MAX_BURST_LEN-1:0][63:0] valid_test_strobes_narrow_four_byte_offset_4_bytes_shift_left_4 = {
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000
  };

  localparam bit[AXI5_MAX_BURST_LEN-1:0][7:0] valid_test_strobes_narrow_four_byte_offset_4_bytes = {
    8'b00001111
  };

  // this is for a narrow burst, 4 bytes out of 8 bytes, with a four-byte offset
  localparam bit [AXI5_MAX_BURST_LEN-1:0][63:0] valid_test_data_narrow_zero_byte_offset_4_bytes = {
    64'h0123456700000000,
    64'h00000000ABCDEF01,
    64'h456789AB00000000,
    64'h00000000EF012345,
    64'h89ABCDEF00000000,
    64'h0000000012345678,
    64'hABCDEF0100000000,
    64'h00000000456789AB,
    64'hEF01234500000000,
    64'h00000000789ABCDE,
    64'h89ABCDEF00000000,
    64'h0000000067890123,
    64'hCDEF678900000000,
    64'h00000000CDEF4567,
    64'hF012345600000000,
    64'h0000000089ABCDEF
  };

  localparam bit [AXI5_MAX_BURST_LEN-1:0][63:0] valid_test_data_narrow_zero_byte_offset_4_bytes_shift_right_4 = {
    64'h89ABCDEF00000000,
    64'h0000000023456789,
    64'hCDEF012300000000,
    64'h000000006789ABCD,
    64'h0123456700000000,
    64'h000000009ABCDEF0,
    64'h2345678900000000,
    64'h00000000CDEF0123,
    64'h6789ABCD00000000,
    64'h00000000F0123456,
    64'h2345670100000000,
    64'h00000000ABCDEF45,
    64'hABCDEF4500000000,
    64'h00000000EF0123AB,
    64'h789ABC8900000000,
    64'h0000000001234567
  };

  localparam bit [AXI5_MAX_BURST_LEN-1:0][63:0] valid_test_strobes_narrow_zero_byte_offset_4_bytes_shift_right_4 = {
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111
  };

  localparam bit[AXI5_MAX_BURST_LEN-1:0][7:0] valid_test_strobes_narrow_zero_byte_offset_4_bytes = {
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111,
    8'b11110000,
    8'b00001111
  };

  // data re-ordered as if beginning at offset 0e
  localparam bit [AXI5_MAX_BURST_LEN-1:0][63:0] valid_wrap_test_data = {
    64'hCDEF6789ABCDEF45,
    64'hABCDEF4567890123,
    64'h89ABCDEF23456701,
    64'hF0123456789ABCDE,
    64'hEF0123456789ABCD,
    64'hCDEF0123456789AB,
    64'hABCDEF0123456789,
    64'h9ABCDEF012345678,
    64'h89ABCDEF01234567,
    64'h6789ABCDEF012345,
    64'h456789ABCDEF0123,
    64'h23456789ABCDEF01,
    64'h0123456789ABCDEF,
    64'h0123456789ABCDEF,
    64'hF0123456789ABC89,
    64'hEF0123ABCDEF4567
  };

  // outputs correspond to memory above, with a wrapping burst starting at position 0e=14
  // assumes 4-word segment that cuts 1 byte from first and last word 
  localparam bit [AXI5_MAX_BURST_LEN-1:0][63:0] expected_wrap_output_1_burst = {
    64'hF0123456789ABC89,
    64'hEF0123ABCDEF4567
  };

  localparam bit [AXI5_MAX_BURST_LEN-1:0][63:0] expected_wrap_output_3_burst = {
    64'h0123456789ABCDEF,
    64'h0123456789ABCDEF,
    64'hF0123456789ABC89,
    64'hEF0123ABCDEF4567
  };

  localparam bit [AXI5_MAX_BURST_LEN-1:0][63:0] expected_wrap_output_7_burst = {
    64'h00,
    64'h00,
    64'h00,
    64'h00,
    64'h0123456789ABCDEF,
    64'h0123456789ABCDEF,
    64'hF0123456789ABC89,
    64'hEF0123ABCDEF4567
  };


  localparam bit [AXI5_MAX_BURST_LEN-1:0][63:0] expected_wrap_output_15_burst = {
    64'h00,
    64'h00,
    64'h00,
    64'h00,
    64'h00,
    64'h00,
    64'h00,
    64'h00,
    64'h00,
    64'h00,
    64'h00,
    64'h00,
    64'h0123456789ABCDEF,
    64'h0123456789ABCDEF,
    64'hF0123456789ABC89,
    64'hEF0123ABCDEF4567
  };


  `ifdef NORTHCAPE_TEST_COVERAGE
    // (at least in Vivado), there is a limit on how much coverage data can be collected, leading to simulator crash...
    localparam TEST_REPETITIONS=8;
  `else
    localparam TEST_REPETITIONS=64;
  `endif
  
  `define REPEAT_TEST(TEST_COMMAND) \
    for(int test_repetition_counter = 0; test_repetition_counter < TEST_REPETITIONS; test_repetition_counter++)  \
    begin  \
      `uvm_info(COMPONENT_NAME,$sformatf("Test repetition %d of %d",test_repetition_counter+1,TEST_REPETITIONS),UVM_DEBUG) \
      TEST_COMMAND;  \
    end

  //===================================
  // This is the UUT that we're 
  // running the Unit Tests on
  //===================================

  localparam AXI_USER_WIDTH = $bits(northcape_axi_user_t);
  localparam AXI_ID_WIDTH = 4;
  localparam AXI_DATA_WIDTH = 64;
  localparam AXI_ADDR_WIDTH = 64;
  localparam device_id_t READ_CHAN_DEVICE_ID = 0;
  localparam device_id_t WRITE_CHAN_DEVICE_ID = 1;

  logic [63:0] wrap_resolved_addr;

  typedef NorthcapeMMUTransaction#(.READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID), .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID), .AXI_DATA_WIDTH(AXI_DATA_WIDTH), .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_USER_WIDTH(AXI_USER_WIDTH), .AXI_ID_WIDTH(AXI_ID_WIDTH),.CHECK_CMT_OVERLAP(1)) transaction_t;
  typedef NorthcapeGenerator#(transaction_t) generator_t;
  
  
  typedef NorthcapeGenericEnv#(
    .AGENT_TYPE(mmu_agent_t),
    .RESET_INTERFACE_NAME(MMU_RESET_INTERFACE_NAME)
  ) mmu_env_t;

  typedef NorthcapeMMUCommon#(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),
    .ACCEPT_AXI_WRAP_BURSTS(1),
    .IS_WRITE_CHAN(0)
  ) mmu_common_t;

  
  function automatic void prepare_transaction_slave(ref transaction_t new_request, input axis_validate_request_perm_t expected_transaction_type, input logic[63:0] test_addr, input axi_len_t test_len, input axi_burst_t burst_type, input axi_atop_t atomic_type, input bit regression_keep_valid_high = 0, input bit[AXI_ADDR_WIDTH-1:0] cmt_base = valid_test_cmt_start, input int unsigned cmt_size_clog2 = valid_test_cmt_size_clog_2, axi_size_t size, input bit[7:0] input_strobes = 8'hff);
    new_request.axi_request_type = expected_transaction_type == READ ? AXI_TEST_READ : AXI_TEST_WRITE;
    new_request.capability_token = test_addr;
    new_request.test_len = test_len;
    new_request.burst_type = burst_type;
    new_request.atomic_type.atop_type = atomic_type;
    new_request.atomic_type.atop_subtype = '0; 

    // regressions
    new_request.regression_keep_valid_high = regression_keep_valid_high;

    // unused / default
    new_request.test_id = '0;
    new_request.test_lock = 0;
    new_request.test_cache = '0;
    new_request.test_prot = '0;
    new_request.test_qos = '0;
    new_request.test_region = '0;
    new_request.test_size = size;


    new_request.write_strobes = '0;
    for(int i = 0; i < test_len + 1; i++)
    begin
      new_request.write_strobes[i] = input_strobes;
    end

    new_request.cmt_base_addr = cmt_base;
    new_request.cmt_size_clog2 = cmt_size_clog2;
  
  endfunction

  function automatic void prepare_transaction_master(ref transaction_t new_request, input axis_validate_request_perm_t expected_transaction_type, segment_base_addr_t test_addr, input axi_len_t test_len, input axi_burst_t burst_type, input axi_atop_t atomic_type, axi_resp_t response, bit regression_ready_before_valid = 0, axi_size_t size);

    new_request.axi_request_type = expected_transaction_type == READ ? AXI_TEST_READ : AXI_TEST_WRITE;
    new_request.physical_address = test_addr;
    new_request.test_len = test_len;
    new_request.burst_type = burst_type;
    new_request.atomic_type.atop_type = atomic_type;
    new_request.atomic_type.atop_subtype = '0;
    new_request.given_response = response;
    new_request.expected_response = response;

    new_request.test_id = '0;
    new_request.test_lock = 0;
    new_request.test_cache = '0;
    new_request.test_prot = '0;
    new_request.test_qos = '0;
    new_request.test_region = '0;
    new_request.test_size = size;

    // regressions
    new_request.regression_ready_before_valid = regression_ready_before_valid;
  
  endfunction


  function automatic void prepare_transaction_resolver(ref transaction_t new_request, input logic [63:0] test_addr, input segment_base_addr_t segment_base, input segment_length_t segment_length, input axis_validate_request_perm_t expected_transaction_type, input northcape_restriction_type_t restr_type, input northcape_restriction_body_t restr_body, input bit is_instruction_fetch, input bit is_irq);

    new_request.resolver_expected_request.address = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(test_addr);
    new_request.resolver_expected_request.tag = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(test_addr);

    if(expected_transaction_type == READ && is_instruction_fetch)
    begin
      new_request.resolver_expected_request.access_type = is_irq ? EXECUTE_IRQ : EXECUTE;
      new_request.instruction_fetch = 1'b1;
      new_request.test_user_in = {is_irq, 1'b1};
      new_request.is_irq = is_irq;
    end
    else
    begin
      unique case(expected_transaction_type)
        READ:
          new_request.resolver_expected_request.access_type = is_irq ? READ_IRQ : READ;
        WRITE:
          new_request.resolver_expected_request.access_type = is_irq ? WRITE_IRQ : WRITE;
        READ_WRITE:
          new_request.resolver_expected_request.access_type = is_irq ? READ_WRITE_IRQ : READ_WRITE;
        default:
        begin
          `uvm_fatal(COMPONENT_NAME, $sformatf("Did not expect access type %s", new_request.resolver_expected_request.access_type.name()));
        end
      endcase

      new_request.instruction_fetch = 1'b0;
      new_request.is_irq = is_irq;
      new_request.test_user_in = {is_irq, 1'b0};
    end

    new_request.resolver_expected_request.device_id = (expected_transaction_type == READ) ? READ_CHAN_DEVICE_ID : WRITE_CHAN_DEVICE_ID;

    `uvm_info(COMPONENT_NAME,$sformatf("Setting resolver address to %x segment length to %x",segment_base, segment_length),UVM_DEBUG);

    new_request.resolver_response.address = segment_base;
    new_request.resolver_response.segment_length = segment_length;
    new_request.resolver_response.restriction = restr_body;
    new_request.resolver_response.restriction_type = restr_type;
    new_request.resolver_response.error_code = NORTHCAPE_RESOLVE_NO_ERROR;
  
  endfunction

  typedef bit [AXI5_MAX_BURST_LEN-1:0][63:0] expected_data_t;

  function automatic expected_data_t prepare_read_chan_data(input integer actual_test_length, input axi_burst_t burst_type, input segment_length_t real_segment_length, input bit[AXI5_MAX_BURST_LEN-1:0][63:0] expected_memory, input bit[63:0] expected_first_word, input logic[63:0] expected_last_word, input logic is_atomic);
    bit [AXI5_MAX_BURST_LEN-1:0][63:0] ret;
      
    for(int i = 0; i < actual_test_length; i++)
    begin
      unique case(burst_type)
      INCR:
        if(i == actual_test_length - 1)
        begin
          ret[i] = expected_last_word;
        end
        else if(i == 0)
        begin
          ret[i] = expected_first_word;
        end
        else
        begin
          ret[i] = expected_memory[i];
        end
      FIXED:
        ret[i] = expected_first_word;
        // should just return the same word over and over
      WRAP:
        if(i == 0)
        begin
          ret[i] = expected_first_word;
        end
        else if(i == (real_segment_length+7) / 8 - 1)
        begin
          `uvm_info(COMPONENT_NAME,$sformatf("Expecting last word %x at index %d",expected_last_word,i),UVM_DEBUG);
          ret[i] = expected_last_word;
        end
        else
        begin
          `uvm_info(COMPONENT_NAME,$sformatf("Expecting word %x at index %d", expected_memory[i],i),UVM_DEBUG);
          ret[i] = expected_memory[i];
        end
      BURST_RESERVED:
      begin
        `uvm_fatal(COMPONENT_NAME,"Burst should never be reserved!");
      end
      endcase
      
    end


    return ret;
  endfunction


  function automatic void test_valid_read(input logic[63:0] test_addr, input axi_len_t test_len, input axi_burst_t burst_type, input segment_base_addr_t segment_base, input segment_length_t real_segment_length, input bit [AXI5_MAX_BURST_LEN-1:0][63:0] simulated_memory, input bit [AXI5_MAX_BURST_LEN-1:0][63:0] expected_memory, input logic[63:0] expected_first_word, input logic[63:0] expected_last_word, input bit regression_keep_valid_high=0, input bit sample_coverage_data = 1, axi_size_t size = $clog2(AXI_DATA_WIDTH/8), input northcape_restriction_type_t restr_type=NORTHCAPE_RESTRICTIONS_NONE, input northcape_restriction_body_t restr_body='0, bit is_instruction_fetch= 1'b0, bit is_irq = 1'b0, input capability_off_t extra_offset = '0);
    transaction_t new_request;
    uvm_queue#(transaction_t) queue;


    new_request = generator_t::generate_transaction_ephemeral();
    new_request.invalid_access = 0;
    
    prepare_transaction_slave(new_request, READ, test_addr, test_len, burst_type, ATOMIC_NONE, regression_keep_valid_high, .size(size));
    prepare_transaction_master(new_request, READ, segment_base + extra_offset, test_len, burst_type, ATOMIC_NONE, OKAY, .size(size));
    
    prepare_transaction_resolver(new_request, test_addr, segment_base, real_segment_length, READ, restr_type, restr_body, is_instruction_fetch, is_irq);

    new_request.expected_data = prepare_read_chan_data({24'h0, test_len} + 1, burst_type, real_segment_length, expected_memory, expected_first_word, expected_last_word, 0);
    new_request.expected_response = OKAY;
    
    new_request.response_data = simulated_memory;


    
    assert(uvm_config_db#(uvm_queue#(transaction_t))::get(null,"",MMU_TRANSACTION_QUEUE_NAME,queue));

    `uvm_info(COMPONENT_NAME,$sformatf("I have pushed a read test with data %x",new_request.expected_data),UVM_DEBUG);
    
    queue.push_back(new_request);
    
  endfunction

  function automatic void test_failing_read(input logic[63:0] test_addr, input axi_len_t test_len, input axi_burst_t burst_type, input segment_base_addr_t segment_base, input segment_length_t real_segment_length, input bit regression_keep_valid_high=0, input bit sample_coverage_data = 1, input bit[AXI_ADDR_WIDTH-1:0] cmt_base = valid_test_cmt_start, input int unsigned cmt_size_clog2 = valid_test_cmt_size_clog_2, axi_size_t size = $clog2(AXI_DATA_WIDTH/8), input northcape_restriction_type_t restr_type=NORTHCAPE_RESTRICTIONS_NONE, input northcape_restriction_body_t restr_body='0, bit is_instruction_fetch= 1'b0, bit is_irq = 1'b0);
    logic slave_complete, resolver_complete;
    bit [AXI5_MAX_BURST_LEN-1:0][63:0] expected_data; // all-zeros
    transaction_t new_request;
    axi_test_request_result_t result;
    uvm_queue#(transaction_t) queue;

    new_request = generator_t::generate_transaction_ephemeral();
    new_request.invalid_access = 1;

    prepare_transaction_slave(new_request, READ, test_addr, test_len, burst_type, ATOMIC_NONE, regression_keep_valid_high, .cmt_base(cmt_base), .cmt_size_clog2(cmt_size_clog2), .size(size));

    prepare_transaction_resolver(new_request, test_addr, segment_base, real_segment_length, READ, restr_type, restr_body, is_instruction_fetch, is_irq);

    if(is_instruction_fetch)
    begin
      // failing reads return ebreak instructions
      for(int i = 0; i <= test_len; i++)
      begin
        expected_data[i] = mmu_common_t::INSTRUCTION_FETCH_ERROR_RESP;
      end
      new_request.expected_data = expected_data;
      new_request.expected_response = OKAY;
    end
    else
    begin
      new_request.expected_data = expected_data;
      new_request.expected_response = DECERR;
    end

    slave_complete = 0;

    assert(uvm_config_db#(uvm_queue#(transaction_t))::get(null,"",MMU_TRANSACTION_QUEUE_NAME,queue));
    queue.push_back(new_request);
    
  endfunction

  function automatic void test_valid_write(input logic[63:0] test_addr, input axi_len_t test_len, input axi_burst_t burst_type, input segment_base_addr_t segment_base, input segment_length_t real_segment_length, input bit[AXI5_MAX_BURST_LEN-1:0][63:0] input_memory, input bit[AXI5_MAX_BURST_LEN-1:0][7:0] expected_strobes, input axi_atop_t atomic_type, input bit [AXI5_MAX_BURST_LEN-1:0][63:0] simulated_memory, input bit [AXI5_MAX_BURST_LEN-1:0][63:0] expected_memory, input logic[63:0] expected_first_word, input logic[63:0] expected_last_word, bit regression_ready_before_valid = 0, input bit regression_keep_valid_high = 0, input bit sample_coverage_data = 1, axi_size_t size = $clog2(AXI_DATA_WIDTH/8), input bit[AXI5_MAX_BURST_LEN-1:0][63:0] expected_write_data=input_memory, input northcape_restriction_type_t restr_type=NORTHCAPE_RESTRICTIONS_NONE, input northcape_restriction_body_t restr_body='0, input capability_off_t extra_offset = '0, bit is_irq = 1'b0, input bit[7:0] input_strobes = 8'hff);
    bit [AXI5_MAX_BURST_LEN-1:0][63:0] expected_data;
    transaction_t new_request;
    axi_test_request_result_t result;
    uvm_queue#(transaction_t) queue;

    new_request = generator_t::generate_transaction_ephemeral();
    new_request.invalid_access = 0;

    // atomic transactions THAT RETURN DATA must request READ and WRITE
    prepare_transaction_slave(new_request, (atomic_type == ATOMIC_NONE || atomic_type == ATOMIC_STORE) ? WRITE : READ_WRITE, test_addr, test_len, burst_type, atomic_type, regression_keep_valid_high, .size(size), .input_strobes(input_strobes));
    prepare_transaction_master(new_request, (atomic_type == ATOMIC_NONE || atomic_type == ATOMIC_STORE) ? WRITE : READ_WRITE, segment_base + extra_offset, test_len, burst_type, atomic_type, OKAY, regression_ready_before_valid, .size(size));

    prepare_transaction_resolver(new_request, test_addr, segment_base, real_segment_length, (atomic_type == ATOMIC_NONE || atomic_type == ATOMIC_STORE) ? WRITE : READ_WRITE, restr_type, restr_body, 1'b0, is_irq);

    if(!(atomic_type == ATOMIC_NONE || atomic_type == ATOMIC_STORE))
    begin
      `uvm_info(COMPONENT_NAME,"Is atomic test!",UVM_DEBUG);
      // read response required
      expected_data = prepare_read_chan_data({24'h0, test_len} + 1, burst_type, real_segment_length, expected_memory, expected_first_word, expected_last_word, 1);
    end

    `uvm_info(COMPONENT_NAME,"starting write test!",UVM_DEBUG);

    new_request.expected_data = expected_data;
    new_request.write_data = input_memory;
    new_request.atomic_type.atop_type = atomic_type;
    new_request.atomic_type.atop_subtype = '0;
    new_request.expected_response = OKAY;

    new_request.expected_write_data = expected_write_data;
    new_request.response_data = simulated_memory;
    new_request.expected_write_strobes = expected_strobes;

    assert(uvm_config_db#(uvm_queue#(transaction_t))::get(null,"",MMU_TRANSACTION_QUEUE_NAME,queue));
    queue.push_back(new_request);

  endfunction

  function automatic void test_failing_write(input logic[63:0] test_addr, input axi_len_t test_len, input axi_burst_t burst_type, input segment_base_addr_t segment_base, input segment_length_t real_segment_length, input axi_atop_t atomic_type, input bit regression_keep_valid_high=0, input bit sample_coverage_data = 1, input bit[AXI_ADDR_WIDTH-1:0] cmt_base = valid_test_cmt_start, input int unsigned cmt_size_clog2 = valid_test_cmt_size_clog_2, axi_size_t size = $clog2(AXI_DATA_WIDTH/8), input northcape_restriction_type_t restr_type=NORTHCAPE_RESTRICTIONS_NONE, input northcape_restriction_body_t restr_body='0, bit is_irq = 1'b0);
    bit [AXI5_MAX_BURST_LEN-1:0][63:0] expected_data;
    transaction_t new_request;
    axi_test_request_result_t result;
    uvm_queue#(transaction_t) queue;

    new_request = generator_t::generate_transaction_ephemeral();

    new_request.invalid_access = 1;

    // atomic transactions THAT RETURN DATA must request READ and WRITE
    prepare_transaction_slave(new_request, (atomic_type == ATOMIC_NONE || atomic_type == ATOMIC_STORE) ? WRITE : READ_WRITE, test_addr, test_len, burst_type, atomic_type, regression_keep_valid_high, .cmt_base(cmt_base), .cmt_size_clog2(cmt_size_clog2), .size(size));
    prepare_transaction_resolver(new_request, test_addr, segment_base, real_segment_length, (atomic_type == ATOMIC_NONE || atomic_type == ATOMIC_STORE) ? WRITE : READ_WRITE, restr_type, restr_body, 1'b0, is_irq);

    new_request.write_data = expected_data;
    new_request.atomic_type.atop_type = atomic_type;
    new_request.atomic_type.atop_subtype = '0;
    new_request.expected_data = expected_data; // all-zeros
    new_request.expected_response = DECERR;

    assert(uvm_config_db#(uvm_queue#(transaction_t))::get(null,"",MMU_TRANSACTION_QUEUE_NAME,queue));
    queue.push_back(new_request);
  endfunction

  logic[63:0] expected_start_word, expected_end_word;

  `NORTHCAPE_UVM_TEST(mmu_requests_permission_check_on_read,mmu_env_t)
    `REPEAT_TEST(test_valid_read(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len]));
    
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_correctly_reads_segments_which_end_mid_word,mmu_env_t)
    `uvm_info(COMPONENT_NAME,"7 Bytes",UVM_DEBUG);
    `REPEAT_TEST(test_valid_read(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length - 1, valid_test_data, valid_test_data, valid_test_data[0], 64'h0023456789ABCDEF));
    `uvm_info(COMPONENT_NAME,"6 Bytes",UVM_DEBUG); 
    `REPEAT_TEST(test_valid_read(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length - 2, valid_test_data, valid_test_data, valid_test_data[0], 64'h0000456789ABCDEF));
    `uvm_info(COMPONENT_NAME,"5 Bytes",UVM_DEBUG);
    `REPEAT_TEST(test_valid_read(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length - 3, valid_test_data, valid_test_data, valid_test_data[0], 64'h0000006789ABCDEF));
    `uvm_info(COMPONENT_NAME,"4 Bytes",UVM_DEBUG);
    `REPEAT_TEST(test_valid_read(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length - 4, valid_test_data, valid_test_data, valid_test_data[0], 64'h0000000089ABCDEF));
    `uvm_info(COMPONENT_NAME,"3 Bytes",UVM_DEBUG);
    `REPEAT_TEST(test_valid_read(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length - 5, valid_test_data, valid_test_data, valid_test_data[0], 64'h0000000000ABCDEF));
    `uvm_info(COMPONENT_NAME,"2 Bytes",UVM_DEBUG);
    `REPEAT_TEST(test_valid_read(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length - 6, valid_test_data, valid_test_data, valid_test_data[0], 64'h000000000000CDEF));
    `uvm_info(COMPONENT_NAME,"1 Bytes",UVM_DEBUG);
    `REPEAT_TEST(test_valid_read(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length - 7, valid_test_data, valid_test_data, valid_test_data[0], 64'h00000000000000EF));
  `NORTHCAPE_UVM_TEST_END
  
  `NORTHCAPE_UVM_TEST(mmu_correctly_reads_fixed_bursts,mmu_env_t)
    `REPEAT_TEST(test_valid_read(valid_test_addr, valid_test_len, FIXED, valid_test_segment_base, 8, valid_test_data_fixed, valid_test_data_fixed, valid_test_data[0], valid_test_data[0]));
  `NORTHCAPE_UVM_TEST_END

`ifndef NORTHCAPE_MMU_NO_AXI_WRAP
  `NORTHCAPE_UVM_TEST(mmu_correctly_reads_wrap_bursts,mmu_env_t)
    // segment bounds computed from test address and burst length based on schema
    `uvm_info(COMPONENT_NAME,"Testing burst len 2",UVM_DEBUG);
    `REPEAT_TEST(test_valid_read(valid_test_addr, 1, WRAP, valid_test_segment_base, 16, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[1]));
    `uvm_info(COMPONENT_NAME,"Testing burst len 4",UVM_DEBUG);
    `REPEAT_TEST(test_valid_read(valid_test_addr, 3, WRAP, valid_test_segment_base, 32, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[3]));
    `uvm_info(COMPONENT_NAME,"Testing burst len 8",UVM_DEBUG);
    `REPEAT_TEST(test_valid_read(valid_test_addr, 7, WRAP, valid_test_segment_base, 64, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[7]));
    `uvm_info(COMPONENT_NAME,"Testing burst len 16",UVM_DEBUG);
    `REPEAT_TEST(test_valid_read(valid_test_addr, 15, WRAP, valid_test_segment_base, 128, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[15]));

  `NORTHCAPE_UVM_TEST_END
`endif

`ifndef NORTHCAPE_MMU_NO_AXI_WRAP
  // many CPUs use wrapping bursts to load cache lines
  // cache lines can be larger than the actual segments that we are allowing access to
  // in this test, we make sure that the request is accepted without leaking any information beyond the permissible segment
  // for added edge case test, we define segment such that 1 byte of first and last word needs to be masked out
  `NORTHCAPE_UVM_TEST(mmu_correctly_reads_wrap_bursts_larger_than_segment,mmu_env_t)
    for(int end_off = 0; end_off < 8; end_off = end_off + 1)
    begin
      // segment is 4 words long
      expected_start_word = valid_wrap_test_data[0];
      expected_end_word = valid_wrap_test_data[3] & ((1<<(64-end_off * 8)) - 1);
      `uvm_info(COMPONENT_NAME,$sformatf("Testing burst with start offset %d end offset %d expected start word %x expected end word %x",0, end_off, expected_start_word, expected_end_word),UVM_DEBUG);
      `uvm_info(COMPONENT_NAME,"Testing burst len 2",UVM_DEBUG);
      `REPEAT_TEST(test_valid_read(valid_test_addr, 1, WRAP, valid_test_segment_base, 32 - end_off, valid_wrap_test_data, expected_wrap_output_1_burst, expected_start_word, expected_end_word));
      `uvm_info(COMPONENT_NAME,"Testing burst len 4",UVM_DEBUG);
      `REPEAT_TEST(test_valid_read(valid_test_addr, 3, WRAP, valid_test_segment_base, 32 - end_off, valid_wrap_test_data, expected_wrap_output_3_burst, expected_start_word, expected_end_word));
      `uvm_info(COMPONENT_NAME,"Testing burst len 8",UVM_DEBUG);
      `REPEAT_TEST(test_valid_read(valid_test_addr, 7, WRAP, valid_test_segment_base, 32 - end_off, valid_wrap_test_data, expected_wrap_output_7_burst, expected_start_word, expected_end_word));
      `uvm_info(COMPONENT_NAME,"Testing burst len 16",UVM_DEBUG);
      `REPEAT_TEST(test_valid_read(valid_test_addr, 15, WRAP, valid_test_segment_base, 32 - end_off, valid_wrap_test_data, expected_wrap_output_15_burst, expected_start_word, expected_end_word));
    end
  `NORTHCAPE_UVM_TEST_END
`endif

  `NORTHCAPE_UVM_TEST(mmu_refuses_burst_for_invalid_segment_read,mmu_env_t)
    `REPEAT_TEST(test_failing_read(valid_test_addr, valid_test_len, INCR, valid_test_segment_base, '0));
    `REPEAT_TEST(test_failing_read(valid_test_addr, valid_test_len, FIXED, valid_test_segment_base, '0));
`ifndef NORTHCAPE_MMU_NO_AXI_WRAP
    `REPEAT_TEST(test_failing_read(valid_test_addr, valid_test_len, WRAP, valid_test_segment_base, '0));
`endif
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_refuses_burst_for_invalid_segment_0_length_read,mmu_env_t)
    `REPEAT_TEST(test_failing_read(valid_test_addr, 0, INCR, valid_test_segment_base, '0));
    `REPEAT_TEST(test_failing_read(valid_test_addr, 0, FIXED, valid_test_segment_base, '0));
`ifndef NORTHCAPE_MMU_NO_AXI_WRAP
    `REPEAT_TEST(test_failing_read(valid_test_addr, 0, WRAP, valid_test_segment_base, '0));
`endif
  `NORTHCAPE_UVM_TEST_END

  // transaction starts after the end of the segment
  `NORTHCAPE_UVM_TEST(mmu_refuses_burst_for_out_of_bounds_read,mmu_env_t)
    `REPEAT_TEST(test_failing_read(overflow_test_addr, valid_test_len, INCR, valid_test_segment_base, valid_test_segment_length));
    `REPEAT_TEST(test_failing_read(overflow_test_addr, valid_test_len, FIXED, valid_test_segment_base, valid_test_segment_length));
  `NORTHCAPE_UVM_TEST_END

  // transaction leaves the bounds of the segment
  `NORTHCAPE_UVM_TEST(mmu_refuses_burst_for_escaping_read_fixed,mmu_env_t)
    `REPEAT_TEST(test_failing_read(overflow_test_addr, valid_test_len, FIXED, valid_test_segment_base, valid_test_segment_length));
  `NORTHCAPE_UVM_TEST_END


  `ifndef NORTHCAPE_MMU_NO_AXI_WRAP
    `NORTHCAPE_UVM_TEST(mmu_refuses_burst_for_undefined_wrap_length_read,mmu_env_t)
    for(axi_len_t invalid_length = 0; invalid_length < 15 && invalid_length != 1 && invalid_length != 3 && invalid_length != 7; invalid_length = invalid_length + 1)
    begin
      `uvm_info(COMPONENT_NAME,"Testing invalid wrap for burst length %u!",invalid_length);
      `REPEAT_TEST(test_failing_read(valid_test_addr, invalid_length, WRAP, valid_test_segment_base, valid_test_segment_length));
    end
  `NORTHCAPE_UVM_TEST_END
  `endif

  `NORTHCAPE_UVM_TEST(mmu_refuses_read_for_cmt,mmu_env_t)
    `REPEAT_TEST(test_failing_read(valid_test_addr, valid_test_len, INCR, valid_test_segment_base, valid_test_segment_length, .cmt_base(valid_test_segment_base), .cmt_size_clog2(4)));
    `REPEAT_TEST(test_failing_read(valid_test_addr, valid_test_len, FIXED, valid_test_segment_base, 8, .cmt_base(valid_test_segment_base), .cmt_size_clog2(4)));
`ifndef NORTHCAPE_MMU_NO_AXI_WRAP
    `REPEAT_TEST(test_failing_read(valid_test_addr, 15, WRAP, valid_test_segment_base, 128, .cmt_base(valid_test_segment_base), .cmt_size_clog2(4)));
`endif
  `NORTHCAPE_UVM_TEST_END

  function void initialize_test_strobes(inout logic [AXI5_MAX_BURST_LEN-1:0][7:0] strobes, input axi_len_t test_len);
    strobes = '0;
    for(int i = 0; i < test_len + 1; i++)
    begin
      strobes[i] = '1;
    end
  endfunction

  `NORTHCAPE_UVM_TEST(mmu_can_do_simple_write,mmu_env_t)
    initialize_test_strobes(valid_test_strobes, valid_test_len);
    `REPEAT_TEST(test_valid_write(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_correctly_writes_segments_which_end_mid_word,mmu_env_t)
    for(int i=1; i < 8; i = i + 1)
    begin
      initialize_test_strobes(valid_test_strobes, valid_test_len);
      valid_test_strobes[valid_test_len] = (1<<(8-i))-1;
      `uvm_info(COMPONENT_NAME,$sformatf("%d Bytes with expected last strobe %x",i,valid_test_strobes[valid_test_len]),UVM_DEBUG);
      `REPEAT_TEST(test_valid_write(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length-i, valid_test_data, valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0));
    end
  `NORTHCAPE_UVM_TEST_END

  
  `NORTHCAPE_UVM_TEST(mmu_correctly_writes_fixed_bursts,mmu_env_t)
    initialize_test_strobes(valid_test_strobes, valid_test_len);
    `REPEAT_TEST(test_valid_write(valid_test_addr, valid_test_len, FIXED, valid_test_segment_base, 8, valid_test_data, valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0));
  `NORTHCAPE_UVM_TEST_END

  `ifndef NORTHCAPE_MMU_NO_AXI_WRAP
  `NORTHCAPE_UVM_TEST(mmu_correctly_writes_wrap_bursts,mmu_env_t)
    // segment bounds computed from test address and burst length based on schema
    `uvm_info(COMPONENT_NAME,"Testing burst len 2",UVM_DEBUG);
    initialize_test_strobes(valid_test_strobes, 1);
    `REPEAT_TEST(test_valid_write(valid_test_addr, 1, WRAP, valid_test_segment_base, 16, valid_test_data[1:0],  valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0));
    `uvm_info(COMPONENT_NAME,"Testing burst len 4",UVM_DEBUG);
    initialize_test_strobes(valid_test_strobes, 3);
    `REPEAT_TEST(test_valid_write(valid_test_addr, 3, WRAP, valid_test_segment_base, 32, valid_test_data[3:0],  valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0));
    `uvm_info(COMPONENT_NAME,"Testing burst len 8",UVM_DEBUG);
    initialize_test_strobes(valid_test_strobes, 7);
    `REPEAT_TEST(test_valid_write(valid_test_addr, 7, WRAP, valid_test_segment_base, 64, valid_test_data[7:0],  valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0));
    `uvm_info(COMPONENT_NAME,"Testing burst len 16",UVM_DEBUG);
    initialize_test_strobes(valid_test_strobes, 15);
    `REPEAT_TEST(test_valid_write(valid_test_addr, 15, WRAP, valid_test_segment_base, 128, valid_test_data[15:0],  valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0));

  `NORTHCAPE_UVM_TEST_END
`endif

`ifndef NORTHCAPE_MMU_NO_AXI_WRAP
  // many CPUs use wrapping bursts to load cache lines
  // cache lines can be larger than the actual segments that we are allowing access to
  // in this test, we make sure that the request is accepted without leaking any information beyond the permissible segment
  // for added edge case test, we define segment such that 1 byte of first and last word needs to be masked out
  `NORTHCAPE_UVM_TEST(mmu_correctly_writes_wrap_bursts_larger_than_segment,mmu_env_t)
    for(int i = 4; i < valid_test_len+1; i = i + 1)
    begin
      valid_test_strobes[i] = 8'h00;
    end
    for(int end_off = 0; end_off < 8; end_off = end_off + 1)
    begin
      // segment is 4 words long
      valid_test_strobes[0] = 8'hff;
      valid_test_strobes[1] = '1;
      valid_test_strobes[2] = '0;
      valid_test_strobes[3] = '0;
      `uvm_info(COMPONENT_NAME,$sformatf("Testing burst with start offset %d end offset %d expected start word %x expected end word %x",0, end_off, valid_test_strobes[0], valid_test_strobes[3]),UVM_DEBUG);
      `uvm_info(COMPONENT_NAME,"Testing burst len 2",UVM_DEBUG);
      `REPEAT_TEST(test_valid_write(valid_test_addr, 1, WRAP, valid_test_segment_base, 32 - end_off, valid_wrap_test_data[1:0], valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0));
      `uvm_info(COMPONENT_NAME,"Testing burst len 4",UVM_DEBUG);
      valid_test_strobes[1] = '1;
      valid_test_strobes[2] = '1;
      valid_test_strobes[3] = 8'hff & ((1<<(8-end_off)) - 1);
      `REPEAT_TEST(test_valid_write(valid_test_addr, 3, WRAP, valid_test_segment_base, 32 - end_off, valid_wrap_test_data[3:0], valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0));
      `uvm_info(COMPONENT_NAME,"Testing burst len 8",UVM_DEBUG);
      `REPEAT_TEST(test_valid_write(valid_test_addr, 7, WRAP, valid_test_segment_base, 32 - end_off, valid_wrap_test_data[7:0], valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0));
      `uvm_info(COMPONENT_NAME,"Testing burst len 16",UVM_DEBUG);
      `REPEAT_TEST(test_valid_write(valid_test_addr, 15, WRAP, valid_test_segment_base, 32 - end_off, valid_wrap_test_data[15:0], valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0));
    end
  `NORTHCAPE_UVM_TEST_END
`endif

`NORTHCAPE_UVM_TEST(mmu_refuses_burst_for_invalid_segment_write,mmu_env_t)
    `REPEAT_TEST(test_failing_write(valid_test_addr, valid_test_len, INCR, valid_test_segment_base, '0, ATOMIC_NONE));
    `REPEAT_TEST(test_failing_write(valid_test_addr, valid_test_len, FIXED, valid_test_segment_base, '0, ATOMIC_NONE));
`ifndef NORTHCAPE_MMU_NO_AXI_WRAP
    `REPEAT_TEST(test_failing_write(valid_test_addr, valid_test_len, WRAP, valid_test_segment_base, '0, ATOMIC_NONE));
`endif
  `NORTHCAPE_UVM_TEST_END


  `NORTHCAPE_UVM_TEST(mmu_refuses_burst_for_invalid_segment_0_length_write,mmu_env_t)
    `REPEAT_TEST(test_failing_write(valid_test_addr, 0, INCR, valid_test_segment_base, '0, ATOMIC_NONE));
    `REPEAT_TEST(test_failing_write(valid_test_addr, 0, FIXED, valid_test_segment_base, '0, ATOMIC_NONE));
`ifndef NORTHCAPE_MMU_NO_AXI_WRAP
    `REPEAT_TEST(test_failing_write(valid_test_addr, 0, WRAP, valid_test_segment_base, '0, ATOMIC_NONE));
`endif
  `NORTHCAPE_UVM_TEST_END

  // transaction starts after the end of the segment
  `NORTHCAPE_UVM_TEST(mmu_refuses_burst_for_out_of_bounds_write,mmu_env_t)
    `REPEAT_TEST(test_failing_write(overflow_test_addr, valid_test_len, INCR, valid_test_segment_base, valid_test_segment_length, ATOMIC_NONE));
    `REPEAT_TEST(test_failing_write(overflow_test_addr, valid_test_len, FIXED, valid_test_segment_base, valid_test_segment_length, ATOMIC_NONE));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_refuses_burst_for_escaping_write_fixed,mmu_env_t)
    `REPEAT_TEST(test_failing_write(overflow_test_addr, valid_test_len, FIXED, valid_test_segment_base, valid_test_segment_length, ATOMIC_NONE));
  `NORTHCAPE_UVM_TEST_END


  `ifndef NORTHCAPE_MMU_NO_AXI_WRAP
    `NORTHCAPE_UVM_TEST(mmu_refuses_burst_for_undefined_wrap_length_write,mmu_env_t)
    for(axi_len_t invalid_length = 0; invalid_length < 15 && invalid_length != 1 && invalid_length != 3 && invalid_length != 7; invalid_length = invalid_length + 1)
    begin
      `uvm_info(COMPONENT_NAME,$sformatf("Testing invalid wrap for burst length %u!",invalid_length),UVM_DEBUG);
      `REPEAT_TEST(test_failing_write(valid_test_addr, invalid_length, WRAP, valid_test_segment_base, valid_test_segment_length, ATOMIC_NONE));
    end
  `NORTHCAPE_UVM_TEST_END
  `endif



  `NORTHCAPE_UVM_TEST(mmu_can_do_simple_atomic_write,mmu_env_t)
    initialize_test_strobes(valid_test_strobes, valid_test_len);
    `REPEAT_TEST(test_valid_write(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_strobes, ATOMIC_LOAD, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len]));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_correctly_atomically_writes_segments_which_end_mid_word,mmu_env_t)
    for(int i=1; i < 8; i = i + 1)
    begin
      logic [63:0] last_word_read;
      initialize_test_strobes(valid_test_strobes, valid_test_len);
      valid_test_strobes[valid_test_len] = (1<<(8-i))-1;
      last_word_read = valid_test_data[valid_test_len] & (1<<((8-i)*8))-1;
      `uvm_info(COMPONENT_NAME,$sformatf("%d Bytes with expected last strobe %x last word %x",i,valid_test_strobes[valid_test_len], last_word_read),UVM_DEBUG);
      `REPEAT_TEST(test_valid_write(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length-i, valid_test_data, valid_test_strobes, ATOMIC_LOAD, valid_test_data, valid_test_data, valid_test_data[0], last_word_read));
    end
  `NORTHCAPE_UVM_TEST_END


  `NORTHCAPE_UVM_TEST(mmu_refuses_burst_for_out_of_bounds_write_atomic,mmu_env_t)
    `REPEAT_TEST(test_failing_write(overflow_test_addr, valid_test_len, INCR, valid_test_segment_base, valid_test_segment_length, ATOMIC_SWAP_OR_COMPARE));
    `REPEAT_TEST(test_failing_write(overflow_test_addr, valid_test_len, FIXED, valid_test_segment_base, valid_test_segment_length, ATOMIC_SWAP_OR_COMPARE));
  `NORTHCAPE_UVM_TEST_END

  function void do_write_then_read_test();
    test_valid_write(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_strobes, ATOMIC_STORE, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len]);
    // read channel could be stuck waiting for data for atomic store now - test with a simple read
    test_valid_read(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len]);
  endfunction

  `NORTHCAPE_UVM_TEST(mmu_can_do_simple_atomic_store,mmu_env_t)
    initialize_test_strobes(valid_test_strobes, valid_test_len);
    do_write_then_read_test();
  `NORTHCAPE_UVM_TEST_END


  // regression tests from breaks in hardware
  `NORTHCAPE_UVM_TEST(mmu_can_handle_two_word_bursts,mmu_env_t)
    `REPEAT_TEST(test_valid_read(valid_test_addr, 1, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[1]));
    
  `NORTHCAPE_UVM_TEST_END


  `NORTHCAPE_UVM_TEST(mmu_can_do_read_after_atomic,mmu_env_t)
    initialize_test_strobes(valid_test_strobes, valid_test_len);
    // regression: read channel gets stuck when ready before valid on W channel
    test_valid_write(valid_test_addr, 0, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_strobes, ATOMIC_LOAD, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[0], .regression_ready_before_valid(1), .input_strobes('1));
    test_valid_read(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len]);
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_does_not_keep_ready_high,mmu_env_t)
    // regression: read channel gets stuck when ready before valid on W channel
    initialize_test_strobes(valid_test_strobes, valid_test_len);

    test_valid_read(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len], .regression_keep_valid_high(1));
    test_valid_write(valid_test_addr, 0, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_strobes, ATOMIC_LOAD, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[0], .regression_keep_valid_high(1), .input_strobes('1));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_refuses_write_for_cmt,mmu_env_t)
    initialize_test_strobes(valid_test_strobes, valid_test_len);
    `REPEAT_TEST(test_failing_write(valid_test_addr, valid_test_len, INCR, valid_test_segment_base, valid_test_segment_length, ATOMIC_NONE, .cmt_base(valid_test_segment_base), .cmt_size_clog2(4)));
    `REPEAT_TEST(test_failing_write(valid_test_addr, valid_test_len, FIXED, valid_test_segment_base, 8, ATOMIC_NONE, .cmt_base(valid_test_segment_base), .cmt_size_clog2(4)));
`ifndef NORTHCAPE_MMU_NO_AXI_WRAP
    `REPEAT_TEST(test_failing_write(valid_test_addr, 15, WRAP, valid_test_segment_base, 128, ATOMIC_NONE, .cmt_base(valid_test_segment_base), .cmt_size_clog2(4)));
`endif
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_can_handle_narrow_bursts_read_1,mmu_env_t)
    `REPEAT_TEST(test_valid_read(aligned_valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data_narrow_zero_byte_offset_4_bytes, valid_test_data_narrow_zero_byte_offset_4_bytes, valid_test_data_narrow_zero_byte_offset_4_bytes[0], valid_test_data_narrow_zero_byte_offset_4_bytes[valid_test_len], .size($clog2(4))));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_can_handle_narrow_bursts_read_2,mmu_env_t)  
    `REPEAT_TEST(test_valid_read(aligned_valid_test_addr+4, 0, valid_test_burst, valid_test_segment_base+4, valid_test_segment_length, valid_test_data, '0, valid_test_data_narrow_four_byte_offset_4_bytes_shift_left_4, valid_test_data_narrow_four_byte_offset_4_bytes_shift_left_4, .size($clog2(4)), .extra_offset(4)));
    // only 1-beat transfers are supported here
    `REPEAT_TEST(test_failing_read(aligned_valid_test_addr+4, 1, valid_test_burst, valid_test_segment_base+4, valid_test_segment_length, .size($clog2(4))));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_can_handle_narrow_bursts_read_3,mmu_env_t)  
    // expect data to be four-byte shifted, based on my address
    // the same is not true for the segment base, though - need to shift left
    `REPEAT_TEST(test_valid_read(aligned_valid_test_addr+4, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_data_narrow_four_byte_offset_4_bytes, valid_test_data_narrow_four_byte_offset_4_bytes[0], valid_test_data_narrow_four_byte_offset_4_bytes[valid_test_len], .size($clog2(4)), .extra_offset(4)));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_can_handle_narrow_bursts_read_4,mmu_env_t)
    // expect data to be zero-byte shifted, based on my address
    `REPEAT_TEST(test_valid_read(aligned_valid_test_addr, 0, valid_test_burst, valid_test_segment_base+4, valid_test_segment_length, valid_test_data, valid_test_data, valid_test_data[0]>>32, valid_test_data[0]>>32, .size($clog2(4))));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_can_handle_narrow_bursts_write_1,mmu_env_t)
    initialize_test_strobes(valid_test_strobes, valid_test_len);
    `REPEAT_TEST(test_valid_write(aligned_valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0, .size($clog2(4)), .input_strobes('1)));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_can_handle_narrow_bursts_write_2,mmu_env_t)
    initialize_test_strobes(valid_test_strobes, valid_test_len);
    `REPEAT_TEST(test_valid_write(aligned_valid_test_addr+4, 0, valid_test_burst, valid_test_segment_base+4, valid_test_segment_length, valid_test_data, valid_test_strobes, ATOMIC_NONE, valid_test_data, '0, '0, '0, .size($clog2(4)), .extra_offset(4), .input_strobes('1), .expected_write_data(valid_test_data_narrow_four_byte_offset_4_bytes_shift_left_4)));
    `REPEAT_TEST(test_failing_write(aligned_valid_test_addr+4, 1, valid_test_burst, valid_test_segment_base+4, valid_test_segment_length, ATOMIC_NONE, .size($clog2(4))));
  `NORTHCAPE_UVM_TEST_END
  
  `NORTHCAPE_UVM_TEST(mmu_can_handle_narrow_bursts_write_3,mmu_env_t)
    // need to shift left
    initialize_test_strobes(valid_test_strobes, valid_test_len);
    `REPEAT_TEST(test_valid_write(aligned_valid_test_addr+4, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0, .size($clog2(4)), .extra_offset(4), .input_strobes('1)));
  `NORTHCAPE_UVM_TEST_END
    
  `NORTHCAPE_UVM_TEST(mmu_can_handle_narrow_bursts_write_4,mmu_env_t)
    // need to shift left
    `REPEAT_TEST(test_valid_write(aligned_valid_test_addr, 0, valid_test_burst, valid_test_segment_base+4, valid_test_segment_length, valid_test_data, 8'hf0, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0, .size($clog2(4)),.expected_write_data(valid_test_data_narrow_four_byte_offset_4_bytes_shift_left_4), .input_strobes('1)));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_can_forward_device_specific_bits_in_user,mmu_env_t)
  begin
    northcape_restriction_body_t restr_body;
    restr_body.device_interpreted_bits = 64'hfeedbeefdeadbeef;

    `REPEAT_TEST(test_valid_read(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len], .restr_type(NORTHCAPE_RESTRICTIONS_DEVICE_INTERPRETED), .restr_body(restr_body)));
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_requests_execute_on_instruction_fetch,mmu_env_t)
    `REPEAT_TEST(test_valid_read(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len], .is_instruction_fetch(1'b1)));
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_understands_task_id_set_restriction,mmu_env_t)
  begin
    for(int i = 0; i < TEST_REPETITIONS; i++)
    begin
      northcape_restriction_body_t restr_body;
      restr_body.task_restriction.task_id = 32'hdead + i;
      restr_body.task_restriction.device_id = READ_CHAN_DEVICE_ID>>1;
      // the scoreboard will check whether the reported task ID is correct
      test_valid_read(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len], .is_instruction_fetch(1'b1), .restr_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .restr_body(restr_body));
    end
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_ignores_offset_in_first_but_not_second_set_task_id_calls,mmu_env_t)
  begin
    northcape_restriction_body_t restr_body;
    restr_body.task_restriction.task_id = 32'hdead;
    restr_body.task_restriction.device_id = READ_CHAN_DEVICE_ID>>1;
    
    for(int i = 0; i < TEST_REPETITIONS; i++)
    begin
      if(i == 0)
      begin
        // with offset --> refuse
        test_failing_read(64'd1000, valid_test_len, valid_test_burst, valid_test_segment_base, 2000, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len], .is_instruction_fetch(1'b1), .restr_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .restr_body(restr_body));
        // no offset --> accept
        test_valid_read('0, valid_test_len, valid_test_burst, valid_test_segment_base, 2000, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len], .is_instruction_fetch(1'b1), .restr_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .restr_body(restr_body), .extra_offset('0));
      end
      else
      begin
        test_valid_read(64'd1000 + (i*(AXI_ADDR_WIDTH/8)), valid_test_len, valid_test_burst, valid_test_segment_base, 2000, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len], .is_instruction_fetch(1'b1), .restr_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .restr_body(restr_body), .extra_offset((32'd1000 + (i*(AXI_ADDR_WIDTH/8)))));
      end
    end
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_understands_task_id_set_restriction_for_write,mmu_env_t)
  begin
    for(int i = 0; i < TEST_REPETITIONS; i++)
    begin
      northcape_restriction_body_t restr_body;
      restr_body.task_restriction.task_id = 32'hdead + i;
      restr_body.task_restriction.device_id = READ_CHAN_DEVICE_ID>>1;
      // the scoreboard will check whether the reported task ID is correct
      if(i%2 == 0)
      begin
        test_valid_read(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len], .is_instruction_fetch(1'b1), .restr_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .restr_body(restr_body));
      end
      else
      begin
        initialize_test_strobes(valid_test_strobes, valid_test_len);
        test_valid_write(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0, .restr_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .restr_body(restr_body), .is_irq(1'b1), .input_strobes('1));
      end
    end
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_understands_set_task_id_with_interrupt,mmu_env_t)
  begin
    for(int i = 0; i < TEST_REPETITIONS; i++)
    begin
      northcape_restriction_body_t restr_body;

      // set task ID to a normal task via subsystem call
      restr_body.task_restriction.task_id = 32'hdead + i;
      restr_body.task_restriction.device_id = READ_CHAN_DEVICE_ID>>1;
      test_valid_read(0, 0, valid_test_burst, valid_test_segment_base, TEST_REPETITIONS * AXI_DATA_WIDTH/8, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[0], .is_instruction_fetch(1'b1), .restr_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .restr_body(restr_body));

      restr_body.task_restriction.task_id = 32'hbeef + i;
      restr_body.task_restriction.device_id = READ_CHAN_DEVICE_ID>>1;

      for(int j = 0; j < TEST_REPETITIONS; j++)
      begin
        // IRQ handler
        test_valid_read(j*AXI_DATA_WIDTH/8, 0, valid_test_burst, 32'hca11ab00, TEST_REPETITIONS * AXI_DATA_WIDTH/8, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[0], .is_instruction_fetch(1'b1), .is_irq(1), .restr_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .restr_body(restr_body), .extra_offset(j*AXI_DATA_WIDTH/8));
        initialize_test_strobes(valid_test_strobes, 0);
        test_valid_write(j*AXI_DATA_WIDTH/8, 0, valid_test_burst, 32'hca11ab00, TEST_REPETITIONS * AXI_DATA_WIDTH/8, valid_test_data, valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0, .restr_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND), .restr_body(restr_body), .extra_offset(j*AXI_DATA_WIDTH/8), .is_irq(1'b1), .input_strobes('1));
      end

      restr_body.task_restriction.task_id = 32'hdead + i;
      restr_body.task_restriction.device_id = READ_CHAN_DEVICE_ID>>1;

      for(int j = 1; j < TEST_REPETITIONS-1; j++)
      begin
      // continue task after iret
      test_valid_read(j*AXI_DATA_WIDTH/8, 0, valid_test_burst, valid_test_segment_base, TEST_REPETITIONS * AXI_DATA_WIDTH/8, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[0], .is_instruction_fetch(1'b1), .restr_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND), .restr_body(restr_body), .extra_offset(j*AXI_DATA_WIDTH/8));
      test_valid_write(j*AXI_DATA_WIDTH/8, 0, valid_test_burst, valid_test_segment_base, TEST_REPETITIONS * AXI_DATA_WIDTH/8, valid_test_data, valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0, .restr_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND), .restr_body(restr_body), .extra_offset(j*AXI_DATA_WIDTH/8), .input_strobes('1));
      end

    end
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_understands_request_with_irq_when_not_in_irq_mode,mmu_env_t)
  begin
    northcape_restriction_body_t restr_body;

    restr_body.task_restriction.task_id = 32'hdead;
    restr_body.task_restriction.device_id = READ_CHAN_DEVICE_ID>>1;

    // IRQ handler sets IRQ task ID
    test_valid_read(64'd0, valid_test_len, valid_test_burst, valid_test_segment_base, 2000, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len], .is_instruction_fetch(1'b1), .is_irq(1'b1), .restr_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .restr_body(restr_body));

    for(int i = 0; i < TEST_REPETITIONS; i++)
    begin

      restr_body.task_restriction.task_id = i;

      // subsystem call in non-IRQ mode sets non-IRQ task ID
      test_valid_read(0, 0, valid_test_burst, 32'hca11ab00, AXI_DATA_WIDTH/8, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[0], .is_instruction_fetch(1'b1), .is_irq(1'b0), .restr_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .restr_body(restr_body));

      restr_body.task_restriction.task_id = 32'hdead;

      // read transaction with IRQ=1, but no EXECUTE with IRQ=1 precedes
      // this can happen when ISR is executed from cache
      // MMU needs to apply the IRQ task ID here
      test_valid_read(i*AXI_DATA_WIDTH/8, valid_test_len, valid_test_burst, valid_test_segment_base, 2000, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len], .is_instruction_fetch(1'b0), .is_irq(1'b1), .restr_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND), .restr_body(restr_body), .extra_offset(i*AXI_DATA_WIDTH/8));

    end
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_understands_request_without_irq_when_in_irq_mode,mmu_env_t)
    for(int i = 0; i < TEST_REPETITIONS; i++)
    begin
      northcape_restriction_body_t restr_body;

      // set task ID to a normal task via subsystem call
      restr_body.task_restriction.task_id = 32'hdead + i;
      restr_body.task_restriction.device_id = READ_CHAN_DEVICE_ID>>1;

      // IRQ handler
      test_valid_read(0, 0, valid_test_burst, 32'hca11ab00, AXI_DATA_WIDTH/8, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[0], .is_instruction_fetch(1'b1), .is_irq(1), .restr_type(NORTHCAPE_RESTRICTIONS_SET_TASK_ID), .restr_body(restr_body));

      // read transaction with IRQ=0, but no EXECUTE with IRQ=0 precedes
      // the CPU should never generate this
      // if it did, an adversary could try to circumvent task id restriction and steal data from last IRQ handler
      // hence, the MMU needs to refuse this
      test_valid_read(64'd0, valid_test_len, valid_test_burst, valid_test_segment_base, 2000, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len], .is_instruction_fetch(1'b0), .is_irq(1'b0), .restr_type(NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND), .restr_body(restr_body));

    end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_indicates_irq_flag_when_in_irq_mode,mmu_env_t)
    for(int i = 0; i < TEST_REPETITIONS; i++)
    begin
      // EXECUTE_IRQ requested
      test_valid_read(0, 0, valid_test_burst, 32'hca11ab00, AXI_DATA_WIDTH/8, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[0], .is_instruction_fetch(1'b1), .is_irq(1));
      // READ_IRQ requested
      test_valid_read(64'd0, valid_test_len, valid_test_burst, valid_test_segment_base, 2000, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len], .is_instruction_fetch(1'b0), .is_irq(1'b1));
      // WRITE_IRQ requested
      initialize_test_strobes(valid_test_strobes, valid_test_len);
      test_valid_write(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_strobes, ATOMIC_NONE, valid_test_data, valid_test_data, '0, '0, .is_irq(1'b1));
      // READ_WRITE_IRQ requested
      initialize_test_strobes(valid_test_strobes, valid_test_len);
      test_valid_write(valid_test_addr, valid_test_len, valid_test_burst, valid_test_segment_base, valid_test_segment_length, valid_test_data, valid_test_strobes, ATOMIC_LOAD, valid_test_data, valid_test_data, valid_test_data[0], valid_test_data[valid_test_len], .is_irq(1'b1));
    end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_returns_ebreak_instructions_on_error_in_instr_fetch, mmu_env_t)
    `REPEAT_TEST(test_failing_read(valid_test_addr, valid_test_len, INCR, valid_test_segment_base, '0, .is_instruction_fetch(1'b1)));
  `NORTHCAPE_UVM_TEST_END

  // this is a regression test, based on a real failure in hardware
  `NORTHCAPE_UVM_TEST(regression_mmu_can_do_one_byte_writes,mmu_env_t)
  begin
    // same data, but barrel-shifted (see next test)
    const bit[63:0] test_data_in = 64'h4747474747474747, test_data_out = test_data_in;
    // as the segment base has an offset of f, while the capabability token has offset of 0, I have to shift the byte all the way to the left
    const bit [7:0] valid_test_strobes_in = 8'b00000001, valid_test_strobes_out = 8'b10000000;
    // additional scenario with all-ones strobe to catch "fix" of just passing strobes through
    `REPEAT_TEST(test_valid_write(64'hbadec0401cf90000, 0, INCR, 32'h90a64c9f, 1, test_data_in, valid_test_strobes_out, ATOMIC_NONE, test_data_out, test_data_out, test_data_out, '0, .expected_write_data(test_data_out), .input_strobes('1), .size(0)));
    // the exact scenario that failed
    `REPEAT_TEST(test_valid_write(64'hbadec0401cf90000, 0, INCR, 32'h90a64c9f, 1, test_data_in, valid_test_strobes_out, ATOMIC_NONE, test_data_out, test_data_out, test_data_out, '0, .expected_write_data(test_data_out), .input_strobes(valid_test_strobes_in), .size(0)));
  end
  `NORTHCAPE_UVM_TEST_END

  // read version of the regression test
  `NORTHCAPE_UVM_TEST(regression_mmu_can_do_one_byte_reads,mmu_env_t)
  begin
    // as the segment base has an offset of f, while the capabability token has offset of 0, I have to shift the byte all the way to the RIGHT
    // also, only one byte is covered by the capability
    const bit[63:0] test_data_in = 64'h0706050403020100, test_data_out = 64'h0000000000000007;
    // additional scenario with all-ones strobe to catch "fix" of just passing strobes through
    `REPEAT_TEST(test_valid_read(64'hbadec0401cf90000, 0, INCR, 32'h90a64c9f, 1, test_data_in, test_data_out, test_data_out, test_data_out, .size(0)));
    
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_can_do_one_byte_writes_with_1_byte_capabilities,mmu_env_t)
  begin
    for(int i = 0; i < 8; i++)
    begin
      const bit[63:0] test_data_in = 64'h0001020304050607, test_data_out = test_data_in << 8*i | (test_data_in >> 64 - 8 * i);
      // input offset must be 0, as we have a one-byte capability
      // output offset must equal the base
      const bit [7:0] valid_test_strobes_in = 8'b00000001, valid_test_strobes_out = 8'b1 << i;
      `REPEAT_TEST(test_valid_write(64'hbadec0401cf90000, 0, INCR, 32'h90a64c90 + i, 1, test_data_in, valid_test_strobes_out, ATOMIC_NONE, test_data_out, test_data_out, '0, '0, .expected_write_data(test_data_out), .input_strobes('1), .size(0)));
    end
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_can_do_one_byte_reads_with_1_byte_capabilities,mmu_env_t)
  begin
    for(int i = 0; i < 8; i++)
    begin
      const bit[63:0] test_data_in = 64'h0001020304050607;
      const int shift = i * 8;
      // mask goes on first
      const bit [63:0] test_data_mask = 64'h00000000000000ff << shift;
      // shift the masked data for output to the client
      const bit[63:0] test_data_masked = test_data_in & test_data_mask, test_data_out = test_data_masked >> shift | (test_data_masked << 64 - shift);
      `REPEAT_TEST(test_valid_read(64'hbadec0401cf90000, 0, INCR, 32'h90a64c90 + i, 1, test_data_in, test_data_out, test_data_out, test_data_out, .size(0)));
    end
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_can_do_one_byte_writes_with_8_byte_capabilities,mmu_env_t)
  begin
    for(int offset = 0; offset < 8; offset++)
    begin
      // within the scope of this test, we stay in the first byte lane
      // starting in the second byte lane, we are aligned again - other tests cover this
      for(int base = 0; offset + base < 8; base++)
      begin
        const int shift = base * 8;
        const bit[63:0] test_data_in = 64'h0001020304050607, test_data_out = test_data_in << shift | (test_data_in >> 64 - shift);
        // input offset must be 0, as we have a one-byte capability
        // output offset must equal the base
        const bit [7:0] valid_test_strobes_in = 8'b00000001 << offset, valid_test_strobes_out = valid_test_strobes_in << (shift / 8) | (valid_test_strobes_in >> (8 - shift / 8));
        
        `REPEAT_TEST(test_valid_write(64'hbadec0401cf90000 + offset, 0, INCR, 32'h90a64c90 + base, offset+1, test_data_in, valid_test_strobes_out, ATOMIC_NONE, test_data_out, test_data_out, '0, '0, .expected_write_data(test_data_out), .input_strobes(valid_test_strobes_in), .size(0), .extra_offset(offset)));
      end
    end
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_can_do_one_byte_reads_with_8_byte_capabilities,mmu_env_t)
  begin
    for(int offset = 0; offset < 8; offset++)
    begin
      // within the scope of this test, we stay in the first byte lane
      // starting in the second byte lane, we are aligned again - other tests cover this
      for(int base = 0; offset + base < 8; base++)
      begin
        const int shift = base * 8;
        const bit[63:0] test_data_in = 64'h0001020304050607;
        // mask goes on first
        bit [63:0] test_data_mask = 64'h0000000000000000;
        bit[63:0] test_data_masked, test_data_out;

        for(int i = 0; i < 8; i++)
        begin
          if(i >= base && i <= base + offset)
          begin
            test_data_mask[8*i+:8] = 8'hff;
          end
        end
        // shift the masked data for output to the client
        test_data_masked = test_data_in & test_data_mask;
        test_data_out = test_data_masked >> shift | (test_data_masked << 64 - shift);
        `uvm_info(COMPONENT_NAME, $sformatf("For base %d offset %d computed mask %x test data %x", base, offset, test_data_mask, test_data_out), UVM_HIGH);
        `REPEAT_TEST(test_valid_read(64'hbadec0401cf90000 + offset, 0, INCR, 32'h90a64c90 + base, offset+1, test_data_in, test_data_out, test_data_out, test_data_out, .size(0), .extra_offset(offset)));  
      end
    end
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_can_do_two_byte_writes_with_8_byte_capabilities,mmu_env_t)
  begin
    for(int offset = 0; offset < 8; offset++)
    begin
      // within the scope of this test, we stay in the first byte lane
      // starting in the second byte lane, we are aligned again - other tests cover this
      for(int base = 0; offset + base + 2 < 8; base++)
      begin
        const int shift = base * 8;
        const bit[63:0] test_data_in = 64'h0001020304050607, test_data_out = test_data_in << shift | (test_data_in >> 64 - shift);
        // input offset must be 0, as we have a one-byte capability
        // output offset must equal the base
        const bit [7:0] valid_test_strobes_in = 8'b00000011 << offset, valid_test_strobes_out = valid_test_strobes_in << (shift / 8) | (valid_test_strobes_in >> (8 - shift / 8));
        
        `REPEAT_TEST(test_valid_write(64'hbadec0401cf90000 + offset, 0, INCR, 32'h90a64c90 + base, offset+2, test_data_in, valid_test_strobes_out, ATOMIC_NONE, test_data_out, test_data_out, '0, '0, .expected_write_data(test_data_out), .input_strobes(valid_test_strobes_in), .size(1), .extra_offset(offset)));
      end
    end
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_can_do_two_byte_reads_with_8_byte_capabilities,mmu_env_t)
  begin
    for(int offset = 0; offset < 8; offset++)
    begin
      // within the scope of this test, we stay in the first byte lane
      // starting in the second byte lane, we are aligned again - other tests cover this
      for(int base = 0; offset + base + 2 < 8; base++)
      begin
        const int shift = base * 8;
        const bit[63:0] test_data_in = 64'h0001020304050607;
        // mask goes on first
        bit [63:0] test_data_mask = 64'h0000000000000000;
        bit[63:0] test_data_masked, test_data_out;

        for(int i = 0; i < 8; i++)
        begin
          if(i >= base && i < base + offset + 2)
          begin
            test_data_mask[8*i+:8] = 8'hff;
          end
        end
        // shift the masked data for output to the client
        test_data_masked = test_data_in & test_data_mask;
        test_data_out = test_data_masked >> shift | (test_data_masked << 64 - shift);
        `uvm_info(COMPONENT_NAME, $sformatf("For base %d offset %d computed mask %x test data %x", base, offset, test_data_mask, test_data_out), UVM_HIGH);
        `REPEAT_TEST(test_valid_read(64'hbadec0401cf90000 + offset, 0, INCR, 32'h90a64c90 + base, offset+2, test_data_in, test_data_out, test_data_out, test_data_out, .size(1), .extra_offset(offset)));  
      end
    end
  end
  `NORTHCAPE_UVM_TEST_END


  `NORTHCAPE_UVM_TEST(mmu_can_do_four_byte_writes_with_8_byte_capabilities,mmu_env_t)
  begin
    for(int offset = 0; offset < 8; offset++)
    begin
      // within the scope of this test, we stay in the first byte lane
      // starting in the second byte lane, we are aligned again - other tests cover this
      for(int base = 0; offset + base + 4 < 8; base++)
      begin
        const int shift = base * 8;
        const bit[63:0] test_data_in = 64'h0001020304050607,test_data_out = test_data_in << shift | (test_data_in >> 64 - shift);
        // input offset must be 0, as we have a one-byte capability
        // output offset must equal the base
        const bit [7:0] valid_test_strobes_in = 8'b00001111 << offset, valid_test_strobes_out = valid_test_strobes_in << (shift / 8) | (valid_test_strobes_in >> (8 - shift / 8));
        
        `REPEAT_TEST(test_valid_write(64'hbadec0401cf90000 + offset, 0, INCR, 32'h90a64c90 + base, offset+4, test_data_in, valid_test_strobes_out, ATOMIC_NONE, test_data_out, test_data_out, '0, '0, .expected_write_data(test_data_out), .input_strobes(valid_test_strobes_in), .size(2), .extra_offset(offset)));
      end
    end
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_can_do_four_byte_reads_with_8_byte_capabilities,mmu_env_t)
  begin
    for(int offset = 0; offset < 8; offset++)
    begin
      // within the scope of this test, we stay in the first byte lane
      // starting in the second byte lane, we are aligned again - other tests cover this
      for(int base = 0; offset + base + 4 < 8; base++)
      begin
        const int shift = base * 8;
        const bit[63:0] test_data_in = 64'h0001020304050607;
        // mask goes on first
        bit [63:0] test_data_mask = 64'h0000000000000000;
        bit[63:0] test_data_masked, test_data_out;

        for(int i = 0; i < 8; i++)
        begin
          if(i >= base && i < base + offset + 4)
          begin
            test_data_mask[8*i+:8] = 8'hff;
          end
        end
        // shift the masked data for output to the client
        test_data_masked = test_data_in & test_data_mask;
        test_data_out = test_data_masked >> shift | (test_data_masked << 64 - shift);
        `uvm_info(COMPONENT_NAME, $sformatf("For base %d offset %d computed mask %x test data %x", base, offset, test_data_mask, test_data_out), UVM_HIGH);
        `REPEAT_TEST(test_valid_read(64'hbadec0401cf90000 + offset, 0, INCR, 32'h90a64c90 + base, offset+4, test_data_in, test_data_out, test_data_out, test_data_out, .size(2), .extra_offset(offset)));  
      end
    end
  end
  `NORTHCAPE_UVM_TEST_END

  `NORTHCAPE_UVM_TEST(mmu_refuses_requests_that_require_shift_across_byte_lanes,mmu_env_t)
  begin
    // impossible with 1 byte

    // two-byte edge cases
    `REPEAT_TEST(test_failing_write(64'hbadec0401cf90000, 0, INCR, 32'h90a64c90 + 32'h7, 16, ATOMIC_NONE, .size(1)));
    `REPEAT_TEST(test_failing_read(64'hbadec0401cf90000, 0, INCR, 32'h90a64c90 + 32'h7, 16, .size(1)));

    // four-byte edge cases
    `REPEAT_TEST(test_failing_write(64'hbadec0401cf90000, 0, INCR, 32'h90a64c90 + 32'h5, 16, ATOMIC_NONE, .size(2)));
    `REPEAT_TEST(test_failing_write(64'hbadec0401cf90000, 0, INCR, 32'h90a64c90 + 32'h6, 16, ATOMIC_NONE, .size(2)));
    `REPEAT_TEST(test_failing_write(64'hbadec0401cf90000, 0, INCR, 32'h90a64c90 + 32'h7, 16, ATOMIC_NONE, .size(2)));
    `REPEAT_TEST(test_failing_read(64'hbadec0401cf90000, 0, INCR, 32'h90a64c90 + 32'h5, 16, .size(2)));
    `REPEAT_TEST(test_failing_read(64'hbadec0401cf90000, 0, INCR, 32'h90a64c90 + 32'h6, 16, .size(2)));
    `REPEAT_TEST(test_failing_read(64'hbadec0401cf90000, 0, INCR, 32'h90a64c90 + 32'h7, 16, .size(2)));

    // 8-byte edge cases
    for(int i = 1; i < 8; i++)
    begin
      `REPEAT_TEST(test_failing_write(64'hbadec0401cf90000, 0, INCR, 32'h90a64c90 + i, 16, ATOMIC_NONE, .size(3)));
      `REPEAT_TEST(test_failing_read(64'hbadec0401cf90000, 0, INCR, 32'h90a64c90 + i, 16, .size(3)));
    end

  end
  `NORTHCAPE_UVM_TEST_END

endpackage
