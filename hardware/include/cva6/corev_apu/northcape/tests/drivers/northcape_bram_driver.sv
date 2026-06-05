package automatic northcape_bram_driver;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum logic {
    NORTHCAPE_BRAM_READ,
    NORTHCAPE_BRAM_WRITE
  } northcape_bram_transaction_type_t;

  class NorthcapeBRAMRequest #(
      parameter DATA_WIDTH = -1,
      parameter DATA_DEPTH = -1
  ) extends uvm_sequence_item;

    localparam ADDR_WIDTH = $clog2(DATA_DEPTH);
    logic [DATA_WIDTH - 1 : 0] data;
    logic [ADDR_WIDTH - 1 : 0] addr;
    northcape_bram_transaction_type_t transaction_type;

    function new(string name = "");
      super.new(name);
    endfunction

    localparam string COMPONENT_NAME = "Northcape BRAM Request";

    typedef NorthcapeBRAMRequest#(
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_DEPTH(DATA_DEPTH)
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

      data = other_transaction.data;
      addr = other_transaction.addr;
      transaction_type = other_transaction.transaction_type;
    endfunction

    function string convert2string();
      string s;

      s = $sformatf("Data %x address %x transaction type %s", data, addr, transaction_type.name());
      return s;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Comparing result %s with %s", convert2string(), rhs.convert2string()), UVM_HIGH);

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      if (data !== other_transaction.data) begin
        `uvm_error(COMPONENT_NAME, "Data does not match!");
        return 1'b0;
      end

      if (addr !== other_transaction.addr) begin
        `uvm_error(COMPONENT_NAME, "Addr does match!");
        return 1'b0;
      end

      if (transaction_type !== other_transaction.transaction_type) begin
        `uvm_error(COMPONENT_NAME, "Translation type does match!");
        return 1'b0;
      end

      return 1'b1;
    endfunction

  endclass

  class NorthcapeBramDriverModuleInterface #(
      parameter DATA_WIDTH = -1,
      parameter DATA_DEPTH = -1
  );

    typedef NorthcapeBRAMRequest#(
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_DEPTH(DATA_DEPTH)
    ) bram_request_t;


    // module -> driver: give me data please
    semaphore request_semaphore;
    // driver -> module: data available
    semaphore response_semaphore;
    // driver -> module: data to be returned for this read request
    uvm_queue #(bram_request_t) read_data_in_queue;

    // module-> driver: write data available
    semaphore write_semaphore;
    // module -> driver: request that the DUT made (address, type, write data if any)
    uvm_queue #(bram_request_t) response_data_queue;

    function new();
      request_semaphore = new();
      response_semaphore = new();
      read_data_in_queue = new();

      write_semaphore = new();
      response_data_queue = new();
    endfunction
  endclass

  class automatic NorthcapeBRAMDriver #(
      parameter DATA_WIDTH = -1,
      parameter DATA_DEPTH = -1,
      parameter string MODULE_INTERFACE_NAME = "NORTHCAPE_BRAM_MODULE_INTERFACE"
  ) extends uvm_driver #(NorthcapeBRAMRequest #(
      .DATA_WIDTH(DATA_WIDTH),
      .DATA_DEPTH(DATA_DEPTH)
  ));

    typedef NorthcapeBRAMRequest#(
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_DEPTH(DATA_DEPTH)
    ) transaction_t;
    typedef NorthcapeBramDriverModuleInterface#(
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_DEPTH(DATA_DEPTH)
    ) module_interface_t;

    module_interface_t module_interface;
    uvm_analysis_port #(transaction_t) ap;

    localparam COMPONENT_NAME = "Northcape BRAM Driver";

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      bit uvm_config_db_ok;
      ap = new("result_port", this);

      uvm_config_db_ok = uvm_config_db#(module_interface_t)::get(this, "", MODULE_INTERFACE_NAME,
                                                                 module_interface);
      if (!uvm_config_db_ok) begin
        `uvm_fatal(COMPONENT_NAME, "Could not get module interface!");
      end

    endfunction : build_phase

    task handle_read_requests(uvm_phase phase);
      forever begin
        transaction_t transaction;
        `uvm_info(COMPONENT_NAME, "Waiting for read request!", UVM_DEBUG);
        module_interface.request_semaphore.get();

        phase.raise_objection(this);
        `uvm_info(COMPONENT_NAME, "Got read request!", UVM_DEBUG);
        seq_item_port.get_next_item(transaction);
        `uvm_info(COMPONENT_NAME, "Got transaction!", UVM_DEBUG);
        module_interface.read_data_in_queue.push_back(transaction);
        `uvm_info(COMPONENT_NAME, "Provided write data!", UVM_DEBUG);
        module_interface.response_semaphore.put();
        seq_item_port.item_done();
        phase.drop_objection(this);
      end

    endtask

    task handle_writes(uvm_phase phase);
      forever begin
        `uvm_info(COMPONENT_NAME, "Waiting for write data!", UVM_DEBUG);
        module_interface.write_semaphore.get();
        phase.raise_objection(this);
        `uvm_info(COMPONENT_NAME, "Got write data!", UVM_DEBUG);
        ap.write(module_interface.response_data_queue.pop_front());
        phase.drop_objection(this);
      end
    endtask

    task run_phase(uvm_phase phase);
      fork
        handle_read_requests(phase);
        handle_writes(phase);
      join
    endtask

  endclass


endpackage


module northcape_bram_driver_mod #(
    parameter int DATA_WIDTH = -1,
    parameter int DATA_DEPTH = -1,
    // both parameters ignored - exist purely for interface compatibility
    parameter bit INIT_TO_ZERO = 1'b1,
    parameter bit WRITE_FIRST = 1'b0,
    // sync between driver and module!
    parameter string MODULE_INTERFACE_NAME = "NORTHCAPE_BRAM_MODULE_INTERFACE",
    localparam int ADDR_WIDTH = $clog2(DATA_DEPTH)
) (
    input logic clk_i,

    // port A
    input logic [DATA_WIDTH-1:0] a_wdata_i,
    input logic a_wenable_i,
    output logic [DATA_WIDTH-1:0] a_rdata_o,
    input logic [ADDR_WIDTH-1:0] a_addr_i,
    input logic a_enable_i,

    // port B
    input logic [DATA_WIDTH-1:0] b_wdata_i,
    input logic b_wenable_i,
    output logic [DATA_WIDTH-1:0] b_rdata_o,
    input logic [ADDR_WIDTH-1:0] b_addr_i,
    input logic b_enable_i
);

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import northcape_bram_driver::*;

  typedef NorthcapeBramDriverModuleInterface#(
      .DATA_WIDTH(DATA_WIDTH),
      .DATA_DEPTH(DATA_DEPTH)
  ) module_interface_t;
  typedef NorthcapeBRAMRequest#(
      .DATA_WIDTH(DATA_WIDTH),
      .DATA_DEPTH(DATA_DEPTH)
  ) bram_request_t;

  module_interface_t module_interface;

  localparam string COMPONENT_NAME = "Northcape BRAM driver";

  initial begin
    module_interface = new();
    uvm_config_db#(module_interface_t)::set(null, "", MODULE_INTERFACE_NAME, module_interface);
  end

  always @(posedge (clk_i)) begin : port_a_logic
    automatic bram_request_t bram_request;
    if (a_enable_i) begin
      bram_request = new();
      bram_request.transaction_type = a_wenable_i ? NORTHCAPE_BRAM_WRITE : NORTHCAPE_BRAM_READ;
      bram_request.addr = a_addr_i;
      unique case (bram_request.transaction_type)
        NORTHCAPE_BRAM_WRITE: begin
          // this is a write transaction -> just record and send to scoreboard
          bram_request.data = a_wdata_i;
          a_rdata_o <= 'x;
        end
        default: begin
          automatic bram_request_t read_request;
          bram_request.data = '0;

          // driver, git me data please
          module_interface.request_semaphore.put();
          `uvm_info(COMPONENT_NAME, "Waiting for BRAM read data from driver (Port A)!", UVM_DEBUG);
          module_interface.response_semaphore.get();
          read_request = module_interface.read_data_in_queue.pop_front();
          `uvm_info(COMPONENT_NAME, $sformatf("Got read data %x (Port A)", read_request.data),
                    UVM_DEBUG);
          a_rdata_o <= read_request.data;
        end
      endcase
      module_interface.response_data_queue.push_back(bram_request);
      `uvm_info(COMPONENT_NAME, "Pushing write semaphore! (Port A)", UVM_DEBUG);
      module_interface.write_semaphore.put();
    end
  end : port_a_logic

  always @(posedge (clk_i)) begin : port_b_logic
    automatic bram_request_t bram_request;
    if (b_enable_i) begin
      bram_request = new();
      bram_request.transaction_type = b_wenable_i ? NORTHCAPE_BRAM_WRITE : NORTHCAPE_BRAM_READ;
      bram_request.addr = b_addr_i;
      unique case (bram_request.transaction_type)
        NORTHCAPE_BRAM_WRITE: begin
          // this is a write transaction -> just record and send to scoreboard
          bram_request.data = b_wdata_i;
          b_rdata_o <= 'x;
        end
        default: begin
          automatic bram_request_t read_request;
          bram_request.data = '0;

          // driver, git me data please
          module_interface.request_semaphore.put();
          `uvm_info(COMPONENT_NAME, "Waiting for BRAM read data from driver! (Port B)", UVM_DEBUG);
          module_interface.response_semaphore.get();
          read_request = module_interface.read_data_in_queue.pop_front();
          `uvm_info(COMPONENT_NAME, $sformatf("Got read data %x (Port B)", read_request.data),
                    UVM_DEBUG);
          b_rdata_o <= read_request.data;
        end
      endcase
      module_interface.response_data_queue.push_back(bram_request);
      `uvm_info(COMPONENT_NAME, "Pushing write semaphore! (Port B)", UVM_DEBUG);
      module_interface.write_semaphore.put();
    end
  end : port_b_logic


endmodule
