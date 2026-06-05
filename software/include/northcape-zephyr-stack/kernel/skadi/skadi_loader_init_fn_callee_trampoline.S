#include <zephyr/toolchain.h>
#include <zephyr/linker/sections.h>
#include <zephyr/arch/riscv/csr.h>

.global skadi_loader_init_fn_callee_trampoline
.p2align 3
/**
  * @brief trampoline for calling into an init function of a subsystem.
  * We cannot jump into an init function directly with set-task-id, as it is not at the beginning of the segment.
  * If we use derive on the init function, the relocation is off.
  */
skadi_loader_init_fn_callee_trampoline:
    // we abuse the global pointer to pass the actual function we want to call
    mv t1, gp
    li gp, 0
#ifdef CONFIG_SKADI_RESET_BRANCH_TABLE_ON_SUBSYSTEM_CALL
    // destroy branch target prediction entries to prevent speculatively executing a subsystem call beyond our bounds
    csrrsi x0, 0x7C0, 2
#endif
    //Allocate space for return address on stack
    addi sp, sp, -8
    /* Save return address */
    sd ra, 0(sp)  

    /* TODO this enables FPU for all subsystems, even the ones which do not use it, during init... */
    li t0, MSTATUS_FS
    csrs mstatus, t0

    // jump to t1, destroying ra
    jalr t1
    // restore our original return address
    // stack is destroyed anyway after return, so no need to waste cycles re-adjusting it
    ld ra, 0(sp)
#ifdef CONFIG_SKADI_RESET_BRANCH_TABLE_ON_SUBSYSTEM_CALL
    // destroy branch target prediction entries to prevent speculatively executing a subsystem call beyond our bounds
    csrrsi x0, 0x7C0, 2
    // force any memory transactions to commit
    fence
#endif
    // return using our original return address
    ret
    // padding for speculative fetching of next instruction
    // otherwise, there might be a read error cause by the speculative fetch running outside of the segment
    .byte 0, 1, 2, 3, 4, 5, 6, 7
    .byte 8, 9, 10, 11, 12, 13, 14, 15

.global skadi_loader_init_fn_callee_trampoline_end
skadi_loader_init_fn_callee_trampoline_end:
    nop
    nop


GTEXT(skadi_subsystem_mtimer_sched_hook_reloc)
/*
 * Used by subsystem return / callee trampolines in loader
 */
.p2align 3
skadi_subsystem_mtimer_sched_hook_reloc:
	.dword 0x0
