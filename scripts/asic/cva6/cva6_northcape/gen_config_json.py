#!/bin/env python3
from json import dump


OFFSET_X = 100 
OFFSET_Y = 100

template_object = {
  "DESIGN_NAME": "cva6_wrapper_verilog",
  "VERILOG_FILES": ["dir::../../../../hardware/hdl/asic_wrappers/sram_hpdcache_wrapper.v","dir::cva6_flattened.v"],
  "VDD_NETS": [
	  "vccd1"
  ],

  "GND_NETS": [
	  "vssd1"
  ],
  "FP_CORE_UTIL": 30,
  "FP_SIZING": "absolute",
  "PL_TIME_DRIVEN": True,
  "PL_ROUTABILITY_CHECK_OVERFLOW": 0.5,
  "RUN_ANTENNA_REPAIR": False,
  "PL_TARGET_RC_METRIC": 0.95,
  "CLOCK_PERIOD": 100,
  "CLOCK_PORT": "aclk",
  "RUN_LINTER": False,
  "GRT_OVERFLOW_ITERS": 500,
  "GRT_ALLOW_CONGESTION": True,
  "PL_USE_FASTROUTE_INSTEAD_OF_RUDY": True,
  # some top-level inputs are DELIBERATELY not connected to anything (e.g., Northcape AXI stream ports, AXI user ports, Macro spare pins)
  "ERROR_ON_DISCONNECTED_PINS": False,
  "MACROS": {
    "sram_hpdcache_64x128": {
      "instances": {
      },
      
      "gds": [
          "dir::../../macros/sram_hpdcache_64x128/sram_hpdcache_64x128.gds"
      ],
      "lef": [
          "dir::../../macros/sram_hpdcache_64x128/sram_hpdcache_64x128.lef"
      ],
      "nl": [
      ],
      "spef": {
      },
      "lib": {
        "*ff_025C_1v80": ["dir::../../macros/sram_hpdcache_64x128/sram_hpdcache_64x128_FF_1p8V_25C.lib"],
        "*ff_n40C_1v95": ["dir::../../macros/sram_hpdcache_64x128/sram_hpdcache_64x128_FF_1p95V_40C.lib"],
        "*ss_025C_1v80": ["dir::../../macros/sram_hpdcache_64x128/sram_hpdcache_64x128_SS_1p8V_25C.lib"],
        "*ss_100C_1v60": ["dir::../../macros/sram_hpdcache_64x128/sram_hpdcache_64x128_SS_1p6V_100C.lib"],
        "*tt_000C_1v80": ["dir::../../macros/sram_hpdcache_64x128/sram_hpdcache_64x128_TT_1p8V_0C.lib"],
        "*tt_025C_1v80": ["dir::../../macros/sram_hpdcache_64x128/sram_hpdcache_64x128_TT_1p8V_25C.lib"],
        "*tt_100C_1v80": ["dir::../../macros/sram_hpdcache_64x128/sram_hpdcache_64x128_TT_1p8V_100C.lib"]
	  },
      "spice": [],
      "sdf": {}
    }
  },

  "PDN_MACRO_CONNECTIONS": [".*sram0 vccd1 vssd1 vccd1 vssd1"],
  "MAGIC_CAPTURE_ERRORS": False
}

ASSOCIATIVITY=8
NUM_ENTRIES=512
CMT_ENTRY_SIZE=256
ASSOC_METADATA_SIZE=40

PRIMITIVE_WIDTH=256
PRIMITIVE_DEPTH=64

COL_WIDTH = (ASSOCIATIVITY * (CMT_ENTRY_SIZE + ASSOC_METADATA_SIZE))

STOREBUFFER_SIZE=8
NUM_COLS_STORE_BUFFER = int((CMT_ENTRY_SIZE + PRIMITIVE_WIDTH-1) / PRIMITIVE_WIDTH)
NUM_ROWS_STORE_BUFFER = int((STOREBUFFER_SIZE + PRIMITIVE_DEPTH - 1) / PRIMITIVE_DEPTH)

NUM_ROWS_CACHE_OUTER=2
NUM_COLS_CACHE_OUTER=8

NUM_COLS_CACHE =  1
NUM_ROWS_CACHE = 2

NUM_COLS_MEMCTRL = 1
NUM_ROWS_MEMCTRL = 2
NUM_ROWS_MEMCTRL_OUTER = 8
NUM_COLS_MEMCTRL_OUTER = 1


NUM_COLS_ICACHE = 1
NUM_ICACHE_SRAMS = 4
NUM_ICACHE_SRAM_CUTS = 2
NUM_ROWS_ICACHE = 2
# 2 data cuts, 1 tag cut
NUM_COLS_MAX = NUM_COLS_CACHE_OUTER * NUM_COLS_CACHE + NUM_COLS_MEMCTRL * NUM_COLS_MEMCTRL_OUTER + NUM_ICACHE_SRAM_CUTS * NUM_COLS_ICACHE + NUM_COLS_ICACHE

EXTRA_HORIZONTAL_SEPARATION=500
EXTRA_VERTICAL_SEPARATION=500

SRAM_WIDTH=558
SRAM_HEIGHT=214

NUM_ROWS_CACHE_REAL = max(NUM_ROWS_CACHE * NUM_ROWS_CACHE_OUTER, NUM_ROWS_MEMCTRL_OUTER * NUM_ROWS_MEMCTRL, NUM_ICACHE_SRAMS * NUM_ROWS_ICACHE)

def main():
    
    print(f"Cache grid {NUM_COLS_CACHE} * {NUM_ROWS_CACHE}")
    print(f"Store buffer grid {NUM_COLS_STORE_BUFFER} * {NUM_ROWS_STORE_BUFFER}")
    # center macros and leave some space aroudn them for logic
    DIE_WIDTH = NUM_COLS_MAX * SRAM_WIDTH + (NUM_COLS_MAX-1)*EXTRA_HORIZONTAL_SEPARATION + 2 * OFFSET_X
    # account for store buffer
    DIE_HEIGHT = (NUM_ROWS_CACHE_REAL) * SRAM_HEIGHT + (NUM_ROWS_CACHE_REAL-1)*EXTRA_VERTICAL_SEPARATION + 2 * OFFSET_Y
    print(f"Die area {DIE_WIDTH} * {DIE_HEIGHT}")

    template_object["DIE_AREA"] = f"0 0 {DIE_WIDTH} {DIE_HEIGHT}"
    # data
    for outer_row in range(0, NUM_ROWS_CACHE_OUTER):
        for outer_col in range(0, NUM_COLS_CACHE_OUTER):
            for row in range(0, NUM_ROWS_CACHE):
                for col in range(0, NUM_COLS_CACHE):
                    inst_name = f"i_cva6_wrapper.i_ariane.i_cva6.gen_cache_wt.i_cache_subsystem.i_wt_dcache.i_wt_dcache_mem.gen_ram_without_error_bit.gen_data_banks[{outer_row}].i_data_sram.gen_cut[{outer_col}].i_tc_sram_wrapper.i_tc_sram.i_sram.gen_row[{row}].gen_col[{col}].i_sram_cell.sram0"
                    template_object["MACROS"]["sram_hpdcache_64x128"]["instances"][inst_name] = {
                        "location": [
                            OFFSET_X + (col + outer_col * NUM_COLS_CACHE) * (SRAM_WIDTH + EXTRA_HORIZONTAL_SEPARATION),
                            OFFSET_Y + (outer_row * NUM_ROWS_CACHE + row) * (SRAM_HEIGHT + EXTRA_VERTICAL_SEPARATION)
                        ],
                        "orientation": "N"
                    }
    #tag
    for outer_row in range(0, NUM_ROWS_MEMCTRL_OUTER):
        for outer_col in range(0, NUM_COLS_MEMCTRL_OUTER):
            for row in range(0, NUM_ROWS_MEMCTRL):
                for col in range(0, NUM_COLS_MEMCTRL):
                    inst_name = f"i_cva6_wrapper.i_ariane.i_cva6.gen_cache_wt.i_cache_subsystem.i_wt_dcache.i_wt_dcache_mem.gen_tag_srams[{outer_row}].i_tag_sram.gen_cut[{outer_col}].i_tc_sram_wrapper.i_tc_sram.i_sram.gen_row[{row}].gen_col[{col}].i_sram_cell.sram0"
                    template_object["MACROS"]["sram_hpdcache_64x128"]["instances"][inst_name] = {
                        "location": [
                            OFFSET_X + NUM_COLS_CACHE_OUTER * NUM_COLS_CACHE * (SRAM_WIDTH + EXTRA_HORIZONTAL_SEPARATION) + col * (SRAM_WIDTH + EXTRA_HORIZONTAL_SEPARATION),
                            OFFSET_Y + (outer_row * NUM_ROWS_MEMCTRL + row) * (SRAM_HEIGHT + EXTRA_VERTICAL_SEPARATION)
                        ],
                        "orientation": "N"
                    }
    # data SRAM - cut 0
    for outer_row in range(0, NUM_ICACHE_SRAMS):
        for row in range(0, NUM_ROWS_ICACHE):
            for col in range(0, NUM_COLS_ICACHE):
                inst_name = f"i_cva6_wrapper.i_ariane.i_cva6.gen_cache_wt.i_cache_subsystem.i_cva6_icache.gen_sram[{outer_row}].data_sram.gen_cut[0].i_tc_sram_wrapper.i_tc_sram.i_sram.gen_row[{row}].gen_col[{col}].i_sram_cell.sram0"
                template_object["MACROS"]["sram_hpdcache_64x128"]["instances"][inst_name] = {
                    "location": [
                        OFFSET_X + (NUM_COLS_CACHE_OUTER * NUM_COLS_CACHE + NUM_COLS_MEMCTRL_OUTER) * (SRAM_WIDTH + EXTRA_HORIZONTAL_SEPARATION) + col * (SRAM_WIDTH + EXTRA_HORIZONTAL_SEPARATION),
                        OFFSET_Y + (outer_row * NUM_ROWS_ICACHE + row) * (SRAM_HEIGHT + EXTRA_VERTICAL_SEPARATION)
                    ],
                    "orientation": "N"
                }
    # data SRAM - cut 1
    for outer_row in range(0, NUM_ICACHE_SRAMS):
        for row in range(0, NUM_ROWS_ICACHE):
            for col in range(0, NUM_COLS_ICACHE):
                inst_name = f"i_cva6_wrapper.i_ariane.i_cva6.gen_cache_wt.i_cache_subsystem.i_cva6_icache.gen_sram[{outer_row}].data_sram.gen_cut[1].i_tc_sram_wrapper.i_tc_sram.i_sram.gen_row[{row}].gen_col[{col}].i_sram_cell.sram0"
                template_object["MACROS"]["sram_hpdcache_64x128"]["instances"][inst_name] = {
                    "location": [
                        OFFSET_X + (NUM_COLS_CACHE_OUTER * NUM_COLS_CACHE + NUM_COLS_MEMCTRL_OUTER + NUM_COLS_ICACHE) * (SRAM_WIDTH + EXTRA_HORIZONTAL_SEPARATION) + col * (SRAM_WIDTH + EXTRA_HORIZONTAL_SEPARATION),
                        OFFSET_Y + (outer_row * NUM_ROWS_ICACHE + row) * (SRAM_HEIGHT + EXTRA_VERTICAL_SEPARATION)
                    ],
                    "orientation": "N"
                }
    # tag
    for outer_row in range(0, NUM_ICACHE_SRAMS):
        for row in range(0, NUM_ROWS_ICACHE):
            for col in range(0, NUM_COLS_ICACHE):
                inst_name = f"i_cva6_wrapper.i_ariane.i_cva6.gen_cache_wt.i_cache_subsystem.i_cva6_icache.gen_sram[{outer_row}].tag_sram.gen_cut[0].i_tc_sram_wrapper.i_tc_sram.i_sram.gen_row[{row}].gen_col[{col}].i_sram_cell.sram0"
                template_object["MACROS"]["sram_hpdcache_64x128"]["instances"][inst_name] = {
                    "location": [
                        OFFSET_X + (NUM_COLS_CACHE_OUTER * NUM_COLS_CACHE + NUM_COLS_MEMCTRL_OUTER + 2 * NUM_COLS_ICACHE) * (SRAM_WIDTH + EXTRA_HORIZONTAL_SEPARATION) + col * (SRAM_WIDTH + EXTRA_HORIZONTAL_SEPARATION),
                        OFFSET_Y + (outer_row * NUM_ROWS_MEMCTRL + row) * (SRAM_HEIGHT + EXTRA_VERTICAL_SEPARATION)
                    ],
                    "orientation": "N"
                }
    with open("config.json", "w") as output:
        dump(template_object, output, indent=4)
    

if __name__ == "__main__":
    main()
