#include <zephyr/drivers/timer/system_timer.h>
#include <zephyr/skadi/skadi_subsystem.h>

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(skadi_sys_clock_timer_isr);

void sys_clock_timer_isr(void){
    skadi_sys_clock_timer_isr();
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_sys_clock_set_timeout, int32_t ticks, bool idle);

void sys_clock_set_timeout(int32_t ticks, bool idle){
    __skadi_sys_clock_set_timeout(ticks, idle);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint32_t, __skadi_sys_clock_elapsed);

uint32_t sys_clock_elapsed(void){
    return __skadi_sys_clock_elapsed();
}
