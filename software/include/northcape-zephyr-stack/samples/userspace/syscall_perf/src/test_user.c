/*
 * Copyright (c) 2020 BayLibre, SAS
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/kernel.h>
#include <stdio.h>

#include <zephyr/skadi/skadi_benchmark.h>
#include "skadi_benchmark_syscall.h"

#define REPETITIONS 100

/*
 * 0xC00 is CSR cycle
 * 0xC02 is CSR instret
 */
void user_thread_function(void *p1, void *p2, void *p3)
{
	register unsigned long cycle_before, cycle_count;
	register unsigned long inst_before, inst_count;
	unsigned long half_cycle, half_instr;

	struct skadi_benchmark_state benchmarks_cycles[REPETITIONS], half_benchmark_cycles[REPETITIONS];

	printf("User thread started\n");

	for(int i = 0; i < REPETITIONS; i++) {
		k_sleep(K_MSEC(100));

		skadi_benchmark_prepare_sample(&benchmarks_cycles[i]);
		skadi_benchmark_prepare_sample(&half_benchmark_cycles[i]);

		inst_before = csr_read(0xC02);
		cycle_before = csr_read(0xC00);
		k_current_cycle_instr_get(&half_cycle, &half_instr);
		cycle_count = csr_read(0xC00);
		inst_count = csr_read(0xC02);

		if (cycle_count > cycle_before) {
			cycle_count -= cycle_before;
		} else {
			cycle_count += 0xFFFFFFFF - cycle_before;
		}

		if (inst_count > inst_before) {
			inst_count -= inst_before;
		} else {
			inst_count += 0xFFFFFFFF - inst_before;
		}

		/* Remove CSR accesses to be more accurate */
		inst_count -= 3;

		skadi_benchmark_add_sample(&benchmarks_cycles[i], cycle_count);
		skadi_benchmark_add_sample(&half_benchmark_cycles[i], half_cycle - cycle_before);

		printf("User thread(%p):\t\t%8lu cycles\t%8lu instructions (half)\t%8lu instructions (full)\n",
			k_current_get(), cycle_count, half_instr - inst_before - 3, inst_count);
	}

	skadi_benchmark_evaluate_samples(half_benchmark_cycles, REPETITIONS, 0, "cycles microbenchmarks (half)");
	skadi_benchmark_evaluate_samples(benchmarks_cycles, REPETITIONS, 0, "cycles microbenchmarks (full)");
}
