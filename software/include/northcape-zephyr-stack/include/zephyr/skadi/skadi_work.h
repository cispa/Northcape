#ifndef SKADI_WORK_H
#define SKADI_WORK_H

#include <zephyr/kernel.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_loader.h>
#include <zephyr/skadi/skadi_sched.h>

/* k_work function wrappers */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_work_init, struct k_work *work, k_work_handler_t handler);

static inline void skadi_work_init(struct k_work *work, k_work_handler_t handler){

    __skadi_work_init(work, handler);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_work_busy_get, const struct k_work *work);

static inline int skadi_work_busy_get(const struct k_work *work){

    return __skadi_work_busy_get(work);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_work_submit_to_queue, struct k_work_q *queue, struct k_work *work);

static inline int skadi_work_submit_to_queue(struct k_work_q *queue, struct k_work *work){
    __ASSERT_NO_MSG(work !=NULL);
    __ASSERT_NO_MSG(queue !=NULL);

    return __skadi_work_submit_to_queue(queue, work);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_work_submit, struct k_work *work);

static inline int skadi_work_submit(struct k_work *work){
    __ASSERT_NO_MSG(work !=NULL);
    return __skadi_work_submit(work);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(bool, __skadi_work_flush, struct k_work *work, struct k_work_sync *sync);

static inline bool skadi_work_flush(struct k_work *work, struct k_work_sync *sync){
    bool ret;
    struct k_work_sync *sync_token = skadi_cap_ops_derive_arg(sync, sizeof(*sync));

    __ASSERT_NO_MSG(sync_token);
    __ASSERT_NO_MSG(work !=NULL);
    
    ret = __skadi_work_flush(work, sync_token);

    skadi_cap_ops_drop(sync_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_work_cancel, struct k_work *work);

static inline int skadi_work_cancel(struct k_work *work){
    __ASSERT_NO_MSG(work !=NULL);
    return __skadi_work_cancel(work);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_work_cancel_sync, struct k_work *work, struct k_work_sync *sync);

static inline int skadi_work_cancel_sync(struct k_work *work, struct k_work_sync *sync){
    bool ret;
    struct k_work_sync *sync_token = skadi_cap_ops_derive_arg(sync, sizeof(*sync));

    __ASSERT_NO_MSG(sync_token);
    __ASSERT_NO_MSG(work !=NULL);
    
    ret = __skadi_work_cancel_sync(work, sync_token);

    skadi_cap_ops_drop(sync_token);

    return ret;
}

/* k_work_queue function wrappers */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_work_queue_init, struct k_work_q *queue);

static inline void skadi_work_queue_init(struct k_work_q *queue){

    __skadi_work_queue_init(queue);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_work_queue_start, struct k_work_q *queue, k_thread_stack_t *stack, size_t stack_size, int prio, const struct k_work_queue_config *cfg);

static inline void skadi_work_queue_start(struct k_work_q *queue, k_thread_stack_t *stack, size_t stack_size, int prio, const struct k_work_queue_config *cfg){
    struct k_work_queue_config cfg_copy = {0};
    const struct k_work_queue_config *cfg_token = cfg ? skadi_cap_ops_derive_arg_ro(&cfg_copy, sizeof(cfg_copy)) : NULL;
    const char *original_name = cfg ? cfg->name : NULL;
    const char *name_token = original_name ? skadi_cap_ops_derive_arg_ro(original_name, strlen(original_name)+1) : NULL;
    k_thread_stack_t *thread_stack = skadi_cap_ops_derive_arg(stack, stack_size);
    __ASSERT_NO_MSG(queue);

    __ASSERT_NO_MSG(thread_stack);

    if(cfg){
        cfg_copy.name = name_token;
        cfg_copy.no_yield = cfg->no_yield;
        cfg_copy.essential = cfg->essential;
    }

    if(cfg){
        __ASSERT_NO_MSG(cfg_token);

        if(original_name){
            __ASSERT_NO_MSG(name_token);
        }
    }

    __skadi_work_queue_start(queue, thread_stack, stack_size, prio, cfg_token);

    if(cfg_token){
        skadi_cap_ops_drop(cfg_token);
    }
    if(name_token){
        skadi_cap_ops_drop(name_token);
    }
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_work_queue_drain, struct k_work_q *queue, bool plug);

static inline int skadi_work_queue_drain(struct k_work_q *queue, bool plug){
    __ASSERT_NO_MSG(queue);
    return __skadi_work_queue_drain(queue, plug);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_work_queue_unplug, struct k_work_q *queue);

static inline int skadi_work_queue_unplug(struct k_work_q *queue){
    __ASSERT_NO_MSG(queue);
    return __skadi_work_queue_unplug(queue);
}

/* k_work_delayable function wrappers */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_work_init_delayable, struct k_work_delayable *dwork, k_work_handler_t handler);

static inline void skadi_work_init_delayable(struct k_work_delayable *dwork, k_work_handler_t handler){
    __skadi_work_init_delayable(dwork, handler);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_work_delayable_busy_get, const struct k_work_delayable *work);

static inline int skadi_work_delayable_busy_get(const struct k_work_delayable *dwork){
    
    __ASSERT_NO_MSG(dwork);

    return __skadi_work_delayable_busy_get(dwork);
}

/* k_work_schedule functions */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_work_schedule_for_queue, struct k_work_q *queue, struct k_work_delayable *dwork, k_timeout_t delay);

static inline int skadi_work_schedule_for_queue(struct k_work_q *queue, struct k_work_delayable *dwork, k_timeout_t delay){
    __ASSERT_NO_MSG(queue);
    __ASSERT_NO_MSG(dwork);

    return __skadi_work_schedule_for_queue(queue, dwork, delay);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_work_schedule, struct k_work_delayable *dwork, k_timeout_t delay);

static inline int skadi_work_schedule(struct k_work_delayable *dwork, k_timeout_t delay){
    __ASSERT_NO_MSG(dwork);

    return __skadi_work_schedule(dwork, delay);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_work_reschedule_for_queue, struct k_work_q *queue, struct k_work_delayable *dwork, k_timeout_t delay);

static inline int skadi_work_reschedule_for_queue(struct k_work_q *queue, struct k_work_delayable *dwork, k_timeout_t delay){
    __ASSERT_NO_MSG(queue);
    __ASSERT_NO_MSG(dwork);

    return __skadi_work_reschedule_for_queue(queue, dwork, delay);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_work_reschedule, struct k_work_delayable *dwork, k_timeout_t delay);

static inline int skadi_work_reschedule(struct k_work_delayable *dwork, k_timeout_t delay){
    __ASSERT_NO_MSG(dwork);

    return __skadi_work_reschedule(dwork, delay);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(bool, __skadi_work_flush_delayable, struct k_work_delayable *dwork, struct k_work_sync *sync);

static inline bool skadi_work_flush_delayable(struct k_work_delayable *dwork, struct k_work_sync *sync){
    bool ret;
    struct k_work_sync *sync_token = skadi_cap_ops_derive_arg(sync, sizeof(*sync));

    __ASSERT_NO_MSG(sync_token);
    __ASSERT_NO_MSG(dwork !=NULL);
    
    ret = __skadi_work_flush_delayable(dwork, sync_token);

    skadi_cap_ops_drop(sync_token);

    return ret;
}


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_work_cancel_delayable, struct k_work_delayable *dwork);

static inline int skadi_work_cancel_delayable(struct k_work_delayable *dwork){
    __ASSERT_NO_MSG(dwork);

    return __skadi_work_cancel_delayable(dwork);
}


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(bool, __skadi_work_cancel_delayable_sync, struct k_work_delayable *dwork, struct k_work_sync *sync);

static inline bool skadi_work_cancel_delayable_sync(struct k_work_delayable *dwork, struct k_work_sync *sync){
    bool ret;
    struct k_work_sync *sync_token = skadi_cap_ops_derive_arg(sync, sizeof(*sync));

    __ASSERT_NO_MSG(sync_token);
    __ASSERT_NO_MSG(dwork !=NULL);
    
    ret = __skadi_work_cancel_delayable_sync(dwork, sync_token);

    skadi_cap_ops_drop(sync_token);

    return ret;
}



SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(k_ticks_t, __skadi_work_delayable_remaining_get, const struct k_work_delayable *dwork);
static inline k_ticks_t skadi_work_delayable_remaining_get(const struct k_work_delayable *dwork){
    return __skadi_work_delayable_remaining_get(dwork);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_work_cleanup, struct k_work *work);
static inline void skadi_work_cleanup(struct k_work *work){
    __skadi_work_cleanup(work);
}


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_work_queue_cleanup, struct k_work_q *queue);
static inline void skadi_work_queue_cleanup(struct k_work_q *queue){
    __skadi_work_queue_cleanup(queue);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_dwork_cleanup, struct k_work_delayable *work);
static inline void skadi_work_cleanup_delayable(struct k_work_delayable *dwork){
    __skadi_dwork_cleanup(dwork);
}

static inline bool skadi_work_delayable_is_pending(const struct k_work_delayable *dwork){
    return skadi_work_delayable_busy_get(dwork) != 0;
}

static inline bool skadi_work_is_pending(const struct k_work *work){
    return skadi_work_busy_get(work) != 0;
}

#endif /* SKADI_WORK_H */
