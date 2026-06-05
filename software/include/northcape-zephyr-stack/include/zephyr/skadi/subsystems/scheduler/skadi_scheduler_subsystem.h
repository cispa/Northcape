#ifndef SKADI_SCHEDULER_SUBSYSTEM_H
#define SKADI_SCHEDULER_SUBSYSTEM_H

#include <zephyr/skadi/skadi_subsystem.h>

/**
 * @brief Yield current thread and let the scheduler decide who should run next.
 *
 * This subsystem call allows a thread to yield itself.
 *
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(skadi_sched_yield, void)

#endif
