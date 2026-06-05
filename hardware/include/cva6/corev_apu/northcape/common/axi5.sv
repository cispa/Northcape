/**
  * Interface and data types for the AXI 5 protocol.
  */

package axi5;

  /// AXI Transaction Burst Type.
  typedef enum logic [1:0] {
    FIXED = 2'b00,
    INCR = 2'b01,
    WRAP = 2'b10,
    BURST_RESERVED = 2'b11
  } axi_burst_t;
  /// AXI Transaction Response Type.
  typedef enum logic [1:0] {
    OKAY   = 2'b00,
    EXOKAY = 2'b01,
    SLVERR = 2'b10,
    DECERR = 2'b11
  } axi_resp_t;
  /// AXI Transaction Cacheability Type.
  typedef logic [3:0] axi_cache_t;
  /// AXI Transaction Protection Type.
  typedef logic [2:0] axi_prot_t;
  /// AXI Transaction Quality of Service Type.
  typedef logic [3:0] axi_qos_t;
  /// AXI Transaction Region Type.
  typedef logic [3:0] axi_region_t;
  /// AXI Transaction Length Type.
  typedef logic [7:0] axi_len_t;
  /// AXI Transaction Size Type.
  typedef logic [2:0] axi_size_t;

  localparam AXI5_MAX_BURST_LEN = 256;

  localparam axi_len_t AXI5_WRAP_VALID_LENGTHS[4] = {8'd1, 8'd3, 8'd7, 8'd15};

  typedef enum logic [1:0] {
    ATOMIC_NONE = 2'b00,
    ATOMIC_STORE = 2'b01,
    ATOMIC_LOAD = 2'b10,
    ATOMIC_SWAP_OR_COMPARE = 2'b11
  } axi_atop_t;

  typedef struct packed {
    axi_atop_t  atop_type;
    logic [3:0] atop_subtype;
  } axi5_atop_t;

  // wrapper for generic functions
  class axi5_address_calculations #(
      parameter int AXI_ADDR_WIDTH = -1
  );

    static function logic [AXI_ADDR_WIDTH - 1:0] axi5_wrapped_burst_get_wrap_mask(
        axi_len_t burst_len, axi_size_t burst_size);
      logic [AXI_ADDR_WIDTH - 1:0] wrap_mask;
      wrap_mask = '1;

      if (burst_len == 1) begin
        wrap_mask = (1 << (burst_size + 1)) - 1;
      end
      if (burst_len == 3) begin
        wrap_mask = (1 << (burst_size + 2)) - 1;
      end
      if (burst_len == 7) begin
        wrap_mask = (1 << (burst_size + 3)) - 1;
      end
      if (burst_len == 15) begin
        wrap_mask = (1 << (burst_size + 4)) - 1;
      end

      return wrap_mask;
    endfunction

    static function logic [AXI_ADDR_WIDTH - 1:0] axi5_wrapped_burst_get_start_address(
        axi_len_t burst_len, axi_size_t burst_size, logic [AXI_ADDR_WIDTH - 1:0] burst_addr);
      logic [AXI_ADDR_WIDTH - 1:0] wrap_address;
      wrap_address = axi5_wrapped_burst_get_wrap_mask(burst_len, burst_size);
      return burst_addr & ~wrap_address;
    endfunction

    static function logic [AXI_ADDR_WIDTH - 1:0] axi5_wrapped_burst_get_end_address(
        axi_len_t burst_len, axi_size_t burst_size, logic [AXI_ADDR_WIDTH - 1:0] burst_addr);
      logic [AXI_ADDR_WIDTH - 1:0] wrap_address;
      wrap_address = axi5_wrapped_burst_get_wrap_mask(burst_len, burst_size);
      return burst_addr | wrap_address;
    endfunction

  endclass


endpackage : axi5
/// interfaces cannot be defined in modules...

interface Axi5Lite #(
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ADDR_WIDTH = -1
) (
    input logic clk_i,
    input logic rst_ni
);
  // address write (AW) chan
  logic                                         awvalid;
  logic                                         awready;
  logic            [    AXI_ADDR_WIDTH - 1 : 0] awaddr;
  logic            [                       2:0] awprot;

  // write data (wd) chan
  logic                                         wvalid;
  logic                                         wready;
  logic            [    AXI_DATA_WIDTH - 1 : 0] wdata;
  logic            [AXI_DATA_WIDTH / 8 - 1 : 0] wstrb;

  // write response (b) chan
  logic                                         bvalid;
  logic                                         bready;
  axi5::axi_resp_t                              bresp;

  // address read (AR) chan
  logic                                         arvalid;
  logic                                         arready;
  logic            [    AXI_ADDR_WIDTH - 1 : 0] araddr;
  logic            [                       2:0] arprot;

  // read data (d) chan
  logic                                         rvalid;
  logic                                         rready;
  logic            [    AXI_DATA_WIDTH - 1 : 0] rdata;
  axi5::axi_resp_t                              rresp;

  modport FROM(
      input clk_i, rst_ni, awready, wready, bvalid, bresp, arready, rvalid, rdata, rresp,
      output awvalid, awaddr, awprot, wvalid, wdata, wstrb, bready, arvalid, araddr, arprot, rready
  );
  modport TO(
      output awready, wready, bvalid, bresp, arready, rvalid, rdata, rresp,
      input clk_i, rst_ni, awvalid, awaddr, awprot, wvalid, wdata, wstrb, bready, arvalid, araddr, arprot, rready
  );

`ifndef VERILATOR
  // TODO not supported
  clocking transmitter_clocking @(posedge (clk_i));
    input awready;
    input wready;
    input bvalid;
    input bresp;
    input arready;
    input rvalid;
    input rdata;
    input rresp;
    output awvalid;
    output awaddr;
    output awprot;
    output wvalid;
    output wdata;
    output wstrb;
    output bready;
    output arvalid;
    output araddr;
    output arprot;
    output rready;
  endclocking

  modport TEST(clocking transmitter_clocking, input rst_ni);

  task perform_write(input logic [AXI_ADDR_WIDTH - 1 : 0] awaddr,
                     input logic [AXI_DATA_WIDTH - 1 : 0] wdata,
                     input logic [AXI_DATA_WIDTH/8 - 1 : 0] wstrb, output axi5::axi_resp_t bresp,
                     logic [2:0] awprot);
    @(transmitter_clocking);
    transmitter_clocking.awaddr  <= awaddr;
    transmitter_clocking.awprot  <= awprot;
    transmitter_clocking.awvalid <= 1;

    transmitter_clocking.wdata   <= wdata;
    transmitter_clocking.wstrb   <= wstrb;
    transmitter_clocking.wvalid  <= 1;

    @(transmitter_clocking.awready or transmitter_clocking.wready);

    if (transmitter_clocking.awready) begin
      transmitter_clocking.awvalid <= 0;
      if (transmitter_clocking.wready != 1'b1) begin
        @(transmitter_clocking.wready);
      end
    end

    if (transmitter_clocking.wready) begin
      transmitter_clocking.wvalid <= 0;
    end

    transmitter_clocking.bready <= 1;

    if (transmitter_clocking.bvalid != 1'b1) begin
      @(transmitter_clocking.bvalid);
    end else begin
      // DUT must see the ready signal for one clock
      @(transmitter_clocking);
    end

    transmitter_clocking.bready <= 0;

    bresp = transmitter_clocking.bresp;
  endtask
`endif

endinterface

interface Axi5 #(
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH   = -1,
    parameter AXI_USER_WIDTH = -1   // unused by default
) (
    input logic clk_i,
    input logic rst_ni
);
  // read address channel
  logic              [    AXI_ID_WIDTH-1:0] arid;
  logic              [  AXI_ADDR_WIDTH-1:0] araddr;
  axi5::axi_len_t                           arlen;
  axi5::axi_size_t                          arsize;
  axi5::axi_burst_t                         arburst;
  logic                                     arlock;
  axi5::axi_cache_t                         arcache;
  axi5::axi_prot_t                          arprot;
  axi5::axi_qos_t                           arqos;
  axi5::axi_region_t                        arregion;
  logic              [  AXI_USER_WIDTH-1:0] aruser;
  logic                                     arvalid;
  logic                                     arready;
  // write atomic channel
  axi5::axi_atop_t                          atop_type;
  logic              [                 3:0] atop_subtype;

  // write address channel
  logic              [    AXI_ID_WIDTH-1:0] awid;
  logic              [  AXI_ADDR_WIDTH-1:0] awaddr;
  axi5::axi_len_t                           awlen;
  axi5::axi_size_t                          awsize;
  axi5::axi_burst_t                         awburst;
  logic                                     awlock;
  axi5::axi_cache_t                         awcache;
  axi5::axi_prot_t                          awprot;
  axi5::axi_qos_t                           awqos;
  axi5::axi_region_t                        awregion;
  logic              [  AXI_USER_WIDTH-1:0] awuser;
  logic                                     awvalid;
  logic                                     awready;


  // write data channel
  // AXI3 bw compatibility only
  logic              [    AXI_ID_WIDTH-1:0] wid;
  logic              [  AXI_DATA_WIDTH-1:0] wdata;
  logic              [AXI_DATA_WIDTH/8-1:0] wstrb;
  logic                                     wlast;
  logic              [  AXI_USER_WIDTH-1:0] wuser;
  logic                                     wvalid;
  logic                                     wready;

  // read data channel
  // AXI3 bw compatibility only
  logic              [    AXI_ID_WIDTH-1:0] rid;
  logic              [  AXI_DATA_WIDTH-1:0] rdata;
  axi5::axi_resp_t                          rresp;
  logic                                     rlast;
  logic              [  AXI_USER_WIDTH-1:0] ruser;
  logic                                     rvalid;
  logic                                     rready;

  // write response (b) channel
  logic              [    AXI_ID_WIDTH-1:0] bid;
  axi5::axi_resp_t                          bresp;
  logic              [  AXI_USER_WIDTH-1:0] buser;
  logic                                     bvalid;
  logic                                     bready;

  modport FROM(
      input clk_i, rst_ni,
      input arready,
      output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion, aruser, arvalid,
      input awready,
      output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion, awuser, awvalid, atop_type, atop_subtype,
      output rready,
      input rid, rdata, rresp, rlast, ruser, rvalid,
      input wready,
      output wid, wdata, wstrb, wlast, wuser, wvalid,
      output bready,
      input bid, bresp, buser, bvalid
  );
  modport TO(
      input clk_i, rst_ni,
      output arready,
      input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion, aruser, arvalid,
      output awready,
      input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion, awuser, awvalid, atop_type, atop_subtype,
      input rready,
      output rid, rdata, rresp, rlast, ruser, rvalid,
      output wready,
      input wid, wdata, wstrb, wlast, wuser, wvalid,
      input bready,
      output bid, bresp, buser, bvalid
  );
endinterface


interface Axi5ReadOnly #(
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH   = -1,
    parameter AXI_USER_WIDTH = -1   // unused by default
) (
    input logic clk_i,
    input logic rst_ni
);

  // read address channel
  logic              [  AXI_ID_WIDTH-1:0] arid;
  logic              [AXI_ADDR_WIDTH-1:0] araddr;
  axi5::axi_len_t                         arlen;
  axi5::axi_size_t                        arsize;
  axi5::axi_burst_t                       arburst;
  logic                                   arlock;
  axi5::axi_cache_t                       arcache;
  axi5::axi_prot_t                        arprot;
  axi5::axi_qos_t                         arqos;
  axi5::axi_region_t                      arregion;
  logic              [AXI_USER_WIDTH-1:0] aruser;
  logic                                   arvalid;
  logic                                   arready;

  // read data channel
  // AXI3 bw compatibility only
  logic              [  AXI_ID_WIDTH-1:0] rid;
  logic              [AXI_DATA_WIDTH-1:0] rdata;
  axi5::axi_resp_t                        rresp;
  logic                                   rlast;
  logic              [AXI_USER_WIDTH-1:0] ruser;
  logic                                   rvalid;
  logic                                   rready;

  modport FROM(
      input clk_i, rst_ni,
      input arready,
      output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion, aruser, arvalid,
      output rready,
      input rid, rdata, rresp, rlast, ruser, rvalid
  );
  modport TO(
      input clk_i, rst_ni,
      output arready,
      input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion, aruser, arvalid,
      input rready,
      output rid, rdata, rresp, rlast, ruser, rvalid
  );
endinterface


interface Axi5WriteOnly #(
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter AXI_ID_WIDTH   = -1,
    parameter AXI_USER_WIDTH = -1   // unused by default
) (
    input logic clk_i,
    input logic rst_ni
);
  // write atomic channel
  axi5::axi_atop_t                          atop_type;
  logic              [                 3:0] atop_subtype;

  // write address channel
  logic              [    AXI_ID_WIDTH-1:0] awid;
  logic              [  AXI_ADDR_WIDTH-1:0] awaddr;
  axi5::axi_len_t                           awlen;
  axi5::axi_size_t                          awsize;
  axi5::axi_burst_t                         awburst;
  logic                                     awlock;
  axi5::axi_cache_t                         awcache;
  axi5::axi_prot_t                          awprot;
  axi5::axi_qos_t                           awqos;
  axi5::axi_region_t                        awregion;
  logic              [  AXI_USER_WIDTH-1:0] awuser;
  logic                                     awvalid;
  logic                                     awready;


  // write data channel
  // AXI3 bw compatibility only
  logic              [    AXI_ID_WIDTH-1:0] wid;
  logic              [  AXI_DATA_WIDTH-1:0] wdata;
  logic              [AXI_DATA_WIDTH/8-1:0] wstrb;
  logic                                     wlast;
  logic              [  AXI_USER_WIDTH-1:0] wuser;
  logic                                     wvalid;
  logic                                     wready;

  // write response (b) channel
  logic              [    AXI_ID_WIDTH-1:0] bid;
  axi5::axi_resp_t                          bresp;
  logic              [  AXI_USER_WIDTH-1:0] buser;
  logic                                     bvalid;
  logic                                     bready;

  modport FROM(
      input clk_i, rst_ni,
      input awready,
      output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion, awuser, awvalid, atop_type, atop_subtype,
      input wready,
      output wid, wdata, wstrb, wlast, wuser, wvalid,
      output bready,
      input bid, bresp, buser, bvalid
  );
  modport TO(
      input clk_i, rst_ni,
      output awready,
      input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion, awuser, awvalid, atop_type, atop_subtype,
      output wready,
      input wid, wdata, wstrb, wlast, wuser, wvalid,
      input bready,
      output bid, bresp, buser, bvalid
  );
endinterface
