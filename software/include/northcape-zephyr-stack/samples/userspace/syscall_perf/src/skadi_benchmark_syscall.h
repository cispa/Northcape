#include <zephyr/kernel.h>
#include <zephyr/internal/syscall_handler.h>
#ifndef _SKADI_BENCHMARK_SYSCALL_H
#define _SKADI_BENCHMARK_SYSCALL_H

__syscall void k_current_cycle_instr_get(unsigned long *cycle_half, unsigned long *instr_half);

#include <zephyr/syscalls/skadi_benchmark_syscall.h>
#endif
