#include <zephyr/skadi/skadi_subsystem.h>

/* dummies for trampolines */
void _skadi_subsystem_yield_stub(void){
    __ASSERT(false, "This should NEVER be called!");
}
void (*dummy_writable_2)(void) = _skadi_subsystem_yield_stub;
void (**skadi_subsystem_mtimer_sched_hook)(void) = &dummy_writable_2;

static struct skadi_subsystem_stack_manager __skadi_subsystem_stacks;
static struct skadi_subsystem_stack_manager_irq __skadi_subsystem_stacks_irq;

struct skadi_subsystem_stack_manager *skadi_subsystem_stacks = &__skadi_subsystem_stacks;
struct skadi_subsystem_stack_manager_irq *skadi_subsystem_stacks_irq = &__skadi_subsystem_stacks_irq;
/* we cannot rely on the library to do this for us */
static bool skadi_library_prepare_stacks(void){
    return skadi_init_subsystem_stacks(skadi_subsystem_stacks, SKADI_CURRENT_TASK_ID) && skadi_init_subsystem_stacks_irq(skadi_subsystem_stacks_irq, SKADI_CURRENT_TASK_ID);
}

/* need the free list to be created... */
SKADI_SUBSYSTEM_INIT_FUNCTIONS(skadi_library_prepare_stacks);

#if !defined(SKADI_SUBSYSTEM_ALLOCATOR) || defined(CONFIG_SOC_SERIES_CV64A6_PROVIDE_TEST_POWEROFF)
/* the allocator does not call anything */
SKADI_SUBSYSTEM_DECLARE_CALLER_TRAMPOLINE(skadi_subsystem);

/* somewhere for the trampoline to park its scheduler stub */
uint64_t dummy_number;
/* needs to live in the TEXT segment to be relocatable by the code */
uint64_t __attribute__((section(".text.skadi.trampolines.skadi_subsystem_mtimer_sched_hook_reloc,\"ax\",@progbits #"))) skadi_subsystem_mtimer_sched_hook_reloc = (uint64_t)(uintptr_t)&dummy_number;

static bool skadi_library_prepare_caller_trampolines(void){
    /* this needs to be relocated*/
    return skadi_subsystem_setup_return_addr();
}

static const void *const preinit_functions[] __used Z_GENERIC_SECTION(".preinit_array") = {
    skadi_library_prepare_caller_trampolines
};


#endif

#if defined(SKADI_SUBSYSTEM_ALLOCATOR) && defined(CONFIG_SOC_SERIES_CV64A6_PROVIDE_TEST_POWEROFF)
/* allocator needs a local implementation of memcpy for initializing the trampolines */

void *memcpy(void *dest, const void *src, size_t n){
    uint8_t *restrict dest_u8 = dest;
    const uint8_t *restrict src_u8 = src;

    for(size_t i=0; i < n; i++){
        dest_u8[i] = src_u8[i];
    }

    return dest;
}


#endif

/* filled in by skadi loader */
skadi_task_id_t _skadi_current_subsystem_id;

/* to Skadi loader - how many trampolines do I need? */
__attribute__((visibility("default"))) const int _skadi_num_caller_trampolines = CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS;
#ifdef CONFIG_SKADI_SUBSYS_SYNC_UP
__attribute__((visibility("default"))) const int _skadi_num_caller_trampolines_irq = CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS_IRQ;
#endif

#if !defined(LIBC_SUBSYSTEM)
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int*, __skadi_errno);
int *z_errno(void){
    return __skadi_errno();
}
#endif
