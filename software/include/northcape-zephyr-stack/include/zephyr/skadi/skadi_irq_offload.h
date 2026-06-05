#ifndef SKADI_IRQ_OFFLOAD_H
#define SKADI_IRQ_OFFLOAD_H

#include <zephyr/skadi/skadi_subsystem.h>

#include <zephyr/irq_offload.h>

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_irq_offload, irq_offload_routine_t routine, const void *parameter);

static void skadi_irq_offload(irq_offload_routine_t routine, const void *parameter){
    __skadi_irq_offload(routine, parameter);
}

#endif /* SKADI_IRQ_OFFLOAD_H */
