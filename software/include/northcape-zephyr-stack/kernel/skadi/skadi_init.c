#include <ksched.h>

#include <zephyr/skadi/skadi_allocator.h>
#include <zephyr/skadi/skadi_init_alloc.h>
#include <zephyr/skadi/skadi_ops_driver.h>
#include <zephyr/skadi/skadi_loader.h>
#include <zephyr/skadi/skadi_init.h>

#include <zephyr/skadi/skadi_ariane_genesysii.h>

#include <zephyr/init.h>
#include <zephyr/kernel.h>

#include <zephyr/arch/riscv/csr.h>
#include <zephyr/sys/barrier.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(skadi_init, CONFIG_SKADI_LOG_LEVEL);

typedef void(*cva6_nonstandard_isr_t)(void);

extern void _skadi_exception_wrapper_callee_trampoline(void);
extern void _skadi_exception_wrapper_callee_trampoline_end(void);
extern void _skadi_subsystem_yield_stub(void);

static void reserved_isr_handler(void){
    LOG_ERR("Received reserved interrupt!");
    k_panic();
}

struct cva6_nonstandard_isr_table {
    cva6_nonstandard_isr_t exception_isr;
    cva6_nonstandard_isr_t supervisor_software_interrupt_isr;
    cva6_nonstandard_isr_t reserved_isr_1;
    cva6_nonstandard_isr_t machine_software_interrupt_isr;
    cva6_nonstandard_isr_t reserved_isr_2;
    cva6_nonstandard_isr_t supervisor_timer_interrupt_isr;
    cva6_nonstandard_isr_t reserved_isr_3;
    cva6_nonstandard_isr_t machine_timer_interrupt_isr;
    cva6_nonstandard_isr_t reserved_isr_4;
    cva6_nonstandard_isr_t supervisor_external_interrupt_isr;
    cva6_nonstandard_isr_t reserved_isr_5;
    cva6_nonstandard_isr_t machine_external_interrupt_isr;
} __attribute__((__packed__));

#define CVA6_NONSTANDARD_MTVEC_MODE_VECTORED 0x3

/*
 * Called at init time.
 * Creates direct capability for unusable physical addresses after DRAM.
 */
static inline bool create_cap_physical_address_space_after_dram(void){
	void* unusable_memory_capability;
	bool success;
	
	LOG_INF("Step 1 - Remove unusable physical address space at the end of the DRAM!");
	success = skadi_cap_ops_create_simple(SKADI_ROOT_CAP_TOKEN, 1, SKADI_ROOT_CAPABILITY_END_BYTES - (SKADI_ARIANE_DRAM_BASE_BYTES + SKADI_ARIANE_DRAM_LENGTH_BYTES - SKADI_CMT_LENGTH_BYTES), &unusable_memory_capability);

	if(success){
		LOG_INF("Step 1 success - created capability %p!\n",unusable_memory_capability);
        return true;
	}
	else{
		LOG_ERR("Step 1 error!\n");
        return false;
	}
}

/* these are found byt the allocator their well-known names */
void* __skadi_allocator_arena;
uintptr_t __skadi_allocator_arena_start;
uint32_t __skadi_allocator_arena_size_bytes;

/*
 * Called at init time.
 * Creates direct capability for the "Arena", which is a reserved memory region at the end of the DRAM.
 */
static inline bool create_skadi_arena(void){
    bool success;
    void* skadi_arena;
    uint32_t skadi_arena_size_bytes;
    skadi_restriction_t task_restriction = SKADI_TASK_ID_BOUND_RESTRICTION(SKADI_TASK_ID_LOADER, SKADI_DEVICE_ID_CPU);
    

    LOG_INF("Step 2 - Create Skadi Arena with length %llu at end of DRAM!",SKADI_ARIANE_RESERVED_LENGTH_BYTES);

    skadi_arena = 0;
    skadi_arena_size_bytes = 0;

    success = skadi_cap_ops_create_simple(SKADI_ROOT_CAP_TOKEN, 1, SKADI_ARIANE_RESERVED_LENGTH_BYTES - CONFIG_SKADI_INIT_ALLOC_HEAP_SIZE, &skadi_arena);

    if(success && skadi_arena){
        LOG_INF("Step 2 success - created skadi arena %p!",(void*)skadi_arena);
        skadi_arena_size_bytes = SKADI_ARIANE_RESERVED_LENGTH_BYTES;
        /* llext will take care of conveying these to the allocator */
        __skadi_allocator_arena = skadi_arena;
        __skadi_allocator_arena_start = SKADI_ARIANE_RESERVED_BASE_BYTES + CONFIG_SKADI_INIT_ALLOC_HEAP_SIZE;
        __skadi_allocator_arena_size_bytes = SKADI_ARIANE_RESERVED_LENGTH_BYTES - CONFIG_SKADI_INIT_ALLOC_HEAP_SIZE;
    }
    else{
        LOG_ERR("Failed to create skadi arena!");
        return false;
    }

    LOG_INF("Step 3 - Create loader's private heap with length %u between remaining root capability and Northape Arena!", CONFIG_SKADI_INIT_ALLOC_HEAP_SIZE);

    success = skadi_cap_ops_create(SKADI_ROOT_CAP_TOKEN, task_restriction, 1, CONFIG_SKADI_INIT_ALLOC_HEAP_SIZE, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, &skadi_arena);

    if(success && skadi_arena){
        LOG_INF("Step 3 success - created loader's private heap %p!", (void*)skadi_arena);

        skadi_init_alloc_set_heap(skadi_arena);

        return true;
    }
    else{
        LOG_ERR("Failed to create loader's private heap!");
        return false;
    }

    return true;

}

static struct cva6_nonstandard_isr_table *isr_table = NULL, *isr_table_writable;


void skadi_init_register_exception_handler(cva6_nonstandard_isr_t exception_isr){
    isr_table_writable->exception_isr = exception_isr;
}

/* used to overwrite timer interrupt ISR*/
/* exported to subsystems */
void (***skadi_subsystem_mtimer_sched_hook_loader)(void);
void (**skadi_subsystem_mtimer_sched_hook)(void);

skadi_task_id_t _skadi_current_subsystem_id = SKADI_TASK_ID_LOADER;


/* used by the loader's own call stubs*/
extern uint64_t skadi_subsystem_mtimer_sched_hook_reloc;

#ifdef CONFIG_SKADI_LOADER
static struct skadi_subsystem_init_callback_registration isr_table_isr_subsystem_loaded_callback, isr_table_exception_subsystem_loaded_callback;
#endif

static bool external_interrupts_registered, exceptions_registered;

static inline void skadi_init_make_isr_table_read_only_if_possible(void){
    skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

    if(!external_interrupts_registered || !exceptions_registered){
        return;
    }

    LOG_INF("External interrupts for ISR table registered - make ISR table read only!");

    if(skadi_cap_ops_restrict(isr_table, restriction, 0, 0, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS) == false){
        LOG_WRN("Could not drop write permission from ISR table!");
    }
}

#ifdef CONFIG_SKADI_LOADER
static void skadi_init_update_isr_table_external_interrupts(const struct skadi_subsystem_init_callback_registration *registration){
    uintptr_t isr_wrapper;
    
    ARG_UNUSED(registration);

    __ASSERT(isr_table != NULL, "ISR table should be set before this is called!");
    
    isr_wrapper = skadi_loader_get_symbol("_skadi_isr_wrapper_callee_trampoline");

    if(!isr_wrapper){
        LOG_ERR("Could not find ISR wrapper trampoline!");
        return;
    }

    LOG_WRN("ISR token is %p",(void *)isr_wrapper);

    isr_table->supervisor_external_interrupt_isr = (cva6_nonstandard_isr_t) isr_wrapper;
    isr_table->machine_external_interrupt_isr = (cva6_nonstandard_isr_t) isr_wrapper;

    external_interrupts_registered = true;

    skadi_init_make_isr_table_read_only_if_possible();

    // make sure the writes commit
    barrier_dmem_fence_full();
}
#endif

#ifdef CONFIG_SKADI_LOADER
static void skadi_init_update_isr_table_exceptions(const struct skadi_subsystem_init_callback_registration *registration){
    uintptr_t isr_wrapper;
    
    ARG_UNUSED(registration);

    __ASSERT(isr_table != NULL, "ISR table should be set before this is called!");
    
    isr_wrapper = skadi_loader_get_symbol("_skadi_exception_wrapper_callee_trampoline");

    if(!isr_wrapper){
        LOG_ERR("Could not find exception wrapper trampoline!");
        return;
    }

    LOG_WRN("Exception token is %p",(void *)isr_wrapper);


    isr_table_writable->exception_isr =  (cva6_nonstandard_isr_t) isr_wrapper;
    isr_table_writable->supervisor_software_interrupt_isr =  (cva6_nonstandard_isr_t) isr_wrapper;
    isr_table_writable->reserved_isr_1 =  (cva6_nonstandard_isr_t) isr_wrapper;
    isr_table_writable->machine_software_interrupt_isr =  (cva6_nonstandard_isr_t) isr_wrapper;
    isr_table_writable->reserved_isr_2 =  (cva6_nonstandard_isr_t) isr_wrapper;
    isr_table_writable->supervisor_timer_interrupt_isr =  (cva6_nonstandard_isr_t) isr_wrapper;
    isr_table_writable->reserved_isr_3 =  (cva6_nonstandard_isr_t) isr_wrapper;
    isr_table_writable->reserved_isr_4 =  (cva6_nonstandard_isr_t) isr_wrapper;
    isr_table_writable->reserved_isr_5 =  (cva6_nonstandard_isr_t) isr_wrapper;

    exceptions_registered = true;

    skadi_init_make_isr_table_read_only_if_possible();

    // make sure the writes commit
    barrier_dmem_fence_full();
}
#endif

static inline bool skadi_init_isr_table(void){
    uintptr_t mtvec_val;
    void* machine_timer_interrupt_cap;
    bool derive_ok;
    skadi_restriction_t table_restriction = SKADI_NO_RESTRICTION, isr_restriction = SKADI_TASK_ID_RESTRICTION(SKADI_TASK_ID_LOADER, SKADI_DEVICE_ID_CPU, SKADI_RESTRICTIONS_SET_TASK_ID);
    void* isr_wrapper_token;

    // NOT restricted to loader task
    // this would mean that interrupts cannot be handled when another task is running
    // also, need 512-byte alignment - force size big enough that 8-bit token is not used
    isr_table = (struct cva6_nonstandard_isr_table *) skadi_init_alloc_allocate(SKADI_ISR_TABLE_SIZE, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, false);

    if(!isr_table){
        LOG_ERR("Could not allocate ISR table!");
        return false;
    }
    // cva6 (or the MMU) will translate this
    mtvec_val = (uintptr_t) isr_table;
    

    __ASSERT((mtvec_val & 0x1ff) == 0, "ISR table should be 512-byte aligned!");

    memset(isr_table, 0, sizeof(*isr_table));

    derive_ok = skadi_cap_ops_derive(_skadi_exception_wrapper_callee_trampoline, isr_restriction, (size_t)((uintptr_t) _skadi_exception_wrapper_callee_trampoline_end - (uintptr_t) _skadi_exception_wrapper_callee_trampoline), skadi_get_capability_offset(_skadi_exception_wrapper_callee_trampoline), SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, &isr_wrapper_token);

    __ASSERT_NO_MSG(derive_ok);

    if(!derive_ok){
        LOG_ERR("Could not derive ISR token!");
        return false;
    }
#if defined(CONFIG_SKADI_LOADER)
    isr_table->exception_isr = (void*)isr_wrapper_token;
#else
    /* features such as FP exceptions, system calls, ... */
    extern void _isr_wrapper(void);
    isr_table->exception_isr = (void*)_isr_wrapper;
#endif
    isr_table->supervisor_software_interrupt_isr = (void*)isr_wrapper_token;
    isr_table->reserved_isr_1 = reserved_isr_handler;
    isr_table->machine_software_interrupt_isr = (void*)isr_wrapper_token;
    isr_table->reserved_isr_2 = reserved_isr_handler;
    isr_table->supervisor_timer_interrupt_isr = (void*)isr_wrapper_token;
    isr_table->reserved_isr_3 = reserved_isr_handler;
#if defined(CONFIG_SKADI_LOADER)
    isr_table->machine_timer_interrupt_isr = _skadi_subsystem_yield_stub;
#else
    isr_table->machine_timer_interrupt_isr = (void*)_isr_wrapper;
#endif
    isr_table->reserved_isr_4 = reserved_isr_handler;
    isr_table->supervisor_external_interrupt_isr = (void*)isr_wrapper_token;
    isr_table->reserved_isr_5 = reserved_isr_handler;
    isr_table->machine_external_interrupt_isr = (void*)isr_wrapper_token;


    LOG_INF("Setting mtvec!");


    csr_write(mtvec, mtvec_val | CVA6_NONSTANDARD_MTVEC_MODE_VECTORED);

    // skadi tasks are given a writable capability for the mtimer handler
    // they can use this to register an individual preempt stub, allowing them to to a subsystem call into the scheduler
    // they are not intended to read/write the rest of the table, and the rest of the table is made read-only when all handlers are registered too
    // note that the token is deliberately NOT IRQ accessible - this prevents the ISR subsystem from stealing the interrupted task's TID by changing the interrupt handler
    derive_ok = skadi_cap_ops_derive(isr_table, table_restriction, sizeof(uintptr_t), offsetof(struct cva6_nonstandard_isr_table, machine_timer_interrupt_isr), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &machine_timer_interrupt_cap);

    if(!derive_ok || !machine_timer_interrupt_cap){
        LOG_ERR("Could not derive writable capability for user tasks' mtimer handler!");
        return false;
    }
    else{
        LOG_INF("Got machine timer interrupt cap: %p", (void*) machine_timer_interrupt_cap);
    }
    // note that this is deliberately not IRQ accessible - see above
    skadi_subsystem_mtimer_sched_hook_loader = (void*) skadi_init_alloc_allocate(sizeof(*skadi_subsystem_mtimer_sched_hook_loader), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, false);

    if(!skadi_subsystem_mtimer_sched_hook_loader){
        LOG_ERR("Could not alloc mtimer sched hook!");
        return false;
    }

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
    *skadi_subsystem_mtimer_sched_hook_loader = (__typeof__(*skadi_subsystem_mtimer_sched_hook_loader))machine_timer_interrupt_cap;
#pragma GCC diagnostic pop

    skadi_subsystem_mtimer_sched_hook_reloc = (uint64_t) (uintptr_t) *skadi_subsystem_mtimer_sched_hook_loader;
    skadi_subsystem_mtimer_sched_hook = *skadi_subsystem_mtimer_sched_hook_loader;

#ifdef CONFIG_SKADI_LOADER
    isr_table_isr_subsystem_loaded_callback.subsys_name = "isr";
    isr_table_isr_subsystem_loaded_callback.callback = skadi_init_update_isr_table_external_interrupts;
    isr_table_exception_subsystem_loaded_callback.subsys_name = "exception";
    isr_table_exception_subsystem_loaded_callback.callback = skadi_init_update_isr_table_exceptions;

    skadi_subsystem_init_register_callback(&isr_table_isr_subsystem_loaded_callback);
    skadi_subsystem_init_register_callback(&isr_table_exception_subsystem_loaded_callback);
#endif

    /* prevent subsystems from overwriting the table - they cannot use the writable capability */
    isr_table_writable = skadi_cap_ops_derive_arg_tid(isr_table, sizeof(*isr_table), SKADI_TASK_ID_LOADER);
    __ASSERT_NO_MSG(isr_table_writable);
    skadi_init_make_isr_table_read_only_if_possible();

    return isr_table_writable != NULL;
}

static struct skadi_subsystem_stack_manager __skadi_subsystem_stacks;
static struct skadi_subsystem_stack_manager_irq __skadi_subsystem_stacks_irq;


struct skadi_subsystem_stack_manager *skadi_subsystem_stacks = &__skadi_subsystem_stacks;
struct skadi_subsystem_stack_manager_irq *skadi_subsystem_stacks_irq = &__skadi_subsystem_stacks_irq;

SKADI_SUBSYSTEM_DECLARE_CALLER_TRAMPOLINE(skadi_subsystem);

struct skadi_subsystem_caller_trampoline *__skadi__skadi_subsystem_caller_trampolines[CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS];
struct skadi_subsystem_caller_trampoline *__skadi__skadi_subsystem_caller_trampolines_irq[CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS_IRQ];

#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALL_ALLOC_ITERATIONS
/* for loader subsystem calls */
long skadi_subsystem_callee_trampoline_alloc_its;
long skadi_subsystem_caller_trampoline_alloc_its;
#endif

static bool skadi_library_prepare_stacks(void){
    return skadi_init_subsystem_stacks(skadi_subsystem_stacks, SKADI_TASK_ID_LOADER) && skadi_init_subsystem_stacks_irq(skadi_subsystem_stacks_irq, SKADI_TASK_ID_LOADER) && skadi_subsystem_setup_return_addr();
}

static inline bool prepare_skadi_caller_stacks(void){
    for(int i = 0; i < CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS; i++){
        /* restriction added immediately in setup function */
        __skadi__skadi_subsystem_caller_trampolines[i] = skadi_init_alloc_allocate_aligned(sizeof(*__skadi__skadi_subsystem_caller_trampolines[i]), SKADI_ALL_PERMISSIONS, false, SKADI_CALLER_TRAMPOLINE_ALIGNMENT);

        if(!__skadi__skadi_subsystem_caller_trampolines[i]){
            return false;
        }
    }
#ifdef CONFIG_SKADI_SUBSYS_SYNC_UP
    for(int i = 0; i < CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS_IRQ; i++){
        /* restriction added immediately in setup function */
        __skadi__skadi_subsystem_caller_trampolines_irq[i] = skadi_init_alloc_allocate_aligned(sizeof(*__skadi__skadi_subsystem_caller_trampolines_irq[i]), SKADI_ALL_PERMISSIONS, false, SKADI_CALLER_TRAMPOLINE_ALIGNMENT);

        if(!__skadi__skadi_subsystem_caller_trampolines_irq[i]){
            return false;
        }
    }
#endif
    return true;
}

void skadi_init_clear_irq_stack(void *irq_stack){
    uint8_t* allocated_stack =  irq_stack;
    allocated_stack -= skadi_get_capability_offset(allocated_stack);

    skadi_allocator_free(allocated_stack);
}

#ifdef CONFIG_SKADI_DEBUG_UNRESTRICTED_ROOT_CAP
static bool skadi_restrict_root_cap(void){
    return true;
}
#else
static bool skadi_restrict_root_cap(void){
    skadi_restriction_t loader_restriction = SKADI_TASK_ID_RESTRICTION(SKADI_TASK_ID_LOADER, SKADI_DEVICE_ID_CPU, SKADI_RESTRICTIONS_TASK_ID_BOUND);

    return skadi_cap_ops_restrict(SKADI_ROOT_CAP_TOKEN, loader_restriction, 0, 0, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS);
}
#endif



__boot_func static int skadi_init(void){
    int ret;
    

    ret = 0;

    LOG_INF("Initializing skadi memory management!");

    /* need to be prepared first */
#if defined(CONFIG_SKADI_LOADER)
    csr_write(SKADI_MTIMER_HOOK_CSR, _skadi_subsystem_yield_stub);
#else
    csr_write(SKADI_MTIMER_HOOK_CSR, _isr_wrapper);
#endif
    

    LOG_INF("Wrote initial address %p into hook CSR %x!", _isr_wrapper, SKADI_MTIMER_HOOK_CSR);

    skadi_cap_ops_set_northcape_enabled();

    LOG_INF("Northcape was enabled!");

    ret = create_cap_physical_address_space_after_dram() ? 0 : 1;
    ret = ret || create_skadi_arena() ? 0 : 1;
    ret = ret || skadi_init_isr_table() ? 0 : 1;
    ret = ret || prepare_skadi_caller_stacks() ? 0 : 1;
    ret = ret || skadi_library_prepare_stacks() ? 0 : 1;
    ret = ret || skadi_restrict_root_cap() ? 0 : 1;
    
    LOG_INF("Skadi memory management initialization complete with return status %u!",ret);

    return 0;
}
/* in case the loader is not on, can do the initialization later, allowing us to print errors / status messages via UART */
#if defined(CONFIG_SKADI_LOADER)
SYS_INIT(skadi_init, PRE_KERNEL_1, CONFIG_LOADER_SKADI_ALLOC_INIT_PRIO);
#else
SYS_INIT(skadi_init, POST_KERNEL, CONFIG_LOADER_SKADI_ALLOC_INIT_PRIO);
#endif

#ifdef CONFIG_SKADI_OS_DEBUG_CAP_NUM
    static uint64_t last_caps;

    static void debug_timer_last_caps_handler(struct k_timer *dummy){
        const uint64_t current_caps = skadi_cap_ops_get_capability_count();
        ARG_UNUSED(dummy);

        LOG_INF("Skadi capability report: %"PRIu64" capabilities in the system (delta: %c%"PRIu64")!", current_caps, last_caps > current_caps ? '-' : '+', last_caps > current_caps ? last_caps - current_caps : current_caps - last_caps);
        last_caps = current_caps;
    }
    K_TIMER_DEFINE(skadi_debug_cap_num_timer, debug_timer_last_caps_handler, NULL);

    __boot_func static int skadi_register_debug_cap_num_hander(void){
        k_timer_start(&skadi_debug_cap_num_timer, K_SECONDS(CONFIG_SKADI_OS_DEBUG_CAP_NUM_TIMER_PERIOD), K_SECONDS(CONFIG_SKADI_OS_DEBUG_CAP_NUM_TIMER_PERIOD));
        return 0;
    }

    SYS_INIT(skadi_register_debug_cap_num_hander, POST_KERNEL, 0);
#endif

#ifdef CONFIG_SKADI_TRACK_CYCLES_OPS
atomic_t skadi_cycles_create;
atomic_t skadi_cycles_derive;
atomic_t skadi_cycles_drop;
atomic_t skadi_cycles_merge;
atomic_t skadi_cycles_clone;
atomic_t skadi_cycles_revoke;
atomic_t skadi_cycles_lock;
atomic_t skadi_cycles_inspect;
atomic_t skadi_cycles_restrict;
atomic_t skadi_cycles_sweep;

atomic_t skadi_cycles_create_ops;
atomic_t skadi_cycles_derive_ops;
atomic_t skadi_cycles_drop_ops;
atomic_t skadi_cycles_merge_ops;
atomic_t skadi_cycles_clone_ops;
atomic_t skadi_cycles_revoke_ops;
atomic_t skadi_cycles_lock_ops;
atomic_t skadi_cycles_inspect_ops;
atomic_t skadi_cycles_restrict_ops;
atomic_t skadi_cycles_sweep_ops;

atomic_t skadi_failed_occupied_checks_create_ops;
atomic_t skadi_failed_occupied_checks_derive_ops;
atomic_t skadi_failed_occupied_checks_drop_ops;
atomic_t skadi_failed_occupied_checks_merge_ops;
atomic_t skadi_failed_occupied_checks_clone_ops;
atomic_t skadi_failed_occupied_checks_revoke_ops;
atomic_t skadi_failed_occupied_checks_lock_ops;
atomic_t skadi_failed_occupied_checks_inspect_ops;
atomic_t skadi_failed_occupied_checks_restrict_ops;
atomic_t skadi_failed_occupied_checks_sweep_ops;

#endif
