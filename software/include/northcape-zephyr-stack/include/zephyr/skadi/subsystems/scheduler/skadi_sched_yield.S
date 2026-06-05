#include <zephyr/toolchain.h>
#include <zephyr/linker/sections.h>

#include <zephyr/skadi/skadi_asm.h>

#include <zephyr/arch/riscv/csr.h>
#include <zephyr/skadi/skadi_ops_constants.h>

#ifdef SKADI_SUBSYSTEM_HAS_FPU
/* need to save FPU regs as well: 12 tmp regs, 8 arg regs, 12 callee-saved regs */
#define SKADI_SUBSYSTEM_YIELD_STACK_SIZE (272+256)
#else
#define SKADI_SUBSYSTEM_YIELD_STACK_SIZE 272
#endif
#define MIE_MTIE MIP_MTIP

GTEXT(_skadi_subsystem_yield_stub)
GTEXT(_skadi_subsystem_yield_stub_return)
GTEXT(_skadi_subsystem_yield_stub_return_end)

GTEXT(skadi_subsystem_mtimer_sched_hook_reloc)

.p2align 3
skadi_subsystem_mtimer_sched_hook_reloc:
	.dword 0x0

.p2align 3
.skadi_sched_yield_stub_return_addr_reloc:
	.dword skadi_sched_yield_stub_return_addr

.p2align 3
.skadi_sched_yield_callee_trampoline_reloc:
    .dword skadi_sched_yield_callee_trampoline

#if defined(CONFIG_PROFILING_PERF) && !defined(LOADER_SUBSYSTEM)
GDATA(skadi_profiling_current_isr_state_reloc)
.p2align 3
.skadi_profiling_current_isr_state_reloc:
    .dword skadi_profiling_current_isr_state_reloc
#endif

#ifdef CONFIG_SKADI_DEBUG
.skadi_sched_yield_dummy_loop:
    j .skadi_sched_yield_dummy_loop
#endif

.type skadi_sched_yield_callee_trampoline, %function

SECTION_FUNC(TEXT, _skadi_subsystem_yield_stub)
#ifdef CONFIG_SKADI_DEBUG
    beqz sp, .skadi_sched_yield_dummy_loop
#endif
    addi sp, sp, -SKADI_SUBSYSTEM_YIELD_STACK_SIZE
    sd ra, 8(sp)
    /* sp is stored somewhere else */
    sd t0, 32(sp)
    sd t1, 40(sp)
    sd t2, 48(sp)
    /* remainder of register set stored when we are able to yield */
    /* save exception and return state */
    csrr t0, mepc
    sd t0, 248(sp)

#if defined(CONFIG_PROFILING_PERF) && !defined(LOADER_SUBSYSTEM)
/* careful - might not have been set up properly yet! */
    ld t1, .skadi_profiling_current_isr_state_reloc
beqz t1, _perf_done
    ld t1, 0(t1) /* double indirection - large code model */
beqz t1, _perf_done
    sd t0, 0(t1) /* mepc */
    sd s0, 8(t1) /* fp */
    sd ra, 16(t1) /* ra */
    li t0, 0x1
    sd t0, 24(t1) /* valid */
_perf_done:
#endif

    csrr t0, mie
    sd t0, 264(sp)

    /* prevent leaking any information via mtval, mepc */
    csrw mtval, zero
    csrw mepc, zero

    /* we need this to return into normal code segment from return trampoline */
    la t0, skadi_sched_yield_restore_regs
    sd t0, 0(sp)

    /* yield subsystem call token */
    ld t0, .skadi_sched_yield_callee_trampoline_reloc

    /* load address of _skadi_subsystem_yield_stub_return with set-task-id, for return */
    ld ra, .skadi_sched_yield_stub_return_addr_reloc
    ld ra, 0(ra)
    
    /* TODO this is not reentrant */
    /* save the stack pointer with the registers */
    /* code segment is not writable, so the actual value needs to live in data segment and be run-time relocated */
    ld t1, .skadi_sched_yield_return_sp_reloc

    /* check the stack pointer */
    ld t2, 0(t1)
    beq t2, zero, _skadi_sched_yield_stack_free
    /* a stack pointer is already here - we cannot yield. We restore the original registers, disable the timer interrupt and return. */

    /* disable timer interrupt - otherwise, we would end up here again */
    li t0, MIE_MTIE
    csrc mie, t0

    /* restore registers */
    ld t0, 248(sp)
    csrw mepc, t0

    ld t0, 32(sp)
    ld t1, 40(sp)
    ld t2, 48(sp)
    ld ra, 8(sp)
    /* sp = original value */
    addi sp, sp, SKADI_SUBSYSTEM_YIELD_STACK_SIZE

    /* continue execution */
    /* at some point, we return or call someone else, who should be able to continue yielding */
    mret

/* no stack pointer - can safely continue */
_skadi_sched_yield_stack_free:
    sd sp, 0(t1)

    /* we need to continue saving registers... */
    sd gp, 16(sp)
    sd tp, 24(sp)
    sd s0, 56(sp)
    sd s1, 64(sp)
    sd a0, 72(sp)
    sd a1, 80(sp)
    sd a2, 88(sp)
    sd a3, 96(sp)
    sd a4, 104(sp)
    sd a5, 112(sp)
    sd a6, 120(sp)
    sd a7, 128(sp)
    sd s2, 136(sp)
    sd s3, 144(sp)
    sd s4, 152(sp)
    sd s5, 160(sp)
    sd s6, 168(sp)
    sd s7, 176(sp)
    sd s8, 184(sp)
    sd s9, 192(sp)
    sd s10, 200(sp)
    sd s11, 208(sp)
    sd t3, 216(sp)
    sd t4, 224(sp)
    sd t5, 232(sp)
    sd t6, 240(sp)

    csrr t1, mstatus
    sd t1, 256(sp)

#ifdef SKADI_SUBSYSTEM_HAS_FPU
    li t2, MSTATUS_FS
    and t1, t1, t2
    /* FPU not yet setup - leave the FPU alone for now */
    beqz t1, fp_store_done

    /* FP temporaries */
    fsd ft0, 272(sp)
    fsd ft1, 280(sp)
    fsd ft2, 288(sp)
    fsd ft3, 296(sp)
    fsd ft4, 304(sp)
    fsd ft5, 312(sp)
    fsd ft6, 320(sp)
    fsd ft7, 328(sp)
    fsd ft8, 336(sp)
    fsd ft9, 344(sp)
    fsd ft10, 352(sp)
    fsd ft11, 360(sp)

    /* FP callee-saved */
    fsd fs0, 368(sp)
    fsd fs1, 376(sp)
    fsd fs2, 384(sp)
    fsd fs3, 392(sp)
    fsd fs4, 400(sp)
    fsd fs5, 408(sp)
    fsd fs6, 416(sp)
    fsd fs7, 424(sp)
    fsd fs8, 432(sp)
    fsd fs9, 440(sp)
    fsd fs10, 448(sp)
    fsd fs11, 456(sp)

    /* FP args */
    fsd fa0, 464(sp)
    fsd fa1, 472(sp)
    fsd fa2, 480(sp)
    fsd fa3, 488(sp)
    fsd fa4, 496(sp)
    fsd fa5, 504(sp)
    fsd fa6, 512(sp)
    fsd fa7, 520(sp)

#if defined(CONFIG_SKADI_SUBSYSTEM_CALL_NOCHECKS) || defined(CONFIG_SKADI_FAST_REG_ZERO_INSTRUCTION)
    /* nothing to do */
#else

    /* FP temporaries */
    fmv.d.x ft0, zero
    fmv.d.x ft1, zero
    fmv.d.x ft2, zero
    fmv.d.x ft3, zero
    fmv.d.x ft4, zero
    fmv.d.x ft5, zero
    fmv.d.x ft6, zero
    fmv.d.x ft7, zero
    fmv.d.x ft8, zero
    fmv.d.x ft9, zero
    fmv.d.x ft10, zero
    fmv.d.x ft11, zero

    /* FP callee-saved */
    fmv.d.x fs0, zero
    fmv.d.x fs1, zero
    fmv.d.x fs2, zero
    fmv.d.x fs3, zero
    fmv.d.x fs4, zero
    fmv.d.x fs5, zero
    fmv.d.x fs6, zero
    fmv.d.x fs7, zero
    fmv.d.x fs8, zero
    fmv.d.x fs9, zero
    fmv.d.x fs10, zero
    fmv.d.x fs11, zero

    /* FP args */
    fmv.d.x fa0, zero
    fmv.d.x fa1, zero
    fmv.d.x fa2, zero
    fmv.d.x fa3, zero
    fmv.d.x fa4, zero
    fmv.d.x fa5, zero
    fmv.d.x fa6, zero
    fmv.d.x fa7, zero
#endif /* CONFIG_SKADI_SUBSYSTEM_CALL_NOCHECKS || CONFIG_SKADI_FAST_REG_ZERO_INSTRUCTION */

fp_store_done:
#endif

#if defined(CONFIG_SKADI_SUBSYSTEM_CALL_NOCHECKS) || defined(CONFIG_SKADI_FAST_REG_ZERO_INSTRUCTION)
    /* nothing to do */
#else
    /* destroy registers except t0, ra which we need for the call */
    li sp, 0
    li gp, 0
    li tp, 0
    li t1, 0
    li t2, 0
    li s0, 0
    li s1, 0
    li a0, 0
    li a1, 0
    li a2, 0
    li a3, 0
    li a4, 0
    li a5, 0
    li a6, 0
    li a7, 0
    li s2, 0
    li s3, 0
    li s4, 0
    li s5, 0
    li s6, 0
    li s7, 0
    li s8, 0
    li s9, 0
    li s10, 0
    li s11, 0
    li t3, 0
    li t4, 0
    li t5, 0
    li t6, 0
#endif /* CONFIG_SKADI_SUBSYSTEM_CALL_NOCHECKS || CONFIG_SKADI_FAST_REG_ZERO_INSTRUCTION */

#ifdef CONFIG_SKADI_FAST_REG_ZERO_INSTRUCTION
    ld t1, .skadi_sched_yield_clear_arg_mask
    SKADI_REGCALL(t1)
#endif

    csrwi mepc, 0

    /* do subsystem call */
    jr t0
SECTION_FUNC(TEXT, _skadi_subsystem_yield_stub_return)


    /* returned from subsystem call */
    /* load SP via double indirection */
    ld sp, .skadi_sched_yield_return_sp_reloc

    /* make sure that the stack pointer is cleared, such that we can yield again */
    ld t1, 0(sp)
    sd zero, 0(sp)
    mv sp, t1

    /* continue in skadi_sched_yield_restore_regs, but in normal code segment instead of return trampoline - can access all globals etc. */
    ld t0, 0(sp)
    jr t0


skadi_sched_yield_restore_regs:
    /* restore address at which we were preempted */
    ld t0, 248(sp)
    csrw mepc, t0

#ifdef CONFIG_SKADI_DEBUG
    li a0, 2
    /* if hook was not properly initialized, spin */
    beqz t0, .skadi_sched_yield_dummy_loop
#endif

    /* restore IRQ handler for preemption */

    la t1, _skadi_subsystem_yield_stub
    csrw SKADI_MTIMER_HOOK_CSR, t1     

    /* restore IRQ state */
    ld t1, 256(sp)
    csrw mstatus, t1
    
    ld t0, 264(sp)
    csrw mie, t0

#ifdef SKADI_SUBSYSTEM_HAS_FPU
    li t2, MSTATUS_FS
    and t1, t1, t2 
    /* FPU not yet setup - leave the FPU alone for now */
    beqz t1, fp_restore_done

    /* FP temporaries */
    fld ft0, 272(sp)
    fld ft1, 280(sp)
    fld ft2, 288(sp)
    fld ft3, 296(sp)
    fld ft4, 304(sp)
    fld ft5, 312(sp)
    fld ft6, 320(sp)
    fld ft7, 328(sp)
    fld ft8, 336(sp)
    fld ft9, 344(sp)
    fld ft10, 352(sp)
    fld ft11, 360(sp)

    /* FP callee-saved */
    fld fs0, 368(sp)
    fld fs1, 376(sp)
    fld fs2, 384(sp)
    fld fs3, 392(sp)
    fld fs4, 400(sp)
    fld fs5, 408(sp)
    fld fs6, 416(sp)
    fld fs7, 424(sp)
    fld fs8, 432(sp)
    fld fs9, 440(sp)
    fld fs10, 448(sp)
    fld fs11, 456(sp)

    /* FP args */
    fld fa0, 464(sp)
    fld fa1, 472(sp)
    fld fa2, 480(sp)
    fld fa3, 488(sp)
    fld fa4, 496(sp)
    fld fa5, 504(sp)
    fld fa6, 512(sp)
    fld fa7, 520(sp)

fp_restore_done:
#endif

    /* restore regs */
    ld ra, 8(sp)
    ld gp, 16(sp)
    ld tp, 24(sp)
    ld t0, 32(sp)
    ld t1, 40(sp)
    ld t2, 48(sp)
    ld s0, 56(sp)
    ld s1, 64(sp)
    ld a0, 72(sp)
    ld a1, 80(sp)
    ld a2, 88(sp)
    ld a3, 96(sp)
    ld a4, 104(sp)
    ld a5, 112(sp)
    ld a6, 120(sp)
    ld a7, 128(sp)
    ld s2, 136(sp)
    ld s3, 144(sp)
    ld s4, 152(sp)
    ld s5, 160(sp)
    ld s6, 168(sp)
    ld s7, 176(sp)
    ld s8, 184(sp)
    ld s9, 192(sp)
    ld s10, 200(sp)
    ld s11, 208(sp)
    ld t3, 216(sp)
    ld t4, 224(sp)
    ld t5, 232(sp)
    ld t6, 240(sp)

    /* restore stack */
    addi sp, sp, SKADI_SUBSYSTEM_YIELD_STACK_SIZE

    /* continue execution */
    mret

.p2align 3
.skadi_sched_yield_return_sp_reloc:
	.dword skadi_sched_yield_stack_ptr_save
#ifdef CONFIG_SKADI_FAST_REG_ZERO_INSTRUCTION
.p2align 3
.skadi_sched_yield_clear_arg_mask:
    .dword SKADI_CLEAR_REG_YIELD_STUB
#endif

SECTION_FUNC(TEXT, _skadi_subsystem_yield_stub_return_end)
    nop


