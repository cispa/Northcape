# pragma once

#ifndef SKADI_ARIANE_GENESYSII_H
#define SKADI_ARIANE_GENESYSII_H
    #include <zephyr/devicetree.h>
    
    #define SKADI_ARIANE_DRAM_LENGTH_BYTES (DT_REG_SIZE(DT_CHOSEN(zephyr_sram)) + DT_REG_SIZE(DT_CHOSEN(skadi_test_arena)) + DT_REG_SIZE(DT_CHOSEN(skadi_mem_arena)))
    
    #define SKADI_ARIANE_DRAM_BASE_BYTES DT_REG_ADDR_U64_RAW(DT_CHOSEN(zephyr_sram))

    // all requests into CMT are unconditionally rejected
    #define SKADI_CMT_LENGTH_ENTRIES 32768
    // 256 bit / 32 byte per entry
    #define SKADI_CMT_LENGTH_BYTES ((SKADI_CMT_LENGTH_ENTRIES*32))

    // begin of reserved region
    // zephyr is not allowed to use it
    #define SKADI_ARIANE_RESERVED_BASE_BYTES DT_REG_ADDR_U64_RAW(DT_CHOSEN(skadi_mem_arena))
    #define SKADI_ARIANE_RESERVED_LENGTH_BYTES (SKADI_ARIANE_DRAM_BASE_BYTES + SKADI_ARIANE_DRAM_LENGTH_BYTES - SKADI_CMT_LENGTH_BYTES - SKADI_ARIANE_RESERVED_BASE_BYTES)

    #define SKADI_ROOT_CAPABILITY_END_BYTES 0xffffffff

#endif
