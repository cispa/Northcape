#include <zephyr/toolchain.h>
#include <zephyr/arch/riscv/csr.h>

GTEXT(skadi_sched_yield_callee_trampoline)

skadi_sched_yield_callee_trampoline:
    csrci mstatus, MSTATUS_MIE
    ret
