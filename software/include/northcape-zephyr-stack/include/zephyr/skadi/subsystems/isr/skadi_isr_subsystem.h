#ifndef SKADI_ISR_SUBSYSTEM_H
#define SKADI_ISR_SUBSYSTEM_H
#include <zephyr/skadi/skadi_subsystem.h>

/* not supported in loader binary */
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(bool, skadi_isr_register_handler, const int irq_number, const void *arg, void (*isr)(const void *arg));
#endif

#endif
