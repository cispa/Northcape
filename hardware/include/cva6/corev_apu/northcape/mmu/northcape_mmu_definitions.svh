/**
  * Common definitions for the Northcape MMU.
  */

typedef logic [AXI_ADDR_WIDTH-1:0] axi_bus_addr_t;
typedef logic [$clog2(AXI_DATA_WIDTH/8)-1:0] byte_in_burst_count_t;

typedef logic [$clog2(AXI_DATA_WIDTH/8):0] segment_size_correction_t;
