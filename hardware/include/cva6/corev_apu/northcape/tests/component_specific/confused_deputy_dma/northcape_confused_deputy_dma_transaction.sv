/**
 * Data structures for generating and checking Northcape DMA transactions.
 */

package northcape_confused_deputy_dma_transaction;
  import northcape_types::*;
  import northcape_test::*;
  import axi5::*;
  import uvm_pkg::*;
  `include "uvm_macros.svh"



  /**
 * Holds all provided and expected data for a DMA transaction.
 */
  class automatic NorthcapeDMATransaction #(
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1
  ) extends uvm_sequence_item;
    `uvm_object_param_utils(
        NorthcapeDMATransaction#(AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_ID_WIDTH, AXI_USER_WIDTH));


    localparam COMPONENT_NAME = "Northcape DMA Transaction";

    typedef NorthcapeDMATransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) my_type_t;

    rand bit [AXI_ADDR_WIDTH-1:0] source_addr;
    rand bit [AXI_ADDR_WIDTH-1:0] dst_addr;
    rand int unsigned axi_transfer_len;

    constraint axi_transfer_len_possible {axi_transfer_len / 8 <= AXI5_MAX_BURST_LEN;}

    bit [AXI_ID_WIDTH-1:0] test_id;

    rand bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] data;

    rand axi_resp_t read_response, write_response;

    Axi5DelayGenerator delay_gen;

`ifdef NORTHCAPE_TEST_COVERAGE
    covergroup cover_group;
      cov_dst_addr: coverpoint dst_addr[2:0] {
        bins offset_zero = {3'h0};
        bins offset_one = {3'h1};
        bins offset_two = {3'h2};
        bins offset_three = {3'h3};
        bins offset_four = {3'h4};
        bins offset_five = {3'h5};
        bins offset_six = {3'h6};
        bins offset_seven = {3'h7};
      }
      cov_transf_len: coverpoint axi_transfer_len;
      cov_resp_read: coverpoint read_response;
      cov_resp_write: coverpoint write_response;
      cross cov_dst_addr, cov_transf_len, cov_resp_read, cov_resp_write;
    endgroup

    function new(string name = "");
      super.new(name);

      cover_group = new;
      delay_gen   = new;
    endfunction

    function void sample_coverage();
      cover_group.sample();
    endfunction
`else
    function new(string name = "");
      super.new(name);
    endfunction

    function void sample_coverage();

    endfunction
`endif

    function automatic void post_randomize();
      bit [AXI_ADDR_WIDTH-1:0] source_addr_mask;
      source_addr_mask = (1 << $clog2(AXI_ADDR_WIDTH / 8)) - 1;

      source_addr = source_addr & ~source_addr_mask;
      `uvm_info(COMPONENT_NAME, $sformatf("Aligned source addr %x", source_addr), UVM_DEBUG);

    endfunction

    function void do_copy(uvm_object rhs);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "Copy RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      source_addr = other_transaction.source_addr;
      dst_addr = other_transaction.dst_addr;
      axi_transfer_len = other_transaction.axi_transfer_len;

      test_id = other_transaction.test_id;
      data = other_transaction.data;
      read_response = other_transaction.read_response;
      write_response = other_transaction.write_response;
      delay_gen = other_transaction.delay_gen;

    endfunction

    function string convert2string();

      return $sformatf(
          "Source %x dest %x len %d ID %x user %x data %x read_response %s write_response %s",
          source_addr,
          dst_addr,
          axi_transfer_len,
          test_id,
          0,
          data,
          read_response.name(),
          write_response.name()
      );
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "Compare RHS is null!");
      end

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end
      return source_addr == other_transaction.source_addr &&
            dst_addr == other_transaction.dst_addr &&
            axi_transfer_len == other_transaction.axi_transfer_len &&
            test_id == other_transaction.test_id &&
            data == other_transaction.data &&
            read_response == other_transaction.read_response &&
            write_response == other_transaction.write_response;

    endfunction

    function axi_len_t convert_to_axi_len();
      axi_len_t ret;

      ret = axi_transfer_len / (AXI_DATA_WIDTH / 8);

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Have computed initial ret %d (starting with 0) from transfer len %d",
                ret,
                axi_transfer_len
                ), UVM_DEBUG);

      if (axi_transfer_len != 0) begin
        if ((axi_transfer_len % (AXI_DATA_WIDTH / 8)) == 0) begin
          ret = ret - 1;
        end
      end else begin
        ret = 0;
      end

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Have computed ret %d (starting with 0) from transfer len %d", ret, axi_transfer_len
                ), UVM_DEBUG);

      return ret;
    endfunction
  endclass

  class automatic NorthcapeDMATransactionMasterSideRead #(
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1
  ) extends NorthcapeDMATransaction #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) implements INorthcapeAXITransactionMasterSide#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  );
    localparam string COMPONENT_NAME = "Northcape DMA Transaction Master Read";

    virtual function axi_test_request_type_t get_axi_request_type();
      return AXI_TEST_READ;
    endfunction

    virtual function axi_len_t get_test_len();
      return super.convert_to_axi_len();
    endfunction

    virtual function bit [AXI_ID_WIDTH-1:0] get_test_id();
      return test_id;
    endfunction

    virtual function bit [AXI_USER_WIDTH-1:0] get_test_user();
      return '0;
    endfunction

    virtual function bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] get_response_data();
      return data;
    endfunction

    // (read only) response
    virtual function axi_resp_t get_given_response();
      return read_response;
    endfunction

    // regressions: specific scenarios that failed in hardware and are unlikely to appear in random testing
    // force ready high before valid
    virtual function bit get_regression_ready_before_valid();
      return 1;
    endfunction
    // keep arvalid/awvalid after a ready, accepting a second transaction
    virtual function bit get_regression_keep_valid_high();
      return 1;
    endfunction

    virtual function bit generate_random_delay(axi_test_delay_type delay_type);
      return delay_gen.generate_random_delay(delay_type);
    endfunction

    virtual function axi_atop_t get_atomic_type();
      return ATOMIC_NONE;
    endfunction

    function new(string name = "");
      super.new(name);
    endfunction

    virtual function string to_string();
      return convert2string();
    endfunction
  endclass

  class automatic NorthcapeDMATransactionMasterSideWrite #(
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1
  ) extends NorthcapeDMATransaction #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) implements INorthcapeAXITransactionMasterSide#(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  );

    localparam string COMPONENT_NAME = "Northcape DMA Transaction Master Write";

    virtual function axi_test_request_type_t get_axi_request_type();
      return AXI_TEST_WRITE;
    endfunction

    virtual function axi_len_t get_test_len();
      return super.convert_to_axi_len();
    endfunction

    virtual function bit [AXI_ID_WIDTH-1:0] get_test_id();
      return test_id;
    endfunction

    virtual function bit [AXI_USER_WIDTH-1:0] get_test_user();
      return '0;
    endfunction

    virtual function bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] get_response_data();
      `uvm_error(COMPONENT_NAME, "Should not ask a write transaction for response data!");
      return '0;
    endfunction

    // (read only) response
    virtual function axi_resp_t get_given_response();
      return write_response;
    endfunction

    // regressions: specific scenarios that failed in hardware and are unlikely to appear in random testing
    // force ready high before valid
    virtual function bit get_regression_ready_before_valid();
      return 1;
    endfunction
    // keep arvalid/awvalid after a ready, accepting a second transaction
    virtual function bit get_regression_keep_valid_high();
      return 1;
    endfunction

    virtual function bit generate_random_delay(axi_test_delay_type delay_type);
      return delay_gen.generate_random_delay(delay_type);
    endfunction

    virtual function axi_atop_t get_atomic_type();
      return ATOMIC_NONE;
    endfunction

    function new(string name = "");
      super.new(name);
    endfunction

    virtual function string to_string();
      return convert2string();
    endfunction
  endclass

endpackage : northcape_confused_deputy_dma_transaction
