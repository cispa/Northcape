/*
 * Copyright (c) 2021 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/kernel.h>
#include <zephyr/timing/timing.h>
#include "utils.h"

#include <zephyr/skadi/skadi_benchmark.h>

#ifdef SKADI_SUBSYSTEM
#include <zephyr/skadi/skadi_subsystem.h>
#endif

#define TEST_COUNT 100
#define TEST_SIZE 10

static struct skadi_benchmark_state malloc_samples_1[TEST_COUNT],
			   malloc_samples_2[TEST_COUNT];

void heap_malloc_free(void)
{
	timing_t heap_malloc_start_time = 0U;
	timing_t heap_malloc_end_time = 0U;

	timing_t heap_free_start_time = 0U;
	timing_t heap_free_end_time = 0U;

	uint32_t count = 0U;
	uint32_t sum_malloc = 0U;
	uint32_t sum_free = 0U;

	bool  failed = false;
	char  error_string[80];
	char  description[120];
	const char *notes = "";

	timing_start();

	while (count != TEST_COUNT) {
		skadi_benchmark_prepare_sample(&malloc_samples_1[count]);
		skadi_benchmark_prepare_sample(&malloc_samples_2[count]);
		heap_malloc_start_time = timing_counter_get();
#ifdef SKADI_SUBSYSTEM
		void *allocated_mem = skadi_allocator_alloc_rw(TEST_SIZE);
#else
		void *allocated_mem = k_malloc(TEST_SIZE);
#endif

		heap_malloc_end_time = timing_counter_get();
		if (allocated_mem == NULL) {
			error_count++;
			snprintk(error_string, 78,
				  "alloc memory @ iteration %d", count);
			notes = error_string;
			break;
		}

		heap_free_start_time = timing_counter_get();
#ifdef SKADI_SUBSYSTEM
		skadi_allocator_free(allocated_mem);
#else
		k_free(allocated_mem);
#endif
		heap_free_end_time = timing_counter_get();

		sum_malloc += timing_cycles_get(&heap_malloc_start_time,
				&heap_malloc_end_time);
		sum_free += timing_cycles_get(&heap_free_start_time,
				&heap_free_end_time);

		skadi_benchmark_add_sample(&malloc_samples_1[count], timing_cycles_to_ns(timing_cycles_get(&heap_malloc_start_time,
			&heap_malloc_end_time)));
		skadi_benchmark_add_sample(&malloc_samples_2[count], timing_cycles_to_ns(timing_cycles_get(&heap_free_start_time,
			&heap_free_end_time)));
		count++;
	}

	/*
	 * If count is 0, it means that there is not enough memory heap
	 * to do k_malloc at least once. Override the error string.
	 */

	if (count == 0) {
		failed = true;
		notes = "Memory heap too small--increase it.";
	}

	snprintf(description, sizeof(description),
		 "%-40s - Average time for heap malloc",
		 "heap.malloc.immediate");
	PRINT_STATS_AVG(description, sum_malloc, count, failed, notes);
	skadi_benchmark_evaluate_samples(malloc_samples_1, TEST_COUNT, 0, description);

	snprintf(description, sizeof(description),
		 "%-40s - Average time for heap free",
		 "heap.free.immediate");
	PRINT_STATS_AVG(description, sum_free, count, failed, notes);
	skadi_benchmark_evaluate_samples(malloc_samples_1, TEST_COUNT, 0, description);

	timing_stop();
}
