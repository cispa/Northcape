#include "cv64a6.h"

#include <stdint.h>
#include <stdio.h>

#include <zephyr/irq.h>
#include <zephyr/sys/poweroff.h>

#include <zephyr/llext/symbol.h>


FUNC_NORETURN void z_cv64a6_finish_test(const int32_t status){

/* allocator cannot (yet) use printf */
#ifndef SKADI_SUBSYSTEM_ALLOCATOR
    printf("Finishing test with status %u-",status);

    if(status == 0){
        printf("TEST SUCCESS!\n");
    }
    else{
        printf("TEST FAIL!\n");
    }
#endif

    z_sys_poweroff();
}


void z_sys_poweroff(void){
#ifndef SKADI_SUBSYSTEM_ALLOCATOR
    printf("System poweroff!\n");
#endif

    for (;;){
        __asm__ volatile(
            "wfi"
        );
    }
}

void arch_system_halt(int reason){
    (void) reason;
#ifdef CONFIG_SKADI_EXPECTED_EXCEPTION
    z_cv64a6_finish_test(0);
#else
    z_cv64a6_finish_test(1);
#endif
}
