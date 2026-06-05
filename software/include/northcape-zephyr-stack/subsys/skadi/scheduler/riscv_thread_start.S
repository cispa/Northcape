#include <zephyr/toolchain.h>
#include <offsets_short.h>
#include "asm_macros.inc"

#define RESTORE_ARG_REGS(op) \
	RV_E(	op a0, __struct_arch_esf_a0_OFFSET(sp)	);\
	RV_E(	op a1, __struct_arch_esf_a1_OFFSET(sp)	);\
	RV_E(	op a2, __struct_arch_esf_a2_OFFSET(sp)	);\
	RV_E(	op a3, __struct_arch_esf_a3_OFFSET(sp)	);\
	RV_E(	op a4, __struct_arch_esf_a4_OFFSET(sp)	);\
	RV_E(	op a5, __struct_arch_esf_a5_OFFSET(sp)	);\
	RV_I(	op a6, __struct_arch_esf_a6_OFFSET(sp)	);\
	RV_I(	op a7, __struct_arch_esf_a7_OFFSET(sp)	);\
	RV_E(	op ra, __struct_arch_esf_ra_OFFSET(sp)	)



GTEXT(z_riscv_thread_start)

z_riscv_thread_start:

	/* Restore MEPC and MSTATUS registers - we never get here when mepc is not writable */
	lr t0, __struct_arch_esf_mepc_OFFSET(sp)
	lr t2, __struct_arch_esf_mstatus_OFFSET(sp)
	csrw mepc, t0
	csrw mstatus, t2

	RESTORE_ARG_REGS(lr)

	addi sp, sp, __struct_arch_esf_SIZEOF

#ifdef CONFIG_SKADI_RESET_BRANCH_TABLE_ON_SUBSYSTEM_CALL
    /* flush reads/writes/branch prediction and clear cache */				
	csrrsi x0, 0x7C0, 2														
    fence												
#endif					
#ifndef CONFIG_SKADI_CACHE_INTEGRATION
	/* flush data cache */													
	csrwi 0x7C1, 0x00														
	csrwi 0x7C1, 0x01														
	/* flush instruction cache */											
	csrwi 0x7C0, 0x00														
	csrwi 0x7C0, 0x01
#endif

	mret
