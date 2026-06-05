#include "cv64a6.h"

#include <stdint.h>
#include <stdio.h>

#include <zephyr/sys/poweroff.h>


#include <zephyr/llext/symbol.h>

#ifdef CONFIG_SKADI_OS
#include <zephyr/skadi/skadi_subsystem.h>
#endif

// the CV64a6 testbench looks for a symbol called "tohost" and determines its load address
// when something is written to the symbol, this terminates the test
// the last bit of the written data indicate success or failure of the test

// the test bench must be able to find the symbol in the ELF by reading its symbols
#ifdef SKADI_SUBSYSTEM
extern volatile int32_t tohost;
#else
volatile int32_t tohost = 0;
#endif

static int32_t cv64a6_test_status = 0;

FUNC_NORETURN void z_cv64a6_finish_test(const int32_t status){
    cv64a6_test_status = status;

    sys_poweroff();
}

#ifdef SKADI_SUBSYSTEM

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_z_sys_poweroff, int32_t test_status);

FUNC_NORETURN void z_sys_poweroff(void){
    __skadi_z_sys_poweroff(cv64a6_test_status);
    CODE_UNREACHABLE;
}

#else
/* the loader has access to tohost, while the submodules to not*/
FUNC_NORETURN void __z_sys_poweroff(int32_t test_status){
    // write to this special address signals to the sim that we wish to end the simulation
    tohost = 0x1 | (test_status << 1);

    CODE_UNREACHABLE;
}

FUNC_NORETURN void z_sys_poweroff(void){
    __z_sys_poweroff(cv64a6_test_status);
}

#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, __skadi_z_sys_poweroff, int32_t test_status)
    __z_sys_poweroff(test_status);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_z_sys_poweroff)

static int soc_poweroff_initialize_trampolines(void){
    return __skadi_z_sys_poweroff_register_init_function() == true ? 0 : -EINVAL;
}

SYS_INIT(soc_poweroff_initialize_trampolines, PRE_KERNEL_1, CONFIG_LOADER_SKADI_TRAMPOLINE_INIT_PRIO);
#endif /* CONFIG_SKADI_LOADER */
#endif /* SKADI_SUBSYSTEM */

void arch_system_halt(int reason){
    (void) reason;
#ifdef CONFIG_SKADI_EXPECTED_EXCEPTION
    z_cv64a6_finish_test(0);
#else
    z_cv64a6_finish_test(1);
#endif
}

