#ifndef SKADI_SCHED_H
#define SKADI_SCHED_H

#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_loader.h>

/* filled by the skadi loader; token for ISR table entry*/
extern void (**skadi_subsystem_mtimer_sched_hook)(void);
/* filled by the build-time linker */
/* from skadi_sched_yield.S */
extern void (_skadi_subsystem_yield_stub)(void);
extern void (_skadi_subsystem_yield_stub_return)(void);
extern void (_skadi_subsystem_yield_stub_return_end)(void);
extern uint64_t skadi_subsystem_mtimer_sched_hook_reloc;

#define SKADI_REQUEST_TIME_INTERRUPT_HOOK_NO_INIT                                                                                                   \
    /* set-task-id token for _skadi_subsystem_yield_stub_return */                                                                                  \
    void *skadi_sched_yield_stub_return_addr;                                                                                                       \
    /* used to save the stack pointer during the yield subsystem call; needs to be in data segment to be writable */                                \
    void* skadi_sched_yield_stack_ptr_save;                                                                                                         \
    static bool skadi_sched_yield_stub_setup_return_addr(void) {                                                                                    \
        const size_t function_pointer_bytes = (uintptr_t) &_skadi_subsystem_yield_stub_return_end -                                                 \
                                              (uintptr_t) &_skadi_subsystem_yield_stub_return;                                                      \
        const skadi_task_id_t task_id = SKADI_CURRENT_TASK_ID;                                                                                      \
        const skadi_restriction_t restriction = SKADI_TASK_ID_RESTRICTION(task_id, SKADI_DEVICE_ID_CPU, SKADI_RESTRICTIONS_SET_TASK_ID);            \
        skadi_subsystem_mtimer_sched_hook_reloc = (uint64_t) skadi_subsystem_mtimer_sched_hook;                                                     \
        return skadi_cap_ops_derive(_skadi_subsystem_yield_stub_return, restriction,                                                                \
                                        function_pointer_bytes, skadi_get_capability_offset( _skadi_subsystem_yield_stub_return),                   \
                                        SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_CACHEABLE_TLB |                         \
                                        SKADI_PERMISSION_CACHEABLE_ACCESS, /* not IRQ accessible - should not be called in ISR */                   \
                                        &skadi_sched_yield_stub_return_addr) && skadi_sched_yield_stub_return_addr != 0;                            \
    }                                                                                                                                               \

/**
 * @brief Request capability token for mtimer ISR in ISR table, allowing this thread to be preempted.
 * 
 * we include this here to prevent a dependency circle between this header and the subsystem header
 * 
 * 
 */
#define SKADI_REQUEST_TIME_INTERRUPT_HOOK                                                                                                           \
    SKADI_REQUEST_TIME_INTERRUPT_HOOK_NO_INIT                                                                                                        \
    static const void *const skadi_sched_yield_stub_setup_return_addr_init_fn_ptrs[] __used Z_GENERIC_SECTION(".preinit_array") = {                 \
            skadi_sched_yield_stub_setup_return_addr                                                                                                \
    }


/**
 * 
 * @brief Setup timer hook in init function.
 * Needs to be called manually in custom initialization function to prevent interrupt taking control.
 * 
 */
#define SKADI_INSTALL_TIME_INTERRUPT_HOOK                                                              \
    csr_write(SKADI_MTIMER_HOOK_CSR, &_skadi_subsystem_yield_stub);

struct skadi_thread_create_params {
    struct k_thread *new_thread;
	k_thread_stack_t *stack;
	size_t stack_size;
    k_thread_entry_t entry;
	void *p1;
    void *p2;
    void *p3;
	int prio;
    uint32_t options;
    k_timeout_t delay;
};

#ifdef SKADI_SUBSYSTEM

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_yield);

#define skadi_yield __skadi_yield

/* in the loader, use the z_impl_* variants directly */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_thread_start, k_tid_t thread);

#define skadi_thread_start(THREAD)              \
    __skadi_thread_start(THREAD)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(k_tid_t, __skadi_thread_create, const struct skadi_thread_create_params *params);

static inline k_tid_t skadi_thread_create(const struct skadi_thread_create_params *params){
    struct skadi_thread_create_params adjusted_params = *params;
    const struct skadi_thread_create_params *params_derived = skadi_cap_ops_derive_arg_ro(&adjusted_params, sizeof(*params));
    k_thread_stack_t *thread_stack = skadi_cap_ops_derive_arg(params->stack, params->stack_size);
    
    /* thread needs to continue to exist... */
    k_tid_t ret;
    __ASSERT_NO_MSG(params_derived);
    /* TODO leaked */
    __ASSERT_NO_MSG(thread_stack);
    adjusted_params.stack = thread_stack;

    params->new_thread->stack_info.start = (uintptr_t) thread_stack;

    ret = __skadi_thread_create(params_derived);

    skadi_cap_ops_drop(params_derived);

    return ret;
}

static inline void skadi_thread_cleanup(k_tid_t thread){
    __ASSERT_NO_MSG(thread);
    __ASSERT_NO_MSG(thread->stack_info.start);
    skadi_cap_ops_drop((void*)thread->stack_info.start);
    thread->stack_info.start=0;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int32_t, skadi_sleep, k_timeout_t timeout);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int32_t, skadi_usleep, int32_t us);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_thread_abort, k_tid_t thread);

static inline void skadi_thread_abort(k_tid_t thread){
    __skadi_thread_abort(thread);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_thread_suspend, k_tid_t thread);

static inline void skadi_thread_suspend(k_tid_t thread){
    __ASSERT_NO_MSG(thread);
    __skadi_thread_suspend(thread);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_thread_resume, k_tid_t thread);

static inline void skadi_thread_resume(k_tid_t thread){
    __ASSERT_NO_MSG(thread);
    __skadi_thread_resume(thread);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_thread_priority_set, k_tid_t thread, int prio);

static inline void skadi_thread_priority_set(k_tid_t thread, int prio){
    __ASSERT_NO_MSG(thread);
    __skadi_thread_priority_set(thread, prio);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_thread_join, k_tid_t thread, k_timeout_t timeout);

static inline int skadi_thread_join(k_tid_t thread, k_timeout_t timeout){
    __ASSERT_NO_MSG(thread);
    return __skadi_thread_join(thread, timeout);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_thread_name_set, k_tid_t thread, const char *str);

static inline int _skadi_thread_name_set(k_tid_t thread, const char *str, const char *file, const int line){
    const char *str_token = skadi_cap_ops_derive_arg_ro(str, strlen(str) + 1);
    int ret;
    
    ARG_UNUSED(file);
    ARG_UNUSED(line);

    ret = str_token ? __skadi_thread_name_set(thread, str_token) : -ENOMEM;
    
    if(str_token){
        skadi_cap_ops_drop(str_token);
    }
    return ret;
}

#define skadi_thread_name_set(THREAD,STR) _skadi_thread_name_set(THREAD, STR, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_thread_name_copy, k_tid_t thread, char *buf, size_t size);

static inline int skadi_thread_name_copy(k_tid_t thread, char *buf, size_t size){
    char *str_token = skadi_cap_ops_derive_arg(buf, size);
    int ret = str_token ? __skadi_thread_name_copy(thread, str_token, size) : -ENOMEM;
    
    if(str_token){
        skadi_cap_ops_drop(str_token);
    }
    return ret;
}

#ifdef CONFIG_SKADI_LIBRARY_LOCAL_CLOCK
    /* defined in skadi_local_allocator.c, a part of the per-subsystem library */
    extern uint32_t skadi_sys_clock_cycle_get_32(void);
    extern uint64_t skadi_sys_clock_cycle_get_64(void);
    extern int64_t skadi_sys_clock_tick_get(void);
#else
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint32_t,skadi_sys_clock_cycle_get_32, void);
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint64_t,skadi_sys_clock_cycle_get_64, void);
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int64_t,skadi_sys_clock_tick_get, void);
#endif


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int64_t,skadi_uptime_ticks, void);

static inline int64_t skadi_uptime_get(void){
    return k_ticks_to_ms_floor64(skadi_uptime_ticks());
}

static inline int32_t skadi_uptime_get_32(void){
    return (int32_t) skadi_uptime_get();
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(k_ticks_t,__skadi_timeout_remaining, const struct _timeout *timeout);

static inline k_ticks_t skadi_timeout_remaining(const struct _timeout *timeout){
    const struct _timeout *timeout_token = skadi_cap_ops_derive_arg_ro(timeout, sizeof(*timeout));
    k_ticks_t ret;

    __ASSERT_NO_MSG(timeout_token);

    if(!timeout_token){
        return 0;
    }

    ret = __skadi_timeout_remaining(timeout_token);

    skadi_cap_ops_drop(timeout_token);

    return ret;
}


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(bool,__skadi_thread_addr_in_stack, k_tid_t thread, uintptr_t addr);

#define skadi_thread_addr_in_stack __skadi_thread_addr_in_stack


extern uintptr_t *const skadi_sched_current_reloc;

static inline k_tid_t skadi_current_get(void){
    /* faster than subsystem call */
    return (k_tid_t) *skadi_sched_current_reloc;
}

static inline k_thread_stack_t *skadi_thread_stack_alloc(size_t size, int flags){
    (void) flags; /* indicated userspace, not implemented */
    __ASSERT_NO_MSG(!flags);

    return skadi_allocator_alloc_rw(size);
}

static inline int skadi_thread_stack_free(k_thread_stack_t *stack){
    return skadi_allocator_free(stack) ? 0 : -EINVAL;
}
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_thread_priority_get, k_tid_t thread);

static inline int skadi_thread_priority_get(k_tid_t thread){
    return __skadi_thread_priority_get(thread);
}

static inline int32_t skadi_msleep(int32_t ms){
    return skadi_sleep(Z_TIMEOUT_MS(ms));
}

static inline int32_t skadi_cycle_get_32(void){
    return skadi_sys_clock_cycle_get_32();
}

static inline int64_t skadi_cycle_get_64(void){
    return skadi_sys_clock_cycle_get_64();
}

/* inlined from timeout.c */
static inline k_timepoint_t skadi_sys_timepoint_calc(k_timeout_t timeout)
{
	k_timepoint_t timepoint;

	if (K_TIMEOUT_EQ(timeout, K_FOREVER)) {
		timepoint.tick = UINT64_MAX;
	} else if (K_TIMEOUT_EQ(timeout, K_NO_WAIT)) {
		timepoint.tick = 0;
	} else {
		k_ticks_t dt = timeout.ticks;

		if (IS_ENABLED(CONFIG_TIMEOUT_64BIT) && Z_TICK_ABS(dt) >= 0) {
			timepoint.tick = Z_TICK_ABS(dt);
		} else {
			timepoint.tick = skadi_sys_clock_tick_get() + MAX(1, dt);
		}
	}

	return timepoint;
}

static inline k_timeout_t skadi_sys_timepoint_timeout(k_timepoint_t timepoint)
{
	uint64_t now, remaining;

	if (timepoint.tick == UINT64_MAX) {
		return K_FOREVER;
	}
	if (timepoint.tick == 0) {
		return K_NO_WAIT;
	}

	now = skadi_sys_clock_tick_get();
	remaining = (timepoint.tick > now) ? (timepoint.tick - now) : 0;
	return K_TICKS(remaining);
}

static inline bool skadi_sys_timepoint_expired(k_timepoint_t timepoint)
{
	return K_TIMEOUT_EQ(skadi_sys_timepoint_timeout(timepoint), Z_TIMEOUT_NO_WAIT);
}

#endif /* SKADI_SUBSYSTEM*/

/* in skadi_library to prevent high amount of unneccessary instantiations */
extern void skadi_subsystem_yield(void);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_thread_heap_assign, struct k_thread *thread, struct k_heap *heap);

#define skadi_thread_heap_assign(THREAD, HEAD) __skadi_thread_heap_assign(THREAD, HEAD)

#endif /* SKADI_SCHED_H */
