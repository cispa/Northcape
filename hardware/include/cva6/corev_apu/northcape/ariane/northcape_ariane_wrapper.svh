import axi5::*;

/**
  * Wrapper between Northcape AXI interfaces and Ariane/PULP AXI interfaces.
  */

// FROM a northcape bus TO an ariane bus
`define MAP_NORTHCAPE_INTERFACE_TO_ARIANE_INTERFACE(NORTHCAPE_BUS, ARIANE_BUS)  \
    /*  read address channel */                                                                                        \
    assign ``ARIANE_BUS``.ar_id = ``NORTHCAPE_BUS``.arid;                                           \
    assign ``ARIANE_BUS``.ar_addr = ``NORTHCAPE_BUS``.araddr;                                       \
    assign ``ARIANE_BUS``.ar_len = ``NORTHCAPE_BUS``.arlen;                                         \
    assign ``ARIANE_BUS``.ar_size = ``NORTHCAPE_BUS``.arsize;                                       \
    assign ``ARIANE_BUS``.ar_lock = ``NORTHCAPE_BUS``.arlock;                                       \
    assign ``ARIANE_BUS``.ar_cache = ``NORTHCAPE_BUS``.arcache;                                     \
    assign ``ARIANE_BUS``.ar_prot = ``NORTHCAPE_BUS``.arprot;                                        \
    assign ``ARIANE_BUS``.ar_region = ``NORTHCAPE_BUS``.arregion;                                   \
    assign ``ARIANE_BUS``.ar_user = ``NORTHCAPE_BUS``.aruser;                                       \
    assign ``ARIANE_BUS``.ar_qos = ``NORTHCAPE_BUS``.arqos;                                       \
    assign ``ARIANE_BUS``.ar_prot = ``NORTHCAPE_BUS``.arprot;                                       \
                                                                                                                      \
    /*  mismatching types of enum... */                                                                                \
    always_comb begin                                                                       \
      unique case(``NORTHCAPE_BUS``.arburst)                                                           \
        FIXED:                                                                                                         \
          ``ARIANE_BUS``.ar_burst = BURST_FIXED;                                                                    \
        INCR:                                                                                                          \
          ``ARIANE_BUS``.ar_burst = BURST_INCR;                                                                     \
        WRAP:                                                                                                          \
          ``ARIANE_BUS``.ar_burst = BURST_WRAP;                                                                     \
        default:                                                                                                       \
          ``ARIANE_BUS``.ar_burst = 2'b11; /*  RESERVED */                                                          \
      endcase                                                                                                          \
    end                                                                                     \
                                                                                                                      \
    /*  read address handshaking */                                                                                    \
    assign ``ARIANE_BUS``.ar_valid = ``NORTHCAPE_BUS``.arvalid;                                     \
    assign ``NORTHCAPE_BUS``.arready = ``ARIANE_BUS``.ar_ready;                                     \
                                                                                                                      \
    /*  read data channel */                                                                                           \
    assign ``NORTHCAPE_BUS``.rid = ``ARIANE_BUS``.r_id;                                            \
    assign ``NORTHCAPE_BUS``.rdata = ``ARIANE_BUS``.r_data;                                        \
    assign ``NORTHCAPE_BUS``.rlast = ``ARIANE_BUS``.r_last;                                        \
    assign ``NORTHCAPE_BUS``.ruser = ``ARIANE_BUS``.r_user;                                        \
                                                                                                                      \
    /*  mismatching types of enum... */                                                                                \
    always_comb begin                                                                              \
      unique case(``ARIANE_BUS``.r_resp)                                                                            \
        RESP_OKAY:                                                                                                     \
          ``NORTHCAPE_BUS``.rresp = OKAY;                                                             \
        RESP_EXOKAY:                                                                                                   \
          ``NORTHCAPE_BUS``.rresp = EXOKAY;                                                           \
        RESP_DECERR:                                                                                                   \
          ``NORTHCAPE_BUS``.rresp = DECERR;                                                           \
        RESP_SLVERR:                                                                                                   \
          ``NORTHCAPE_BUS``.rresp = SLVERR;                                                           \
      endcase                                                                                                          \
    end                                                                                            \
                                                                                                                      \
    /*  read data handshaking */                                                                                       \
    assign ``ARIANE_BUS``.r_ready = ``NORTHCAPE_BUS``.rready;                                      \
    assign ``NORTHCAPE_BUS``.rvalid = ``ARIANE_BUS``.r_valid;                                      \
                                                                                                                      \
    /*  write address channel */                                                                                       \
    assign ``ARIANE_BUS``.aw_id = ``NORTHCAPE_BUS``.awid;                                           \
    assign ``ARIANE_BUS``.aw_addr = ``NORTHCAPE_BUS``.awaddr;                                       \
    assign ``ARIANE_BUS``.aw_len = ``NORTHCAPE_BUS``.awlen;                                         \
    assign ``ARIANE_BUS``.aw_size = ``NORTHCAPE_BUS``.awsize;                                       \
    assign ``ARIANE_BUS``.aw_lock = ``NORTHCAPE_BUS``.awlock;                                       \
    assign ``ARIANE_BUS``.aw_cache = ``NORTHCAPE_BUS``.awcache;                                     \
    assign ``ARIANE_BUS``.aw_prot = ``NORTHCAPE_BUS``.awprot;                                        \
    assign ``ARIANE_BUS``.aw_region = ``NORTHCAPE_BUS``.awregion;                                   \
    assign ``ARIANE_BUS``.aw_user = ``NORTHCAPE_BUS``.awuser;                                       \
    assign ``ARIANE_BUS``.aw_atop = {``NORTHCAPE_BUS``.atop_type,``NORTHCAPE_BUS``.atop_subtype} ;                                             \
    assign ``ARIANE_BUS``.aw_qos = ``NORTHCAPE_BUS``.awqos;                                       \
    assign ``ARIANE_BUS``.aw_prot = ``NORTHCAPE_BUS``.awprot;                                       \
                                                                                                                      \
    /*  mismatching types of enum... */                                                                                \
    always_comb begin                                                                      \
      unique case(``NORTHCAPE_BUS``.awburst)                                                           \
        FIXED:                                                                                                         \
          ``ARIANE_BUS``.aw_burst = BURST_FIXED;                                                                    \
        INCR:                                                                                                          \
          ``ARIANE_BUS``.aw_burst = BURST_INCR;                                                                     \
        WRAP:                                                                                                          \
          ``ARIANE_BUS``.aw_burst = BURST_WRAP;                                                                     \
        default:                                                                                                       \
          ``ARIANE_BUS``.aw_burst = 2'b11; /*  RESERVED */                                                          \
      endcase                                                                                                          \
    end                                                                                    \
                                                                                                                      \
    /*  write address handshaking */                                                                                   \
    assign ``ARIANE_BUS``.aw_valid = ``NORTHCAPE_BUS``.awvalid;                                     \
    assign ``NORTHCAPE_BUS``.awready = ``ARIANE_BUS``.aw_ready;                                     \
                                                                                                                      \
    /*  write data channel */                                                                                          \
    assign ``ARIANE_BUS``.w_strb = ``NORTHCAPE_BUS``.wstrb;                                        \
    assign ``ARIANE_BUS``.w_last = ``NORTHCAPE_BUS``.wlast;                                        \
    assign ``ARIANE_BUS``.w_user = ``NORTHCAPE_BUS``.wuser;                                        \
    assign ``ARIANE_BUS``.w_data = ``NORTHCAPE_BUS``.wdata;                                        \
                                                                                                                      \
    /*  write data handshaking */                                                                                      \
    assign ``ARIANE_BUS``.w_valid = ``NORTHCAPE_BUS``.wvalid;                                      \
    assign ``NORTHCAPE_BUS``.wready = ``ARIANE_BUS``.w_ready;                                      \
                                                                                                                      \
                                                                                                                      \
    /*  write response channel */                                                                                      \
    assign ``NORTHCAPE_BUS``.bid = ``ARIANE_BUS``.b_id;                                            \
    assign ``NORTHCAPE_BUS``.buser = ``ARIANE_BUS``.b_user;                                        \
                                                                                                                      \
    /*  mismatching types of enum... */                                                                                \
    always_comb begin                                                                             \
      unique case(``ARIANE_BUS``.b_resp)                                                                            \
        RESP_OKAY:                                                                                                     \
          ``NORTHCAPE_BUS``.bresp = OKAY;                                                             \
        RESP_EXOKAY:                                                                                                   \
          ``NORTHCAPE_BUS``.bresp = EXOKAY;                                                           \
        RESP_DECERR:                                                                                                   \
          ``NORTHCAPE_BUS``.bresp = DECERR;                                                           \
        RESP_SLVERR:                                                                                                   \
          ``NORTHCAPE_BUS``.bresp = SLVERR;                                                           \
      endcase                                                                                                          \
    end                                                                                           \
                                                                                                                      \
    /*  write response handshaking */                                                                                  \
    assign ``ARIANE_BUS``.b_ready = ``NORTHCAPE_BUS``.bready;                                      \
    assign ``NORTHCAPE_BUS``.bvalid = ``ARIANE_BUS``.b_valid;                                      

// TO a northcape bus FROM an ariane bus
`define MAP_NORTHCAPE_INTERFACE_FROM_ARIANE_INTERFACE(ARIANE_BUS, NORTHCAPE_BUS)  \
    /*  read address channel */                                                                                        \
    assign ``NORTHCAPE_BUS``.arid = ``ARIANE_BUS``.ar_id;                                           \
    assign ``NORTHCAPE_BUS``.araddr = ``ARIANE_BUS``.ar_addr;                                       \
    assign ``NORTHCAPE_BUS``.arlen = ``ARIANE_BUS``.ar_len;                                         \
    assign ``NORTHCAPE_BUS``.arsize = ``ARIANE_BUS``.ar_size;                                       \
    assign ``NORTHCAPE_BUS``.arlock = ``ARIANE_BUS``.ar_lock;                                       \
    assign ``NORTHCAPE_BUS``.arcache = ``ARIANE_BUS``.ar_cache;                                     \
    assign ``NORTHCAPE_BUS``.arprot = ``ARIANE_BUS``.ar_prot;                                        \
    assign ``NORTHCAPE_BUS``.arregion = ``ARIANE_BUS``.ar_region;                                   \
    assign ``NORTHCAPE_BUS``.aruser = ``ARIANE_BUS``.ar_user;                                       \
    assign ``NORTHCAPE_BUS``.arqos = ``ARIANE_BUS``.ar_qos;                                       \
    assign ``NORTHCAPE_BUS``.arprot = ``ARIANE_BUS``.ar_prot;                                       \
                                                                                                                      \
    /*  mismatching types of enum... */                                                                                \
    always_comb begin                                                                       \
      unique case(``ARIANE_BUS``.ar_burst)                                                           \
        BURST_FIXED:                                                                                                         \
          ``NORTHCAPE_BUS``.arburst = FIXED;                                                                    \
        BURST_INCR:                                                                                                          \
          ``NORTHCAPE_BUS``.arburst = INCR;                                                                     \
        BURST_WRAP:                                                                                                          \
          ``NORTHCAPE_BUS``.arburst = WRAP;                                                                     \
        default:                                                                                                       \
          ``NORTHCAPE_BUS``.arburst = BURST_RESERVED; /*  RESERVED */                                                          \
      endcase                                                                                                          \
    end                                                                                     \
                                                                                                                      \
    /*  read address handshaking */                                                                                    \
    assign ``NORTHCAPE_BUS``.arvalid = ``ARIANE_BUS``.ar_valid;                                     \
    assign ``ARIANE_BUS``.ar_ready = ``NORTHCAPE_BUS``.arready;                                     \
                                                                                                                      \
    /*  read data channel */                                                                                           \
    assign ``ARIANE_BUS``.r_id = ``NORTHCAPE_BUS``.rid;                                            \
    assign ``ARIANE_BUS``.r_data = ``NORTHCAPE_BUS``.rdata;                                        \
    assign ``ARIANE_BUS``.r_last = ``NORTHCAPE_BUS``.rlast;                                        \
    assign ``ARIANE_BUS``.r_user = ``NORTHCAPE_BUS``.ruser;                                        \
                                                                                                                      \
    /*  mismatching types of enum... */                                                                                \
    always_comb begin                                                                              \
      unique case(``NORTHCAPE_BUS``.rresp)                                                                            \
        OKAY:                                                                                                     \
          ``ARIANE_BUS``.r_resp = RESP_OKAY;                                                             \
        EXOKAY:                                                                                                   \
          ``ARIANE_BUS``.r_resp = RESP_EXOKAY;                                                           \
        DECERR:                                                                                                   \
          ``ARIANE_BUS``.r_resp = RESP_DECERR;                                                           \
        SLVERR:                                                                                                   \
          ``ARIANE_BUS``.r_resp = RESP_SLVERR;                                                           \
      endcase                                                                                                          \
    end                                                                                            \
                                                                                                                      \
    /*  read data handshaking */                                                                                       \
    assign ``NORTHCAPE_BUS``.rready = ``ARIANE_BUS``.r_ready;                                      \
    assign ``ARIANE_BUS``.r_valid = ``NORTHCAPE_BUS``.rvalid;                                      \
                                                                                                                      \
    /*  write address channel */                                                                                       \
    assign ``NORTHCAPE_BUS``.awid = ``ARIANE_BUS``.aw_id;                                           \
    assign ``NORTHCAPE_BUS``.awaddr = ``ARIANE_BUS``.aw_addr;                                       \
    assign ``NORTHCAPE_BUS``.awlen = ``ARIANE_BUS``.aw_len;                                         \
    assign ``NORTHCAPE_BUS``.awsize = ``ARIANE_BUS``.aw_size;                                       \
    assign ``NORTHCAPE_BUS``.awlock = ``ARIANE_BUS``.aw_lock;                                       \
    assign ``NORTHCAPE_BUS``.awcache = ``ARIANE_BUS``.aw_cache;                                     \
    assign ``NORTHCAPE_BUS``.awprot = ``ARIANE_BUS``.aw_prot;                                        \
    assign ``NORTHCAPE_BUS``.awregion = ``ARIANE_BUS``.aw_region;                                   \
    assign ``NORTHCAPE_BUS``.awuser = ``ARIANE_BUS``.aw_user;                                       \
    assign ``ARIANE_BUS``.aw_atop = {``NORTHCAPE_BUS``.atop_type,``NORTHCAPE_BUS``.atop_subtype} ;                                             \
    assign ``NORTHCAPE_BUS``.awqos = ``ARIANE_BUS``.aw_qos;                                       \
    assign ``NORTHCAPE_BUS``.awprot = ``ARIANE_BUS``.aw_prot;                                       \
                                                                                                                      \
    /*  mismatching types of enum... */                                                                                \
    always_comb begin                                                                      \
      unique case(``ARIANE_BUS``.aw_burst)                                                           \
        BURST_FIXED:                                                                                                         \
          ``NORTHCAPE_BUS``.awburst = FIXED;                                                                    \
        BURST_INCR:                                                                                                          \
          ``NORTHCAPE_BUS``.awburst = INCR;                                                                     \
        BURST_WRAP:                                                                                                          \
          ``NORTHCAPE_BUS``.awburst = WRAP;                                                                     \
        default:                                                                                                       \
          ``NORTHCAPE_BUS``.awburst = BURST_RESERVED; /*  RESERVED */                                                          \
      endcase                                                                                                          \
    end                                                                                    \
                                                                                                                      \
    /*  write address handshaking */                                                                                   \
    assign ``NORTHCAPE_BUS``.awvalid = ``ARIANE_BUS``.aw_valid;                                     \
    assign ``ARIANE_BUS``.aw_ready = ``NORTHCAPE_BUS``.awready;                                     \
                                                                                                                      \
    /*  write data channel */                                                                                          \
    assign ``NORTHCAPE_BUS``.wstrb = ``ARIANE_BUS``.w_strb;                                        \
    assign ``NORTHCAPE_BUS``.wlast = ``ARIANE_BUS``.w_last;                                        \
    assign ``NORTHCAPE_BUS``.wuser = ``ARIANE_BUS``.w_user;                                        \
    assign ``NORTHCAPE_BUS``.wdata = ``ARIANE_BUS``.w_data;                                        \
                                                                                                                      \
    /*  write data handshaking */                                                                                      \
    assign ``NORTHCAPE_BUS``.wvalid = ``ARIANE_BUS``.w_valid;                                      \
    assign ``ARIANE_BUS``.w_ready = ``NORTHCAPE_BUS``.wready;                                      \
                                                                                                                      \
                                                                                                                      \
    /*  write response channel */                                                                                      \
    assign ``ARIANE_BUS``.b_id  =``NORTHCAPE_BUS``.bid;                                            \
    assign ``ARIANE_BUS``.b_user = ``NORTHCAPE_BUS``.buser;                                        \
                                                                                                                      \
    /*  mismatching types of enum... */                                                                                \
    always_comb begin                                                                             \
      unique case(``NORTHCAPE_BUS``.bresp)                                                                            \
        OKAY:                                                                                                     \
          ``ARIANE_BUS``.b_resp = RESP_OKAY;                                                             \
        EXOKAY:                                                                                                   \
          ``ARIANE_BUS``.b_resp = RESP_EXOKAY;                                                           \
        DECERR:                                                                                                   \
          ``ARIANE_BUS``.b_resp = RESP_DECERR;                                                           \
        SLVERR:                                                                                                   \
          ``ARIANE_BUS``.b_resp = RESP_SLVERR;                                                           \
      endcase                                                                                                          \
    end                                                                                           \
                                                                                                                      \
    /*  write response handshaking */                                                                                  \
    assign ``NORTHCAPE_BUS``.bready = ``ARIANE_BUS``.b_ready;                                      \
    assign ``ARIANE_BUS``.b_valid = ``NORTHCAPE_BUS``.bvalid;                                      

// TO a northcape bus FROM an ariane bus
`define MAP_NORTHCAPE_LITE_INTERFACE_FROM_ARIANE_INTERFACE(ARIANE_BUS, NORTHCAPE_BUS)  \
    /*  read address channel */                                                                                        \
    assign ``NORTHCAPE_BUS``.araddr = ``ARIANE_BUS``.ar_addr;                                       \
    assign ``NORTHCAPE_BUS``.arprot = ``ARIANE_BUS``.ar_prot;                                        \
                                                                                                                      \
    /*  read address handshaking */                                                                                    \
    assign ``NORTHCAPE_BUS``.arvalid = ``ARIANE_BUS``.ar_valid;                                     \
    assign ``ARIANE_BUS``.ar_ready = ``NORTHCAPE_BUS``.arready;                                     \
                                                                                                                      \
    /*  read data channel */                                                                                           \
    assign ``ARIANE_BUS``.r_data = ``NORTHCAPE_BUS``.rdata;                                        \
                                                                                                                      \
    /*  mismatching types of enum... */                                                                                \
    always_comb begin                                                                              \
      unique case(``NORTHCAPE_BUS``.rresp)                                                                            \
        OKAY:                                                                                                     \
          ``ARIANE_BUS``.r_resp = RESP_OKAY;                                                             \
        EXOKAY:                                                                                                   \
          ``ARIANE_BUS``.r_resp = RESP_EXOKAY;                                                           \
        DECERR:                                                                                                   \
          ``ARIANE_BUS``.r_resp = RESP_DECERR;                                                           \
        SLVERR:                                                                                                   \
          ``ARIANE_BUS``.r_resp = RESP_SLVERR;                                                           \
      endcase                                                                                                          \
    end                                                                                            \
                                                                                                                      \
    /*  read data handshaking */                                                                                       \
    assign ``NORTHCAPE_BUS``.rready = ``ARIANE_BUS``.r_ready;                                      \
    assign ``ARIANE_BUS``.r_valid = ``NORTHCAPE_BUS``.rvalid;                                      \
                                                                                                                      \
    /*  write address channel */                                                                                       \
    assign ``NORTHCAPE_BUS``.awaddr = ``ARIANE_BUS``.aw_addr;                                       \
    assign ``NORTHCAPE_BUS``.awprot = ``ARIANE_BUS``.aw_prot;                                        \
                                                                                                                      \
                                                                                                                      \
    /*  write address handshaking */                                                                                   \
    assign ``NORTHCAPE_BUS``.awvalid = ``ARIANE_BUS``.aw_valid;                                     \
    assign ``ARIANE_BUS``.aw_ready = ``NORTHCAPE_BUS``.awready;                                     \
                                                                                                                      \
    /*  write data channel */                                                                                          \
    assign ``NORTHCAPE_BUS``.wstrb = ``ARIANE_BUS``.w_strb;                                        \
    assign ``NORTHCAPE_BUS``.wdata = ``ARIANE_BUS``.w_data;                                        \
                                                                                                                      \
    /*  write data handshaking */                                                                                      \
    assign ``NORTHCAPE_BUS``.wvalid = ``ARIANE_BUS``.w_valid;                                      \
    assign ``ARIANE_BUS``.w_ready = ``NORTHCAPE_BUS``.wready;                                      \
                                                                                                                      \
                                                                                                                      \
    /*  write response channel */                                                                                      \
                                                                                                                      \
    /*  mismatching types of enum... */                                                                                \
    always_comb begin                                                                             \
      unique case(``NORTHCAPE_BUS``.bresp)                                                                            \
        OKAY:                                                                                                     \
          ``ARIANE_BUS``.b_resp = RESP_OKAY;                                                             \
        EXOKAY:                                                                                                   \
          ``ARIANE_BUS``.b_resp = RESP_EXOKAY;                                                           \
        DECERR:                                                                                                   \
          ``ARIANE_BUS``.b_resp = RESP_DECERR;                                                           \
        SLVERR:                                                                                                   \
          ``ARIANE_BUS``.b_resp = RESP_SLVERR;                                                           \
      endcase                                                                                                          \
    end                                                                                           \
                                                                                                                      \
    /*  write response handshaking */                                                                                  \
    assign ``NORTHCAPE_BUS``.bready = ``ARIANE_BUS``.b_ready;                                      \
    assign ``ARIANE_BUS``.b_valid = ``NORTHCAPE_BUS``.bvalid;       


/**
  * Wrapper for ariane-style AXI5 request/response structs to Northcape AXI5 interfaces.
  */
`define NORTHCAPE_MAP_ARIANE_AXI_INTERFACES(NORTHCAPE_IN_PREFIX, NORTHCAPE_OUT_PREFIX,
                                            ARIANE_PREFIX, MEMORY_PREFIX)    \
    /* assignments to SLAVE side of the MMU */                                                                       \
                                                                                                                     \
  /*  read address channel */                                                                                        \
  assign ``NORTHCAPE_IN_PREFIX``.arid = ``ARIANE_PREFIX``_req.ar.id;                                        \
  assign ``NORTHCAPE_IN_PREFIX``.araddr = ``ARIANE_PREFIX``_req.ar.addr;                                    \
  assign ``NORTHCAPE_IN_PREFIX``.arlen = ``ARIANE_PREFIX``_req.ar.len;                                      \
  assign ``NORTHCAPE_IN_PREFIX``.arsize = ``ARIANE_PREFIX``_req.ar.size;                                    \
  assign ``NORTHCAPE_IN_PREFIX``.arlock = ``ARIANE_PREFIX``_req.ar.lock;                                    \
  assign ``NORTHCAPE_IN_PREFIX``.arcache = ``ARIANE_PREFIX``_req.ar.cache;                                  \
  assign ``NORTHCAPE_IN_PREFIX``.arprot = ``ARIANE_PREFIX``_req.ar.prot;                                     \
  assign ``NORTHCAPE_IN_PREFIX``.arregion = ``ARIANE_PREFIX``_req.ar.region;                                \
  assign ``NORTHCAPE_IN_PREFIX``.aruser = ``ARIANE_PREFIX``_req.ar.user;                                    \
  assign ``NORTHCAPE_IN_PREFIX``.arqos = ``ARIANE_PREFIX``_req.ar.qos;                                      \
  assign ``NORTHCAPE_IN_PREFIX``.arprot = ``ARIANE_PREFIX``_req.ar.prot;                                      \
                                                                                                                     \
  /*  mismatching types of enum... */                                                                                \
  always_comb begin: burstEnumMapperReadSlave                                                                        \
    unique case(``ARIANE_PREFIX``_req.ar.burst)                                                                      \
      BURST_FIXED:                                                                                                   \
        ``NORTHCAPE_IN_PREFIX``.arburst = FIXED;                                                            \
      BURST_INCR:                                                                                                    \
        ``NORTHCAPE_IN_PREFIX``.arburst = INCR;                                                             \
      BURST_WRAP:                                                                                                    \
        ``NORTHCAPE_IN_PREFIX``.arburst = WRAP;                                                             \
      default:                                                                                                       \
        ``NORTHCAPE_IN_PREFIX``.arburst = BURST_RESERVED;                                                   \
    endcase                                                                                                          \
  end: burstEnumMapperReadSlave                                                                                      \
                                                                                                                     \
  /*  read address handshaking */                                                                                    \
  assign ``NORTHCAPE_IN_PREFIX``.arvalid = ``ARIANE_PREFIX``_req.ar_valid;                                  \
  assign ``ARIANE_PREFIX``_resp.ar_ready = ``NORTHCAPE_IN_PREFIX``.arready;                                 \
                                                                                                                     \
  /*  read data channel */                                                                                           \
  assign ``ARIANE_PREFIX``_resp.r.id = ``NORTHCAPE_IN_PREFIX``.rid;                                        \
  assign ``ARIANE_PREFIX``_resp.r.data = ``NORTHCAPE_IN_PREFIX``.rdata;                                    \
  assign ``ARIANE_PREFIX``_resp.r.resp = ``NORTHCAPE_IN_PREFIX``.rresp;                                    \
  assign ``ARIANE_PREFIX``_resp.r.last = ``NORTHCAPE_IN_PREFIX``.rlast;                                    \
  assign ``ARIANE_PREFIX``_resp.r.user = ``NORTHCAPE_IN_PREFIX``.ruser;                                    \
                                                                                                                     \
  /*  read data handshaking */                                                                                       \
  assign ``NORTHCAPE_IN_PREFIX``.rready = ``ARIANE_PREFIX``_req.r_ready;                                   \
  assign ``ARIANE_PREFIX``_resp.r_valid = ``NORTHCAPE_IN_PREFIX``.rvalid;                                  \
                                                                                                                     \
  /*  write address channel */                                                                                       \
  assign ``NORTHCAPE_IN_PREFIX``.awid = ``ARIANE_PREFIX``_req.aw.id;                                        \
  assign ``NORTHCAPE_IN_PREFIX``.awaddr = ``ARIANE_PREFIX``_req.aw.addr;                                    \
  assign ``NORTHCAPE_IN_PREFIX``.awlen = ``ARIANE_PREFIX``_req.aw.len;                                      \
  assign ``NORTHCAPE_IN_PREFIX``.awsize = ``ARIANE_PREFIX``_req.aw.size;                                    \
  assign ``NORTHCAPE_IN_PREFIX``.awlock = ``ARIANE_PREFIX``_req.aw.lock;                                    \
  assign ``NORTHCAPE_IN_PREFIX``.awcache = ``ARIANE_PREFIX``_req.aw.cache;                                  \
  assign ``NORTHCAPE_IN_PREFIX``.awprot = ``ARIANE_PREFIX``_req.aw.prot;                                     \
  assign ``NORTHCAPE_IN_PREFIX``.awregion = ``ARIANE_PREFIX``_req.aw.region;                                \
  assign ``NORTHCAPE_IN_PREFIX``.awuser = ``ARIANE_PREFIX``_req.aw.user;                                    \
  assign ``NORTHCAPE_IN_PREFIX``.awqos = ``ARIANE_PREFIX``_req.aw.qos;                                    \
  assign ``NORTHCAPE_IN_PREFIX``.awprot = ``ARIANE_PREFIX``_req.aw.prot;                                    \
                                                                                                                     \
  always_comb begin: burstEnumMapperWriteSlave                                                                       \
    unique case(``ARIANE_PREFIX``_req.aw.burst)                                                                      \
      BURST_FIXED:                                                                                                   \
        ``NORTHCAPE_IN_PREFIX``.awburst = FIXED;                                                            \
      BURST_INCR:                                                                                                    \
        ``NORTHCAPE_IN_PREFIX``.awburst = INCR;                                                             \
      BURST_WRAP:                                                                                                    \
        ``NORTHCAPE_IN_PREFIX``.awburst = WRAP;                                                             \
      default:                                                                                                       \
        ``NORTHCAPE_IN_PREFIX``.awburst = BURST_RESERVED;                                                   \
    endcase                                                                                                          \
  end: burstEnumMapperWriteSlave                                                                                     \
                                                                                                                     \
  /*  write address handshaking */                                                                                   \
  assign ``NORTHCAPE_IN_PREFIX``.awvalid = ``ARIANE_PREFIX``_req.aw_valid;                                  \
  assign ``ARIANE_PREFIX``_resp.aw_ready = ``NORTHCAPE_IN_PREFIX``.awready;                                 \
                                                                                                                     \
  /*  write data channel */                                                                                          \
  assign ``NORTHCAPE_IN_PREFIX``.wstrb = ``ARIANE_PREFIX``_req.w.strb;                                     \
  assign ``NORTHCAPE_IN_PREFIX``.wlast = ``ARIANE_PREFIX``_req.w.last;                                     \
  assign ``NORTHCAPE_IN_PREFIX``.wuser = ``ARIANE_PREFIX``_req.w.user;                                     \
  assign ``NORTHCAPE_IN_PREFIX``.wdata = ``ARIANE_PREFIX``_req.w.data;                                     \
  assign ``NORTHCAPE_IN_PREFIX``.wid = '0; /* Legacy for Axi3 compatibility */                                     \
                                                                                                                     \
  assign ``NORTHCAPE_IN_PREFIX``.atop_subtype = ``ARIANE_PREFIX``_req.aw.atop[3:0];                        \
                                                                                                                     \
  always_comb begin: atopEnumWrapperSlave                                                                            \
  unique case(``ARIANE_PREFIX``_req.aw.atop[5:4])                                                                    \
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
  assign ``NORTHCAPE_IN_PREFIX``.wvalid = ``ARIANE_PREFIX``_req.w_valid;                                   \
  assign ``ARIANE_PREFIX``_resp.w_ready = ``NORTHCAPE_IN_PREFIX``.wready;                                  \
                                                                                                                     \
  /*  write response channel */                                                                                      \
  assign ``ARIANE_PREFIX``_resp.b.id = ``NORTHCAPE_IN_PREFIX``.bid;                                        \
  assign ``ARIANE_PREFIX``_resp.b.resp = ``NORTHCAPE_IN_PREFIX``.bresp;                                    \
  assign ``ARIANE_PREFIX``_resp.b.user = ``NORTHCAPE_IN_PREFIX``.buser;                                    \
                                                                                                                     \
  /*  write response handshaking */                                                                                  \
  assign ``NORTHCAPE_IN_PREFIX``.bready = ``ARIANE_PREFIX``_req.b_ready;                                   \
  assign ``ARIANE_PREFIX``_resp.b_valid = ``NORTHCAPE_IN_PREFIX``.bvalid;                                  \
  assign ``ARIANE_PREFIX``_resp.b.user = ``NORTHCAPE_IN_PREFIX``.buser;                                  \
                                                                                                                     \
  /*  assignments to MASTER side of the MMU */                                                                       \
  `MAP_NORTHCAPE_INTERFACE_TO_ARIANE_INTERFACE(NORTHCAPE_OUT_PREFIX,MEMORY_PREFIX)
