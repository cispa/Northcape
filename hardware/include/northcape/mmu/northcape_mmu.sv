/**
  * Top-level Northcape MMU component.
  */
import northcape_types::*;
import axi5::*;

module northcape_mmu #(
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_ID_WIDTH = -1,
    parameter AXI_USER_WIDTH = -1,
    parameter bit ACCEPT_AXI_WRAP_BURSTS = 1,
    parameter device_id_t READ_CHAN_DEVICE_ID = -1,
    parameter device_id_t WRITE_CHAN_DEVICE_ID = -1,
    // set to one to prevent all accesses that resolve into the CMT table
    parameter bit SELF_PRESERVATION_MODE_ACTIVE = 1,
    parameter bit SHIFTING_ACTIVE = 1,
    // cover edge case where bursts partially leave the capability and we need to censor information?
    parameter bit MASKING_ACTIVE = 1,
    parameter bit ENABLE_ILA = 0,
    // can device be trusted with X-only capabilities?
    parameter bit DEVICE_INDICATES_EXECUTE = 1'b0,
    // bypass MMU until CMT reset is done?
    parameter bit MMU_BYPASS_UNTIL_CMT_RESET_DONE_ENABLED = 1'b0
) (
    input logic clk_i,
    input logic rst_ni,

    // AXI Slave Interface
    Axi5.TO axi_slave,

    // AXI Master Interface 
    Axi5.FROM axi_master,

    Axis5.TRANSMITTER axis_validate_request_read,
    Axis5.RECEIVER axis_validate_response_read,
    Axis5.TRANSMITTER axis_validate_request_write,
    Axis5.RECEIVER axis_validate_response_write,

    // current CMT metadata from operations module
    NorthcapeCMTInterface.CONSUMER cmt_interface
);

  `include "axi5_assign.svh"
  `include "northcape_unread.vh"

  // signal from the write to the read side that it needs to forward read response from atomic transaction. Valid for one cycle.
  atomic_transaction_request_t atomic_transaction_request;

  // current task id is set by the read chan during subsystem calls
  // otherwise read by read chan, write chan
  // distinguish one task ID in normal execution and one in interrupt to allow ISRs to do subsystem calls, securely transition back into original task
  task_id_t current_task_id_irq;
  task_id_t current_task_id_non_irq;

  logic rd_channel_is_waiting_for_atomic;

  logic in_read_d, in_read_q;
  logic in_write_d, in_write_q;
  logic axi_transaction_active;

  logic in_bypass_d, in_bypass_q;

  Axi5ReadOnly #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) axi_slave_read (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );
  Axi5ReadOnly #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) axi_master_read (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );

  Axi5WriteOnly #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) axi_slave_write (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );
  Axi5WriteOnly #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) axi_master_write (
      .clk_i (clk_i),
      .rst_ni(rst_ni)
  );


  always_comb begin : mmuBypassLogic

    if (in_bypass_q) begin
      `NORTHCAPE_MAP_INTERFACES(, axi_master, =, axi_slave);

      `AXI5_RESET_AR_CHANNEL_MASTER_CUSTOM(axi_master_read, =);
      `AXI5_RESET_AR_CHANNEL_SLAVE_CUSTOM(axi_slave_read, =);

      `AXI5_RESET_AW_CHANNEL_MASTER_CUSTOM(axi_master_write, =);
      `AXI5_RESET_AW_CHANNEL_SLAVE_CUSTOM(axi_slave_write, =);

      `AXI5_RESET_R_CHANNEL_MASTER_CUSTOM(axi_master_read, =);
      `AXI5_RESET_R_CHANNEL_SLAVE_CUSTOM(axi_slave_read, =);

      `AXI5_RESET_W_CHANNEL_MASTER_CUSTOM(axi_master_write, =);
      `AXI5_RESET_W_CHANNEL_SLAVE_CUSTOM(axi_slave_write, =);

      `AXI5_RESET_B_CHANNEL_MASTER_CUSTOM(axi_master_write, =);
      `AXI5_RESET_B_CHANNEL_SLAVE_CUSTOM(axi_slave_write, =);

      if (cmt_interface.reset_done) begin
        // need to make sure not to accept new transaction - might otherwise never complete
        axi_master.awvalid = 1'b0;
        axi_slave.awready  = 1'b0;

        axi_master.arvalid = 1'b0;
        axi_slave.arready  = 1'b0;
      end



    end else begin
      `NORTHCAPE_MAP_INTERFACES_READ(, axi_slave_read, =, axi_slave);
      `NORTHCAPE_MAP_INTERFACES_READ(, axi_master, =, axi_master_read);

      `NORTHCAPE_MAP_INTERFACES_WRITE(, axi_slave_write, =, axi_slave);
      `NORTHCAPE_MAP_INTERFACES_WRITE(, axi_master, =, axi_master_write);
    end
  end : mmuBypassLogic

  generate
    if (MMU_BYPASS_UNTIL_CMT_RESET_DONE_ENABLED == 1'b1) begin
      always_ff @(posedge (clk_i), negedge (rst_ni)) begin : bypasFFs
        if (!rst_ni) begin
          in_bypass_q <= 1'b1;
          in_read_q   <= 1'b0;
          in_write_q  <= 1'b0;
        end else begin
          in_bypass_q <= in_bypass_d;
          in_read_q   <= in_read_d;
          in_write_q  <= in_write_d;
        end
      end : bypasFFs

      always_comb begin : mmuBypassFSM
        if (in_bypass_q) begin
          if (in_read_q) begin
            // last beat and no new transaction - leave transaction
            in_read_d = !(axi_master.rvalid && axi_master.rlast && axi_slave.rready) && !(axi_slave.arvalid && axi_master.arready);
          end else begin
            in_read_d = axi_slave.arvalid && axi_master.arready;
          end

          if (in_write_q) begin
            // last beat and no new transaction - leave transaction
            // no need to wait for b channel - MMU will always pass it through
            in_write_d = !(axi_slave.awvalid && axi_master.awready) && !(axi_slave.wvalid && axi_slave.wlast && axi_master.wready);
          end else begin
            in_write_d = axi_slave.awvalid && axi_master.awready;
          end
          in_bypass_d = in_bypass_q;

          axi_transaction_active = in_write_d || in_read_d;
          if (cmt_interface.reset_done) begin
            // leave bypass as soon as AXI transaction stops
            in_bypass_d = in_bypass_q && axi_transaction_active;
          end
        end else begin
          // signals do not matter any more - we will not go back into bypass mode
          axi_transaction_active = 1'b0;
          in_bypass_d = 1'b0;
          in_read_d = 1'b0;
          in_write_d = 1'b0;
        end
      end : mmuBypassFSM

    end else begin
      assign in_bypass_q = 1'b0;
    end
  endgenerate


  northcape_mmu_read_chan #(
      .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .ACCEPT_AXI_WRAP_BURSTS(ACCEPT_AXI_WRAP_BURSTS),
      .SELF_PRESERVATION_MODE_ACTIVE(SELF_PRESERVATION_MODE_ACTIVE),
      .MASKING_ACTIVE(MASKING_ACTIVE),
      .SHIFTING_ACTIVE(SHIFTING_ACTIVE),
      .ENABLE_ILA(ENABLE_ILA),
      .DEVICE_INDICATES_EXECUTE(DEVICE_INDICATES_EXECUTE)
  ) read_chan (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .axi_slave (axi_slave_read.TO),
      .axi_master(axi_master_read.FROM),

      .axis_validate_request_read  (axis_validate_request_read),
      .axis_validate_response_read (axis_validate_response_read),
      .atomic_transaction_request_i(atomic_transaction_request),

      .task_id_irq_q_o(current_task_id_irq),
      .task_id_non_irq_q_o(current_task_id_non_irq),

      .cmt_interface(cmt_interface),

      .rd_channel_is_waiting_for_atomic_o(rd_channel_is_waiting_for_atomic)
  );

  northcape_mmu_write_chan #(
      .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .AXI_USER_WIDTH(AXI_USER_WIDTH),
      .ACCEPT_AXI_WRAP_BURSTS(ACCEPT_AXI_WRAP_BURSTS),
      .SELF_PRESERVATION_MODE_ACTIVE(SELF_PRESERVATION_MODE_ACTIVE),
      .MASKING_ACTIVE(MASKING_ACTIVE),
      .SHIFTING_ACTIVE(SHIFTING_ACTIVE),
      .ENABLE_ILA(ENABLE_ILA),
      .DEVICE_INDICATES_EXECUTE(DEVICE_INDICATES_EXECUTE)
  ) write_chan (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      .axi_slave (axi_slave_write.TO),
      .axi_master(axi_master_write.FROM),

      .axis_validate_request_write (axis_validate_request_write),
      .axis_validate_response_write(axis_validate_response_write),
      .atomic_transaction_request_o(atomic_transaction_request),

      .current_task_id_irq_i(current_task_id_irq),
      .current_task_id_non_irq_i(current_task_id_non_irq),

      .cmt_interface(cmt_interface),

      .rd_channel_is_waiting_for_atomic_i(rd_channel_is_waiting_for_atomic)
  );


  `NORTHCAPE_UNREAD(axi_slave.clk_i);
  `NORTHCAPE_UNREAD(axi_slave.rst_ni);
  `NORTHCAPE_UNREAD(axi_master.clk_i);
  `NORTHCAPE_UNREAD(axi_master.rst_ni);
  `NORTHCAPE_UNREAD(cmt_interface.need_flush_data_caches);
  `NORTHCAPE_UNREAD(cmt_interface.wrote_any_capability);
  `NORTHCAPE_UNREAD(cmt_interface.written_capability);
endmodule
