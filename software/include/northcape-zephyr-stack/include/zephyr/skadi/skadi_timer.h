#ifndef SKADI_TIMER_H
#define SKADI_TIMER_H

#include <zephyr/kernel.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_loader.h>
#include <zephyr/skadi/skadi_sched.h>

/* k_timer function wrappers */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_timer_init, struct k_timer *timer, k_timer_expiry_t expiry_fn, k_timer_stop_t stop_fn);

static inline void skadi_timer_init(struct k_timer *timer, k_timer_expiry_t expiry_fn, k_timer_stop_t stop_fn){
    __skadi_timer_init(timer, expiry_fn, stop_fn);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_timer_start, struct k_timer *timer, k_timeout_t duration, k_timeout_t period);

static inline void skadi_timer_start(struct k_timer *timer, k_timeout_t duration, k_timeout_t period){

    __ASSERT_NO_MSG(timer);

    __skadi_timer_start(timer, duration, period);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_timer_stop, struct k_timer *timer);

static inline void skadi_timer_stop(struct k_timer *timer){

    __ASSERT_NO_MSG(timer);
    
    __skadi_timer_stop(timer);
}


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint32_t, __skadi_timer_status_get, struct k_timer *timer);

static inline uint32_t skadi_timer_status_get(struct k_timer *timer){

    __ASSERT_NO_MSG(timer);
    
    return __skadi_timer_status_get(timer);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint32_t, __skadi_timer_status_sync, struct k_timer *timer);

static inline uint32_t skadi_timer_status_sync(struct k_timer *timer){

    __ASSERT_NO_MSG(timer);
    
    return __skadi_timer_status_sync(timer);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_timer_cleanup, struct k_timer *timer);

static inline void skadi_timer_cleanup(struct k_timer *timer){

    __skadi_timer_cleanup(timer);
}

#ifdef CONFIG_SYS_CLOCK_EXISTS
    
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(k_ticks_t, __skadi_timer_expires_ticks, const struct k_timer *timer);
    #define skadi_timer_expires_ticks(TIMER) __skadi_timer_expires_ticks(TIMER)

    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(k_ticks_t, __skadi_timer_remaining_ticks, const struct k_timer *timer);
    #define skadi_timer_remaining_ticks(TIMER) __skadi_timer_remaining_ticks(TIMER)

    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(k_ticks_t, __skadi_timer_remaining_get, const struct k_timer *timer);
    static inline uint32_t skadi_timer_remaining_get(const struct k_timer *timer){
        return __skadi_timer_remaining_get(timer);
    }
#endif

/* inlines */
#define skadi_timer_user_data_set(TIMER, USER_DATA) k_timer_user_data_set(TIMER, USER_DATA)
#define skadi_timer_user_data_get(TIMER) k_timer_user_data_get(TIMER)


#endif /* SKADI_TIMER_H */
