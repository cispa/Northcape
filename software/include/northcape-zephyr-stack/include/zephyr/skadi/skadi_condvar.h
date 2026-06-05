#ifndef SKADI_CONDVAR_H
#define SKADI_CONDVAR_H

#include <zephyr/kernel.h>
#include <zephyr/skadi/skadi_subsystem.h>

#ifdef SKADI_SUBSYSTEM
/* in the loader, use the z_impl_* variants directly */

#define SKADI_CONDVAR_ASSERT(COND, FILE, LINE)                   \
    __ASSERT(COND, "Condvar is null at %s:%d", FILE, LINE);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_condvar_init, struct k_condvar *condvar);

static inline int _skadi_condvar_init(struct k_condvar *condvar, const char *file, const int line){
    int ret;

    ret = __skadi_condvar_init(condvar);

    return ret;
}

#define skadi_condvar_init(CONDVAR) _skadi_condvar_init(CONDVAR, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_condvar_signal, struct k_condvar *condvar);

static inline int _skadi_condvar_signal(struct k_condvar *condvar, const char *file, const int line){
    SKADI_CONDVAR_ASSERT(condvar, file, line);
    return __skadi_condvar_signal(condvar);
}

#define skadi_condvar_signal(CONDVAR) _skadi_condvar_signal(CONDVAR, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_condvar_broadcast, struct k_condvar *condvar);

static inline int _skadi_condvar_broadcast(struct k_condvar *condvar, const char *file, const int line){
    SKADI_CONDVAR_ASSERT(condvar, file, line);
    return __skadi_condvar_broadcast(condvar);
}

#define skadi_condvar_broadcast(CONDVAR) _skadi_condvar_broadcast(CONDVAR, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_condvar_wait, struct k_condvar *condvar, struct k_mutex *mutex, k_timeout_t timeout);

static inline int _skadi_condvar_wait(struct k_condvar *condvar, struct k_mutex *mutex, k_timeout_t timeout, const char *file, const int line){
    SKADI_CONDVAR_ASSERT(condvar, file, line);
    __ASSERT_NO_MSG(mutex);
    return __skadi_condvar_wait(condvar, mutex, timeout);
}

#define skadi_condvar_wait(CONDVAR, MUTEX, TIMEOUT) _skadi_condvar_wait(CONDVAR, MUTEX, TIMEOUT, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_condvar_cleanup, struct k_condvar *cond);
static inline void skadi_condvar_cleanup(struct k_condvar *cond){
    __skadi_condvar_cleanup(cond);
}

#endif /* SKADI_SUBSYSTEM */

extern void skadi_subsystem_yield(void);
#endif /* SKADI_CONDVAR_H */
