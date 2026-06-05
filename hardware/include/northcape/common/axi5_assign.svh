/**
  * Definitions for assigning a (channel of a) northcape AXI 5 interface to another northcape interface.
  */
`ifndef AXI5_ASSIGN_H
`define AXI5_ASSIGN_H

import axi5::*;
/* verilog_format: off */
`define NORTHCAPE_MAP_INTERFACES(ASSIGN_OR_BLANK, TARGET_INTERFACE, ASSIGN_OP, SOURCE_INTERFACE) \
  /* verilog_format: on */                                                                        \
  /*  read address channel */                                                                                         \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arid ASSIGN_OP ``SOURCE_INTERFACE``.arid;                                           \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.araddr ASSIGN_OP ``SOURCE_INTERFACE``.araddr;                                        \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arlen ASSIGN_OP ``SOURCE_INTERFACE``.arlen;                                          \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arsize ASSIGN_OP ``SOURCE_INTERFACE``.arsize;                                        \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arlock ASSIGN_OP ``SOURCE_INTERFACE``.arlock;                                        \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arcache ASSIGN_OP ``SOURCE_INTERFACE``.arcache;                                      \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arprot ASSIGN_OP ``SOURCE_INTERFACE``.arprot;                                         \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arregion ASSIGN_OP ``SOURCE_INTERFACE``.arregion;                                    \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.aruser ASSIGN_OP ``SOURCE_INTERFACE``.aruser;                                        \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arburst ASSIGN_OP ``SOURCE_INTERFACE``.arburst;                                        \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arqos ASSIGN_OP ``SOURCE_INTERFACE``.arqos;                                        \
                                                                                                                       \
  /*  read address handshaking */                                                                                    \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arvalid ASSIGN_OP ``SOURCE_INTERFACE``.arvalid;                                  \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.arready ASSIGN_OP ``TARGET_INTERFACE``.arready;                                 \
                                                                                                                     \
  /*  read data channel */                                                                                           \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.rid ASSIGN_OP ``TARGET_INTERFACE``.rid;                                        \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.rdata ASSIGN_OP ``TARGET_INTERFACE``.rdata;                                    \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.rresp ASSIGN_OP ``TARGET_INTERFACE``.rresp;                                    \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.rlast ASSIGN_OP ``TARGET_INTERFACE``.rlast;                                    \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.ruser ASSIGN_OP ``TARGET_INTERFACE``.ruser;                                    \
                                                                                                                     \
  /*  read data handshaking */                                                                                       \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.rready ASSIGN_OP ``SOURCE_INTERFACE``.rready;                                   \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.rvalid ASSIGN_OP ``TARGET_INTERFACE``.rvalid;                                  \
                                                                                                                     \
  /*  write address channel */                                                                                       \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awid ASSIGN_OP ``SOURCE_INTERFACE``.awid;                                        \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awaddr ASSIGN_OP ``SOURCE_INTERFACE``.awaddr;                                    \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awlen ASSIGN_OP ``SOURCE_INTERFACE``.awlen;                                      \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awsize ASSIGN_OP ``SOURCE_INTERFACE``.awsize;                                    \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awlock ASSIGN_OP ``SOURCE_INTERFACE``.awlock;                                    \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awcache ASSIGN_OP ``SOURCE_INTERFACE``.awcache;                                  \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awprot ASSIGN_OP ``SOURCE_INTERFACE``.awprot;                                     \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awregion ASSIGN_OP ``SOURCE_INTERFACE``.awregion;                                \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awuser ASSIGN_OP ``SOURCE_INTERFACE``.awuser;                                    \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awburst ASSIGN_OP ``SOURCE_INTERFACE``.awburst; \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awqos ASSIGN_OP ``SOURCE_INTERFACE``.awqos;                                        \
                                                                                                                     \
  /*  write address handshaking */                                                                                   \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awvalid ASSIGN_OP ``SOURCE_INTERFACE``.awvalid;                                  \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.awready ASSIGN_OP ``TARGET_INTERFACE``.awready;                                 \
                                                                                                                     \
  /*  write data channel */                                                                                          \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.wstrb ASSIGN_OP ``SOURCE_INTERFACE``.wstrb;                                     \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.wlast ASSIGN_OP ``SOURCE_INTERFACE``.wlast;                                     \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.wuser ASSIGN_OP ``SOURCE_INTERFACE``.wuser;                                     \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.wdata ASSIGN_OP ``SOURCE_INTERFACE``.wdata;                                     \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.wid ASSIGN_OP ``SOURCE_INTERFACE``.wid;                                        \
                                                                                                                     \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.atop_subtype ASSIGN_OP ``SOURCE_INTERFACE``.atop_subtype;                        \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.atop_type ASSIGN_OP ``SOURCE_INTERFACE``.atop_type;                        \
                                                                                                                     \
  /*  write data handshaking */                                                                                      \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.wvalid ASSIGN_OP ``SOURCE_INTERFACE``.wvalid;                                   \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.wready ASSIGN_OP ``TARGET_INTERFACE``.wready;                                  \
                                                                                                                     \
  /*  write response channel */                                                                                      \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.bid ASSIGN_OP ``TARGET_INTERFACE``.bid;                                        \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.bresp ASSIGN_OP ``TARGET_INTERFACE``.bresp;                                    \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.buser ASSIGN_OP ``TARGET_INTERFACE``.buser;                                    \
                                                                                                                     \
  /*  write response handshaking */                                                                                  \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.bready ASSIGN_OP ``SOURCE_INTERFACE``.bready;               \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.bvalid ASSIGN_OP ``TARGET_INTERFACE``.bvalid                    

/* verilog_format: off */
`define NORTHCAPE_MAP_INTERFACES_READ(ASSIGN_OR_BLANK, TARGET_INTERFACE, ASSIGN_OP, SOURCE_INTERFACE) \
/* verilog_format: on */ \
  /*  read address channel */                                                                                         \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arid ASSIGN_OP ``SOURCE_INTERFACE``.arid;                                           \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.araddr ASSIGN_OP ``SOURCE_INTERFACE``.araddr;                                        \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arlen ASSIGN_OP ``SOURCE_INTERFACE``.arlen;                                          \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arsize ASSIGN_OP ``SOURCE_INTERFACE``.arsize;                                        \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arlock ASSIGN_OP ``SOURCE_INTERFACE``.arlock;                                        \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arcache ASSIGN_OP ``SOURCE_INTERFACE``.arcache;                                      \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arprot ASSIGN_OP ``SOURCE_INTERFACE``.arprot;                                         \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arregion ASSIGN_OP ``SOURCE_INTERFACE``.arregion;                                    \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.aruser ASSIGN_OP ``SOURCE_INTERFACE``.aruser;                                        \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arburst ASSIGN_OP ``SOURCE_INTERFACE``.arburst;                                        \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arqos ASSIGN_OP ``SOURCE_INTERFACE``.arqos;                                        \
                                                                                                                       \
  /*  read address handshaking */                                                                                    \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.arvalid ASSIGN_OP ``SOURCE_INTERFACE``.arvalid;                                  \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.arready ASSIGN_OP ``TARGET_INTERFACE``.arready;                                 \
                                                                                                                     \
  /*  read data channel */                                                                                           \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.rid ASSIGN_OP ``TARGET_INTERFACE``.rid;                                        \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.rdata ASSIGN_OP ``TARGET_INTERFACE``.rdata;                                    \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.rresp ASSIGN_OP ``TARGET_INTERFACE``.rresp;                                    \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.rlast ASSIGN_OP ``TARGET_INTERFACE``.rlast;                                    \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.ruser ASSIGN_OP ``TARGET_INTERFACE``.ruser;                                    \
                                                                                                                     \
  /*  read data handshaking */                                                                                       \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.rready ASSIGN_OP ``SOURCE_INTERFACE``.rready;                                   \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.rvalid ASSIGN_OP ``TARGET_INTERFACE``.rvalid                                  


/* verilog_format: off */
`define NORTHCAPE_MAP_INTERFACES_WRITE(ASSIGN_OR_BLANK, TARGET_INTERFACE, ASSIGN_OP, SOURCE_INTERFACE) \
/* verilog_format: on */ \
  /*  write address channel */                                                                                       \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awid ASSIGN_OP ``SOURCE_INTERFACE``.awid;                                        \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awaddr ASSIGN_OP ``SOURCE_INTERFACE``.awaddr;                                    \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awlen ASSIGN_OP ``SOURCE_INTERFACE``.awlen;                                      \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awsize ASSIGN_OP ``SOURCE_INTERFACE``.awsize;                                    \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awlock ASSIGN_OP ``SOURCE_INTERFACE``.awlock;                                    \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awcache ASSIGN_OP ``SOURCE_INTERFACE``.awcache;                                  \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awprot ASSIGN_OP ``SOURCE_INTERFACE``.awprot;                                     \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awregion ASSIGN_OP ``SOURCE_INTERFACE``.awregion;                                \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awuser ASSIGN_OP ``SOURCE_INTERFACE``.awuser;                                    \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awburst ASSIGN_OP ``SOURCE_INTERFACE``.awburst; \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awqos ASSIGN_OP ``SOURCE_INTERFACE``.awqos; \
                                                                                                                     \
  /*  write address handshaking */                                                                                   \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.awvalid ASSIGN_OP ``SOURCE_INTERFACE``.awvalid;                                  \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.awready ASSIGN_OP ``TARGET_INTERFACE``.awready;                                 \
                                                                                                                     \
  /*  write data channel */                                                                                          \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.wstrb ASSIGN_OP ``SOURCE_INTERFACE``.wstrb;                                     \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.wlast ASSIGN_OP ``SOURCE_INTERFACE``.wlast;                                     \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.wuser ASSIGN_OP ``SOURCE_INTERFACE``.wuser;                                     \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.wdata ASSIGN_OP ``SOURCE_INTERFACE``.wdata;                                     \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.wid ASSIGN_OP ``SOURCE_INTERFACE``.wid;                                     \
                                                                                                                     \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.atop_subtype ASSIGN_OP ``SOURCE_INTERFACE``.atop_subtype;                        \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.atop_type ASSIGN_OP ``SOURCE_INTERFACE``.atop_type;                        \
                                                                                                                     \
  /*  write data handshaking */                                                                                      \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.wvalid ASSIGN_OP ``SOURCE_INTERFACE``.wvalid;                                   \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.wready ASSIGN_OP ``TARGET_INTERFACE``.wready;                                  \
                                                                                                                     \
  /*  write response channel */                                                                                      \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.bid ASSIGN_OP ``TARGET_INTERFACE``.bid;                                        \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.bresp ASSIGN_OP ``TARGET_INTERFACE``.bresp;                                    \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.buser ASSIGN_OP ``TARGET_INTERFACE``.buser;                                    \
                                                                                                                     \
  /*  write response handshaking */                                                                                  \
  ASSIGN_OR_BLANK ``TARGET_INTERFACE``.bready ASSIGN_OP ``SOURCE_INTERFACE``.bready;               \
  ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.bvalid ASSIGN_OP ``TARGET_INTERFACE``.bvalid                                 

/* verilog_format: off */
`define NORTHCAPE_MAP_STREAM_INTERFACES(ASSIGN_OR_BLANK, TARGET_INTERFACE, ASSIGN_OP, SOURCE_INTERFACE) \
/* verilog_format: on */  \
    ASSIGN_OR_BLANK ``TARGET_INTERFACE``.tvalid ASSIGN_OP ``SOURCE_INTERFACE``.tvalid;                    \
    ASSIGN_OR_BLANK ``TARGET_INTERFACE``.tdata ASSIGN_OP ``SOURCE_INTERFACE``.tdata;                    \
    ASSIGN_OR_BLANK ``TARGET_INTERFACE``.tstrb ASSIGN_OP ``SOURCE_INTERFACE``.tstrb;                    \
    ASSIGN_OR_BLANK ``TARGET_INTERFACE``.tkeep ASSIGN_OP ``SOURCE_INTERFACE``.tkeep;                    \
    ASSIGN_OR_BLANK ``TARGET_INTERFACE``.tlast ASSIGN_OP ``SOURCE_INTERFACE``.tlast;                    \
    ASSIGN_OR_BLANK ``TARGET_INTERFACE``.tid ASSIGN_OP ``SOURCE_INTERFACE``.tid;                    \
    ASSIGN_OR_BLANK ``TARGET_INTERFACE``.tdest ASSIGN_OP ``SOURCE_INTERFACE``.tdest;                    \
    ASSIGN_OR_BLANK ``TARGET_INTERFACE``.tuser ASSIGN_OP ``SOURCE_INTERFACE``.tuser;                    \
    ASSIGN_OR_BLANK ``TARGET_INTERFACE``.twakeup ASSIGN_OP ``SOURCE_INTERFACE``.twakeup;                    \
    ASSIGN_OR_BLANK ``SOURCE_INTERFACE``.tready ASSIGN_OP ``TARGET_INTERFACE``.tready

`endif

`define AXI5_RESET_AR_CHANNEL_SLAVE_CUSTOM(intf, OP)  \
  intf.arid OP '0;                                    \
  intf.araddr OP '0;                                  \
  intf.arlen OP '0;                                   \
  intf.arsize OP '0;                                  \
  intf.arburst OP BURST_RESERVED;                     \
  intf.arlock OP 0;                                   \
  intf.arcache OP '0;                                 \
  intf.arprot OP '0;                                  \
  intf.arqos OP '0;                                   \
  intf.arregion OP '0;                                \
  intf.aruser OP '0;                                  \
  intf.arvalid OP 0                        

`define AXI5_RESET_AR_CHANNEL_SLAVE(intf)     \
  `AXI5_RESET_AR_CHANNEL_SLAVE_CUSTOM(intf, =)

`define AXI5_RESET_AW_CHANNEL_SLAVE_CUSTOM(intf, OP)  \
  intf.awid OP '0;                                    \
  intf.awaddr OP '0;                                  \
  intf.awlen OP '0;                                   \
  intf.awsize OP '0;                                  \
  intf.awburst OP BURST_RESERVED;                     \
  intf.awlock OP 0;                                   \
  intf.awcache OP '0;                                 \
  intf.awprot OP '0;                                  \
  intf.awqos OP '0;                                   \
  intf.awregion OP '0;                                \
  intf.awuser OP '0;                                  \
  intf.awvalid OP 0;                                  \
  intf.atop_type OP ATOMIC_NONE;                      \
  intf.atop_subtype OP '0

`define AXI5_RESET_AW_CHANNEL_SLAVE(intf)     \
 `AXI5_RESET_AW_CHANNEL_SLAVE_CUSTOM(intf, =)

`define AXI5_RESET_W_CHANNEL_SLAVE_CUSTOM(intf, OP)       \
  intf.wid OP '0;                                         \
  intf.wdata OP '0;                                       \
  intf.wstrb OP '0;                                       \
  intf.wlast OP 0;                                        \
  intf.wuser OP '0;                                       \
  intf.wvalid OP 0

`define AXI5_RESET_W_CHANNEL_SLAVE(intf)     \
  `AXI5_RESET_W_CHANNEL_SLAVE_CUSTOM(intf, =)                          
  
`define AXI5_RESET_R_CHANNEL_SLAVE_CUSTOM(intf,OP)     \
  intf.rready OP 0                           

`define AXI5_RESET_R_CHANNEL_SLAVE(intf)     \
  `AXI5_RESET_R_CHANNEL_SLAVE_CUSTOM(intf, =)

`define AXI5_RESET_B_CHANNEL_SLAVE_CUSTOM(intf, OP)     \
  intf.bready OP 0       

`define AXI5_RESET_B_CHANNEL_SLAVE(intf)     \
  `AXI5_RESET_B_CHANNEL_SLAVE_CUSTOM(intf, =)
  
`define AXI5_RESET_AR_CHANNEL_MASTER_CUSTOM(intf, OP)    \
  intf.arready OP 0

`define AXI5_RESET_AR_CHANNEL_MASTER(intf)     \
  `AXI5_RESET_AR_CHANNEL_MASTER_CUSTOM(intf, =)

`define AXI5_RESET_AW_CHANNEL_MASTER_CUSTOM(intf, OP)    \
  intf.awready OP 0

`define AXI5_RESET_AW_CHANNEL_MASTER(intf)     \
  `AXI5_RESET_AW_CHANNEL_MASTER_CUSTOM(intf, =)

`define AXI5_RESET_W_CHANNEL_MASTER_CUSTOM(intf, OP)     \
  intf.wready OP 0

`define AXI5_RESET_W_CHANNEL_MASTER(intf)     \
  `AXI5_RESET_W_CHANNEL_MASTER_CUSTOM(intf, =)

`define AXI5_RESET_R_CHANNEL_MASTER_CUSTOM(intf, OP)     \
  intf.rid OP '0;                             \
  intf.rdata OP '0;                           \
  intf.rresp OP SLVERR;                       \
  intf.rlast OP 0;                            \
  intf.ruser OP '0;                           \
  intf.rvalid OP 0                          

`define AXI5_RESET_R_CHANNEL_MASTER(intf)     \
  `AXI5_RESET_R_CHANNEL_MASTER_CUSTOM(intf, =) 

`define AXI5_RESET_B_CHANNEL_MASTER_CUSTOM(intf, OP)     \
  intf.bid OP '0;                             \
  intf.bresp OP SLVERR;                       \
  intf.buser OP '0;                           \
  intf.bvalid OP 0                                               

`define AXI5_RESET_B_CHANNEL_MASTER(intf)     \
  `AXI5_RESET_B_CHANNEL_MASTER_CUSTOM(intf, =)
