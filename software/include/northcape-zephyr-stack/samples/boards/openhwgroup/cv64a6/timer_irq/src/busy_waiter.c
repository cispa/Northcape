#include <zephyr/logging/log.h>
#include <zephyr/irq.h>

#ifdef CONFIG_SKADI_LOADER
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_allocator.h>
#include <zephyr/skadi/skadi_loader.h>
#include <zephyr/skadi/skadi_sched.h>
#endif

LOG_MODULE_REGISTER(skadi_irq_test_busy_waiter, CONFIG_LOG_DEFAULT_LEVEL);

static volatile int dummy_int;

#define BUSY_WAITER_PRINT_DELAY 16384

// dummy callable entrypoint
// used by irq_client to start busy waiter as soon as interrupt scheduled
// primarily used to enforce load order
#if defined(CONFIG_SKADI_LOADER) && defined(CONFIG_TIMER_NMI)
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, busy_waiter_start, void)
#elif defined(CONFIG_SKADI_LOADER)
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, busy_waiter_start, void)
#else
int busy_waiter_start(void)
#endif
{
    dummy_int = 0;
    for(;;){
#ifdef CONFIG_TIMER_NMI
        // disable IRQs to force NMI feature
        (void)arch_irq_lock();
#endif
        if(dummy_int % BUSY_WAITER_PRINT_DELAY == 0){
            LOG_INF("Busy waiting %d!\n", dummy_int);
        }
        dummy_int++;
    }

    return 0;
}
#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(busy_waiter_start)
#endif

// need not have init function - callee trampoline registers its own
