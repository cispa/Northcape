/*
 * Copyright (c) 2024 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/*
 * @file measure time for various LIFO operations
 *
 * This file contains the tests that measures the times for the following
 * LIFO operations from both kernel threads and user threads:
 *  1. Immediately adding a data item to a LIFO
 *  2. Immediately removing a data item from a LIFO
 *  3. Immediately adding a data item to a LIFO with allocation
 *  4. Immediately removing a data item from a LIFO with allocation
 *  5. Blocking on removing a data item from a LIFO
 *  6. Waking (and context switching to) a thread blocked on a LIFO via
 *     k_lifo_put().
 *  7. Waking (and context switching to) a thread blocked on a LIFO via
 *     k_lifo_alloc_put().
 */

#include <zephyr/kernel.h>
#include <zephyr/timing/timing.h>
#include "utils.h"
#include "timing_sc.h"

#ifdef SKADI_SUBSYSTEM
#include <zephyr/skadi/skadi_queue.h>
#endif

#define STACK_SIZE (512 + CONFIG_TEST_EXTRA_STACK_SIZE)

static K_LIFO_DEFINE(lifo);

BENCH_BMEM uintptr_t lifo_data[5];

static struct skadi_benchmark_state lifo_samples_1[CONFIG_BENCHMARK_NUM_ITERATIONS],
			   lifo_samples_2[CONFIG_BENCHMARK_NUM_ITERATIONS],
			   lifo_samples_3[CONFIG_BENCHMARK_NUM_ITERATIONS],
			   lifo_samples_4[CONFIG_BENCHMARK_NUM_ITERATIONS],
			   lifo_samples_5[CONFIG_BENCHMARK_NUM_ITERATIONS],
			   lifo_samples_6[CONFIG_BENCHMARK_NUM_ITERATIONS],
			   lifo_samples_7[CONFIG_BENCHMARK_NUM_ITERATIONS],
			   lifo_samples_8[CONFIG_BENCHMARK_NUM_ITERATIONS];

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, lifo_put_get_thread_entry, void *p1, void *p2, void *p3)
#else
static void lifo_put_get_thread_entry(void *p1, void *p2, void *p3)
#endif
{
	uint32_t num_iterations = (uint32_t)(uintptr_t)p1;
	uint32_t options = (uint32_t)(uintptr_t)p2;
	timing_t start;
	timing_t mid;
	timing_t finish;
	uint64_t put_sum = 0ULL;
	uint64_t get_sum = 0ULL;
	uintptr_t *data;

	if ((options & K_USER) == 0) {
		for (uint32_t i = 0; i < num_iterations; i++) {
			skadi_benchmark_prepare_sample(&lifo_samples_1[i]);
			skadi_benchmark_prepare_sample(&lifo_samples_2[i]);
			start = timing_timestamp_get();

#ifdef SKADI_SUBSYSTEM
			skadi_lifo_put(&lifo, lifo_data);
#else
			k_lifo_put(&lifo, lifo_data);
#endif

			mid = timing_timestamp_get();

#ifdef SKADI_SUBSYSTEM
			data = skadi_lifo_get(&lifo, K_NO_WAIT);
#else
			data = k_lifo_get(&lifo, K_NO_WAIT);
#endif

			finish = timing_timestamp_get();

			put_sum += timing_cycles_get(&start, &mid);
			get_sum += timing_cycles_get(&mid, &finish);
			skadi_benchmark_add_sample(&lifo_samples_1[i], timing_cycles_to_ns(timing_cycles_get(&start, &mid)));
			skadi_benchmark_add_sample(&lifo_samples_2[i], timing_cycles_to_ns(timing_cycles_get(&mid, &finish)));
		}

		timestamp.cycles = put_sum;
#ifdef SKADI_SUBSYSTEM
		skadi_sem_take(&pause_sem, K_FOREVER);
#else
		k_sem_take(&pause_sem, K_FOREVER);
#endif

		timestamp.cycles = get_sum;
#ifdef SKADI_SUBSYSTEM
		skadi_sem_take(&pause_sem, K_FOREVER);
#else
		k_sem_take(&pause_sem, K_FOREVER);
#endif

		put_sum = 0ULL;
		get_sum = 0ULL;
	}

	for (uint32_t i = 0; i < num_iterations; i++) {
		skadi_benchmark_prepare_sample(&lifo_samples_3[i]);
		skadi_benchmark_prepare_sample(&lifo_samples_4[i]);
		start = timing_timestamp_get();
#ifdef SKADI_SUBSYSTEM
		skadi_lifo_alloc_put(&lifo, lifo_data);
#else
		k_lifo_alloc_put(&lifo, lifo_data);
#endif

		mid = timing_timestamp_get();

#ifdef SKADI_SUBSYSTEM
		data = skadi_lifo_get(&lifo, K_NO_WAIT);
#else
		data = k_lifo_get(&lifo, K_NO_WAIT);
#endif

		finish = timing_timestamp_get();

		put_sum += timing_cycles_get(&start, &mid);
		get_sum += timing_cycles_get(&mid, &finish);
		skadi_benchmark_add_sample(&lifo_samples_3[i], timing_cycles_to_ns(timing_cycles_get(&start, &mid)));
		skadi_benchmark_add_sample(&lifo_samples_4[i], timing_cycles_to_ns(timing_cycles_get(&mid, &finish)));
	}

	timestamp.cycles = put_sum;
#ifdef SKADI_SUBSYSTEM
	skadi_sem_take(&pause_sem, K_FOREVER);
#else
	k_sem_take(&pause_sem, K_FOREVER);
#endif


	timestamp.cycles = get_sum;
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(lifo_put_get_thread_entry)
#endif

int lifo_ops(uint32_t num_iterations, uint32_t options)
{
	int      priority;
	uint64_t cycles;
	char     tag[50];
	char     description[120];

#ifdef SKADI_SUBSYSTEM
	struct skadi_thread_create_params params;

	skadi_lifo_init(&lifo);

	priority = skadi_thread_priority_get(skadi_current_get());
#else
	priority = k_thread_priority_get(k_current_get());
#endif

	timing_start();

#ifdef SKADI_SUBSYSTEM
	params.new_thread = &start_thread;
	params.stack = start_stack;
	params.stack_size = K_THREAD_STACK_SIZEOF(start_stack);
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(lifo_put_get_thread_entry);

	params.p1 = (void *)(uintptr_t)num_iterations;
	params.p2 = (void *)(uintptr_t)options;
	params.p3 = NULL;
	params.prio = priority - 1;
	params.options = options;
	params.delay = K_FOREVER;

	skadi_thread_create(&params);
#else
	k_thread_create(&start_thread, start_stack,
			K_THREAD_STACK_SIZEOF(start_stack),
			lifo_put_get_thread_entry,
			(void *)(uintptr_t)num_iterations,
			(void *)(uintptr_t)options, NULL,
			priority - 1, options, K_FOREVER);
#endif

	k_thread_access_grant(&start_thread, &pause_sem, &lifo);

#ifdef SKADI_SUBSYSTEM
	skadi_thread_start(&start_thread);
#else
	k_thread_start(&start_thread);
#endif

	if ((options & K_USER) == 0) {
		snprintf(tag, sizeof(tag),
			 "lifo.put.immediate.%s",
			 options & K_USER ? "user" : "kernel");
		snprintf(description, sizeof(description),
			 "%-40s - Add data to LIFO (no ctx switch)", tag);

		cycles = timestamp.cycles;
		cycles -= timestamp_overhead_adjustment(options, options);
		PRINT_STATS_AVG(description, (uint32_t)cycles,
				num_iterations, false, "");
		skadi_benchmark_evaluate_samples(lifo_samples_1, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);
#ifdef SKADI_SUBSYSTEM
		skadi_sem_give(&pause_sem);
#else
		k_sem_give(&pause_sem);
#endif

		snprintf(tag, sizeof(tag),
			 "lifo.get.immediate.%s",
			 options & K_USER ? "user" : "kernel");
		snprintf(description, sizeof(description),
			 "%-40s - Get data from LIFO (no ctx switch)", tag);
		cycles = timestamp.cycles;
		cycles -= timestamp_overhead_adjustment(options, options);
		PRINT_STATS_AVG(description, (uint32_t)cycles,
				num_iterations, false, "");
		skadi_benchmark_evaluate_samples(lifo_samples_2, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);
#ifdef SKADI_SUBSYSTEM
		skadi_sem_give(&pause_sem);
#else
		k_sem_give(&pause_sem);
#endif
	}

	snprintf(tag, sizeof(tag),
		 "lifo.put.alloc.immediate.%s",
		 options & K_USER ? "user" : "kernel");
	snprintf(description, sizeof(description),
		 "%-40s - Allocate to add data to LIFO (no ctx switch)", tag);

	cycles = timestamp.cycles;
	PRINT_STATS_AVG(description, (uint32_t)cycles,
			num_iterations, false, "");
	skadi_benchmark_evaluate_samples(lifo_samples_3, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);
#ifdef SKADI_SUBSYSTEM
	skadi_sem_give(&pause_sem);
#else
	k_sem_give(&pause_sem);
#endif

	snprintf(tag, sizeof(tag),
		 "lifo.get.free.immediate.%s",
		 options & K_USER ? "user" : "kernel");
	snprintf(description, sizeof(description),
		 "%-40s - Free when getting data from LIFO (no ctx switch)", tag);
	cycles = timestamp.cycles;
	PRINT_STATS_AVG(description, (uint32_t)cycles,
			num_iterations, false, "");
	skadi_benchmark_evaluate_samples(lifo_samples_4, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

#ifdef SKADI_SUBSYSTEM
	skadi_thread_join(&start_thread, K_FOREVER);
	skadi_thread_cleanup(&start_thread);
#else
	k_thread_join(&start_thread, K_FOREVER);
#endif

	timing_stop();

	return 0;
}

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, lifo_alt_thread_entry, void *p1, void *p2, void *p3)
#else
static void alt_thread_entry(void *p1, void *p2, void *p3)
#endif
{
	uint32_t num_iterations = (uint32_t)(uintptr_t)p1;
	uint32_t options = (uint32_t)(uintptr_t)p2;
	timing_t  start;
	timing_t  mid;
	timing_t  finish;
	uint64_t  sum[4] = {0ULL, 0ULL, 0ULL, 0ULL};
	uintptr_t *data;
	uint32_t  i;

	if ((options & K_USER) == 0) {

		/* Used with k_lifo_put() */

		for (i = 0; i < num_iterations; i++) {
			skadi_benchmark_prepare_sample(&lifo_samples_5[i]);
			skadi_benchmark_prepare_sample(&lifo_samples_6[i]);

			/* 1. Block waiting for data on LIFO */

			start = timing_timestamp_get();

#ifdef SKADI_SUBSYSTEM
			data = skadi_lifo_get(&lifo, K_FOREVER);
#else
			data = k_lifo_get(&lifo, K_FOREVER);
#endif

			/* 3. Data obtained. */

			finish = timing_timestamp_get();

			mid = timestamp.sample;

			sum[0] += timing_cycles_get(&start, &mid);
			sum[1] += timing_cycles_get(&mid, &finish);
			skadi_benchmark_add_sample(&lifo_samples_5[i], timing_cycles_to_ns(timing_cycles_get(&start, &mid)));
			skadi_benchmark_add_sample(&lifo_samples_6[i], timing_cycles_to_ns(timing_cycles_get(&mid, &finish)));
		}
	}

	/* Used with k_lifo_alloc_put() */

	for (i = 0; i < num_iterations; i++) {
		skadi_benchmark_prepare_sample(&lifo_samples_7[i]);
		skadi_benchmark_prepare_sample(&lifo_samples_8[i]);

		/* 4. Block waiting for data on LIFO */

		start = timing_timestamp_get();

#ifdef SKADI_SUBSYSTEM
		data = skadi_lifo_get(&lifo, K_FOREVER);
#else
		data = k_lifo_get(&lifo, K_FOREVER);
#endif

		/* 6. Data obtained */

		finish = timing_timestamp_get();

		mid = timestamp.sample;

		sum[2] += timing_cycles_get(&start, &mid);
		sum[3] += timing_cycles_get(&mid, &finish);
		skadi_benchmark_add_sample(&lifo_samples_7[i], timing_cycles_to_ns(timing_cycles_get(&start, &mid)));
		skadi_benchmark_add_sample(&lifo_samples_8[i], timing_cycles_to_ns(timing_cycles_get(&mid, &finish)));
	}

	if ((options & K_USER) == 0) {
		timestamp.cycles = sum[0];
#ifdef SKADI_SUBSYSTEM
		skadi_sem_take(&pause_sem, K_FOREVER);
#else
		k_sem_take(&pause_sem, K_FOREVER);
#endif
		timestamp.cycles = sum[1];
#ifdef SKADI_SUBSYSTEM
		skadi_sem_take(&pause_sem, K_FOREVER);
#else
		k_sem_take(&pause_sem, K_FOREVER);
#endif
	}

	timestamp.cycles = sum[2];
#ifdef SKADI_SUBSYSTEM
	skadi_sem_take(&pause_sem, K_FOREVER);
#else
	k_sem_take(&pause_sem, K_FOREVER);
#endif
	timestamp.cycles = sum[3];
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(lifo_alt_thread_entry)
#endif

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, lifo_start_thread_entry, void *p1, void *p2, void *p3)
#else
static void start_thread_entry(void *p1, void *p2, void *p3)
#endif
{
	uint32_t num_iterations = (uint32_t)(uintptr_t)p1;
	uint32_t options = (uint32_t)(uintptr_t)p2;
	uint32_t i;

#ifdef SKADI_SUBSYSTEM
	skadi_thread_start(&alt_thread);
#else
	k_thread_start(&alt_thread);
#endif

	if ((options & K_USER) == 0) {
		for (i = 0; i < num_iterations; i++) {

			/* 2. Add data thereby waking alt thread */

			timestamp.sample = timing_timestamp_get();

#ifdef SKADI_SUBSYSTEM
			skadi_lifo_put(&lifo, lifo_data);
#else
			k_lifo_put(&lifo, lifo_data);
#endif

		}
	}

	for (i = 0; i < num_iterations; i++) {

		/* 5. Add data thereby waking alt thread */

		timestamp.sample = timing_timestamp_get();
#ifdef SKADI_SUBSYSTEM
		skadi_lifo_alloc_put(&lifo, lifo_data);
#else
		k_lifo_alloc_put(&lifo, lifo_data);
#endif

	}

#ifdef SKADI_SUBSYSTEM
	skadi_thread_join(&alt_thread, K_FOREVER);
	skadi_thread_cleanup(&alt_thread);
#else
	k_thread_join(&alt_thread, K_FOREVER);
#endif
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(lifo_start_thread_entry)
#endif

int lifo_blocking_ops(uint32_t num_iterations, uint32_t start_options,
		      uint32_t alt_options)
{
	int      priority;
	uint64_t cycles;
	char     tag[50];
	char     description[120];

#ifdef SKADI_SUBSYSTEM
	struct skadi_thread_create_params params;

	priority = skadi_thread_priority_get(skadi_current_get());
#else
	priority = k_thread_priority_get(k_current_get());
#endif

	timing_start();

#ifdef SKADI_SUBSYSTEM
	params.new_thread = &start_thread;
	params.stack = start_stack;
	params.stack_size = K_THREAD_STACK_SIZEOF(start_stack);
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(lifo_start_thread_entry);

	params.p1 = (void *)(uintptr_t)num_iterations;
	params.p2 = (void *)(uintptr_t)(start_options | alt_options);
	params.p3 = NULL;
	params.prio = priority - 1;
	params.options = start_options;
	params.delay = K_FOREVER;

	skadi_thread_create(&params);

	params.new_thread = &alt_thread;
	params.stack = alt_stack;
	params.stack_size = K_THREAD_STACK_SIZEOF(alt_stack);
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(lifo_alt_thread_entry);

	params.prio = priority - 2;
	params.options = alt_options;

	skadi_thread_create(&params);
#else
	k_thread_create(&start_thread, start_stack,
			K_THREAD_STACK_SIZEOF(start_stack),
			start_thread_entry,
			(void *)(uintptr_t)num_iterations,
			(void *)(uintptr_t)(start_options | alt_options), NULL,
			priority - 1, start_options, K_FOREVER);

	k_thread_create(&alt_thread, alt_stack,
			K_THREAD_STACK_SIZEOF(alt_stack),
			alt_thread_entry,
			(void *)(uintptr_t)num_iterations,
			(void *)(uintptr_t)(start_options | alt_options), NULL,
			priority - 2, alt_options, K_FOREVER);
#endif

	k_thread_access_grant(&start_thread, &alt_thread, &pause_sem, &lifo);
	k_thread_access_grant(&alt_thread, &pause_sem, &lifo);

#ifdef SKADI_SUBSYSTEM
	skadi_thread_start(&start_thread);
#else
	k_thread_start(&start_thread);
#endif

	if (((start_options | alt_options) & K_USER) == 0) {
		snprintf(tag, sizeof(tag),
			 "lifo.get.blocking.%s_to_%s",
			 alt_options & K_USER ? "u" : "k",
			 start_options & K_USER ? "u" : "k");
		snprintf(description, sizeof(description),
			 "%-40s - Get data from LIFO (w/ ctx switch)", tag);

		cycles = timestamp.cycles;
		PRINT_STATS_AVG(description, (uint32_t)cycles,
				num_iterations, false, "");
		skadi_benchmark_evaluate_samples(lifo_samples_5, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

#ifdef SKADI_SUBSYSTEM
		skadi_sem_give(&pause_sem);
#else
		k_sem_give(&pause_sem);
#endif

		snprintf(tag, sizeof(tag),
			 "lifo.put.wake+ctx.%s_to_%s",
			 start_options & K_USER ? "u" : "k",
			 alt_options & K_USER ? "u" : "k");
		snprintf(description, sizeof(description),
			 "%-40s - Add data to LIFO (w/ ctx switch)", tag);
		cycles = timestamp.cycles;
		PRINT_STATS_AVG(description, (uint32_t)cycles,
				num_iterations, false, "");
		skadi_benchmark_evaluate_samples(lifo_samples_6, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);
#ifdef SKADI_SUBSYSTEM
		skadi_sem_give(&pause_sem);
#else
		k_sem_give(&pause_sem);
#endif
	}

	snprintf(tag, sizeof(tag),
		 "lifo.get.free.blocking.%s_to_%s",
		 alt_options & K_USER ? "u" : "k",
		 start_options & K_USER ? "u" : "k");
	snprintf(description, sizeof(description),
		 "%-40s - Free when getting data from LIFO (w/ ctx switch)", tag);

	cycles = timestamp.cycles;
	PRINT_STATS_AVG(description, (uint32_t)cycles,
			num_iterations, false, "");
	skadi_benchmark_evaluate_samples(lifo_samples_7, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);
#ifdef SKADI_SUBSYSTEM
	skadi_sem_give(&pause_sem);
#else
	k_sem_give(&pause_sem);
#endif

	snprintf(tag, sizeof(tag),
		 "lifo.put.alloc.wake+ctx.%s_to_%s",
		 start_options & K_USER ? "u" : "k",
		 alt_options & K_USER ? "u" : "k");
	snprintf(description, sizeof(description),
		 "%-40s - Allocate to add data to LIFO (w/ ctx siwtch)", tag);
	cycles = timestamp.cycles;
	PRINT_STATS_AVG(description, (uint32_t)cycles,
			num_iterations, false, "");
	skadi_benchmark_evaluate_samples(lifo_samples_8, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

#ifdef SKADI_SUBSYSTEM
	skadi_thread_join(&start_thread, K_FOREVER);
	skadi_thread_cleanup(&start_thread);
#else
	k_thread_join(&start_thread, K_FOREVER);
#endif

	timing_stop();

	return 0;
}
