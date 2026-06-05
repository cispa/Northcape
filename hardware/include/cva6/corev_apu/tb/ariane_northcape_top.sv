/**
  * Module containing instantiations of northcape MMU, resolver, capability operations with SRAM for ariane tb.
  */
module northcape_top #(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = build_config_pkg::build_config(cva6_config_pkg::cva6_cfg),
    parameter int unsigned AXI_ID_WIDTH_SLAVE = -1,
    parameter int unsigned AXI_ID_WIDTH_MASTER = -1,
    parameter int unsigned AXI_ADDRESS_WIDTH = -1,
    parameter int unsigned AXI_DATA_WIDTH = -1,
    parameter int unsigned AXI_USER_WIDTH = -1,
    parameter int unsigned MEMORY_SIZE_WORDS = -1,
    parameter bit STALL_RANDOM_INPUT = 1'b0,
    parameter bit STALL_RANDOM_OUTPUT = 1'b0,
    parameter bit HAS_CACHE_INTERFACE = 1'b1
) (
    input logic clk_i,

    input logic ndmreset_n,
    input logic rst_ni,

    // MMU -> Mem
    AXI_BUS cpu_axi_slave,
    // Resolver -> Mem
    AXI_BUS resolver_axi_slave,
    // Ops -> Mem
    AXI_BUS ops_axi_slave,

    // CPU -> MMU
    input ariane_axi::req_t    axi_ariane_req,
    output ariane_axi::resp_t   axi_ariane_resp,

    // CPU <-> Resolver
    Axis5.RECEIVER axis_validate_request_instr,
    Axis5.TRANSMITTER axis_validate_response_instr,
    Axis5.RECEIVER axis_validate_request_data,
    Axis5.TRANSMITTER axis_validate_response_data,

    NorthcapeCMTInterface.OPS_INTERFACE cmt_interface_producer,

    output logic northcape_l2_resolver_miss_o,
    output logic northcape_l2_resolver_spec_fail_o,
    output logic northcape_l2_ops_miss_o,
    output logic northcape_cache_missunit_stall_o,
    output logic northcape_ops_write_stall_o,
    output logic northcape_cache_flush_o,

    // MMIO bus controlling ops
    AXI_BUS ops_mmio,

    input northcape_types::northcape_cap_ops_rcsr_req_t csr_req_i,
    output northcape_types::northcape_cap_ops_rcsr_resp_t csr_rsp_o
);
  import axi_pkg::BURST_FIXED;
  import axi_pkg::BURST_INCR;
  import axi_pkg::BURST_WRAP;

  import axi_pkg::RESP_OKAY;
  import axi_pkg::RESP_EXOKAY;
  import axi_pkg::RESP_DECERR;
  import axi_pkg::RESP_SLVERR;

  import ariane_soc::DRAMBase;
  import ariane_soc::DRAMLength;

  import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
  `include "axis5_assign.svh"

  // resolver FIFO width - number of max parallel requests
  localparam FIFO_DEPTH_CLOG_2 = 2;
  localparam AXI_LITE_ADDR_WIDTH = AXI_ADDRESS_WIDTH;
  localparam AXI_LITE_DATA_WIDTH = AXI_DATA_WIDTH;
  localparam AXI_DATA_WIDTH_MEM = 256;

  localparam INITIAL_CMT_SIZE_CLOG2 = $clog2(MEMORY_SIZE_WORDS);
  localparam INITIAL_CMT_BASE = DRAMBase + DRAMLength - MEMORY_SIZE_WORDS * $bits(northcape_cmt_entry_t) / 8;

  localparam device_id_t READ_CHAN_DEVICE_ID = 0;
  localparam device_id_t WRITE_CHAN_DEVICE_ID = 1;

  localparam AXI_DW_CONTERTER_MAX_READS = 8;

  // signals between SRAM and axi2mem
  logic                             req;
  logic                             we;
  logic [AXI_ADDRESS_WIDTH-1:0]     addr;
  logic [AXI_DATA_WIDTH_MEM/8-1:0]  be;
  logic [AXI_DATA_WIDTH_MEM-1:0]    wdata;
  logic [AXI_DATA_WIDTH_MEM-1:0]    rdata;
  logic [AXI_USER_WIDTH-1:0]        wuser;
  logic [AXI_USER_WIDTH-1:0]        ruser;

  /**
   * Buses TO AXI downsizer / FROM ops + resolver
   */
   AXI_BUS #(
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH            ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH_MEM           ),
    .AXI_ID_WIDTH   ( AXI_ID_WIDTH_MASTER          ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH               )
   ) ram_bus_slave_ops(), ram_bus_slave_resolver();

`include "northcape_ariane_wrapper.svh"
// AXI-Stream buses to resolvers
Axis5#(.AXIS_TDATA_WIDTH(AXIS_VALIDATE_REQUEST_TDATA_WIDTH), .AXIS_TID_WIDTH(AXIS_VALIDATE_REQUEST_TID_WIDTH), .AXIS_TDEST_WIDTH(AXIS_VALIDATE_REQUEST_TDEST_WIDTH), .AXIS_TUSER_WIDTH(AXIS_VALIDATE_REQUEST_TUSER_WIDTH)) 
    northcape_axis_validate_request_mux[3](.clk_i(clk_i),.rst_ni(ndmreset_n)),
    northcape_axis_validate_request(.clk_i(clk_i),.rst_ni(ndmreset_n));

Axis5#(.AXIS_TDATA_WIDTH(AXIS_VALIDATE_RESPONSE_TDATA_WIDTH), .AXIS_TID_WIDTH(AXIS_VALIDATE_RESPONSE_TID_WIDTH), .AXIS_TDEST_WIDTH(AXIS_VALIDATE_RESPONSE_TDEST_WIDTH), .AXIS_TUSER_WIDTH(AXIS_VALIDATE_RESPONSE_TUSER_WIDTH))
    northcape_axis_validate_response_mmu[2](.clk_i(clk_i),.rst_ni(ndmreset_n)),
    northcape_axis_validate_response(.clk_i(clk_i),.rst_ni(ndmreset_n));


Axi5#(.AXI_DATA_WIDTH(AXI_DATA_WIDTH), .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH), .AXI_ID_WIDTH(AXI_ID_WIDTH_MASTER), .AXI_USER_WIDTH(AXI_USER_WIDTH))
    // interface that goes to SLAVE port of MMU
    northcape_mmu_axi_in(.clk_i(clk_i),.rst_ni(ndmreset_n)),
    // interface that goes to MASTER port of MMU
    northcape_mmu_axi_out(.clk_i(clk_i),.rst_ni(ndmreset_n));

Axi5#(.AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM), .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH), .AXI_ID_WIDTH(AXI_ID_WIDTH_MASTER), .AXI_USER_WIDTH(AXI_USER_WIDTH))
    // interface that goes to master port of resolver
    northcape_resolver_axi_out(.clk_i(clk_i),.rst_ni(ndmreset_n)),
    northcape_cache_axi_out(.clk_i(clk_i), .rst_ni(ndmreset_n)),
    // interface that goes to the master port of ops
    northcape_ops_axi_out(.clk_i(clk_i),.rst_ni(ndmreset_n));

Axi5Lite#(.AXI_DATA_WIDTH(AXI_DATA_WIDTH), .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH)) northcape_ops_mmio(.clk_i(clk_i),.rst_ni(ndmreset_n));

NorthcapeCapabilityCacheInterfaceResolver resolver_interface (.clk_i(clk_i));
NorthcapeCapabilityCacheInterfaceOps ops_interface (.clk_i(clk_i));

// interface that communications CMT location and reset status
NorthcapeCMTInterface#(.AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH)) northcape_cmt_interface(.clk_i(clk_i));

assign cmt_interface_producer.table_size_clog2 = northcape_cmt_interface.table_size_clog2;
assign cmt_interface_producer.cmt_base = northcape_cmt_interface.cmt_base;
assign cmt_interface_producer.reset_done = northcape_cmt_interface.reset_done;
assign cmt_interface_producer.need_flush_data_caches = northcape_cmt_interface.need_flush_data_caches;
assign cmt_interface_producer.wrote_any_capability = northcape_cmt_interface.wrote_any_capability;
assign cmt_interface_producer.written_capability = northcape_cmt_interface.written_capability;

// currently, we have our own memory and self preservation mode might cause false positives
localparam SELF_PRESERVATION_MODE_ACTIVE = 0;

generate
  if(CVA6Cfg.NORTHCAPE_STAGE_ENABLED == 1'b0)
  begin: generateMMU
    /**
      * Northcape MMU
      */
    northcape_mmu 
    #(
    .ACCEPT_AXI_WRAP_BURSTS(0),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH_MASTER),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),

    .READ_CHAN_DEVICE_ID(READ_CHAN_DEVICE_ID),
    .WRITE_CHAN_DEVICE_ID(WRITE_CHAN_DEVICE_ID),

    .SELF_PRESERVATION_MODE_ACTIVE(SELF_PRESERVATION_MODE_ACTIVE),

    // assumes allocator in SW takes care of discrepancy between token address and real address
    .SHIFTING_ACTIVE(1'b1),
    // mask enforcement is required for security, though
    .MASKING_ACTIVE(1'b1),

    // no simulation model
    .ENABLE_ILA(1'b0),


    // this MMU is connected to the CPU
    .DEVICE_INDICATES_EXECUTE(1'b1),
    // do not wait for ops
    .MMU_BYPASS_UNTIL_CMT_RESET_DONE_ENABLED(1'b1)
    )
    i_northcape_mmu
    (
      .clk_i(clk_i),
      .rst_ni(ndmreset_n),

      // AXI Slave interface
      .axi_slave(northcape_mmu_axi_in),

      // AXI Master interface
      .axi_master(northcape_mmu_axi_out),

      .axis_validate_request_read(northcape_axis_validate_request_mux[0].TRANSMITTER),
      .axis_validate_response_read(northcape_axis_validate_response_mmu[0].RECEIVER),
      .axis_validate_request_write(northcape_axis_validate_request_mux[1].TRANSMITTER),
      .axis_validate_response_write(northcape_axis_validate_response_mmu[1].RECEIVER),

      .cmt_interface(northcape_cmt_interface)
      );

    end: generateMMU
    else
    begin: generateMMUBypass
      `NORTHCAPE_MAP_INTERFACES(assign, northcape_mmu_axi_out, =, northcape_mmu_axi_in);
      `AXIS5_ASSIGN(assign, northcape_axis_validate_request_mux[0], =, axis_validate_request_instr);
      `AXIS5_ASSIGN(assign, northcape_axis_validate_request_mux[1], =, axis_validate_request_data);

      `AXIS5_ASSIGN(assign, axis_validate_response_instr, =, northcape_axis_validate_response_mmu[0]);
      `AXIS5_ASSIGN(assign, axis_validate_response_data, =, northcape_axis_validate_response_mmu[1]);
    end: generateMMUBypass
endgenerate

  `NORTHCAPE_MAP_ARIANE_AXI_INTERFACES(northcape_mmu_axi_in,northcape_mmu_axi_out,axi_ariane,cpu_axi_slave)

generate
  if(HAS_CACHE_INTERFACE) begin: gen_capability_cache
    northcape_capability_cache #(
      .HASH_TYPE (northcape_capability_resolver_common::HASH_TYPE_IDENTITY),
      .CACHE_TYPE(northcape_capability_cache_common::NORTHCAPE_CAPABILITY_TYPE_WT_N_ASSOC_BRAM),
      .ASSOCIATIVITY(8),
      .KEEP_TOP_CMT_ENTRIES_ONLY(1'b0),
      .NUM_ENTRIES(512),
      .STORE_BUFFER_SIZE(8),
      .SUPPORT_SPECULATIVE_RESOLVER_LOADS(1'b1),

      .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
      .AXI_ID_WIDTH  (AXI_ID_WIDTH_MASTER),
      .AXI_USER_WIDTH(AXI_USER_WIDTH)
  ) i_capability_cache (
      .clk_i (clk_i),
      .rst_ni(ndmreset_n),

      .axi_master(northcape_cache_axi_out),

      .resolver_port(resolver_interface),
      .ops_port(ops_interface),
      .cmt_interface(northcape_cmt_interface),
      .resolver_port_miss_o(northcape_l2_resolver_miss_o),
      //.resolver_spec_fail_o(resolver_spec_fail_o),
      .ops_port_miss_o(northcape_l2_ops_miss_o),
      .missunit_stall_o(northcape_cache_missunit_stall_o),
      .ops_write_stall_o(northcape_ops_write_stall_o)
  );
    assign resolver_spec_fail_o = 1'b0;
    `MAP_NORTHCAPE_INTERFACE_TO_ARIANE_INTERFACE(northcape_cache_axi_out,ram_bus_slave_resolver)
  end: gen_capability_cache
  else begin: gen_no_cache
    `MAP_NORTHCAPE_INTERFACE_TO_ARIANE_INTERFACE(northcape_resolver_axi_out,ram_bus_slave_resolver)
    assign northcape_l2_resolver_miss_o = 1'b0;
    assign resolver_spec_fail_o = 1'b0;
    assign northcape_l2_ops_miss_o = 1'b0;
    assign northcape_cache_missunit_stall_o =1'b0;
  end: gen_no_cache
endgenerate

  Axis5Mux#(
    .NUMBER_IN_PORTS(3),
    .ARBITRATION_TYPE(axis5_mux::ARBITRATION_RR)
  ) i_mux(
    .clk_i(clk_i),
    .rst_ni(ndmreset_n),
    .in_ports(northcape_axis_validate_request_mux.RECEIVER),
    .out_port(northcape_axis_validate_request.TRANSMITTER)
  );
  
  northcape_capability_resolver#(
    .HASH_TYPE(HASH_TYPE_IDENTITY),
    .HAS_CACHE_INTERFACE(HAS_CACHE_INTERFACE),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH_MASTER),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),
    .FIFO_DEPTH_CLOG_2(FIFO_DEPTH_CLOG_2),
    .CAPABILITY_RESOLVER_RECURSION_DEVICE_ID(2),
    .CACHE_RECURSION_SKIP(1'b1),
    .INPUT_PIPELINE_STAGE_ENABLED(1'b1),
    .PARSER_PIPELINE_STAGE_ENABLED(1'b0),
    .OUTPUT_PIPELINE_STAGE_ENABLED(1'b1)
  )
  i_northcape_capability_resolver (
      .clk_i(clk_i),
      .rst_ni(ndmreset_n),

      .validate_request(northcape_axis_validate_request.RECEIVER),
      .axi_master(northcape_resolver_axi_out),
      .validate_response(northcape_axis_validate_response.TRANSMITTER),
      .validate_request_recursion(northcape_axis_validate_request_mux[2]),

      .cache_interface(resolver_interface),

      
      .cmt_interface(northcape_cmt_interface)
  );

  axi_dw_converter_intf #(
    .AXI_ID_WIDTH(AXI_ID_WIDTH_SLAVE),
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH),
    .AXI_SLV_PORT_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
    .AXI_MST_PORT_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),
    .AXI_MAX_READS(AXI_DW_CONTERTER_MAX_READS)
  )
  i_dw_converter_resolver(
    .clk_i(clk_i),
    .rst_ni(ndmreset_n),
    .slv(ram_bus_slave_resolver),
    .mst(resolver_axi_slave)
  );

  Axis5Demux#(
    .NUMBER_OUT_PORTS(2)
  ) i_demux(
    .in_port(northcape_axis_validate_response.RECEIVER),
    .out_ports(northcape_axis_validate_response_mmu.TRANSMITTER)
  );


  NorthcapeRNGInterface#(.RNG_DATA_WIDTH(NORTHCAPE_CAPABILITY_OPS_RNG_INTERFACE_BITS)) rng_intf(.clk_i(clk_i),.rst_ni(ndmreset_n));

  // RNG
  northcape_rng#(
    .RNG_DATA_WIDTH(NORTHCAPE_CAPABILITY_OPS_RNG_INTERFACE_BITS)
  ) i_rng(
    .intf(rng_intf)
  );

  NorthcapeInterruptInterface #(
      .NUMBER_INTERRUPT_PINS(NORTHCAPE_CAPABILITY_OPS_NUM_IRQS)
  ) irq_interface (
      .clk_i(clk_i)
  );

  // TODO: irq currently not used

  NorthcapeCurrentDeviceTaskInterface current_device_task_interface(.clk_i(clk_i));


  northcape_capability_ops#(
    .HASH_TYPE(HASH_TYPE_IDENTITY),
    .HAS_CACHE_INTERFACE(HAS_CACHE_INTERFACE),

    .AXI_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH_MASTER),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),

    .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
    .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),

    .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
    .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2),
    .OPS_TAG_METHOD(northcape_capability_ops_common::NORTHCAPE_CAPABILITY_OPS_CTR)
  )
  i_northcape_capability_ops (
      .clk_i(clk_i),
      .rst_ni(ndmreset_n),

      .axi_master(northcape_ops_axi_out),
      .axi_slave(northcape_ops_mmio),

      
      .cmt_interface(northcape_cmt_interface),

      .cache_interface(ops_interface),

      .rng_interface(rng_intf),

      .current_device_task_interface(current_device_task_interface),
      .irq_out(irq_interface),
      .csr_req_i(csr_req_i),
      .csr_rsp_o(csr_rsp_o),

      .debug_state_o(/*open*/),
      .debug_is_unlock_o(/*open*/),
      .debug_input_capability_valid_o(/*open*/),
      .debug_update_complete_o(/*open*/),
      .debug_capabilities_valid_o(/*open*/),
      .debug_is_revoke_o(/*open*/),
      .debug_top_state_isr_o(/*open*/)
  );

  assign northcape_cache_flush_o = ops_interface.write_request_flush;

  AXI_LITE#(.AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH),.AXI_DATA_WIDTH(AXI_DATA_WIDTH)) ops_mmio_lite();

  // AXI-LITE does not (always) have user bus
  // so we parse it separately
  northcape_user_parser#(
    .AXI_USER_WIDTH(AXI_USER_WIDTH),
    .PASSTHROUGH_MODE(1'b0)
  ) i_user_parser(
    .clk_i(clk_i),
    .rst_ni(ndmreset_n),

    .s_axi_arvalid(ops_mmio.ar_valid),
    .s_axi_arready(ops_mmio.ar_ready),
    .s_axi_aruser(ops_mmio.ar_user),

    .s_axi_awvalid(ops_mmio.aw_valid),
    .s_axi_awready(ops_mmio.aw_ready),
    .s_axi_awuser(ops_mmio.aw_user),

    .device_task_intf(current_device_task_interface)
  );

  axi_to_axi_lite_intf#(
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH_MASTER),
    .AXI_USER_WIDTH(AXI_USER_WIDTH)
  )
  i_ops_axi_to_axi_lite(
    .clk_i(clk_i),
    .rst_ni(ndmreset_n),
    .testmode_i(0),
    .slv(ops_mmio),
    .mst(ops_mmio_lite)
  );

  `MAP_NORTHCAPE_INTERFACE_TO_ARIANE_INTERFACE(northcape_ops_axi_out,ram_bus_slave_ops)
  `MAP_NORTHCAPE_LITE_INTERFACE_FROM_ARIANE_INTERFACE(ops_mmio_lite, northcape_ops_mmio)

  axi_dw_converter_intf #(
    .AXI_ID_WIDTH(AXI_ID_WIDTH_SLAVE),
    .AXI_ADDR_WIDTH(AXI_ADDRESS_WIDTH),
    .AXI_SLV_PORT_DATA_WIDTH(AXI_DATA_WIDTH_MEM),
    .AXI_MST_PORT_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_USER_WIDTH(AXI_USER_WIDTH),
    .AXI_MAX_READS(AXI_DW_CONTERTER_MAX_READS)
  )
  i_dw_converter_ops(
    .clk_i(clk_i),
    .rst_ni(ndmreset_n),
    .slv(ram_bus_slave_ops),
    .mst(ops_axi_slave)
  );


  `ifdef VERILATOR

    initial begin
      if(AXI_USER_WIDTH < $bits(northcape_axi_user_t))begin
        $display("AXI user width too small: %d bits (need %d bits)!", AXI_USER_WIDTH, $bits(northcape_axi_user_t));
        $stop();
      end
    end

  `endif
endmodule
