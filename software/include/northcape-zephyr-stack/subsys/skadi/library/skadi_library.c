/**
 * @file Utility functions and one-time-defined data for Skadi subsystems.
 */

#include <zephyr/init.h>

#include <zephyr/skadi/skadi_ops_driver.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_sched.h>
#include <zephyr/skadi/skadi_loader.h>


#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(skadi_lib, CONFIG_SKADI_LOG_LEVEL);

#if (defined(CONFIG_SKADI_SCHEDULER_RUNS_WITH_LOADER_TASK_ID) && defined(SCHEDULER_SUBSYSTEM)) || defined(NUUK_SUBSYSTEM)
/* If scheduler runs with task ID 0, we have to accept set-task-ID tokens with our own task ID, as we can be called from the "main"/loader binary too */
#undef SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(...) SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ_ALLOW_SELF(__VA_ARGS__)
#endif

/* request preemption hook */
SKADI_REQUEST_TIME_INTERRUPT_HOOK;

skadi_task_id_t _skadi_current_subsystem_id;

/* to Skadi loader - how many trampolines do I need? */
__attribute__((visibility("default"))) const int _skadi_num_caller_trampolines = CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS;
#ifdef CONFIG_SKADI_SUBSYS_SYNC_UP
__attribute__((visibility("default"))) const int _skadi_num_caller_trampolines_irq = CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS_IRQ;
#endif

/* start below PRE_KERNEL_1, such that on first invocation, we start with first entry */

enum init_level last_init_level = INIT_LEVEL_EARLY;
int last_priority = 0;

/* defined in the linker script */
extern const struct init_entry __init_start[];
extern const struct init_entry __init_EARLY_start[];
extern const struct init_entry __init_PRE_KERNEL_1_start[];
extern const struct init_entry __init_PRE_KERNEL_2_start[];
extern const struct init_entry __init_POST_KERNEL_start[];
extern const struct init_entry __init_APPLICATION_start[];
extern const struct init_entry __init_end[];

static const struct init_entry *skadi_subsystem_levels[] = {
		__init_EARLY_start,
		__init_PRE_KERNEL_1_start,
		__init_PRE_KERNEL_2_start,
		__init_POST_KERNEL_start,
		__init_APPLICATION_start,
#ifdef CONFIG_SMP
		__init_SMP_start,
#endif /* CONFIG_SMP */
		/* End marker */
		__init_end,
	};

/**
 * @brief Returns the lowest pending priority for initialization level level, or -1 if nothing pending at that level
 */
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, skadi_subsystem_get_pending_priority, enum init_level level)
{
    const struct init_entry *entry;
    __ASSERT(level >= INIT_LEVEL_PRE_KERNEL_1, "Subsystems themselves are only loaded PRE_KERNEL_1 - cannot accept lower init level!");
    __ASSERT(level <= INIT_LEVEL_APPLICATION, "Subsystem init level must be <= APPLICATION!");

    if(last_init_level != level){
        /* new init level - need fresh priority */
        last_init_level = level;
        last_priority = 0;
    }

    entry = skadi_subsystem_levels[level];
    entry = &entry[last_priority];

    if(entry >= skadi_subsystem_levels[level+1]){
        /* done with this level */
        return -1;
    }

    return entry -> priority;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(skadi_subsystem_get_pending_priority)

/* based on kernel's init.c */
static int do_device_init(const struct init_entry *entry)
{
	const struct device *dev = entry->dev;
	int rc = 0;

	if (entry->init_fn.dev != NULL) {
		rc = entry->init_fn.dev(dev);
		/* Mark device initialized. If initialization
		 * failed, record the error condition.
		 */
		if (rc != 0) {
			if (rc < 0) {
				rc = -rc;
			}
			if (rc > UINT8_MAX) {
				rc = UINT8_MAX;
			}
			dev->state->init_res = rc;
		}
	}

	dev->state->initialized = true;

	return rc;
}

/**
 * @brief Returns the lowest pending priority for initialization level level, or -1 if nothing pending at that level
 */
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, skadi_subsystem_call_next_init_function, enum init_level level)
{
    const struct init_entry *entry;
    __ASSERT(level >= INIT_LEVEL_PRE_KERNEL_1, "Subsystems themselves are only loaded PRE_KERNEL_1 - cannot accept lower init level!");
    __ASSERT(level <= INIT_LEVEL_APPLICATION, "Subsystem init level must be <= APPLICATION!");

    entry = skadi_subsystem_levels[level];
    entry = &entry[last_priority];

    __ASSERT(entry < skadi_subsystem_levels[level+1], "Last priority should not be outside level!");

    last_priority++;

    if(entry->dev){
        if(entry->init_fn.dev){
            /* the device needs to be marked initialized for certain subsystems (e.g., networking) */
            return do_device_init(entry);
        }
        /* nothing to do */
        return 0;
    }
    if(entry->init_fn.sys){
        return entry->init_fn.sys();
    }
    /* nothing to do */
    return 0;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(skadi_subsystem_call_next_init_function)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS(skadi_sched_yield_dummy, int foo);

extern void skadi_sched_yield_callee_trampoline(int);

void skadi_subsystem_yield(void){
    skadi_sched_yield_dummy(0, skadi_sched_yield_callee_trampoline);
}

static struct skadi_subsystem_stack_manager __skadi_subsystem_stacks;
static struct skadi_subsystem_stack_manager_irq __skadi_subsystem_stacks_irq;

struct skadi_subsystem_stack_manager *skadi_subsystem_stacks = &__skadi_subsystem_stacks;
struct skadi_subsystem_stack_manager_irq *skadi_subsystem_stacks_irq = &__skadi_subsystem_stacks_irq;

SKADI_SUBSYSTEM_DECLARE_CALLER_TRAMPOLINE(skadi_subsystem);


#if !defined(NO_THREADS_IN_CALLEE_TRAMPOLINE) && defined(CONFIG_SKADI_MARK_THREAD_IN_TRAMPOLINE)
typedef void (*skadi_thread_cancelled_callback_t)(k_tid_t thread);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID_ALLOW_SELF(__skadi_thread_abort_register_callback, skadi_thread_cancelled_callback_t callback);

#ifdef SCHEDULER_SUBSYSTEM
/* the scheduler does indeed call itself */
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ_ALLOW_SELF(void, __skadi_thread_abort_callback, k_tid_t thread)
#else
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, __skadi_thread_abort_callback, k_tid_t thread)
#endif
{
    struct k_thread *allocated_thread;

    for(int number_stack = 0; number_stack < CONFIG_SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NUM_STACKS; number_stack++){
        struct k_thread **thread_addr = (struct k_thread **) skadi_subsystem_stacks->tops_of_stack[number_stack];
        /* trampolines store thread pointer at the TOS */
        allocated_thread = *thread_addr;
        if(allocated_thread == thread){
            /* 
             * found a stack occupied by cancelled frame - clear it
             * stacks are set after allocation and cleared before allocation - know that this MUST be associated with cancelled thread
             */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
            /* thread was aborted - can recycle the stack */
            atomic_set_bit((atomic_t *)&skadi_subsystem_stacks->stack_bitmap, number_stack);
#pragma GCC diagnostic pop       
        }
    }

    for(int number_set = 0; number_set < CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS; number_set++){
        allocated_thread = skadi_subsystem_caller_trampoline.trampolines[number_set]->registers->associated_thread;
        if(allocated_thread == thread){
            /* this might otherwise trip sanity check */
            skadi_subsystem_caller_trampoline.trampolines[number_set]->registers->reserved_mutex = 0;
            /* 
             * found a stack occupied by cancelled frame - clear it
             * stacks are set after allocation and cleared before allocation - know that this MUST be associated with cancelled thread
             */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
            /* thread was aborted - can recycle the stack */
            atomic_set_bit((atomic_t *)&skadi_subsystem_caller_trampoline.bitmap, number_set);
#pragma GCC diagnostic pop
        }
    }

}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_thread_abort_callback)
#endif

static bool skadi_library_prepare_caller_trampolines(void){
    return skadi_subsystem_setup_return_addr();
}

static const void *const preinit_functions[] __used Z_GENERIC_SECTION(".preinit_array") = {
    skadi_library_prepare_caller_trampolines
};

static bool skadi_library_prepare_callee_trampoline_stacks(void){
    bool ret = skadi_init_subsystem_stacks(skadi_subsystem_stacks, SKADI_CURRENT_TASK_ID);
    ret &= skadi_init_subsystem_stacks_irq(skadi_subsystem_stacks_irq, SKADI_CURRENT_TASK_ID);
    /* we need the stacks to be set up, at least in the scheduler... */
#if !defined(NO_THREADS_IN_CALLEE_TRAMPOLINE) && defined(CONFIG_SKADI_MARK_THREAD_IN_TRAMPOLINE)
    __skadi_thread_abort_register_callback(SKADI_SUBSYSTEM_FUNCTION_POINTER(__skadi_thread_abort_callback));
#endif
    return ret;
}
/* we need the caller trampolines to be set up before we can use the allocator via subsystem call */
SKADI_SUBSYSTEM_INIT_FUNCTIONS(skadi_library_prepare_callee_trampoline_stacks);

/* loader: illegal self call, and not needed, since not available after load completed anyway */
#if defined(CONFIG_PROFILING_PERF) && !defined(LOADER_SUBSYSTEM)
uintptr_t skadi_profiling_current_isr_state_reloc;
static int setup_perf_reloc(void){
    skadi_profiling_current_isr_state_reloc = skadi_loader_get_symbol("skadi_profiling_current_isr_state");
    __ASSERT_NO_MSG(skadi_profiling_current_isr_state_reloc);

    return 0;
}

SYS_INIT(setup_perf_reloc, APPLICATION, 0);

#endif

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int*, __skadi_errno);
int *z_errno(void){
    return __skadi_errno();
}

