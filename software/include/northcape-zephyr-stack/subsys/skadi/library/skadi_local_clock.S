#include <zephyr/toolchain.h>

GDATA(__skadi_subsystem_mtime_reg_capability)

.skadi_subsystem_mtime_reg_capability_reloc:
    .dword __skadi_subsystem_mtime_reg_capability

/* overwritten in the sys clock */
WTEXT(skadi_sys_clock_cycle_get_32)
WTEXT(skadi_sys_clock_cycle_get_64)

/* uint32_t skadi_sys_clock_cycle_get_32(void); */
SECTION_FUNC(TEXT, skadi_sys_clock_cycle_get_32)
    ld a0, .skadi_subsystem_mtime_reg_capability_reloc
    lw a0, 0(a0)
    ret


/* uint64_t skadi_sys_clock_cycle_get_64(void); */
SECTION_FUNC(TEXT, skadi_sys_clock_cycle_get_64)
    ld a0, .skadi_subsystem_mtime_reg_capability_reloc
    ld a0, 0(a0)
    ret
