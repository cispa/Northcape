#ifndef SKADI_SEM_H
#define SKADI_SEM_H

#include <zephyr/kernel.h>
#include <zephyr/skadi/skadi_subsystem.h>

#ifdef SKADI_SUBSYSTEM
/* in the loader, use the z_impl_* variants directly */

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_sem_init, struct k_sem *sem, unsigned int initial_count, unsigned int limit);

#define SKADI_SEM_ASSERT(SEM, FILE, LINE)                      \
    __ASSERT(SEM, "Uninitialized semaphore at %s:%d", FILE, LINE)

static inline int __skadi_sem_init_wrapper(struct k_sem *sem, unsigned int initial_count, unsigned int limit, const char *file, int line){
    SKADI_SEM_ASSERT(sem, file, line);
    return __skadi_sem_init(sem, initial_count, limit);
}

#define skadi_sem_init(SEM, INITIAL_COUNT, LIMIT)                               \
    __skadi_sem_init_wrapper(SEM, INITIAL_COUNT, LIMIT, __FILE__, __LINE__)     \
    

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_sem_give, struct k_sem *sem);

static inline void __skadi_sem_give_wrapper(struct k_sem *sem, const char *file, int line){
    SKADI_SEM_ASSERT(sem, file, line);
    __skadi_sem_give(sem);
}

#define skadi_sem_give(SEM)                                             \
    __skadi_sem_give_wrapper(SEM, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_sem_take, struct k_sem *sem, k_timeout_t timeout);

static inline int __skadi_sem_take_wrapper(struct k_sem *sem, k_timeout_t timeout, const char *file, int line){
    SKADI_SEM_ASSERT(sem, file, line);
    return __skadi_sem_take(sem, timeout);
}

#define skadi_sem_take(SEM, timeout)                                    \
    __skadi_sem_take_wrapper(SEM, timeout, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_sem_reset, struct k_sem *sem);

static inline int __skadi_sem_reset_wrapper(struct k_sem *sem, const char *file, int line){
    SKADI_SEM_ASSERT(sem, file, line);
    return __skadi_sem_reset(sem);
}

#define skadi_sem_reset(SEM)                                            \
    __skadi_sem_reset_wrapper(SEM, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_sem_count_get, struct k_sem *sem);
static inline int __skadi_sem_count_get_wrapper(struct k_sem *sem, const char *file, int line){
    SKADI_SEM_ASSERT(sem, file, line);
    return __skadi_sem_count_get(sem);
}

#define skadi_sem_count_get(SEM)                                            \
    __skadi_sem_count_get_wrapper(SEM, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_sem_cleanup, struct k_sem *sem);

static inline void skadi_sem_cleanup(struct k_sem *sem){
    __ASSERT_NO_MSG(sem);
    __skadi_sem_cleanup(sem);
}

#endif /* SKADI_SUBSYSTEM */

extern void skadi_subsystem_yield(void);
#endif /* SKADI_SEM_H */
