/*
 * Copyright (c) 2024 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/*
 * @file measure time for various k_stack operations
 *
 * This file contains the tests that measures the times for the following
 * k_stack operations from both kernel threads and user threads:
 *  1. Immediately adding a data item to a k_stack
 *  2. Immediately removing a data item from a k_stack
 *  3. Blocking on removing a data item from a k_stack
 *  4. Waking (and context switching to) a thread blocked on a k_stack
 */

#include <zephyr/kernel.h>
#include <zephyr/timing/timing.h>
#include "utils.h"
#include "timing_sc.h"

#ifdef SKADI_SUBSYSTEM
#include <zephyr/skadi/skadi_stack.h>
#endif

#define MAX_ITEMS  16

static BENCH_BMEM stack_data_t stack_array[MAX_ITEMS];

static struct k_stack stack;

static struct skadi_benchmark_state stack_samples_1[CONFIG_BENCHMARK_NUM_ITERATIONS],
			   stack_samples_2[CONFIG_BENCHMARK_NUM_ITERATIONS],
			   stack_samples_3[CONFIG_BENCHMARK_NUM_ITERATIONS],
			   stack_samples_4[CONFIG_BENCHMARK_NUM_ITERATIONS];

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, stack_push_pop_thread_entry, void *p1, void *p2, void *p3)
#else
static void stack_push_pop_thread_entry(void *p1, void *p2, void *p3)
#endif
{
	uint32_t num_iterations = (uint32_t)(uintptr_t)p1;
	timing_t start;
	timing_t mid;
	timing_t finish;
	uint64_t put_sum = 0ULL;
	uint64_t get_sum = 0ULL;
	stack_data_t  data;

	for (uint32_t i = 0; i < num_iterations; i++) {
		skadi_benchmark_prepare_sample(&stack_samples_1[i]);
		skadi_benchmark_prepare_sample(&stack_samples_2[i]);

		start = timing_timestamp_get();

#ifdef SKADI_SUBSYSTEM
		(void) skadi_stack_push(&stack, 1234);
#else
		(void) k_stack_push(&stack, 1234);
#endif

		mid = timing_timestamp_get();

#ifdef SKADI_SUBSYSTEM
		(void) skadi_stack_pop(&stack, &data, K_NO_WAIT);
#else
		(void) k_stack_pop(&stack, &data, K_NO_WAIT);
#endif

		finish = timing_timestamp_get();

		put_sum += timing_cycles_get(&start, &mid);
		get_sum += timing_cycles_get(&mid, &finish);
		skadi_benchmark_add_sample(&stack_samples_1[i], timing_cycles_to_ns(timing_cycles_get(&start, &mid)));
		skadi_benchmark_add_sample(&stack_samples_2[i], timing_cycles_to_ns(timing_cycles_get(&mid, &finish)));
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
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(stack_push_pop_thread_entry)
#endif

int stack_ops(uint32_t num_iterations, uint32_t options)
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
	skadi_stack_init(&stack, stack_array, MAX_ITEMS);
#else
	k_stack_init(&stack, stack_array, MAX_ITEMS);
#endif

#ifdef SKADI_SUBSYSTEM
	params.new_thread = &start_thread;
	params.stack = start_stack;
	params.stack_size = K_THREAD_STACK_SIZEOF(start_stack);
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(stack_push_pop_thread_entry);

	params.p1 = (void *)(uintptr_t)num_iterations;
	params.p2 = NULL;
	params.p3 = NULL;
	params.prio = priority - 1;
	params.options = options;
	params.delay = K_FOREVER;

	skadi_thread_create(&params);
#else
	k_thread_create(&start_thread, start_stack,
			K_THREAD_STACK_SIZEOF(start_stack),
			stack_push_pop_thread_entry,
			(void *)(uintptr_t)num_iterations,
			NULL, NULL,
			priority - 1, options, K_FOREVER);
#endif

	k_thread_access_grant(&start_thread, &pause_sem, &stack);

#ifdef SKADI_SUBSYSTEM
	skadi_thread_start(&start_thread);
#else
	k_thread_start(&start_thread);
#endif

	snprintf(tag, sizeof(tag),
		 "stack.push.immediate.%s",
		 options & K_USER ? "user" : "kernel");
	snprintf(description, sizeof(description),
		 "%-40s - Add data to k_stack (no ctx switch)", tag);

	cycles = timestamp.cycles;
	cycles -= timestamp_overhead_adjustment(options, options);
	PRINT_STATS_AVG(description, (uint32_t)cycles,
			num_iterations, false, "");
	skadi_benchmark_evaluate_samples(stack_samples_1, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

#ifdef SKADI_SUBSYSTEM
	skadi_sem_give(&pause_sem);
#else
	k_sem_give(&pause_sem);
#endif

	snprintf(tag, sizeof(tag),
		 "stack.pop.immediate.%s",
		 options & K_USER ? "user" : "kernel");
	snprintf(description, sizeof(description),
		 "%-40s - Get data from k_stack (no ctx switch)", tag);
	cycles = timestamp.cycles;
	cycles -= timestamp_overhead_adjustment(options, options);
	PRINT_STATS_AVG(description, (uint32_t)cycles,
			num_iterations, false, "");
	skadi_benchmark_evaluate_samples(stack_samples_2, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

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
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, stack_alt_thread_entry, void *p1, void *p2, void *p3)
#else
static void alt_thread_entry(void *p1, void *p2, void *p3)
#endif
{
	uint32_t num_iterations = (uint32_t)(uintptr_t)p1;
	timing_t  start;
	timing_t  mid;
	timing_t  finish;
	uint64_t  sum[2] = {0ULL, 0ULL};
	uint32_t  i;
	stack_data_t data;

	for (i = 0; i < num_iterations; i++) {
		skadi_benchmark_prepare_sample(&stack_samples_3[i]);
		skadi_benchmark_prepare_sample(&stack_samples_4[i]);

		/* 1. Block waiting for data on k_stack */

		start = timing_timestamp_get();

#ifdef SKADI_SUBSYSTEM
		skadi_stack_pop(&stack, &data, K_FOREVER);
#else
		k_stack_pop(&stack, &data, K_FOREVER);
#endif

		/* 3. Data obtained. */

		finish = timing_timestamp_get();

		mid = timestamp.sample;

		sum[0] += timing_cycles_get(&start, &mid);
		sum[1] += timing_cycles_get(&mid, &finish);
		skadi_benchmark_add_sample(&stack_samples_3[i], timing_cycles_to_ns(timing_cycles_get(&start, &mid)));
		skadi_benchmark_add_sample(&stack_samples_4[i], timing_cycles_to_ns(timing_cycles_get(&mid, &finish)));
	}

	timestamp.cycles = sum[0];
#ifdef SKADI_SUBSYSTEM
	skadi_sem_take(&pause_sem, K_FOREVER);
#else
	k_sem_take(&pause_sem, K_FOREVER);
#endif
	timestamp.cycles = sum[1];
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(stack_alt_thread_entry)
#endif


#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, stack_start_thread_entry, void *p1, void *p2, void *p3)
#else
static void start_thread_entry(void *p1, void *p2, void *p3)
#endif
{
	uint32_t num_iterations = (uint32_t)(uintptr_t)p1;
	uint32_t i;

#ifdef SKADI_SUBSYSTEM
	skadi_thread_start(&alt_thread);
#else
	k_thread_start(&alt_thread);
#endif

	for (i = 0; i < num_iterations; i++) {

		/* 2. Add data thereby waking alt thread */

		timestamp.sample = timing_timestamp_get();

#ifdef SKADI_SUBSYSTEM
		skadi_stack_push(&stack, (stack_data_t)123);
#else
		k_stack_push(&stack, (stack_data_t)123);
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
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(stack_start_thread_entry)
#endif

int stack_blocking_ops(uint32_t num_iterations, uint32_t start_options,
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
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(stack_start_thread_entry);
	
	params.p1 = (void *)(uintptr_t)num_iterations;
	params.p2 = NULL;
	params.p3 = NULL;
	params.prio = priority - 1;
	params.options = start_options;
	params.delay = K_FOREVER;
	
	skadi_thread_create(&params);

	params.new_thread = &alt_thread;
	params.stack = alt_stack;
	params.stack_size = K_THREAD_STACK_SIZEOF(alt_stack);
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(stack_alt_thread_entry);

	params.prio = priority - 2;
	params.options = alt_options;

	skadi_thread_create(&params);
#else

	k_thread_create(&start_thread, start_stack,
			K_THREAD_STACK_SIZEOF(start_stack),
			start_thread_entry,
			(void *)(uintptr_t)num_iterations,
			NULL, NULL,
			priority - 1, start_options, K_FOREVER);

	k_thread_create(&alt_thread, alt_stack,
			K_THREAD_STACK_SIZEOF(alt_stack),
			alt_thread_entry,
			(void *)(uintptr_t)num_iterations,
			NULL, NULL,
			priority - 2, alt_options, K_FOREVER);
#endif

	k_thread_access_grant(&start_thread, &alt_thread, &pause_sem, &stack);
	k_thread_access_grant(&alt_thread, &pause_sem, &stack);

#ifdef SKADI_SUBSYSTEM
	skadi_thread_start(&start_thread);
#else
	k_thread_start(&start_thread);
#endif

	snprintf(tag, sizeof(tag),
		 "stack.pop.blocking.%s_to_%s",
		 alt_options & K_USER ? "u" : "k",
		 start_options & K_USER ? "u" : "k");
	snprintf(description, sizeof(description),
		 "%-40s - Get data from k_stack (w/ ctx switch)", tag);

	cycles = timestamp.cycles;
	PRINT_STATS_AVG(description, (uint32_t)cycles,
			num_iterations, false, "");
	skadi_benchmark_evaluate_samples(stack_samples_3, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);
#ifdef SKADI_SUBSYSTEM
	skadi_sem_give(&pause_sem);
#else
	k_sem_give(&pause_sem);
#endif

	snprintf(tag, sizeof(tag),
		 "stack.push.wake+ctx.%s_to_%s",
		 start_options & K_USER ? "u" : "k",
		 alt_options & K_USER ? "u" : "k");
	snprintf(description, sizeof(description),
		 "%-40s - Add data to k_stack (w/ ctx switch)", tag);
	cycles = timestamp.cycles;
	PRINT_STATS_AVG(description, (uint32_t)cycles,
			num_iterations, false, "");
	skadi_benchmark_evaluate_samples(stack_samples_4, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

#ifdef SKADI_SUBSYSTEM
	skadi_thread_join(&start_thread, K_FOREVER);
	skadi_thread_cleanup(&start_thread);
#else
	k_thread_join(&start_thread, K_FOREVER);
#endif

	timing_stop();

	return 0;
}
