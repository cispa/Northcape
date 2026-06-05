/**
 * Transaction for the Northcape Register Interface.
 */
package northcape_reg_interface_transaction;

  import northcape_types::*;
  import northcape_test::*;
  import axi5::*;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class automatic NorthcapeRegInterfaceAxiLiteTransaction #(
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_DATA_WIDTH = -1
  ) extends uvm_sequence_item;
    typedef NorthcapeRegInterfaceAxiLiteTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) my_type_t;

    localparam COMPONENT_NAME = "Northcape Reg Interface AXI Lite Transaction";

    axi_test_request_type_t transaction_type;
    // provided write data or 0 on read
    rand bit [AXI_DATA_WIDTH-1:0] transaction_data;
    rand bit [AXI_ADDR_WIDTH-1:0] transaction_addr;

    rand bit [AXI_DATA_WIDTH/8-1:0] transaction_write_strobe;

    rand bit [2:0] transaction_prot;

    rand axi_resp_t transaction_response;

    rand bit aw_w_at_same_time;

    constraint transaction_response_matches_address {
      /// TODO currently no error conditions - the interconnect needs to ensure the address is correct, and RO registers not supported
      transaction_response == OKAY;
    }

    function new(string name = "");
      super.new(name);
    endfunction

    function void do_copy(uvm_object rhs);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      transaction_type = other_transaction.transaction_type;
      transaction_data = other_transaction.transaction_data;
      transaction_addr = other_transaction.transaction_addr;
      transaction_write_strobe = other_transaction.transaction_write_strobe;
      transaction_prot = other_transaction.transaction_prot;
      transaction_response = other_transaction.transaction_response;
      aw_w_at_same_time = other_transaction.aw_w_at_same_time;

    endfunction

    function string convert2string;
      return $sformatf(
          "Transaction type %s transaction data %x transaction addr %x transaction strobe %x transaction prot %x transaction response %s aw and w channel valid at same time %b",
          transaction_type.name(),
          transaction_data,
          transaction_addr,
          transaction_write_strobe,
          transaction_prot,
          transaction_response.name(),
          aw_w_at_same_time
      );

    endfunction

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

      return transaction_type == other_transaction.transaction_type &&
                transaction_data == other_transaction.transaction_data &&
                transaction_addr == other_transaction.transaction_addr &&
                transaction_write_strobe == other_transaction.transaction_write_strobe &&
                transaction_prot == other_transaction.transaction_prot &&
                transaction_response == other_transaction.transaction_response &&
                aw_w_at_same_time == other_transaction.aw_w_at_same_time;

    endfunction
  endclass

  /**
 * Holds all provided and expected data for an AXI lite transaction.
 */
  class automatic NorthcapeRegInterfaceTransaction #(
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter NUM_REGS = -1
  ) extends uvm_sequence_item;

    typedef NorthcapeRegInterfaceTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .NUM_REGS(NUM_REGS)
    ) my_type_t;

    typedef NorthcapeRegInterfaceAxiLiteTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) axi_lite_transaction_t;

    rand logic [AXI_DATA_WIDTH-1:0] transaction_regs_in [NUM_REGS];
    rand logic [AXI_DATA_WIDTH-1:0] transaction_regs_out[NUM_REGS];

    localparam COMPONENT_NAME = "Northcape Reg Interface Transaction";

    axi_lite_transaction_t axi_lite_transaction;

    function int get_reg_index();
      int unsigned addresses_per_reg, reg_index;

      addresses_per_reg = $clog2(AXI_DATA_WIDTH / 8);
      reg_index = (this.axi_lite_transaction.transaction_addr >> addresses_per_reg) % NUM_REGS;

      return reg_index;
    endfunction

    function void post_randomize();
      int unsigned reg_index;
      logic [AXI_DATA_WIDTH-1:0] stretched_write_mask;
      bit [AXI_DATA_WIDTH/8-1:0] strobe;

      assert (axi_lite_transaction.randomize());

      reg_index = get_reg_index();

      `uvm_info(COMPONENT_NAME, $sformatf(
                "I think the register index is %d for addr %d, though!",
                reg_index,
                axi_lite_transaction.transaction_addr
                ), UVM_DEBUG);

      stretched_write_mask = 0;
      strobe = axi_lite_transaction.transaction_write_strobe;

      for (int i = AXI_DATA_WIDTH / 8 - 1; i > 0; i--) begin
        if (strobe[i]) begin
          stretched_write_mask += 8'hff;
        end else begin
          stretched_write_mask += 8'h0;
        end
        stretched_write_mask = stretched_write_mask << 8;
      end

      if (axi_lite_transaction.transaction_type == AXI_TEST_READ) begin
        axi_lite_transaction.transaction_data = transaction_regs_in[reg_index];
      end else begin
        axi_lite_transaction.transaction_data = (transaction_regs_out[reg_index] & stretched_write_mask) | (transaction_regs_in[reg_index] & ~stretched_write_mask);
      end

    endfunction

    function new(string name = "");
      super.new(name);
      this.axi_lite_transaction = new("axi_lite_transaction");
    endfunction

    function void do_copy(uvm_object rhs);
      my_type_t other_transaction;
      axi_lite_transaction_t axi_lite_transaction_clone;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      if ($cast(axi_lite_transaction, other_transaction.axi_lite_transaction.clone())) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      transaction_regs_in  = other_transaction.transaction_regs_in;
      transaction_regs_out = other_transaction.transaction_regs_out;
    endfunction

    function string convert2string;
      return $sformatf(
          "AXI Lite Transaction %s regs in %x regs out %x",
          axi_lite_transaction.convert2string(),
          transaction_regs_in,
          transaction_regs_out
      );

    endfunction

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

      return axi_lite_transaction.compare(
          other_transaction.axi_lite_transaction
      ) && transaction_regs_in == other_transaction.transaction_regs_in &&
          transaction_regs_out == other_transaction.transaction_regs_out;

    endfunction
  endclass

endpackage : northcape_reg_interface_transaction
