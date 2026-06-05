#include <zephyr/logging/log.h>

#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_allocator.h>
#include <zephyr/skadi/skadi_loader.h>
#include <zephyr/skadi/skadi_sched.h>

#include <zephyr/init.h>
#include <zephyr/kernel.h>
#include <ksched.h>

#include <zephyr/kernel_structs.h>
#include <zephyr/sw_isr_table.h>
#include <zephyr/arch/cpu.h>

#include "sys_clock_stub.h"
#include <zephyr/skadi/skadi_interface_wrapper.h>


SKADI_INTERFACE_WRAPPER_DECLARE(SKADI_THREAD);


LOG_MODULE_REGISTER(skadi_sched_subsystem, CONFIG_SKADI_SUBSYSTEM_LOG_LEVEL);


extern void z_riscv_switch(struct k_thread *new, struct k_thread *old);

static bool scheduler_was_initialized;

static int register_scheduler_initialized(void){
    scheduler_was_initialized = true;
    
    return 0;
}
/* fired as soon as scheduler was initialized and I can start rescheduling */
SYS_INIT(register_scheduler_initialized, POST_KERNEL, 0);


extern void (**skadi_subsystem_mtimer_sched_hook)(void);
extern void _skadi_subsystem_yield_stub(void);

#ifdef CONFIG_SKADI_COUNT_YIELD_CALLS
atomic_t skadi_num_yield_calls;
EXPORT_SYMBOL(skadi_num_yield_calls);
#endif

/* we need a specialized trampoline for yield: we do not want interrupts to be enabled, but also should not use the ops module for the ISR */
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_WITHOUT_IRQ("j skadi_sched_yield_irq_restored\n\t", false, true, void, skadi_sched_yield)
{
    void *new_thread;
    struct k_thread *old_thread = _current;

    /* in case the scheduler re-enables interrupts after the switch */
    *skadi_subsystem_mtimer_sched_hook = _skadi_subsystem_yield_stub;

    /* acknowledge the timer interrupt, set next timeout and adjust thread slice if necessary */
    sys_clock_timer_isr();

#ifdef CONFIG_SKADI_COUNT_YIELD_CALLS
    atomic_inc(&skadi_num_yield_calls);
#endif

    if(!scheduler_was_initialized){
        /* cannot reschedule yet */
        return;
    }

    new_thread = z_get_next_switch_handle(old_thread);
    if(new_thread){
        z_riscv_switch(new_thread, old_thread);
    }

    
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(skadi_sched_yield)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, __skadi_yield)
    k_yield();
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_yield)

/* alias of the actual k_sleep function - prevents accidentally exposing this to subsystems */
extern int32_t __skadi_k_sleep(k_timeout_t timeout);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int32_t, skadi_sleep, k_timeout_t timeout)
{
   return __skadi_k_sleep(timeout);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(skadi_sleep)

extern int32_t __skadi_k_usleep(int32_t us);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int32_t, skadi_usleep, int32_t us)
{
   return __skadi_k_usleep(us);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(skadi_usleep)

#if defined(CONFIG_SKADI_MARK_THREAD_IN_TRAMPOLINE)
typedef void (*skadi_thread_cancelled_callback_t)(k_tid_t thread);

static skadi_thread_cancelled_callback_t *registered_cancellation_callbacks = NULL;
static size_t num_registered_cancellation_callbacks = 0, callbacks_size = 0;

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ_ALLOW_SELF(void, __skadi_thread_abort_register_callback, skadi_thread_cancelled_callback_t callback)
    if(callbacks_size < num_registered_cancellation_callbacks + 1){
        callbacks_size = 2 * (num_registered_cancellation_callbacks + 1);
        registered_cancellation_callbacks = skadi_allocator_realloc(registered_cancellation_callbacks, callbacks_size * sizeof(registered_cancellation_callbacks[0]));
        __ASSERT_NO_MSG(registered_cancellation_callbacks);
    }

    skadi_subsystem_check_function_pointer(callback, false, true);

    if(!registered_cancellation_callbacks){
        LOG_ERR("Could not register cancellation callback: ENOMEM!");
        return;
    }
    registered_cancellation_callbacks[num_registered_cancellation_callbacks++] = callback;

    LOG_DBG("Registered cancellation check %p!", callback);
    
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_thread_abort_register_callback)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS_ALLOW_SELF(__skadi_cancellation_callback_wrapper, k_tid_t thread);

void skadi_handle_thread_cancellation(k_tid_t thread){
    LOG_DBG("Calling %zu cancellation checks!", num_registered_cancellation_callbacks);

    for(size_t callback = 0; callback < num_registered_cancellation_callbacks; callback++){
        LOG_DBG("Calling cancellation check %p!", registered_cancellation_callbacks[callback]);
        __skadi_cancellation_callback_wrapper((k_tid_t)thread->thread_id, registered_cancellation_callbacks[callback]);
    }
}
#endif

/* shortcut for the (common) case that we were given the current thread */
#define TRANSLATE_THREAD(thread) (thread == _current ? _current : SKADI_INTERFACE_WRAPPER_TRANSLATE(SKADI_THREAD, struct k_thread, thread))

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(bool, __skadi_thread_addr_in_stack, k_tid_t thread, uintptr_t addr)
    struct k_thread *current = TRANSLATE_THREAD(thread);
    return current->stack_info.start <= addr && addr < current->stack_info.start + current->stack_info.size;
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_thread_addr_in_stack)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_thread_priority_get, k_tid_t thread)
    struct k_thread *current = TRANSLATE_THREAD(thread);
    return current->base.prio;
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_thread_priority_get)

#if defined(CONFIG_SKADI_MARK_THREAD_IN_TRAMPOLINE)
extern void __skadi_k_thread_abort(k_tid_t thread);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, __skadi_thread_abort, k_tid_t thread)
    __skadi_k_thread_abort(TRANSLATE_THREAD(thread));
    SKADI_INTERFACE_WRAPPER_REMOVE(SKADI_THREAD, thread);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_thread_abort)
#endif

extern void __skadi_k_thread_priority_set(k_tid_t thread, int prio);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, __skadi_thread_priority_set, k_tid_t thread, int prio)
    __skadi_k_thread_priority_set(TRANSLATE_THREAD(thread), prio);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_thread_priority_set)

extern int __skadi_k_thread_join(k_tid_t thread, k_timeout_t timeout);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_thread_join, k_tid_t thread, k_timeout_t timeout);
    return __skadi_k_thread_join(TRANSLATE_THREAD(thread), timeout);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_thread_join)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, __skadi_thread_suspend, k_tid_t thread);
    k_thread_suspend(TRANSLATE_THREAD(thread));
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_thread_suspend)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, __skadi_thread_resume, k_tid_t thread);
    k_thread_resume(TRANSLATE_THREAD(thread));
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_thread_resume)

extern int __skadi_k_thread_name_set(k_tid_t thread, const char *str);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_thread_name_set, k_tid_t thread, const char *str)
    return __skadi_k_thread_name_set(TRANSLATE_THREAD(thread), str);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_thread_name_set)

extern int __skadi_k_thread_name_copy(k_tid_t thread, char *buf, size_t size);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_thread_name_copy, k_tid_t thread, char *buf, size_t size);
    return __skadi_k_thread_name_copy(TRANSLATE_THREAD(thread), buf, size);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_thread_name_copy)
