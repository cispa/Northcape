#include <zephyr/sys/atomic.h>
#include <zephyr/llext/symbol.h>

atomic_t skadi_num_subsystem_calls;

#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALL_ALLOC_ITERATIONS
long skadi_subsystem_callee_trampoline_alloc_its;
EXPORT_SYMBOL(skadi_subsystem_callee_trampoline_alloc_its);
long skadi_subsystem_caller_trampoline_alloc_its;
EXPORT_SYMBOL(skadi_subsystem_caller_trampoline_alloc_its);
#endif

EXPORT_SYMBOL(skadi_num_subsystem_calls);
