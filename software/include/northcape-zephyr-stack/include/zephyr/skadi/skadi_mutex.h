#ifndef SKADI_MUTEX_H
#define SKADI_MUTEX_H

#include <zephyr/kernel.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_sched.h>

#ifdef SKADI_SUBSYSTEM
/* in the loader, use the z_impl_* variants directly */

#define SKADI_MUTEX_ASSERT(MUTEX, FILE, LINE)                   \
    __ASSERT(MUTEX, "Mutex is null at %s:%d", FILE, LINE)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mutex_init, struct k_mutex *mutex, const struct mutex_owner_lock_count **readable_mutex_ref);

static inline int _skadi_mutex_init(struct k_mutex *mutex, const char *file, const int line){
    const struct mutex_owner_lock_count *readable_ref;
    const struct mutex_owner_lock_count **ref_ptr = skadi_cap_ops_derive_arg_wo(&readable_ref, sizeof(readable_ref));
    int ret;

    __ASSERT_NO_MSG(ref_ptr);

    if(!ref_ptr){
        return -ENOMEM;
    }

    SKADI_MUTEX_ASSERT(mutex, file, line);

    ret = __skadi_mutex_init(mutex, ref_ptr);

    mutex->sched_mutex = readable_ref;

    (void)skadi_cap_ops_drop(ref_ptr);

    return ret;
}

#define skadi_mutex_init(MUTEX) _skadi_mutex_init(MUTEX, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mutex_lock, struct k_mutex *mutex, k_timeout_t timeout);

static inline int _skadi_mutex_lock(struct k_mutex *mutex, k_timeout_t timeout, const char *file, const int line){
    SKADI_MUTEX_ASSERT(mutex, file, line);
    
    return __skadi_mutex_lock(mutex, timeout);
}

#define skadi_mutex_lock(MUTEX, TIMEOUT) _skadi_mutex_lock(MUTEX, TIMEOUT, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mutex_unlock, struct k_mutex *mutex);

static inline int _skadi_mutex_unlock(struct k_mutex *mutex, const char *file, const int line){
    SKADI_MUTEX_ASSERT(mutex, file, line);

    return __skadi_mutex_unlock(mutex);
}
#define skadi_mutex_unlock(MUTEX) _skadi_mutex_unlock(MUTEX, __FILE__, __LINE__)

static inline bool _skadi_mutex_is_locked(struct k_mutex *mutex, const char *file, const int line){
    SKADI_MUTEX_ASSERT(mutex, file, line);

    __ASSERT_NO_MSG(mutex->sched_mutex);

    return mutex->sched_mutex->lock_count && mutex->sched_mutex->owner_id != skadi_current_get();
}
#define skadi_mutex_is_locked(MUTEX) _skadi_mutex_is_locked(MUTEX, __FILE__, __LINE__)

static inline bool _skadi_mutex_is_last_lock(struct k_mutex *mutex, const char *file, const int line){
    SKADI_MUTEX_ASSERT(mutex, file, line);

    __ASSERT_NO_MSG(mutex->sched_mutex);

    return mutex->sched_mutex->lock_count == 1;
}
#define skadi_mutex_is_last_lock(MUTEX) _skadi_mutex_is_last_lock(MUTEX, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mutex_cleanup, struct k_mutex *mutex);


static inline void skadi_mutex_cleanup(struct k_mutex *mutex){
    __skadi_mutex_cleanup(mutex);
}

#endif /* SKADI_SUBSYSTEM */

extern void skadi_subsystem_yield(void);
#endif /* SKADI_MUTEX_H */
