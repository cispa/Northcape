/*
 * Copyright (c) 2024 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/*
 * @file measure time for various condition variable operations
 * 1. Block waiting for a condition variable
 * 2. Signal a condition variable (with context switch)
 */

#include <zephyr/kernel.h>
#include <zephyr/timing/timing.h>
#include "utils.h"
#include "timing_sc.h"

#ifdef SKADI_SUBSYSTEM
#include <zephyr/skadi/skadi_condvar.h>
#include <zephyr/skadi/skadi_mutex.h>
#include <zephyr/skadi/skadi_sched.h>
#endif

static K_CONDVAR_DEFINE(condvar);
static K_MUTEX_DEFINE(mutex);

static struct skadi_benchmark_state condvar_samples_1[CONFIG_BENCHMARK_NUM_ITERATIONS], condvar_samples_2[CONFIG_BENCHMARK_NUM_ITERATIONS];

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, condvar_start_thread_entry, void *p1, void *p2, void *p3)
#else
static void condvar_start_thread_entry(void *p1, void *p2, void *p3)
#endif
{
	uint32_t  num_iterations = (uint32_t)(uintptr_t)p1;
	uint32_t  i;
	timing_t  start;
	timing_t  finish;
	uint64_t  sum[2] = {0ull, 0ull};

#ifdef SKADI_SUBSYSTEM
	skadi_mutex_lock(&mutex, K_FOREVER);

	skadi_thread_start(&alt_thread);
#else
	k_mutex_lock(&mutex, K_FOREVER);

	k_thread_start(&alt_thread);
#endif

	for (i = 0; i < num_iterations; i++) {
		/* 1. Get the first timestamp and block on condvar */

		skadi_benchmark_prepare_sample(&condvar_samples_1[i]);
		skadi_benchmark_prepare_sample(&condvar_samples_2[i]);

		start = timing_timestamp_get();
#ifdef SKADI_SUBSYSTEM
		skadi_condvar_wait(&condvar, &mutex, K_FOREVER);
#else
		k_condvar_wait(&condvar, &mutex, K_FOREVER);
#endif

		/* 3. Get the final timstamp */

		finish = timing_timestamp_get();

		sum[0] += timing_cycles_get(&start, &timestamp.sample);
		sum[1] += timing_cycles_get(&timestamp.sample, &finish);

		skadi_benchmark_add_sample(&condvar_samples_1[i], timing_cycles_to_ns(timing_cycles_get(&start, &timestamp.sample)));
		skadi_benchmark_add_sample(&condvar_samples_2[i], timing_cycles_to_ns(timing_cycles_get(&timestamp.sample, &finish)));
	}

	/* Wait for alt_thread to finish */

#ifdef SKADI_SUBSYSTEM
	skadi_thread_join(&alt_thread, K_FOREVER);
	skadi_thread_cleanup(&alt_thread);
#else
	k_thread_join(&alt_thread, K_FOREVER);
#endif

	timestamp.cycles = sum[0];
#ifdef SKADI_SUBSYSTEM
	skadi_sem_take(&pause_sem, K_FOREVER);
#else
	k_sem_take(&pause_sem, K_FOREVER);
#endif

	timestamp.cycles = sum[1];
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(condvar_start_thread_entry)
#endif

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, condvar_alt_thread_entry, void *p1, void *p2, void *p3)
#else
static void condvar_alt_thread_entry(void *p1, void *p2, void *p3)
#endif
{
	uint32_t  num_iterations = (uint32_t)(uintptr_t)p1;
	uint32_t  i;

	for (i = 0; i < num_iterations; i++) {

		/* 2. Get midpoint timestamp and signal the condvar */

		timestamp.sample = timing_timestamp_get();
#ifdef SKADI_SUBSYSTEM
		skadi_condvar_signal(&condvar);
#else
		k_condvar_signal(&condvar);
#endif
	}
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(condvar_alt_thread_entry)
#endif


int condvar_blocking_ops(uint32_t num_iterations, uint32_t start_options,
			 uint32_t alt_options)
{
	int       priority;
	char      tag[50];
	char      description[120];
	uint64_t  cycles;

#ifdef SKADI_SUBSYSTEM
	struct skadi_thread_create_params params;

	skadi_mutex_init(&mutex);
	skadi_condvar_init(&condvar);
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
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(condvar_start_thread_entry);

	params.p1 = (void *)(uintptr_t)num_iterations;
	params.p2 = NULL;
	params.p3 = NULL;
	params.prio = priority - 2;
	params.options = start_options;
	params.delay = K_FOREVER;

	skadi_thread_create(&params);

	params.new_thread = &alt_thread;
	params.stack = alt_stack;
	params.stack_size = K_THREAD_STACK_SIZEOF(alt_stack);
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(condvar_alt_thread_entry);

	params.p1 = (void *)(uintptr_t)num_iterations;
	params.p2 = NULL;
	params.p3 = NULL;
	params.prio = priority - 1;
	params.options = alt_options;
	params.delay = K_FOREVER;

	skadi_thread_create(&params);
#else
	k_thread_create(&start_thread, start_stack,
			K_THREAD_STACK_SIZEOF(start_stack),
			condvar_start_thread_entry,
			(void *)(uintptr_t)num_iterations,
			NULL, NULL,
			priority - 2, start_options, K_FOREVER);

	k_thread_create(&alt_thread, alt_stack,
			K_THREAD_STACK_SIZEOF(alt_stack),
			condvar_alt_thread_entry,
			(void *)(uintptr_t)num_iterations,
			NULL, NULL,
			priority - 1, alt_options, K_FOREVER);
#endif

	k_thread_access_grant(&start_thread, &alt_thread,
			      &condvar, &mutex, &pause_sem);
	k_thread_access_grant(&alt_thread, &condvar);

	/* Start test thread */
#ifdef SKADI_SUBSYSTEM
	skadi_thread_start(&start_thread);
#else
	k_thread_start(&start_thread);
#endif

	/* Stats gathered. Display them. */

	snprintf(tag, sizeof(tag), "condvar.wait.blocking.%c_to_%c",
		 (start_options & K_USER) ? 'u' : 'k',
		 (alt_options & K_USER) ? 'u' : 'k');
	snprintf(description, sizeof(description),
		 "%-40s - Wait for a condvar (context switch)", tag);

	cycles = timestamp.cycles;
	PRINT_STATS_AVG(description, (uint32_t)cycles,
			num_iterations, false, "");

	
	skadi_benchmark_evaluate_samples(condvar_samples_1, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

#ifdef SKADI_SUBSYSTEM
	skadi_sem_give(&pause_sem);
#else
	k_sem_give(&pause_sem);
#endif

	snprintf(tag, sizeof(tag), "condvar.signal.wake+ctx.%c_to_%c",
		 (alt_options & K_USER) ? 'u' : 'k',
		 (start_options & K_USER) ? 'u' : 'k');
	snprintf(description, sizeof(description),
		 "%-40s - Signal a condvar (context switch)", tag);
	cycles = timestamp.cycles;
	PRINT_STATS_AVG(description, (uint32_t)cycles,
			num_iterations, false, "");
	
	skadi_benchmark_evaluate_samples(condvar_samples_2, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

#ifdef SKADI_SUBSYSTEM
	skadi_thread_join(&start_thread, K_FOREVER);
	skadi_thread_cleanup(&start_thread);
#else
	k_thread_join(&start_thread, K_FOREVER);
#endif

	timing_stop();

	return 0;
}
