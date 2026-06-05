#!/bin/env python3
from json import dump


OFFSET_X = 100 
OFFSET_Y = 100

template_object = {
  "DESIGN_NAME": "northcape_cap_cache_wrapper_verilog",
  "VERILOG_FILES": ["dir::../../../hardware/hdl/asic_wrappers/sram_northcape_wrapper.v","dir::northcape_cap_cache_flattened.v"],
  "VDD_NETS": [
	  "vccd1"
  ],

  "GND_NETS": [
	  "vssd1"
  ],
  "FP_CORE_UTIL": 30,
  "FP_SIZING": "absolute",
  #"PL_ROUTABILITY_MAX_DENSITY": 0.25,
  "PL_TIME_DRIVEN": True,
  "PL_ROUTABILITY_CHECK_OVERFLOW": 0.5,
  "PL_TARGET_DENSITY_PCT": 5,
  # "GPL_OVERFLOW_TARGET": 0.18,
  "PL_TARGET_RC_METRIC": 0.95,
  # "PL_WIRE_LENGTH_COEF": 0.5,
  "CLOCK_PERIOD": 1000,
  "CLOCK_PORT": "aclk",
  "RUN_LINTER": False,
  "GRT_OVERFLOW_ITERS": 500,
  "GRT_ALLOW_CONGESTION": True,
  "PL_USE_FASTROUTE_INSTEAD_OF_RUDY": True,
  "MACROS": {
    "sram_northcape_256x64": {
      "instances": {
      },
      
      "gds": [
          "dir::../macros/sram_northcape_256x64/sram_northcape_256x64.gds"
      ],
      "lef": [
          "dir::../macros/sram_northcape_256x64/sram_northcape_256x64.lef"
      ],
      "nl": [
      ],
      "spef": {
      },
      "lib": {
        "*ff_025C_1v80": ["dir::../macros/sram_northcape_256x64/sram_northcape_256x64_FF_1p8V_25C.lib"],
        "*ff_n40C_1v95": ["dir::../macros/sram_northcape_256x64/sram_northcape_256x64_FF_1p95V_40C.lib"],
        "*ss_025C_1v80": ["dir::../macros/sram_northcape_256x64/sram_northcape_256x64_SS_1p8V_25C.lib"],
        "*ss_100C_1v60": ["dir::../macros/sram_northcape_256x64/sram_northcape_256x64_SS_1p6V_100C.lib"],
        "*tt_000C_1v80": ["dir::../macros/sram_northcape_256x64/sram_northcape_256x64_TT_1p8V_0C.lib"],
        "*tt_025C_1v80": ["dir::../macros/sram_northcape_256x64/sram_northcape_256x64_TT_1p8V_25C.lib"],
        "*tt_100C_1v80": ["dir::../macros/sram_northcape_256x64/sram_northcape_256x64_TT_1p8V_100C.lib"]
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

NUM_COLS_CACHE =  int((COL_WIDTH + PRIMITIVE_WIDTH - 1) / PRIMITIVE_WIDTH)
NUM_ROWS_CACHE = int(((NUM_ENTRIES / ASSOCIATIVITY) + PRIMITIVE_DEPTH - 1) / PRIMITIVE_DEPTH)

NUM_COLS_MAX = 3

if NUM_COLS_CACHE > NUM_COLS_MAX:
    NUM_ROWS_CACHE_REAL = NUM_ROWS_CACHE * (NUM_COLS_CACHE/NUM_COLS_MAX)
    if NUM_COLS_CACHE % NUM_COLS_MAX:
        NUM_ROWS_CACHE_REAL = NUM_ROWS_CACHE_REAL + 1
else:
    NUM_ROWS_CACHE_REAL = NUM_ROWS_CACHE


EXTRA_HORIZONTAL_SEPARATION=1000
EXTRA_VERTICAL_SEPARATION=1000

SRAM_WIDTH=2097
SRAM_HEIGHT=431

def main():
    
    print(f"Cache grid {NUM_COLS_CACHE} * {NUM_ROWS_CACHE}")
    print(f"Store buffer grid {NUM_COLS_STORE_BUFFER} * {NUM_ROWS_STORE_BUFFER}")
    # center macros and leave some space aroudn them for logic
    DIE_WIDTH = NUM_COLS_MAX * SRAM_WIDTH + (NUM_COLS_MAX-1)*EXTRA_HORIZONTAL_SEPARATION + 2 * OFFSET_X
    # account for store buffer
    DIE_HEIGHT = (NUM_ROWS_CACHE_REAL) * SRAM_HEIGHT + (NUM_ROWS_CACHE_REAL-1)*EXTRA_VERTICAL_SEPARATION + 2 * OFFSET_Y
    print(f"Die area {DIE_WIDTH} * {DIE_HEIGHT}")

    template_object["DIE_AREA"] = f"0 0 {DIE_WIDTH} {DIE_HEIGHT}"

    cache_row = 0
    cache_col = 0

    for row in range(0, NUM_ROWS_CACHE):
        for col in range(0, NUM_COLS_CACHE):
            inst_name = f"i_northcape_cap_cache_wrapper.i_northcape_capability_cache.gen_cache_wt_n_assoc_bram.i_cache_wt_direct_bram.i_cache_sram.gen_row[{row}].gen_col[{col}].i_sram_cell.gen_large_sram.sram0"
            template_object["MACROS"]["sram_northcape_256x64"]["instances"][inst_name] = {
                "location": [
                    OFFSET_X + cache_col * (SRAM_WIDTH + EXTRA_HORIZONTAL_SEPARATION),
                    OFFSET_Y + (cache_row) * (SRAM_HEIGHT + EXTRA_VERTICAL_SEPARATION) # store buffer!
                ],
                "orientation": "N"
            }
            cache_col = cache_col + 1
            if cache_col == NUM_COLS_MAX:
                cache_col = 0
                cache_row = cache_row + 1
    for row in range(0, NUM_ROWS_STORE_BUFFER):
        for col in range(0, NUM_COLS_STORE_BUFFER):
            inst_name = f"i_northcape_cap_cache_wrapper.i_northcape_capability_cache.i_writeback_unit.gen_store_buffer.i_store_buffer.i_cmt_buffer.i_sram_dport.gen_row[{row}].gen_col[{col}].i_sram_cell.gen_large_sram.sram0"
            template_object["MACROS"]["sram_northcape_256x64"]["instances"][inst_name] = {
                "location": [
                    OFFSET_X + cache_col * (SRAM_WIDTH + EXTRA_HORIZONTAL_SEPARATION),
                    OFFSET_Y + (cache_row ) * (SRAM_HEIGHT + EXTRA_VERTICAL_SEPARATION) # store buffer!
                ],
                "orientation": "N"
            }
            cache_col = cache_col + 1
            if cache_col == NUM_COLS_MAX:
                cache_col = 0
                cache_row = cache_row + 1
    with open("config.json", "w") as output:
        dump(template_object, output, indent=4)
    

if __name__ == "__main__":
    main()
