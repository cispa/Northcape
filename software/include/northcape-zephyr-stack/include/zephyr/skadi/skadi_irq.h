#ifndef SKADI_IRQ_H
#define SKADI_IRQ_H

#include <zephyr/irq_multilevel.h>

#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/subsystems/isr/skadi_isr_subsystem.h>
#include <zephyr/skadi/subsystems/plic/skadi_plic_subsystem.h>


static inline bool skadi_register_interrupt_handler(const int irq_number, const void *arg, void (*isr)(const void *arg)){
    const unsigned int level = irq_get_level(irq_number);

    switch(level){
/* interrupt controllers not supported in loader binary */
#ifdef SKADI_SUBSYSTEM
        case 1:
            // first level interrupt, e.g., extern or timer
            // ISR subsystem
            return skadi_isr_register_handler(irq_number, arg, isr);
#endif
        default:
            // unknown level
            return skadi_plic_register_handler(irq_number, arg, isr);
    }
}

#define SKADI_IRQ_PRIORITY_DEFAULT 1
#define SKADI_IRQ_PRIORITY_HIGH 10

static inline void skadi_irq_enable(unsigned int irq, unsigned int priority){
    const unsigned int level = irq_get_level(irq);

    switch(level){
        case 1:
            // can directly enable in machine interrupt enable (mie) CSR
            csr_set(mie, 1<<irq);
            break;
        default:
            __ASSERT_NO_MSG(priority);
            // must be PLIC
            // do subsystem calls into PLIC
            // priorities default to zero, zero-priority interrupts never trigger handling
            riscv_plic_set_priority(irq, priority);
            riscv_plic_irq_enable(irq);
            break;
    }
}

static inline void skadi_irq_disable(unsigned int irq){
    const unsigned int level = irq_get_level(irq);

    switch(level){
        case 1:
            // can directly disable in machine interrupt enable (mie) CSR
            csr_clear(mie, 1<<irq);
            break;
        default:
            // must be PLIC
            // do subsystem calls into PLIC
            riscv_plic_irq_disable(irq);
            break;
    }
}

static inline int skadi_irq_is_enabled(unsigned int irq){
    const unsigned int level = irq_get_level(irq);

    switch(level){
        case 1:
            // can directly disable in machine interrupt enable (mie) CSR
            return csr_read(mie) & 1<<irq;
        default:
            // must be PLIC
            // do subsystem calls into PLIC
            return riscv_plic_irq_is_enabled(irq);
    }
}

#endif
