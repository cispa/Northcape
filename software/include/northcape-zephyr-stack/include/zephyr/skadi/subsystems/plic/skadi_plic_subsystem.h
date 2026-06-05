#ifndef SKADI_PLIC_SUBSYSTEM_H
#define SKADI_PLIC_SUBSYSTEM_H
#include <zephyr/skadi/skadi_subsystem.h>

#ifdef SKADI_SUBSYSTEM
    /**
     * @brief Enable a riscv PLIC-specific interrupt line
     *
     * This routine enables a RISCV PLIC-specific interrupt line.
     *
     * @param irq IRQ number to enable (zephyr-provided number, will be parsed as level-2 interrupt)
     */
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(riscv_plic_irq_enable, uint32_t irq);

    /**
     * @brief Disable a riscv PLIC-specific interrupt line
     *
     * This routine disables a RISCV PLIC-specific interrupt line.
     *
     * @param irq IRQ number to disable (zephyr-provided number, will be parsed as level-2 interrupt)
     */
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(riscv_plic_irq_disable, uint32_t irq);

    /**
     * @brief Check if a riscv PLIC-specific interrupt line is enabled
     *
     * This routine checks if a RISCV PLIC-specific interrupt line is enabled.
     * @param irq IRQ number to check
     *
     * @return 1 or 0
     */
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, riscv_plic_irq_is_enabled, uint32_t irq);
    /**
     * @brief Set priority of a riscv PLIC-specific interrupt line
     *
     * This routine set the priority of a RISCV PLIC-specific interrupt line.
     *
     * @param irq IRQ number for which to set priority
     * @param priority Priority of IRQ to set to
     */
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(riscv_plic_set_priority, uint32_t irq, uint32_t priority);

    /**
     * @brief Register ISR for an IRQ with the PLIC.
     *
     * @param irq_number IRQ number for which to register a handler (zephyr-provided number, will be parsed as level-2 interrupt)
     * @return true (OK) or false (Error)
     */
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(bool, skadi_plic_register_handler, const int irq_number, const void *arg, void (*isr)(const void *arg));
#else /* SKADI_SUBSYSTEM */
    /* Implemented in skadi_plic_stub.c*/
    void riscv_plic_irq_enable(uint32_t irq);

    void riscv_plic_irq_disable(uint32_t irq);

    int riscv_plic_irq_is_enabled(uint32_t irq);

    void riscv_plic_set_priority(uint32_t irq, uint32_t priority);

    bool skadi_plic_register_handler(const int irq_number, const void *arg, void (*isr)(const void *arg));
#endif

#endif
