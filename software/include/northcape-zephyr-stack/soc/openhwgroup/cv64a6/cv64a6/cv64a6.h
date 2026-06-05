#pragma once

#ifndef CV64A6_H
#define CV64A6_H

#include <stdint.h>
#include <zephyr/arch/riscv/csr.h>
#include <zephyr/toolchain.h>

#define CV64A6_CSR_DEBUG_OFFSET     0x7cf
#define CV64A6_CSR_NMI_MASK         0x7cd

static inline void skadi_cv64a6_make_interrupt_unmaskeable(long irq){
    csr_write(CV64A6_CSR_NMI_MASK, irq);
}

FUNC_NORETURN void z_cv64a6_finish_test(const int32_t status);

#endif
