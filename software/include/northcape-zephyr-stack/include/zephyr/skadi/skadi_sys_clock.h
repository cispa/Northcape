#ifndef SKADI_SYS_CLOCK_H
#define SKADI_SYS_CLOCK_H

#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_loader.h>
#include <zephyr/drivers/timer/system_timer.h>

#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS(skadi_sys_clock_announce_wrapper, int32_t ticks);


static void (*skadi_sys_clock_announce_ptr)(int32_t ticks) = NULL;
static inline void skadi_sys_clock_announce(int32_t ticks){
    if(!skadi_sys_clock_announce_ptr){
        skadi_sys_clock_announce_ptr = (void*) skadi_loader_get_symbol("__skadi_sys_clock_announce_callee_trampoline");
        __ASSERT_NO_MSG(skadi_sys_clock_announce_ptr);

        if(!skadi_sys_clock_announce_ptr){
            return;
        }
    }

    skadi_sys_clock_announce_wrapper(ticks, skadi_sys_clock_announce_ptr);
}

#ifdef CONFIG_SYS_CLOCK_EXISTS

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(k_timepoint_t, __skadi_sys_timepoint_calc, k_timeout_t timeout);

#define skadi_sys_timepoint_calc(TIMEOUT) __skadi_sys_timepoint_calc(TIMEOUT)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(k_timeout_t, __skadi_sys_timepoint_timeout, k_timepoint_t timeout);

#define skadi_sys_timepoint_timeout(TIMEOUT) __skadi_sys_timepoint_timeout(TIMEOUT)

/* inlines */

#define skadi_sys_timepoint_cmp(A,B) sys_timepoint_cmp(A,B)

#define skadi_sys_timepoint_expired(TIMEPOINT) sys_timepoint_expired(TIMEPOINT)

#endif /* CONFIG_SYS_CLOCK_EXISTS*/


#endif /* CONFIG_SKADI_LOADER */

#endif
