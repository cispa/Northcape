/*
 * Copyright (c) 2016 Jean-Paul Etienne <fractalclone@gmail.com>
 * Copyright (c) 2018 Foundries.io Ltd
 * Copyright (c) 2020 BayLibre, SAS
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/toolchain.h>
#include <zephyr/linker/sections.h>
#include <zephyr/arch/cpu.h>
#include <zephyr/sys/util.h>
#include <zephyr/kernel.h>
#include <zephyr/syscall.h>
#include <zephyr/arch/riscv/csr.h>
#include <zephyr/arch/riscv/irq.h>
#include <zephyr/arch/riscv/syscall.h>
#include "asm_macros.inc"
#include "offsets_short.h"


/* Convenience macro for loading/storing register states. */
#define DO_CALLER_SAVED(op) \
	RV_E(	op t0, __struct_arch_esf_t0_OFFSET(sp)	);\
	RV_E(	op t1, __struct_arch_esf_t1_OFFSET(sp)	);\
	RV_E(	op t2, __struct_arch_esf_t2_OFFSET(sp)	);\
	RV_I(	op t3, __struct_arch_esf_t3_OFFSET(sp)	);\
	RV_I(	op t4, __struct_arch_esf_t4_OFFSET(sp)	);\
	RV_I(	op t5, __struct_arch_esf_t5_OFFSET(sp)	);\
	RV_I(	op t6, __struct_arch_esf_t6_OFFSET(sp)	);\
	RV_E(	op a0, __struct_arch_esf_a0_OFFSET(sp)	);\
	RV_E(	op a1, __struct_arch_esf_a1_OFFSET(sp)	);\
	RV_E(	op a2, __struct_arch_esf_a2_OFFSET(sp)	);\
	RV_E(	op a3, __struct_arch_esf_a3_OFFSET(sp)	);\
	RV_E(	op a4, __struct_arch_esf_a4_OFFSET(sp)	);\
	RV_E(	op a5, __struct_arch_esf_a5_OFFSET(sp)	);\
	RV_I(	op a6, __struct_arch_esf_a6_OFFSET(sp)	);\
	RV_I(	op a7, __struct_arch_esf_a7_OFFSET(sp)	);\
	RV_E(	op ra, __struct_arch_esf_ra_OFFSET(sp)	)

#ifdef CONFIG_EXCEPTION_DEBUG
/* Convenience macro for storing callee saved register [s0 - s11] states. */
#define STORE_CALLEE_SAVED() \
	RV_E(	sr s0, ___callee_saved_t_s0_OFFSET(sp)		);\
	RV_E(	sr s1, ___callee_saved_t_s1_OFFSET(sp)		);\
	RV_I(	sr s2, ___callee_saved_t_s2_OFFSET(sp)		);\
	RV_I(	sr s3, ___callee_saved_t_s3_OFFSET(sp)		);\
	RV_I(	sr s4, ___callee_saved_t_s4_OFFSET(sp)		);\
	RV_I(	sr s5, ___callee_saved_t_s5_OFFSET(sp)		);\
	RV_I(	sr s6, ___callee_saved_t_s6_OFFSET(sp)		);\
	RV_I(	sr s7, ___callee_saved_t_s7_OFFSET(sp)		);\
	RV_I(	sr s8, ___callee_saved_t_s8_OFFSET(sp)		);\
	RV_I(	sr s9, ___callee_saved_t_s9_OFFSET(sp)		);\
	RV_I(	sr s10, ___callee_saved_t_s10_OFFSET(sp)	);\
	RV_I(	sr s11, ___callee_saved_t_s11_OFFSET(sp)	)
#endif /* CONFIG_EXCEPTION_DEBUG */

/* imports */
GDATA(skadi_isr_table)
#ifdef CONFIG_SKADI_DEBUG
GDATA(skadi_isr_level)
#endif
GTEXT(__soc_handle_irq)
GTEXT(_Fault)

#ifdef CONFIG_EXCEPTION_DEBUG
GTEXT(z_riscv_fatal_error_csf)
#else
GTEXT(z_riscv_fatal_error)
#endif /* CONFIG_EXCEPTION_DEBUG */

/* void skadi_isr_wrap_subsystem_call (void *arg, void (*isr)(void *arg)) */
GTEXT(skadi_isr_wrap_subsystem_call)


/* create relocations for data symbols "near" the ISR wrapper */
/* might otherwise be out of range (data/bss segments can have different Skadi token) */
.p2align 3
.isr_stack_reloc:
	.dword isr_stack

.p2align 3
.skadi_isr_table_reloc:
	.dword skadi_isr_table

#ifdef CONFIG_SKADI_DEBUG
.p2align 3
.skadi_isr_level_reloc:
	.dword skadi_isr_level
#endif

/* address of the token using which the current timer ISR can be read/written */
.p2align 3
skadi_isr_timer_sched_hook_reloc:
	.dword 0x0

/* exports */
GTEXT(_skadi_isr_wrapper_callee_trampoline)
GTEXT(skadi_isr_timer_sched_hook_reloc)

/* use ABI name of registers for the sake of simplicity */

/* called at the beginning of the ISR handling by the CPU */
/* must be basic block that retrieves the actual ISR from a PC-relative location and jumps there */
/* will be relocated into a different code segment by the loader after init! */
SECTION_FUNC(TEXT, _skadi_isr_wrapper_callee_trampoline)
/* Provide requested alignment, which depends e.g. on MTVEC format */
/* will be relocated to beginning of the derived segment */
#ifdef CONFIG_SKADI_TEXT_ALIGN_12_BIT
.p2align 12
#else
.balign CONFIG_RISCV_TRAP_HANDLER_ALIGNMENT
#endif
	/* allow all pending loads/stores to complete */
	fence
#ifndef CONFIG_SKADI_CACHE_INTEGRATION
	/* flush instruction cache --> indicate to MMU that we are now running in IRQ context*/
	csrwi 0x7C0, 0x00
	csrwi 0x7C0, 0x01
	/* flush data cache --> prevent spurious reads in IRQ context */
	csrwi 0x7C1, 0x00
	csrwi 0x7C1, 0x01
#endif
	/* flush branch prediction */
	csrsi 0x7C0, 0x02
/* if we have separate ISR register file, there is no need to save the registers - they are from our last invocation */
#ifndef CONFIG_SKADI_ASSUME_IRQ_REGFILE
	csrw mscratch, s0
#endif
	lr s0, .skadi_isr_wrapper_embedded_token_reloc
	jr s0
/* executable token (i.e., address) of _skadi_isr_wrapper */
/* must be set at init time using _skadi_isr_wrapper_callee_trampoline_init */
/* must also be in the trampoline, such that it can access it PC-relatively */
.p2align 3
.skadi_isr_wrapper_embedded_token_reloc:
.dword 0x0
// loader needs to know where the ISR is over
// otherwise refuses to load
GTEXT(_skadi_isr_wrapper_callee_trampoline_end)
SECTION_FUNC(TEXT,_skadi_isr_wrapper_callee_trampoline_end)
_skadi_isr_wrapper_callee_trampoline_end:
	nop

GTEXT(_skadi_isr_wrapper_callee_trampoline_init)
/* void _skadi_isr_wrapper_callee_trampoline_init(void); */
SECTION_FUNC(TEXT, _skadi_isr_wrapper_callee_trampoline_init)
	la t0, _skadi_isr_wrapper
	la t1, .skadi_isr_wrapper_embedded_token_reloc
	sr t0, 0(t1)
	ret

/*
 * Handler called upon each exception/interrupt/fault
 */
SECTION_FUNC(TEXT, _skadi_isr_wrapper)

	/* we need to bring in per-thread ISR stack from relocation */
	ld s0, .isr_stack_reloc
	ld s0, 0(s0)

/* if we have separate ISR register file, there is no need to save the registers */
#ifndef CONFIG_SKADI_ASSUME_IRQ_REGFILE
	/* save current sp on about-to-be-pushed ESF structure */
	sr sp, (-__struct_arch_esf_SIZEOF + __struct_arch_esf_sp_OFFSET)(s0)
#endif
	/* use the shadow stack */
	mv sp, s0

#ifdef CONFIG_SKADI_DEBUG
	ld s0, .skadi_isr_level_reloc
	ld s0, 0(s0)

	/* dummy loop */
	check_level:
	bnez s0, check_level

	ld s0, .skadi_isr_level_reloc
	/* cannot be 0 */
	sd sp, 0(s0)
#endif

#ifndef CONFIG_SKADI_ASSUME_IRQ_REGFILE
	/* get the s0 back */
	csrr s0, mscratch
	/* currently have interrupted register set with the exception of sp, pc */
#endif

	/* Save caller-saved registers on current thread stack. */
	addi sp, sp, -__struct_arch_esf_SIZEOF

#ifndef CONFIG_SKADI_ASSUME_IRQ_REGFILE
	DO_CALLER_SAVED(sr)		;

	/* Save s0 in the esf and load it with &_current_cpu. */
	sr s0, __struct_arch_esf_s0_OFFSET(sp)
#endif


	/* in Skadi IRQ mode, mepc and mstatus are immutable (and cannot be written) */
#ifndef CONFIG_SKADI_ASSUME_IRQ_REGFILE
	/* Save MEPC register */
	csrr t0, mepc
	sr t0, __struct_arch_esf_mepc_OFFSET(sp)
	/* mstatus needed in all scenarios for FP support */
#endif

	/* Save MSTATUS register */
	csrr t2, mstatus
	sr t2, __struct_arch_esf_mstatus_OFFSET(sp)

	/* Skadi/cva6 sets high bit for IRQ */
	csrr t0, mcause
	srli t0, t0, RISCV_MCAUSE_IRQ_POS
	bnez t0, is_interrupt

	/* no interrupt */
	/* we do not handle syscalls or similar, all exceptions imply an error */

	/*
	 * Call _Fault to handle exception.
	 * Stack pointer is pointing to a struct_arch_esf structure, pass it
	 * to _Fault (via register a0).
	 * If _Fault shall return, set return address to
	 * no_reschedule to restore stack.
	 */
	mv a0, sp
	la ra, no_reschedule
	tail _Fault

is_interrupt:

	/* Get IRQ causing interrupt */
	csrr a0, mcause
	li t0, CONFIG_RISCV_MCAUSE_EXCEPTION_MASK
	and a0, a0, t0

	/*
	 * Clear pending IRQ generating the interrupt at SOC level
	 * Pass IRQ number to __soc_handle_irq via register a0
	 */
	jal ra, __soc_handle_irq

	/*
	 * Call corresponding registered function in skadi_isr_table via relocation.
	 * (table is 2-word wide, we should shift index accordingly)
	 */
	ld t0, .skadi_isr_table_reloc
	slli a0, a0, (RV_REGSHIFT + 1)
	add t0, t0, a0

	/* Load argument in a0 register */
	lr a0, 0(t0)

	/* Load ISR function address in register a1 */
	lr a1, RV_REGSIZE(t0)

	/* Call ISR function via wrapper */
	call skadi_isr_wrap_subsystem_call

#ifdef CONFIG_SKADI_DEBUG
	/* IRQs should be off here */
	ld s0, .skadi_isr_level_reloc
	sd zero, 0(s0)
#endif

irq_done:

	/* no stack sentinel - might not be able to read stack's thread */

check_reschedule:

	/* we NEVER reschedule */
	/* that is the job of the timer ISR */

no_reschedule:

#ifndef CONFIG_SKADI_ASSUME_IRQ_REGFILE
	/* Restore MEPC and MSTATUS registers */
	lr t0, __struct_arch_esf_mepc_OFFSET(sp)
	csrw mepc, t0
#endif

	lr t2, __struct_arch_esf_mstatus_OFFSET(sp)
	csrw mstatus, t2

#ifndef CONFIG_SKADI_ASSUME_IRQ_REGFILE
	/* stack with removed ESF structure */
	addi t0, sp, __struct_arch_esf_SIZEOF

	/* Restore s0 (it is no longer ours) */
	lr s0, __struct_arch_esf_s0_OFFSET(sp)
#endif

#ifndef CONFIG_SKADI_ASSUME_IRQ_REGFILE
	/* Restore caller-saved registers from thread stack */
	DO_CALLER_SAVED(lr)

	/* retrieve saved stack pointer */
	lr sp, __struct_arch_esf_sp_OFFSET(sp)
#endif

    /* flush reads/writes/branch prediction and clear cache */				
	csrsi 0x7C0, 2														
    fence																	
#ifndef CONFIG_SKADI_CACHE_INTEGRATION
	/* flush data cache */													
	csrwi 0x7C1, 0x00														
	csrwi 0x7C1, 0x01														
	/* flush instruction cache */											
	csrwi 0x7C0, 0x00														
	csrwi 0x7C0, 0x01
#endif

	mret
