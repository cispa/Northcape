/**
  * Start and check sequences for CapabilityOps.
  */
package northcape_capability_ops_sequence;
  import uvm_pkg::*;
  import northcape_types::*;
  import axi5::*;
  import northcape_test::*;
  import northcape_capability_ops_common::*;
  import northcape_capability_ops_csr_interface_driver::*;

  import northcape_reg_interface_transaction::NorthcapeRegInterfaceAxiLiteTransaction;

  `include "uvm_macros.svh"

  /**
      * Capability Ops enable sequence.
      * Enables the Northcape system as a whole, only needs to be run once.
      * 1 MMIO write to start the system.
      * Waits for CMT reset done signal.
      * Then does one read to make sure that the enabled flag is set and the capability count is 1 (1 root cap).
      */
  class automatic NorthcapeCapabilityOpsEnableSequence #(
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_DATA_WIDTH = -1
  ) extends uvm_sequence #(NorthcapeRegInterfaceAxiLiteTransaction #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
  ));

    typedef virtual NorthcapeCMTInterface #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ).TEST_CONSUMER cmt_interface_t;

    typedef NorthcapeRegInterfaceAxiLiteTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) transaction_t;

    cmt_interface_t cmt_interface;

    function new(cmt_interface_t cmt_interface, string name = "");
      super.new(name);

      this.cmt_interface = cmt_interface;
    endfunction

    localparam COMPONENT_NAME = "Northcape Capability Ops Enable Sequence";

    localparam AXI_DATA_WIDTH_BYTES = AXI_DATA_WIDTH / 8;

    task body();
      transaction_t transaction;

      transaction = new("Axi lite transaction");

      // unused
      transaction.transaction_prot = '0;

      `uvm_info(COMPONENT_NAME, "Sending enable write!", UVM_DEBUG);

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      // write the enable MMIO reg
      transaction.transaction_type = AXI_TEST_WRITE;
      transaction.transaction_addr = 6'h28;
      transaction.transaction_data = {1'b1, 1'b0, 1'b0, 1'b0, 60'h0};
      transaction.transaction_write_strobe = '1;

      finish_item(transaction);

      `uvm_info(COMPONENT_NAME, "Waiting for CMT reset done signal before status check!",
                UVM_DEBUG);

      @(cmt_interface.test_consumer_clocking iff cmt_interface.test_consumer_clocking.reset_done == 1'b1);

      `uvm_info(COMPONENT_NAME, "Got CMT reset done signal - status check!", UVM_DEBUG);

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      // check count and enabled flag
      transaction.transaction_type = AXI_TEST_READ;
      transaction.transaction_addr = 6'h28;

      finish_item(transaction);

    endtask

  endclass

  /**
    * Encoding etc., shared between CSR and MMIO interfaces.
    */
  class automatic NorthcapeCapabilityOpsStartSequenceCommon #(
      parameter type transaction_t = logic
  ) extends uvm_sequence #(transaction_t);
    // fixed by design
    localparam AXI_DATA_WIDTH = 64;
    bit [AXI_DATA_WIDTH-1:0] input_token;

    // restriction bits with different interpretations
    bit [AXI_DATA_WIDTH-1:0] input_restriction;
    northcape_restriction_type_t restriction_type;
    bit restriction_enabled;

    // where the new segment is
    // 0: start of input segment
    // 1: end of input segment
    bit direction;
    // length of the new segment
    segment_length_t new_segment_length;

    // permissions for newly created segment
    bit read_perm;
    bit write_perm;
    bit x_perm;
    bit lockable_perm;
    bit irq_accessible_perm;
    bit cacheable_tlb_perm;
    bit cacheable_access_perm;

    // how long the offset vs. ID fields should be
    capability_type_t intended_capability_type;


    northcape_capability_operation_t operation;

    bit [AXI_DATA_WIDTH-1:0] aux1_input;


    bit use_isr_fsm;

    localparam INPUT_TOKEN_REG_NUM = 0;
    localparam RESTRICTION_REG_NUM = 2;
    localparam CONTROL_STATUS_REG_NUM = 3;
    localparam AUX1_REG_NUM = 4;


    function new(
    string name = "",
    bit [AXI_DATA_WIDTH-1:0] input_token,
    // device and task Id
                 // for restriction
                 bit [AXI_DATA_WIDTH-1:0] input_restriction,
                 northcape_restriction_type_t restriction_type, bit direction,
                 segment_length_t new_segment_length, bit restriction_enabled, bit read_perm,
                 bit write_perm, bit x_perm, bit lockable_perm, bit irq_accessible_perm,
                 bit cacheable_tlb_perm, bit cacheable_access_perm,
                 northcape_capability_operation_t operation,
                 capability_type_t intended_capability_type, bit [AXI_DATA_WIDTH-1:0] aux1_input,
                 bit use_isr_fsm, int pcr_index);
      super.new(name);

      this.input_token = input_token;

      this.input_restriction = input_restriction;
      this.restriction_type = restriction_type;
      this.restriction_enabled = restriction_enabled;

      this.read_perm = read_perm;
      this.write_perm = write_perm;
      this.x_perm = x_perm;
      this.lockable_perm = lockable_perm;
      this.irq_accessible_perm = irq_accessible_perm;
      this.cacheable_tlb_perm = cacheable_tlb_perm;
      this.cacheable_access_perm = cacheable_access_perm;

      this.operation = operation;

      this.direction = direction;
      this.new_segment_length = new_segment_length;
      this.intended_capability_type = intended_capability_type;
      this.aux1_input = aux1_input;
      this.use_isr_fsm = use_isr_fsm;
      this.pcr_index = pcr_index;
    endfunction

    function logic [AXI_DATA_WIDTH-1:0] encode_control_status_reg();
      return {
        9'h0,
        pcr_index,
        cacheable_tlb_perm,
        cacheable_access_perm,
        restriction_type,
        intended_capability_type,
        direction,
        new_segment_length,
        restriction_enabled,
        read_perm,
        write_perm,
        x_perm,
        lockable_perm,
        irq_accessible_perm,
        operation
      };
    endfunction

  endclass



  /**
      * Capability Ops start sequence.
      * Starts one particular operation.
      * 3 writes to Input, restriction, operation.
      */
  class automatic NorthcapeCapabilityOpsStartSequence #(
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_DATA_WIDTH = -1
  ) extends NorthcapeCapabilityOpsStartSequenceCommon #(NorthcapeRegInterfaceAxiLiteTransaction #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
  ));


    typedef NorthcapeRegInterfaceAxiLiteTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) transaction_t;


    function new(
    string name = "",
    bit [AXI_DATA_WIDTH-1:0] input_token,
    // device and task Id
                 // for restriction
                 bit [AXI_DATA_WIDTH-1:0] input_restriction,
                 northcape_restriction_type_t restriction_type, bit direction,
                 segment_length_t new_segment_length, bit restriction_enabled, bit read_perm,
                 bit write_perm, bit x_perm, bit lockable_perm, bit irq_accessible_perm,
                 bit cacheable_tlb_perm, bit cacheable_access_perm,
                 northcape_capability_operation_t operation,
                 capability_type_t intended_capability_type, bit [AXI_DATA_WIDTH-1:0] aux1_input,
                 bit use_isr_fsm, int pcr_index);
      super.new(name, input_token, input_restriction, restriction_type, direction,
                new_segment_length, restriction_enabled, read_perm, write_perm, x_perm,
                lockable_perm, irq_accessible_perm, cacheable_tlb_perm, cacheable_access_perm,
                operation, intended_capability_type, aux1_input, use_isr_fsm, pcr_index);
    endfunction

    localparam COMPONENT_NAME = "Northcape Capability Ops Start Sequence";

    localparam AXI_DATA_WIDTH_BYTES = AXI_DATA_WIDTH / 8;

    task body();
      transaction_t transaction;

      transaction = new("Axi lite transaction");

      // unused
      transaction.transaction_prot = '0;

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      // input token to input register
      transaction.transaction_type = AXI_TEST_WRITE;
      transaction.transaction_addr = {
        this.use_isr_fsm, 6'(AXI_DATA_WIDTH_BYTES * INPUT_TOKEN_REG_NUM)
      };
      transaction.transaction_data = input_token;
      transaction.transaction_write_strobe = '1;

      finish_item(transaction);

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      // restriction input
      // optional, but writing the register does not do anything
      transaction.transaction_type = AXI_TEST_WRITE;
      transaction.transaction_addr = {
        this.use_isr_fsm, 6'(AXI_DATA_WIDTH_BYTES * RESTRICTION_REG_NUM)
      };
      transaction.transaction_data = input_restriction;
      transaction.transaction_write_strobe = '1;

      finish_item(transaction);

      start_item(transaction);

      // Aux 1 input
      // for derive, this is the parent offset
      // optional, but writing the register does not do anything
      transaction.transaction_type = AXI_TEST_WRITE;
      transaction.transaction_addr = {this.use_isr_fsm, 6'(AXI_DATA_WIDTH_BYTES * AUX1_REG_NUM)};
      transaction.transaction_data = aux1_input;
      transaction.transaction_write_strobe = '1;

      finish_item(transaction);

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      transaction.transaction_type = AXI_TEST_WRITE;
      transaction.transaction_addr = {
        this.use_isr_fsm, 6'(AXI_DATA_WIDTH_BYTES * CONTROL_STATUS_REG_NUM)
      };
      transaction.transaction_data = encode_control_status_reg();
      transaction.transaction_write_strobe = '1;

      finish_item(transaction);

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      // expectation: in progress bit set
      transaction.transaction_type = AXI_TEST_READ;
      transaction.transaction_addr = {
        this.use_isr_fsm, 6'(AXI_DATA_WIDTH_BYTES * CONTROL_STATUS_REG_NUM)
      };

      finish_item(transaction);

    endtask

  endclass


  /**
      * Capability Ops start sequence CSR.
      * Starts one particular operation via CSR interface.
      * 3 writes to Input, restriction, operation.
      */
  class automatic NorthcapeCapabilityOpsStartSequenceCSR extends NorthcapeCapabilityOpsStartSequenceCommon #(NorthcapeCapabilityOpsCSRInterfaceTransaction);


    typedef NorthcapeCapabilityOpsCSRInterfaceTransaction transaction_t;

    device_id_t device_id;
    task_id_t   task_id;

    function new(
        string name = "",
        bit [AXI_DATA_WIDTH-1:0] input_token,
        // device and task Id
        // for restriction
        bit [AXI_DATA_WIDTH-1:0] input_restriction, northcape_restriction_type_t restriction_type,
        bit direction, segment_length_t new_segment_length, bit restriction_enabled, bit read_perm,
        bit write_perm, bit x_perm, bit lockable_perm, bit irq_accessible_perm,
        bit cacheable_tlb_perm, bit cacheable_access_perm,
        northcape_capability_operation_t operation, capability_type_t intended_capability_type,
        bit [AXI_DATA_WIDTH-1:0] aux1_input, bit use_isr_fsm, device_id_t device_id,
        task_id_t task_id, int pcr_index);
      super.new(name, input_token, input_restriction, restriction_type, direction,
                new_segment_length, restriction_enabled, read_perm, write_perm, x_perm,
                lockable_perm, irq_accessible_perm, cacheable_tlb_perm, cacheable_access_perm,
                operation, intended_capability_type, aux1_input, use_isr_fsm, pcr_index);
      this.device_id = device_id;
      this.task_id   = task_id;
    endfunction

    localparam COMPONENT_NAME = "Northcape Capability Ops Start Sequence";

    localparam AXI_DATA_WIDTH_BYTES = AXI_DATA_WIDTH / 8;

    task body();
      transaction_t transaction;

      transaction = new("CSR transaction");

      start_item(transaction);

      transaction.request = '0;
      transaction.request.req_valid = 1'b1;
      transaction.request.req_type = CSR_WRITE;
      transaction.request.reg_num = INPUT_TOKEN_REG_NUM;
      transaction.request.reg_new_val = input_token;
      transaction.request.device_id = device_id;
      transaction.request.task_id = task_id;
      transaction.request.is_irq = use_isr_fsm;

      finish_item(transaction);

      start_item(transaction);

      // restriction input
      // optional, but writing the register does not do anything
      transaction.request = '0;
      transaction.request.req_valid = 1'b1;
      transaction.request.req_type = CSR_WRITE;
      transaction.request.reg_num = RESTRICTION_REG_NUM;
      transaction.request.reg_new_val = input_restriction;
      transaction.request.device_id = device_id;
      transaction.request.task_id = task_id;
      transaction.request.is_irq = use_isr_fsm;

      finish_item(transaction);

      start_item(transaction);

      // Aux 1 input
      // for derive, this is the parent offset
      // optional, but writing the register does not do anything
      transaction.request = '0;
      transaction.request.req_valid = 1'b1;
      transaction.request.req_type = CSR_WRITE;
      transaction.request.reg_num = AUX1_REG_NUM;
      transaction.request.reg_new_val = aux1_input;
      transaction.request.device_id = device_id;
      transaction.request.task_id = task_id;
      transaction.request.is_irq = use_isr_fsm;

      finish_item(transaction);

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end


      transaction.request = '0;
      transaction.request.req_valid = 1'b1;
      transaction.request.req_type = CSR_WRITE;
      transaction.request.reg_num = CONTROL_STATUS_REG_NUM;
      transaction.request.reg_new_val = encode_control_status_reg();
      transaction.request.device_id = device_id;
      transaction.request.task_id = task_id;
      transaction.request.is_irq = use_isr_fsm;

      finish_item(transaction);

      // no check read - implementation-specified whether this will (already) show a result

    endtask

  endclass

  /**
      * Capability Ops stop sequence.
      * Checks if Capability Ops is complete.
      */
  class automatic NorthcapeCapabilityOpsStopSequence #(
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_DATA_WIDTH = -1
  ) extends uvm_sequence #(NorthcapeRegInterfaceAxiLiteTransaction #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
  ));


    localparam AXI_DATA_WIDTH_BYTES = AXI_DATA_WIDTH / 8;


    typedef NorthcapeRegInterfaceAxiLiteTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) transaction_t;

    bit use_isr_fsm;

    function new(string name = "", bit use_isr_fsm);
      super.new(name);
      this.use_isr_fsm = use_isr_fsm;
    endfunction

    localparam COMPONENT_NAME = "Northcape Capability Ops Stop Sequence";

    task body();
      transaction_t transaction;

      transaction = new("MMIO transaction");

      // unused
      transaction.transaction_prot = '0;

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      // expectation: complete bit set
      // inspect: also some metadata (will check in scoreboard)
      transaction.transaction_type = AXI_TEST_READ;
      transaction.transaction_addr = {this.use_isr_fsm, 6'(AXI_DATA_WIDTH_BYTES * 3)};

      finish_item(transaction);

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      // for inspect, restriction metadata
      // other operations: empty
      transaction.transaction_type = AXI_TEST_READ;
      transaction.transaction_addr = {this.use_isr_fsm, 6'(AXI_DATA_WIDTH_BYTES * 2)};

      finish_item(transaction);

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      // for inspect, effective base
      // otherwise: empty
      transaction.transaction_type = AXI_TEST_READ;
      transaction.transaction_addr = {this.use_isr_fsm, 6'(AXI_DATA_WIDTH_BYTES * 4)};

      finish_item(transaction);

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      // expectation: correct output token
      transaction.transaction_type = AXI_TEST_READ;
      transaction.transaction_addr = {this.use_isr_fsm, 6'(AXI_DATA_WIDTH_BYTES)};

      finish_item(transaction);

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      // expectation: zeros (reset)
      transaction.transaction_type = AXI_TEST_READ;
      transaction.transaction_addr = {this.use_isr_fsm, 6'(AXI_DATA_WIDTH_BYTES)};

      finish_item(transaction);

      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      // expectation: current capability counter
      transaction.transaction_type = AXI_TEST_READ;
      transaction.transaction_addr = {this.use_isr_fsm, 6'(AXI_DATA_WIDTH_BYTES * 5)};

      finish_item(transaction);

      // check RNG output
      start_item(transaction);

      if (transaction.randomize() == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
      end

      transaction.transaction_type = AXI_TEST_READ;
      transaction.transaction_addr = 6'h30;

      finish_item(transaction);
    endtask

  endclass

  /**
      * Capability Ops stop sequence CSR.
      * Checks if Capability Ops is complete via CSR.
      */
  class automatic NorthcapeCapabilityOpsStopSequenceCSR extends uvm_sequence #(NorthcapeCapabilityOpsCSRInterfaceTransaction);


    localparam AXI_DATA_WIDTH_BYTES = 8;


    typedef NorthcapeCapabilityOpsCSRInterfaceTransaction transaction_t;

    bit use_isr_fsm;
    device_id_t device_id;
    task_id_t task_id;

    function new(string name = "", bit use_isr_fsm, device_id_t device_id, task_id_t task_id);
      super.new(name);
      this.use_isr_fsm = use_isr_fsm;
      this.device_id = device_id;
      this.task_id = task_id;
    endfunction

    localparam COMPONENT_NAME = "Northcape Capability Ops Stop Sequence";

    task body();
      transaction_t transaction;

      transaction = new("MMIO transaction");

      start_item(transaction);

      // expectation: complete bit set
      // inspect: also some metadata (will check in scoreboard)
      transaction.request = '0;
      transaction.request.req_valid = 1'b1;
      transaction.request.req_type = CSR_READ;
      transaction.request.reg_num = 3;
      transaction.request.device_id = device_id;
      transaction.request.task_id = task_id;
      transaction.request.is_irq = use_isr_fsm;

      finish_item(transaction);

      start_item(transaction);

      // for inspect, restriction metadata
      // other operations: empty
      transaction.request = '0;
      transaction.request.req_valid = 1'b1;
      transaction.request.req_type = CSR_READ;
      transaction.request.reg_num = 2;
      transaction.request.device_id = device_id;
      transaction.request.task_id = task_id;
      transaction.request.is_irq = use_isr_fsm;

      finish_item(transaction);

      start_item(transaction);


      // for inspect, effective base
      // otherwise: empty
      transaction.request = '0;
      transaction.request.req_valid = 1'b1;
      transaction.request.req_type = CSR_READ;
      transaction.request.reg_num = 4;
      transaction.request.device_id = device_id;
      transaction.request.task_id = task_id;
      transaction.request.is_irq = use_isr_fsm;

      finish_item(transaction);

      start_item(transaction);

      // expectation: correct output token
      transaction.request = '0;
      transaction.request.req_valid = 1'b1;
      transaction.request.req_type = CSR_READ;
      transaction.request.reg_num = 1;
      transaction.request.device_id = device_id;
      transaction.request.task_id = task_id;
      transaction.request.is_irq = use_isr_fsm;

      finish_item(transaction);

      start_item(transaction);

      // expectation: zeros (reset)
      transaction.request = '0;
      transaction.request.req_valid = 1'b1;
      transaction.request.req_type = CSR_READ;
      transaction.request.reg_num = 1;
      transaction.request.device_id = device_id;
      transaction.request.task_id = task_id;
      transaction.request.is_irq = use_isr_fsm;

      finish_item(transaction);

      start_item(transaction);

      // expectation: current capability counter
      transaction.request = '0;
      transaction.request.req_valid = 1'b1;
      transaction.request.req_type = CSR_READ;
      transaction.request.reg_num = 5;
      transaction.request.device_id = device_id;
      transaction.request.task_id = task_id;
      transaction.request.is_irq = use_isr_fsm;

      finish_item(transaction);

      // check RNG output
      start_item(transaction);

      transaction.request = '0;
      transaction.request.req_valid = 1'b1;
      transaction.request.req_type = CSR_READ;
      transaction.request.reg_num = 6;
      transaction.request.device_id = device_id;
      transaction.request.task_id = task_id;
      transaction.request.is_irq = use_isr_fsm;

      finish_item(transaction);
    endtask

  endclass
endpackage
