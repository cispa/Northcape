/**
 * @file Wrapper functions for PLIC subsystem.
 * This is used to register IRQs in the Skadi loader, e.g., for devices during transition period.
 */


#include <zephyr/skadi/skadi_ops_driver.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(skadi_plic_stub, CONFIG_SKADI_LOG_LEVEL);


void riscv_plic_irq_enable(uint32_t irq){
   LOG_WRN("Skadi loader disabled - PLIC does not exist!");
}

void riscv_plic_irq_disable(uint32_t irq){
    LOG_WRN("Skadi loader disabled - PLIC does not exist!");
}

int riscv_plic_irq_is_enabled(uint32_t irq){
    LOG_WRN("Skadi loader disabled - PLIC does not exist!");
    return -EOPNOTSUPP;
}

void riscv_plic_set_priority(uint32_t irq, uint32_t priority){
    LOG_WRN("Skadi loader disabled - PLIC does not exist!");
}

bool skadi_plic_register_handler(const int irq_number, const void *arg, void (*isr)(const void *arg)){
    LOG_WRN("Skadi loader disabled - PLIC does not exist!");
    return false;
}

/* called by Skadi init as soon as ISR subsystem loaded */
void skadi_plic_stub_configure(void){
    /* nothing to do */
}
