/**
  * Wrapper macros for assigning Northcape AXI5 interfaces to/from individual signals, named according to Xilinx conventions.
  */
/* verilog_format: off */
`define NORTHCAPE_MAP_XILINX_AXI_INTERFACES_IN(NORTHCAPE_IN_PREFIX, IN_PORT_PREFIX) \
/* verilog_format: on */  \
  /*  read address channel */                                                                                         \
  assign ``NORTHCAPE_IN_PREFIX``.arid = ``IN_PORT_PREFIX``_arid;                                           \
  assign ``NORTHCAPE_IN_PREFIX``.araddr = ``IN_PORT_PREFIX``_araddr;                                        \
  assign ``NORTHCAPE_IN_PREFIX``.arlen = ``IN_PORT_PREFIX``_arlen;                                          \
  assign ``NORTHCAPE_IN_PREFIX``.arsize = ``IN_PORT_PREFIX``_arsize;                                        \
  assign ``NORTHCAPE_IN_PREFIX``.arlock = ``IN_PORT_PREFIX``_arlock;                                        \
  assign ``NORTHCAPE_IN_PREFIX``.arcache = ``IN_PORT_PREFIX``_arcache;                                      \
  assign ``NORTHCAPE_IN_PREFIX``.arprot = ``IN_PORT_PREFIX``_arprot;                                         \
  assign ``NORTHCAPE_IN_PREFIX``.arqos = ``IN_PORT_PREFIX``_arqos;                                         \
  assign ``NORTHCAPE_IN_PREFIX``.arregion = ``IN_PORT_PREFIX``_arregion;                                    \
  assign ``NORTHCAPE_IN_PREFIX``.aruser = ``IN_PORT_PREFIX``_aruser;                                        \
                                                                                                                     \
  /*  mismatching types of enum... */                                                                                \
  always_comb begin: burstEnumMapperReadSlave                                                                        \
    unique case(``IN_PORT_PREFIX``_arburst)                                                                        \
      2'b00:                                                                                                            \
        ``NORTHCAPE_IN_PREFIX``.arburst = FIXED;                                                            \
      2'b01:                                                                                                        \
        ``NORTHCAPE_IN_PREFIX``.arburst = INCR;                                                             \
      2'b10:                                                                                                        \
        ``NORTHCAPE_IN_PREFIX``.arburst = WRAP;                                                             \
      default:                                                                                                       \
        ``NORTHCAPE_IN_PREFIX``.arburst = BURST_RESERVED;                                                   \
    endcase                                                                                                          \
  end: burstEnumMapperReadSlave                                                                                      \
                                                                                                                     \
  /*  read address handshaking */                                                                                    \
  assign ``NORTHCAPE_IN_PREFIX``.arvalid = ``IN_PORT_PREFIX``_arvalid;                                  \
  assign ``IN_PORT_PREFIX``_arready = ``NORTHCAPE_IN_PREFIX``.arready;                                 \
                                                                                                                     \
  /*  read data channel */                                                                                           \
  assign ``IN_PORT_PREFIX``_rid = ``NORTHCAPE_IN_PREFIX``.rid;                                        \
  assign ``IN_PORT_PREFIX``_rdata = ``NORTHCAPE_IN_PREFIX``.rdata;                                    \
  assign ``IN_PORT_PREFIX``_rresp = ``NORTHCAPE_IN_PREFIX``.rresp;                                    \
  assign ``IN_PORT_PREFIX``_rlast = ``NORTHCAPE_IN_PREFIX``.rlast;                                    \
  assign ``IN_PORT_PREFIX``_ruser = ``NORTHCAPE_IN_PREFIX``.ruser;                                    \
                                                                                                                     \
  /*  read data handshaking */                                                                                       \
  assign ``NORTHCAPE_IN_PREFIX``.rready = ``IN_PORT_PREFIX``_rready;                                   \
  assign ``IN_PORT_PREFIX``_rvalid = ``NORTHCAPE_IN_PREFIX``.rvalid;                                  \
                                                                                                                     \
  /*  write address channel */                                                                                       \
  assign ``NORTHCAPE_IN_PREFIX``.awid = ``IN_PORT_PREFIX``_awid;                                        \
  assign ``NORTHCAPE_IN_PREFIX``.awaddr = ``IN_PORT_PREFIX``_awaddr;                                    \
  assign ``NORTHCAPE_IN_PREFIX``.awlen = ``IN_PORT_PREFIX``_awlen;                                      \
  assign ``NORTHCAPE_IN_PREFIX``.awsize = ``IN_PORT_PREFIX``_awsize;                                    \
  assign ``NORTHCAPE_IN_PREFIX``.awlock = ``IN_PORT_PREFIX``_awlock;                                    \
  assign ``NORTHCAPE_IN_PREFIX``.awcache = ``IN_PORT_PREFIX``_awcache;                                  \
  assign ``NORTHCAPE_IN_PREFIX``.awprot = ``IN_PORT_PREFIX``_awprot;                                     \
  assign ``NORTHCAPE_IN_PREFIX``.awqos = ``IN_PORT_PREFIX``_awqos;                                     \
  assign ``NORTHCAPE_IN_PREFIX``.awregion = ``IN_PORT_PREFIX``_awregion;                                \
  assign ``NORTHCAPE_IN_PREFIX``.awuser = ``IN_PORT_PREFIX``_awuser;                                    \
                                                                                                                     \
  always_comb begin: burstEnumMapperWriteSlave                                                                       \
    unique case(``IN_PORT_PREFIX``_awburst)                                                                      \
      2'b00:                                                                                                   \
        ``NORTHCAPE_IN_PREFIX``.awburst = FIXED;                                                            \
      2'b01:                                                                                                    \
        ``NORTHCAPE_IN_PREFIX``.awburst = INCR;                                                             \
      2'b10:                                                                                                    \
        ``NORTHCAPE_IN_PREFIX``.awburst = WRAP;                                                             \
      default:                                                                                                       \
        ``NORTHCAPE_IN_PREFIX``.awburst = BURST_RESERVED;                                                   \
    endcase                                                                                                          \
  end: burstEnumMapperWriteSlave                                                                                     \
                                                                                                                     \
  /*  write address handshaking */                                                                                   \
  assign ``NORTHCAPE_IN_PREFIX``.awvalid = ``IN_PORT_PREFIX``_awvalid;                                  \
  assign ``IN_PORT_PREFIX``_awready = ``NORTHCAPE_IN_PREFIX``.awready;                                 \
                                                                                                                     \
  /*  write data channel */                                                                                          \
  assign ``NORTHCAPE_IN_PREFIX``.wstrb = ``IN_PORT_PREFIX``_wstrb;                                     \
  assign ``NORTHCAPE_IN_PREFIX``.wlast = ``IN_PORT_PREFIX``_wlast;                                     \
  assign ``NORTHCAPE_IN_PREFIX``.wuser = ``IN_PORT_PREFIX``_wuser;                                     \
  assign ``NORTHCAPE_IN_PREFIX``.wdata = ``IN_PORT_PREFIX``_wdata;                                     \
  assign ``NORTHCAPE_IN_PREFIX``.wid = '0;                                     \
                                                                                                                     \
  assign ``NORTHCAPE_IN_PREFIX``.atop_subtype = ``IN_PORT_PREFIX``_awatop[3:0];                        \
                                                                                                                     \
  always_comb begin: atopEnumWrapperSlave                                                                            \
  unique case(``IN_PORT_PREFIX``_awatop[5:4])                                                                    \
    2'b00:                                                                                                           \
      ``NORTHCAPE_IN_PREFIX``.atop_type = ATOMIC_NONE;                                                     \
    2'b01:                                                                                                           \
      ``NORTHCAPE_IN_PREFIX``.atop_type = ATOMIC_STORE;                                                    \
    2'b10:                                                                                                           \
      ``NORTHCAPE_IN_PREFIX``.atop_type = ATOMIC_LOAD;                                                     \
    2'b11:                                                                                                           \
      ``NORTHCAPE_IN_PREFIX``.atop_type = ATOMIC_SWAP_OR_COMPARE;                                          \
    default:                                                                                                         \
      ``NORTHCAPE_IN_PREFIX``.atop_type = ATOMIC_NONE; /* Z or X, simulation only*/                        \
  endcase                                                                                                            \
  end: atopEnumWrapperSlave                                                                                          \
                                                                                                                     \
  /*  write data handshaking */                                                                                      \
  assign ``NORTHCAPE_IN_PREFIX``.wvalid = ``IN_PORT_PREFIX``_wvalid;                                   \
  assign ``IN_PORT_PREFIX``_wready = ``NORTHCAPE_IN_PREFIX``.wready;                                  \
                                                                                                                     \
  /*  write response channel */                                                                                      \
  assign ``IN_PORT_PREFIX``_bid = ``NORTHCAPE_IN_PREFIX``.bid;                                        \
  assign ``IN_PORT_PREFIX``_bresp = ``NORTHCAPE_IN_PREFIX``.bresp;                                    \
  assign ``IN_PORT_PREFIX``_buser = ``NORTHCAPE_IN_PREFIX``.buser;                                    \
                                                                                                                     \
  /*  write response handshaking */                                                                                  \
  assign ``NORTHCAPE_IN_PREFIX``.bready = ``IN_PORT_PREFIX``_bready;                                   \
  assign ``IN_PORT_PREFIX``_bvalid = ``NORTHCAPE_IN_PREFIX``.bvalid;                                  

/* verilog_format: off */
`define NORTHCAPE_MAP_XILINX_AXI_INTERFACES_OUT(NORTHCAPE_OUT_PREFIX, OUT_PORT_PREFIX) \
/* verilog_format: on */ \
                                                                                                                      \
                                                                                                                     \
  /*  assignments to MASTER side of the MMU */                                                                       \
                                                                                                                     \
  /*  read address channel */                                                                                        \
  assign ``OUT_PORT_PREFIX``_arid = ``NORTHCAPE_OUT_PREFIX``.arid;                                           \
  assign ``OUT_PORT_PREFIX``_araddr = ``NORTHCAPE_OUT_PREFIX``.araddr;                                       \
  assign ``OUT_PORT_PREFIX``_arlen = ``NORTHCAPE_OUT_PREFIX``.arlen;                                         \
  assign ``OUT_PORT_PREFIX``_arsize = ``NORTHCAPE_OUT_PREFIX``.arsize;                                       \
  assign ``OUT_PORT_PREFIX``_arlock = ``NORTHCAPE_OUT_PREFIX``.arlock;                                       \
  assign ``OUT_PORT_PREFIX``_arcache = ``NORTHCAPE_OUT_PREFIX``.arcache;                                     \
  assign ``OUT_PORT_PREFIX``_arqos = ``NORTHCAPE_OUT_PREFIX``.arqos;                                        \
  assign ``OUT_PORT_PREFIX``_arprot = ``NORTHCAPE_OUT_PREFIX``.arprot;                                        \
  assign ``OUT_PORT_PREFIX``_arregion = ``NORTHCAPE_OUT_PREFIX``.arregion;                                   \
  assign ``OUT_PORT_PREFIX``_aruser = ``NORTHCAPE_OUT_PREFIX``.aruser;                                       \
                                                                                                                     \
  /* This might be a wire type, for which always_comb does not work... */  \
  assign ``OUT_PORT_PREFIX``_arburst = (``NORTHCAPE_OUT_PREFIX``.arburst == FIXED) ? 2'b00 : ((``NORTHCAPE_OUT_PREFIX``.arburst == INCR) ? 2'b01 : ((``NORTHCAPE_OUT_PREFIX``.arburst == WRAP) ? 2'b10 : 2'b11)); \
  /*  read address handshaking */                                                                                    \
  assign ``OUT_PORT_PREFIX``_arvalid = ``NORTHCAPE_OUT_PREFIX``.arvalid;                                     \
  assign ``NORTHCAPE_OUT_PREFIX``.arready = ``OUT_PORT_PREFIX``_arready;                                     \
                                                                                                                     \
  /*  read data channel */                                                                                           \
  assign ``NORTHCAPE_OUT_PREFIX``.rid = ``OUT_PORT_PREFIX``_rid;                                            \
  assign ``NORTHCAPE_OUT_PREFIX``.rdata = ``OUT_PORT_PREFIX``_rdata;                                        \
  assign ``NORTHCAPE_OUT_PREFIX``.rlast = ``OUT_PORT_PREFIX``_rlast;                                        \
  assign ``NORTHCAPE_OUT_PREFIX``.ruser = ``OUT_PORT_PREFIX``_ruser;                                        \
                                                                                                                     \
  /*  mismatching types of enum... */                                                                                \
  always_comb begin: ``NORTHCAPE_OUT_PREFIX``_respEnumMapperRead                                                                              \
    unique case(``OUT_PORT_PREFIX``_rresp)                                                                            \
      2'b00:                                                                                                     \
        ``NORTHCAPE_OUT_PREFIX``.rresp = OKAY;                                                             \
      2'b01:                                                                                                   \
        ``NORTHCAPE_OUT_PREFIX``.rresp = EXOKAY;                                                           \
      2'b11:                                                                                                   \
        ``NORTHCAPE_OUT_PREFIX``.rresp = DECERR;                                                           \
      default:                                                                                                   \
        ``NORTHCAPE_OUT_PREFIX``.rresp = SLVERR;                                                           \
    endcase                                                                                                          \
  end: ``NORTHCAPE_OUT_PREFIX``_respEnumMapperRead                                                                                            \
                                                                                                                     \
  /*  read data handshaking */                                                                                       \
  assign ``OUT_PORT_PREFIX``_rready = ``NORTHCAPE_OUT_PREFIX``.rready;                                      \
  assign ``NORTHCAPE_OUT_PREFIX``.rvalid = ``OUT_PORT_PREFIX``_rvalid;                                      \
                                                                                                                     \
  /*  write address channel */                                                                                       \
  assign ``OUT_PORT_PREFIX``_awid = ``NORTHCAPE_OUT_PREFIX``.awid;                                           \
  assign ``OUT_PORT_PREFIX``_awaddr = ``NORTHCAPE_OUT_PREFIX``.awaddr;                                       \
  assign ``OUT_PORT_PREFIX``_awlen = ``NORTHCAPE_OUT_PREFIX``.awlen;                                         \
  assign ``OUT_PORT_PREFIX``_awsize = ``NORTHCAPE_OUT_PREFIX``.awsize;                                       \
  assign ``OUT_PORT_PREFIX``_awlock = ``NORTHCAPE_OUT_PREFIX``.awlock;                                       \
  assign ``OUT_PORT_PREFIX``_awcache = ``NORTHCAPE_OUT_PREFIX``.awcache;                                     \
  assign ``OUT_PORT_PREFIX``_awqos = ``NORTHCAPE_OUT_PREFIX``.awqos;                                        \
  assign ``OUT_PORT_PREFIX``_awprot = ``NORTHCAPE_OUT_PREFIX``.awprot;                                        \
  assign ``OUT_PORT_PREFIX``_awregion = ``NORTHCAPE_OUT_PREFIX``.awregion;                                   \
  assign ``OUT_PORT_PREFIX``_awuser = ``NORTHCAPE_OUT_PREFIX``.awuser;                                       \
  assign ``OUT_PORT_PREFIX``_awatop = { ``NORTHCAPE_OUT_PREFIX``.atop_type, ``NORTHCAPE_OUT_PREFIX``.atop_subtype } ;                                             \
                                                                                                                     \
  /*  this might be a wire, for which always_comb does not work */                                                   \
  assign ``OUT_PORT_PREFIX``_awburst = (``NORTHCAPE_OUT_PREFIX``.awburst == FIXED) ? 2'b00 : ((``NORTHCAPE_OUT_PREFIX``.awburst == INCR) ? 2'b01 : ((``NORTHCAPE_OUT_PREFIX``.awburst == WRAP) ? 2'b10 : 2'b11)); \
  /*  write address handshaking */                                                                                   \
  assign ``OUT_PORT_PREFIX``_awvalid = ``NORTHCAPE_OUT_PREFIX``.awvalid;                                     \
  assign ``NORTHCAPE_OUT_PREFIX``.awready = ``OUT_PORT_PREFIX``_awready;                                     \
                                                                                                                     \
  /*  write data channel */                                                                                          \
  assign ``OUT_PORT_PREFIX``_wstrb = ``NORTHCAPE_OUT_PREFIX``.wstrb;                                        \
  assign ``OUT_PORT_PREFIX``_wlast = ``NORTHCAPE_OUT_PREFIX``.wlast;                                        \
  assign ``OUT_PORT_PREFIX``_wuser = ``NORTHCAPE_OUT_PREFIX``.wuser;                                        \
  assign ``OUT_PORT_PREFIX``_wdata = ``NORTHCAPE_OUT_PREFIX``.wdata;                                        \
                                                                                                                     \
  /*  write data handshaking */                                                                                      \
  assign ``OUT_PORT_PREFIX``_wvalid = ``NORTHCAPE_OUT_PREFIX``.wvalid;                                      \
  assign ``NORTHCAPE_OUT_PREFIX``.wready = ``OUT_PORT_PREFIX``_wready;                                      \
                                                                                                                     \
                                                                                                                     \
  /*  write response channel */                                                                                      \
  assign ``NORTHCAPE_OUT_PREFIX``.bid = ``OUT_PORT_PREFIX``_bid;                                            \
  assign ``NORTHCAPE_OUT_PREFIX``.buser = ``OUT_PORT_PREFIX``_buser;                                        \
                                                                                                                     \
  /*  mismatching types of enum... */                                                                                \
  always_comb begin: ``NORTHCAPE_OUT_PREFIX``_respEnumMapperWrite                                                                             \
    unique case(``OUT_PORT_PREFIX``_bresp)                                                                            \
      2'b00:                                                                                                     \
        ``NORTHCAPE_OUT_PREFIX``.bresp = OKAY;                                                             \
      2'b01:                                                                                                   \
        ``NORTHCAPE_OUT_PREFIX``.bresp = EXOKAY;                                                           \
      2'b11:                                                                                                   \
        ``NORTHCAPE_OUT_PREFIX``.bresp = DECERR;                                                           \
      default:                                                                                                   \
        ``NORTHCAPE_OUT_PREFIX``.bresp = SLVERR;                                                           \
    endcase                                                                                                          \
  end: ``NORTHCAPE_OUT_PREFIX``_respEnumMapperWrite                                                                                           \
                                                                                                                     \
  /*  write response handshaking */                                                                                  \
  assign ``OUT_PORT_PREFIX``_bready = ``NORTHCAPE_OUT_PREFIX``.bready;                                      \
  assign ``NORTHCAPE_OUT_PREFIX``.bvalid = ``OUT_PORT_PREFIX``_bvalid;                                      


/* verilog_format: off */
`define NORTHCAPE_MAP_XILINX_AXI_INTERFACES(NORTHCAPE_IN_PREFIX, NORTHCAPE_OUT_PREFIX, IN_PORT_PREFIX, OUT_PORT_PREFIX)  \
/* verilog_format: on */  \
    /* assignments to SLAVE side of the MMU */                                                                        \
    `NORTHCAPE_MAP_XILINX_AXI_INTERFACES_IN(NORTHCAPE_IN_PREFIX, IN_PORT_PREFIX)                                      \
    `NORTHCAPE_MAP_XILINX_AXI_INTERFACES_OUT(NORTHCAPE_OUT_PREFIX, OUT_PORT_PREFIX)                                      \

`define NORTHCAPE_MAP_XILINX_AXIS_IN_INTERFACES(NORTHCAPE_PREFIX, XILINX_PREFIX) \
    assign ``NORTHCAPE_PREFIX``.tvalid = ``XILINX_PREFIX``_tvalid; \
    assign ``NORTHCAPE_PREFIX``.tdata = ``XILINX_PREFIX``_tdata; \
    assign ``NORTHCAPE_PREFIX``.tstrb = ``XILINX_PREFIX``_tstrb; \
    assign ``NORTHCAPE_PREFIX``.tkeep = ``XILINX_PREFIX``_tkeep; \
    assign ``NORTHCAPE_PREFIX``.tlast = ``XILINX_PREFIX``_tlast; \
    assign ``NORTHCAPE_PREFIX``.tid = ``XILINX_PREFIX``_tid; \
    assign ``NORTHCAPE_PREFIX``.tdest = ``XILINX_PREFIX``_tdest; \
    assign ``NORTHCAPE_PREFIX``.tuser = ``XILINX_PREFIX``_tuser; \
    assign ``NORTHCAPE_PREFIX``.twakeup = ``XILINX_PREFIX``_twakeup; \
    assign ``XILINX_PREFIX``_tready = ``NORTHCAPE_PREFIX``.tready;

`define NORTHCAPE_MAP_XILINX_AXIS_OUT_INTERFACES(NORTHCAPE_PREFIX, XILINX_PREFIX) \
    assign ``XILINX_PREFIX``_tvalid = ``NORTHCAPE_PREFIX``.tvalid; \
    assign ``XILINX_PREFIX``_tdata = ``NORTHCAPE_PREFIX``.tdata; \
    assign ``XILINX_PREFIX``_tstrb = ``NORTHCAPE_PREFIX``.tstrb; \
    assign ``XILINX_PREFIX``_tkeep = ``NORTHCAPE_PREFIX``.tkeep; \
    assign ``XILINX_PREFIX``_tlast = ``NORTHCAPE_PREFIX``.tlast; \
    assign ``XILINX_PREFIX``_tid = ``NORTHCAPE_PREFIX``.tid; \
    assign ``XILINX_PREFIX``_tdest = ``NORTHCAPE_PREFIX``.tdest; \
    assign ``XILINX_PREFIX``_tuser = ``NORTHCAPE_PREFIX``.tuser; \
    assign ``XILINX_PREFIX``_twakeup = ``NORTHCAPE_PREFIX``.twakeup; \
    assign ``NORTHCAPE_PREFIX``.tready = ``XILINX_PREFIX``_tready;

`define NORTHCAPE_MAP_FROM_XILINX_AXI_LITE_INTERFACE(NORTHCAPE_PREFIX, XILINX_PREFIX) \
  assign ``NORTHCAPE_PREFIX``.awvalid = ``XILINX_PREFIX``_AWVALID; \
  assign ``XILINX_PREFIX``_AWREADY = ``NORTHCAPE_PREFIX``.awready; \
  assign ``NORTHCAPE_PREFIX``.awaddr = ``XILINX_PREFIX``_AWADDR; \
  assign ``NORTHCAPE_PREFIX``.awprot = ``XILINX_PREFIX``_AWPROT; \
  \
  assign ``NORTHCAPE_PREFIX``.wvalid = ``XILINX_PREFIX``_WVALID; \
  assign ``XILINX_PREFIX``_WREADY = ``NORTHCAPE_PREFIX``.wready; \
  assign ``NORTHCAPE_PREFIX``.wdata = ``XILINX_PREFIX``_WDATA; \
  assign ``NORTHCAPE_PREFIX``.wstrb = ``XILINX_PREFIX``_WSTRB; \
  \
  assign ``XILINX_PREFIX``_BVALID = ``NORTHCAPE_PREFIX``.bvalid; \
  assign ``NORTHCAPE_PREFIX``.bready = ``XILINX_PREFIX``_BREADY ; \
  assign ``XILINX_PREFIX``_BRESP = ``NORTHCAPE_PREFIX``.bresp; \
  \
  assign ``NORTHCAPE_PREFIX``.arvalid = ``XILINX_PREFIX``_ARVALID; \
  assign ``XILINX_PREFIX``_ARREADY = ``NORTHCAPE_PREFIX``.arready; \
  assign ``NORTHCAPE_PREFIX``.araddr = ``XILINX_PREFIX``_ARADDR; \
  assign ``NORTHCAPE_PREFIX``.arprot = ``XILINX_PREFIX``_ARPROT; \
  \
  assign ``XILINX_PREFIX``_RVALID = ``NORTHCAPE_PREFIX``.rvalid; \
  assign ``NORTHCAPE_PREFIX``.rready = ``XILINX_PREFIX``_RREADY; \
  assign ``XILINX_PREFIX``_RDATA = ``NORTHCAPE_PREFIX``.rdata; \
  assign ``XILINX_PREFIX``_RRESP = ``NORTHCAPE_PREFIX``.rresp; 

`define NORTHCAPE_MAP_TO_XILINX_AXI_LITE_INTERFACE(NORTHCAPE_PREFIX, XILINX_PREFIX) \
  assign ``XILINX_PREFIX``_AWVALID = ``NORTHCAPE_PREFIX``.awvalid; \
  assign ``NORTHCAPE_PREFIX``.awready = ``XILINX_PREFIX``_AWREADY; \
  assign ``XILINX_PREFIX``_AWADDR = ``NORTHCAPE_PREFIX``.awaddr; \
  assign ``XILINX_PREFIX``_AWPROT = ``NORTHCAPE_PREFIX``.awprot; \
  \
  assign ``XILINX_PREFIX``_WVALID = ``NORTHCAPE_PREFIX``.wvalid; \
  assign ``NORTHCAPE_PREFIX``.wready = ``XILINX_PREFIX``_WREADY; \
  assign ``XILINX_PREFIX``_WDATA = ``NORTHCAPE_PREFIX``.wdata; \
  assign ``XILINX_PREFIX``_WSTRB = ``NORTHCAPE_PREFIX``.wstrb; \
  \
  assign ``NORTHCAPE_PREFIX``.bvalid = ``XILINX_PREFIX``_BVALID ; \
  assign ``XILINX_PREFIX``_BREADY = ``NORTHCAPE_PREFIX``.bready ; \
  assign ``NORTHCAPE_PREFIX``.bresp = ``XILINX_PREFIX``_BRESP; \
  \
  assign ``XILINX_PREFIX``_ARVALID = ``NORTHCAPE_PREFIX``.arvalid; \
  assign ``NORTHCAPE_PREFIX``.arready = ``XILINX_PREFIX``_ARREADY; \
  assign ``XILINX_PREFIX``_ARADDR = ``NORTHCAPE_PREFIX``.araddr; \
  assign ``XILINX_PREFIX``_ARPROT = ``NORTHCAPE_PREFIX``.arprot; \
  \
  assign ``NORTHCAPE_PREFIX``.rvalid = ``XILINX_PREFIX``_RVALID; \
  assign ``XILINX_PREFIX``_RREADY = ``NORTHCAPE_PREFIX``.rready; \
  assign ``NORTHCAPE_PREFIX``.rdata = ``XILINX_PREFIX``_RDATA; \
  assign ``NORTHCAPE_PREFIX``.rresp = ``XILINX_PREFIX``_RRESP;


`define AXI_LITE_INTERFACE_MODULE_DECLARATION(name)    \
    /* AW Channel  */ \
    logic [AXI_LITE_ADDR_WIDTH - 1 : 0] ``name``_AWADDR; \
    logic [2:0] ``name``_AWPROT; \
    logic  ``name``_AWVALID; \
    logic  ``name``_AWREADY; \
    /* W Channel */\
    logic [AXI_DATA_WIDTH - 1 : 0] ``name``_WDATA; \
    logic [AXI_DATA_WIDTH/8 - 1 : 0] ``name``_WSTRB; \
    logic ``name``_WVALID; \
    logic ``name``_WREADY; \
    /* B Channel */\
    logic [1 : 0] ``name``_BRESP; \
    logic ``name``_BVALID; \
    logic ``name``_BREADY; \
    /* AR Channel*/ \
    logic [AXI_LITE_ADDR_WIDTH - 1 : 0] ``name``_ARADDR; \
    logic ``name``_ARVALID; \
    logic [2:0] ``name``_ARPROT; \
    logic ``name``_ARREADY; \
    /* R Channel */\
    logic [AXI_DATA_WIDTH- 1 : 0] ``name``_RDATA; \
    logic [1 : 0] ``name``_RRESP; \
    logic ``name``_RVALID; \
    logic ``name``_RREADY;

`define AXI_LITE_INTERFACE_MODULE_INPUT(name, var_type) \
   /* AW Channel  */ \
    input var_type [AXI_LITE_ADDR_WIDTH - 1 : 0] ``name``_AWADDR, \
    input var_type [2:0] ``name``_AWPROT, \
    input var_type  ``name``_AWVALID, \
    input var_type [AXI_LITE_USER_WIDTH - 1 : 0] ``name``_AWUSER, \
    output var_type  ``name``_AWREADY, \
    /* W Channel */\
    input var_type [AXI_LITE_DATA_WIDTH - 1 : 0] ``name``_WDATA, \
    input var_type [AXI_LITE_DATA_WIDTH/8 - 1 : 0] ``name``_WSTRB, \
    input var_type ``name``_WVALID, \
    output var_type ``name``_WREADY, \
    /* B Channel */\
    output var_type [1 : 0] ``name``_BRESP, \
    output var_type ``name``_BVALID, \
    input var_type ``name``_BREADY, \
    /* AR Channel*/ \
    input var_type [AXI_LITE_ADDR_WIDTH - 1 : 0] ``name``_ARADDR, \
    input var_type ``name``_ARVALID, \
    input var_type [2:0] ``name``_ARPROT, \
    input var_type [AXI_LITE_USER_WIDTH - 1 : 0] ``name``_ARUSER, \
    output var_type ``name``_ARREADY, \
    /* R Channel */\
    output var_type [AXI_LITE_DATA_WIDTH - 1 : 0] ``name``_RDATA, \
    output var_type [1 : 0] ``name``_RRESP, \
    output var_type ``name``_RVALID, \
    input var_type ``name``_RREADY

`define AXI_LITE_INTERFACE_MODULE_OUTPUT(name, var_type) \
   /* AW Channel  */ \
    output var_type [AXI_LITE_ADDR_WIDTH - 1 : 0] ``name``_AWADDR, \
    output var_type [2:0] ``name``_AWPROT, \
    output var_type  ``name``_AWVALID, \
    output var_type [AXI_LITE_USER_WIDTH - 1 : 0] ``name``_AWUSER, \
    input var_type  ``name``_AWREADY, \
    /* W Channel */\
    output var_type [AXI_LITE_DATA_WIDTH - 1 : 0] ``name``_WDATA, \
    output var_type [AXI_LITE_DATA_WIDTH/8 - 1 : 0] ``name``_WSTRB, \
    output var_type ``name``_WVALID, \
    input var_type ``name``_WREADY, \
    /* B Channel */\
    input var_type [1 : 0] ``name``_BRESP, \
    input var_type ``name``_BVALID, \
    output var_type ``name``_BREADY, \
    /* AR Channel*/ \
    output var_type [AXI_LITE_ADDR_WIDTH - 1 : 0] ``name``_ARADDR, \
    output var_type ``name``_ARVALID, \
    output var_type [2:0] ``name``_ARPROT, \
    output var_type [AXI_LITE_USER_WIDTH - 1 : 0] ``name``_ARUSER, \
    input var_type ``name``_ARREADY, \
    /* R Channel */\
    input var_type [AXI_LITE_DATA_WIDTH - 1 : 0] ``name``_RDATA, \
    input var_type [1 : 0] ``name``_RRESP, \
    input var_type ``name``_RVALID, \
    output var_type ``name``_RREADY


`define AXI_LITE_INTERFACE_FORWARD(name)    \
    /* AW Channel  */ \
    .``name``_AWADDR(``name``_AWADDR), \
    .``name``_AWPROT(``name``_AWPROT), \
    .``name``_AWVALID(``name``_AWVALID), \
    .``name``_AWUSER(``name``_AWUSER), \
    .``name``_AWREADY(``name``_AWREADY), \
    /* W Channel */\
    .``name``_WDATA(``name``_WDATA), \
    .``name``_WSTRB(``name``_WSTRB), \
    .``name``_WVALID(``name``_WVALID), \
    .``name``_WREADY(``name``_WREADY), \
    /* B Channel */\
    .``name``_BRESP(``name``_BRESP), \
    .``name``_BVALID(``name``_BVALID), \
    .``name``_BREADY(``name``_BREADY), \
    /* AR Channel*/ \
    .``name``_ARADDR(``name``_ARADDR), \
    .``name``_ARUSER(``name``_ARUSER), \
    .``name``_ARPROT(``name``_ARPROT), \
    .``name``_ARVALID(``name``_ARVALID), \
    .``name``_ARREADY(``name``_ARREADY), \
    /* R Channel */\
    .``name``_RDATA(``name``_RDATA), \
    .``name``_RRESP(``name``_RRESP), \
    .``name``_RVALID(``name``_RVALID), \
    .``name``_RREADY(``name``_RREADY)
