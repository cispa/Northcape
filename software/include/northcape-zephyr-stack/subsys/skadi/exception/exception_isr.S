/*
 * Copyright (c) 2016 Jean-Paul Etienne <fractalclone@gmail.com>
 * Copyright (c) 2018 Foundries.io Ltd
 * Copyright (c) 2020 BayLibre, SAS
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/toolchain.h>
#include <zephyr/arch/riscv/csr.h>

/* void skadi_handle_exception (void) */
GTEXT(skadi_handle_exception)


/* create relocations for data symbols "near" the ISR wrapper */
/* might otherwise be out of range (data/bss segments can have different Skadi token) */
.p2align 3
exception_stack_reloc:
	.dword exception_stack

/* exports */
GTEXT(_skadi_exception_wrapper_callee_trampoline)

/* use ABI name of registers for the sake of simplicity */

/* called at the beginning of the ISR handling by the CPU */
/* must be basic block that retrieves the actual ISR from a PC-relative location and jumps there */
/* will be relocated into a different code segment by the loader after init! */
#ifdef SKADI_SUBSYSTEM
SECTION_FUNC(TEXT, _skadi_exception_wrapper_callee_trampoline)
#else
_skadi_exception_wrapper_callee_trampoline:
#endif
/* Provide requested alignment, which depends e.g. on MTVEC format */
/* will be relocated to beginning of the derived segment */
.balign CONFIG_RISCV_TRAP_HANDLER_ALIGNMENT
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
	ld s0, .skadi_exception_wrapper_embedded_token_reloc
	jr s0
/* executable token (i.e., address) of _skadi_exception_wrapper */
/* must also be in the trampoline, such that it can access it PC-relatively */
.p2align 3
.skadi_exception_wrapper_embedded_token_reloc:
.dword _skadi_exception_wrapper
// loader needs to know where the ISR is over
// otherwise refuses to load
GTEXT(_skadi_exception_wrapper_callee_trampoline_end)
#ifdef SKADI_SUBSYSTEM
SECTION_FUNC(TEXT,_skadi_exception_wrapper_callee_trampoline_end)
#else
_skadi_exception_wrapper_callee_trampoline_end:
#endif
	nop

.p2align 3
.exception_register_set_reloc:
	.dword exception_register_set
#ifdef SKADI_SUBSYSTEM
/*
 * Handler called upon each exception/interrupt/fault
 */
SECTION_FUNC(TEXT, _skadi_exception_wrapper)
#else
_skadi_exception_wrapper:
#endif
	/* we need the register value momentarily */
	csrw mscratch, s0

	ld s0, .exception_register_set_reloc

	/* keep registers for printing error */
	sd a0, 0(s0)
	sd a1, 8(s0)
	sd a2, 16(s0)
	sd a3, 24(s0)
	sd a4, 32(s0)
	sd a5, 40(s0)
	sd a6, 48(s0)
	sd a7, 56(s0)
	sd t0, 64(s0)
	sd t1, 72(s0)
	sd t2, 80(s0)
	sd t3, 88(s0)
	sd t4, 96(s0)
	sd t5, 104(s0)
	sd t6, 112(s0)
	csrr t0, mscratch
	/* the old s0 */
	sd t0, 120(s0)
	sd s1, 128(s0)
	sd s2, 136(s0)
	sd s3, 144(s0)
	sd s4, 152(s0)
	sd s5, 160(s0)
	sd s6, 168(s0)
	sd s7, 176(s0)
	sd s8, 184(s0)
	sd s9, 192(s0)
	sd s10, 200(s0)
	sd s11, 208(s0)
	sd sp, 216(s0)
	sd ra, 224(s0)


	/* CSRs */
	csrr t0, mepc
	sd t0, 232(s0)

	csrr t0, mstatus
	sd t0, 240(s0)

	csrr t0, mtval
	sd t0, 248(s0)

	csrr t0, mcause
	sd t0, 256(s0)


	/* we need to bring in per-thread ISR stack from relocation */
	ld sp, exception_stack_reloc
	ld sp, 0(sp)

	call skadi_handle_exception

	/* skadi_handle_exception SHOULD not return; in case it does, spin */

dummy_loop:
	j dummy_loop

/* the loader's dummy yield stub */
#ifndef SKADI_SUBSYSTEM
GTEXT(_skadi_subsystem_yield_stub)
.p2align 0x3
_skadi_subsystem_yield_stub:
	/* stop the timer interrupt - the loader never reschedules, next call into subsystem will re-set this */
	csrw mscratch, s0
	li s0, MSTATUS_MPIE
	csrc mstatus, s0
	csrr s0, mscratch
	mret
#endif

