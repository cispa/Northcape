/*
 * Copyright (c) 2012-2015 Wind River Systems, Inc.
 * Copyright (c) 2020,2023 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/*
 * @file measure time for mutex lock and unlock
 *
 * This file contains the test that measures mutex lock and unlock times
 * in the kernel. There is no contention on the mutex being tested.
 */

#include <zephyr/kernel.h>
#include <zephyr/timing/timing.h>
#include "utils.h"
#include "timing_sc.h"

#ifdef SKADI_SUBSYSTEM
#include <zephyr/skadi/skadi_mutex.h>
#endif

static K_MUTEX_DEFINE(test_mutex);

static struct skadi_benchmark_state mutex_samples_1[CONFIG_BENCHMARK_NUM_ITERATIONS], mutex_samples_2[CONFIG_BENCHMARK_NUM_ITERATIONS];

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, start_lock_unlock, void *p1, void *p2, void *p3)
#else
static void start_lock_unlock(void *p1, void *p2, void *p3)
#endif
{
	uint32_t  i;
	uint32_t  num_iterations = (uint32_t)(uintptr_t)p1;
	timing_t  start;
	timing_t  finish;
	timing_t  start_inner;
	timing_t  finish_inner;
	uint64_t  lock_cycles;
	uint64_t  unlock_cycles;

	ARG_UNUSED(p2);
	ARG_UNUSED(p3);

	start = timing_timestamp_get();

	/* Recursively lock take the mutex */

	for (i = 0; i < num_iterations; i++) {
		skadi_benchmark_prepare_sample(&mutex_samples_1[i]);
		start_inner = timing_timestamp_get();
#ifdef SKADI_SUBSYSTEM
		skadi_mutex_lock(&test_mutex, K_NO_WAIT);
#else
		k_mutex_lock(&test_mutex, K_NO_WAIT);
#endif
		finish_inner = timing_timestamp_get();
		skadi_benchmark_add_sample(&mutex_samples_1[i], timing_cycles_to_ns(timing_cycles_get(&start_inner, &finish_inner)));
	}

	finish = timing_timestamp_get();

	lock_cycles = timing_cycles_get(&start, &finish);

	start = timing_timestamp_get();

	/* Recursively unlock the mutex */

	for (i = 0; i < num_iterations; i++) {
		skadi_benchmark_prepare_sample(&mutex_samples_2[i]);
		start_inner = timing_timestamp_get();
#ifdef SKADI_SUBSYSTEM
		skadi_mutex_unlock(&test_mutex);
#else
		k_mutex_unlock(&test_mutex);
#endif
		finish_inner = timing_timestamp_get();
		skadi_benchmark_add_sample(&mutex_samples_2[i], timing_cycles_to_ns(timing_cycles_get(&start_inner, &finish_inner)));
	}

	finish = timing_timestamp_get();

	unlock_cycles = timing_cycles_get(&start, &finish);

	timestamp.cycles = lock_cycles;
#ifdef SKADI_SUBSYSTEM
	skadi_sem_take(&pause_sem, K_FOREVER);
#else
	k_sem_take(&pause_sem, K_FOREVER);
#endif

	timestamp.cycles = unlock_cycles;
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(start_lock_unlock)
#endif



/**
 *
 * @brief Test for the multiple mutex lock/unlock time
 *
 * The routine performs multiple mutex locks and then multiple mutex
 * unlocks to measure the necessary time.
 *
 * @return 0 on success
 */
int mutex_lock_unlock(uint32_t num_iterations, uint32_t options)
{
	char tag[50];
	char description[120];
	int  priority;
	uint64_t  cycles;

	timing_start();

#ifdef SKADI_SUBSYSTEM
	struct skadi_thread_create_params params;

	skadi_mutex_init(&test_mutex);
#endif

#ifdef SKADI_SUBSYSTEM
	priority = skadi_thread_priority_get(skadi_current_get());
#else
	priority = k_thread_priority_get(k_current_get());
#endif

timing_start();

#ifdef SKADI_SUBSYSTEM
	params.new_thread = &start_thread;
	params.stack = start_stack;
	params.stack_size = K_THREAD_STACK_SIZEOF(start_stack);
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(start_lock_unlock);

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
			start_lock_unlock,
			(void *)(uintptr_t)num_iterations, NULL, NULL,
			priority - 1, options, K_FOREVER);
#endif

	k_thread_access_grant(&start_thread, &test_mutex, &pause_sem);
#ifdef SKADI_SUBSYSTEM
	skadi_thread_start(&start_thread);
#else
	k_thread_start(&start_thread);
#endif

	cycles = timestamp.cycles;
#ifdef SKADI_SUBSYSTEM
	skadi_sem_give(&pause_sem);
#else
	k_sem_give(&pause_sem);
#endif

	snprintf(tag, sizeof(tag),
		 "mutex.lock.immediate.recursive.%s",
		 (options & K_USER) == K_USER ? "user" : "kernel");
	snprintf(description, sizeof(description),
		 "%-40s - Lock a mutex", tag);
	PRINT_STATS_AVG(description, (uint32_t)cycles, num_iterations,
			false, "");
	skadi_benchmark_evaluate_samples(mutex_samples_1, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

	cycles = timestamp.cycles;

	snprintf(tag, sizeof(tag),
		 "mutex.unlock.immediate.recursive.%s",
		 (options & K_USER) == K_USER ? "user" : "kernel");
	snprintf(description, sizeof(description),
		 "%-40s - Unlock a mutex", tag);
	PRINT_STATS_AVG(description, (uint32_t)cycles, num_iterations,
			false, "");
	skadi_benchmark_evaluate_samples(mutex_samples_2, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

	timing_stop();
	return 0;
}
