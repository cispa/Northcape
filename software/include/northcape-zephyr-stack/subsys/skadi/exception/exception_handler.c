#include <zephyr/logging/log.h>

#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_allocator.h>
#include <zephyr/skadi/skadi_loader.h>

#include <zephyr/kernel.h>
#include <kernel_arch_interface.h>

#include <zephyr/kernel_structs.h>
#include <zephyr/arch/cpu.h>

#include <cv64a6.h>

LOG_MODULE_REGISTER(skadi_exception_subsystem, CONFIG_SKADI_SUBSYSTEM_LOG_LEVEL);

#include <zephyr/skadi/skadi_sched.h>

struct riscv_register_set{
    long a0;
    long a1;
    long a2;
    long a3;
    long a4;
    long a5;
    long a6;
    long a7;
    long t0;
    long t1;
    long t2;
    long t3;
    long t4;
    long t5;
    long t6;
    long s0;
    long s1;
    long s2;
    long s3;
    long s4;
    long s5;
    long s6;
    long s7;
    long s8;
    long s9;
    long s10;
    long s11;
    long sp;
    long ra;
    long mepc;
    long mstatus;
    long mtval;
    long mcause;
};

struct riscv_register_set exception_register_set;

#ifdef SKADI_SUBSYSTEM
struct skadi_subsystem_stack *exception_stack;
#else
struct skadi_subsystem_stack static_exception_stack;
struct skadi_subsystem_stack *exception_stack = (struct skadi_subsystem_stack *)&static_exception_stack.stack[CONFIG_SKADI_SUBSYSTEM_STACK_SIZE+1 - sizeof(void*)];
#endif

extern void _skadi_exception_wrapper_callee_trampoline(void);
extern void _skadi_exception_wrapper_callee_trampoline_end(void);

#ifdef SKADI_SUBSYSTEM
EXPORT_SYMBOL(_skadi_exception_wrapper_callee_trampoline);
EXPORT_SYMBOL(_skadi_exception_wrapper_callee_trampoline_end);
#endif

#define PR_REG "%lx"

/* from fatal.c */
static const char *z_riscv_mcause_str(unsigned long cause)
{
	static const char *const mcause_str[17] = {
		[0] = "Instruction address misaligned",
		[1] = "Instruction Access fault",
		[2] = "Illegal instruction",
		[3] = "Breakpoint",
		[4] = "Load address misaligned",
		[5] = "Load access fault",
		[6] = "Store/AMO address misaligned",
		[7] = "Store/AMO access fault",
		[8] = "Environment call from U-mode",
		[9] = "Environment call from S-mode",
		[10] = "unknown",
		[11] = "Environment call from M-mode",
		[12] = "Instruction page fault",
		[13] = "Load page fault",
		[14] = "unknown",
		[15] = "Store/AMO page fault",
		[16] = "unknown",
	};

    static const char *const mcause_str_northcape[11] = {
		[0] = "No Error / Spurious",
		[1] = "Incorrect capability tag",
		[2] = "Insufficient permissions",
		[3] = "Restriction violation",
		[4] = "Incorrect capability type",
		[5] = "Capability is locked",
		[6] = "Bus error on capability resolution",
		[7] = "Capability bounds exceeded",
		[8] = "Capability overlaps CMT",
		[9] = "Subsystem call to non-zero offset",
		[10] = "Invalid subsystem call target"
	};

    /* Northcape-specific */
    if(cause >= 1024){
        return mcause_str_northcape[MIN(cause-1024, ARRAY_SIZE(mcause_str_northcape) - 1)];
    }

	return mcause_str[MIN(cause, ARRAY_SIZE(mcause_str) - 1)];
}

void skadi_handle_exception(void){
    const char *mcause_str = z_riscv_mcause_str(exception_register_set.mcause);
    LOG_ERR("");
	LOG_ERR(" mcause: %ld, %s", exception_register_set.mcause, (const char *) skadi_cap_ops_derive_arg_ro(mcause_str, strlen(mcause_str)+1));
    LOG_ERR("  mtval: %lx", exception_register_set.mtval);
    LOG_ERR("     a0: " PR_REG "    t0: " PR_REG, exception_register_set.a0, exception_register_set.t0);
    LOG_ERR("     a1: " PR_REG "    t1: " PR_REG, exception_register_set.a1, exception_register_set.t1);
    LOG_ERR("     a2: " PR_REG "    t2: " PR_REG, exception_register_set.a2, exception_register_set.t2);
    LOG_ERR("     a3: " PR_REG, exception_register_set.a3);
    LOG_ERR("     a4: " PR_REG, exception_register_set.a4);
    LOG_ERR("     a5: " PR_REG, exception_register_set.a5);
    LOG_ERR("     a3: " PR_REG "    t3: " PR_REG, exception_register_set.a3, exception_register_set.t3);
    LOG_ERR("     a4: " PR_REG "    t4: " PR_REG, exception_register_set.a4, exception_register_set.t4);
    LOG_ERR("     a5: " PR_REG "    t5: " PR_REG, exception_register_set.a5, exception_register_set.t5);
    LOG_ERR("     a6: " PR_REG "    t6: " PR_REG, exception_register_set.a6, exception_register_set.t6);
    LOG_ERR("     sp: " PR_REG, exception_register_set.sp);
    LOG_ERR("     ra: " PR_REG, exception_register_set.ra);
    LOG_ERR("   mepc: " PR_REG, exception_register_set.mepc);
    LOG_ERR("mstatus: " PR_REG, exception_register_set.mstatus);
    LOG_ERR("");
    LOG_ERR("     s0: " PR_REG "    s6: " PR_REG, exception_register_set.s0, exception_register_set.s6);
    LOG_ERR("     s1: " PR_REG "    s7: " PR_REG, exception_register_set.s1, exception_register_set.s7);
    LOG_ERR("     s2: " PR_REG "    s8: " PR_REG, exception_register_set.s2, exception_register_set.s8);
    LOG_ERR("     s3: " PR_REG "    s9: " PR_REG, exception_register_set.s3, exception_register_set.s9);
    LOG_ERR("     s4: " PR_REG "   s10: " PR_REG, exception_register_set.s4, exception_register_set.s10);
    LOG_ERR("     s5: " PR_REG "   s11: " PR_REG, exception_register_set.s5, exception_register_set.s11);
    LOG_ERR("");

    arch_system_halt(1);
}

#ifdef SKADI_SUBSYSTEM
static bool skadi_exception_init(void){
    SKADI_INSTALL_TIME_INTERRUPT_HOOK;
    
    exception_stack = (struct skadi_subsystem_stack *) skadi_allocator_alloc_rw(sizeof(*exception_stack));

    __ASSERT_NO_MSG(exception_stack);

    if(!exception_stack){
        return false;
    }

    exception_stack = (struct skadi_subsystem_stack *) skadi_subsystem_prepare_allocated_stack(exception_stack, SKADI_CURRENT_TASK_ID, NULL);

	return true;
}
/* we need to initialize the ISR subsystem as soon as the subsystem is loaded */
/* the loader will make it active immediately after loading it */
SKADI_SUBSYSTEM_INIT_FUNCTIONS(skadi_exception_init);
#endif /* SKADI_SUBSYSTEM*/
