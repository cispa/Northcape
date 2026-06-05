/*
 * Copyright (c) 2012-2015 Wind River Systems, Inc.
 * Copyright (c) 2023 Intel Corporation.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/*
 * @file measure time for sema lock and release
 *
 * This file contains the test that measures semaphore give and take time
 * in the kernel. There is no contention on the semaphore being tested.
 */

#include <zephyr/kernel.h>
#include <zephyr/timing/timing.h>
#include "utils.h"
#include "timing_sc.h"

static struct k_sem  sem;

static struct skadi_benchmark_state sema_samples_1[CONFIG_BENCHMARK_NUM_ITERATIONS],
			   sema_samples_2[CONFIG_BENCHMARK_NUM_ITERATIONS],
			   sema_samples_3[CONFIG_BENCHMARK_NUM_ITERATIONS],
			   sema_samples_4[CONFIG_BENCHMARK_NUM_ITERATIONS];

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, sema_alt_thread_entry, void *p1, void *p2, void *p3)
#else
static void alt_thread_entry(void *p1, void *p2, void *p3)
#endif
{
	uint32_t   num_iterations = (uint32_t)(uintptr_t)p1;
	timing_t   mid;

	ARG_UNUSED(p2);
	ARG_UNUSED(p3);

	for (uint32_t i = 0; i < num_iterations; i++) {

		/*
		 * 2. Give the semaphore, thereby forcing a context switch back
		 * to <start_thread>.
		 */

		mid = timing_timestamp_get();
#ifdef SKADI_SUBSYSTEM
		skadi_sem_give(&sem);
#else
		k_sem_give(&sem);
#endif

		/* 5. Share the <mid> timestamp. */

		timestamp.sample = mid;

		/* 6. Give <sem> so <start_thread> resumes execution */

#ifdef SKADI_SUBSYSTEM
		skadi_sem_give(&sem);
#else
		k_sem_give(&sem);
#endif
	}
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(sema_alt_thread_entry)
#endif

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, sema_start_thread_entry, void *p1, void *p2, void *p3)
#else
static void start_thread_entry(void *p1, void *p2, void *p3)
#endif
{
	uint32_t   num_iterations = (uint32_t)(uintptr_t)p1;
	timing_t   start;
	timing_t   mid;
	timing_t   finish;
	uint32_t   i;
	uint64_t   take_sum = 0ull;
	uint64_t   give_sum = 0ull;

	ARG_UNUSED(p2);
	ARG_UNUSED(p3);

#ifdef SKADI_SUBSYSTEM
	skadi_thread_start(&alt_thread);
#else
	k_thread_start(&alt_thread);
#endif

	for (i = 0; i < num_iterations; i++) {
		skadi_benchmark_prepare_sample(&sema_samples_1[i]);
		skadi_benchmark_prepare_sample(&sema_samples_2[i]);

		/*
		 * 1. Block on taking the semaphore and force a context switch
		 * to <alt_thread>.
		 */

		start = timing_timestamp_get();
#ifdef SKADI_SUBSYSTEM
		skadi_sem_take(&sem, K_FOREVER);
#else
		k_sem_take(&sem, K_FOREVER);
#endif

		/* 3. Get the <finish> timestamp. */

		finish = timing_timestamp_get();

		/*
		 * 4. Let <alt_thread> run so it can share its <mid>
		 * timestamp.
		 */
#ifdef SKADI_SUBSYSTEM
		skadi_sem_take(&sem, K_FOREVER);
#else
		k_sem_take(&sem, K_FOREVER);
#endif

		/* 7. Retrieve the <mid> timestamp */

		mid = timestamp.sample;

		take_sum += timing_cycles_get(&start, &mid);
		give_sum += timing_cycles_get(&mid, &finish);
		skadi_benchmark_add_sample(&sema_samples_1[i], timing_cycles_to_ns(timing_cycles_get(&start, &mid)));
		skadi_benchmark_add_sample(&sema_samples_2[i], timing_cycles_to_ns(timing_cycles_get(&mid, &finish)));
	}

#ifdef SKADI_SUBSYSTEM
	skadi_thread_join(&alt_thread, K_FOREVER);
	skadi_thread_cleanup(&alt_thread);
#else
	k_thread_join(&alt_thread, K_FOREVER);
#endif

	/* Share the totals with the main thread */

	timestamp.cycles = take_sum;

#ifdef SKADI_SUBSYSTEM
	skadi_sem_take(&sem, K_FOREVER);
#else
	k_sem_take(&sem, K_FOREVER);
#endif

	timestamp.cycles = give_sum;
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(sema_start_thread_entry)
#endif

void sema_context_switch(uint32_t num_iterations,
			 uint32_t start_options, uint32_t alt_options)
{
	uint64_t  cycles;
	char tag[50];
	char description[120];
	int  priority;

	timing_start();


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
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(sema_start_thread_entry);

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
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(sema_alt_thread_entry);

	params.prio = priority - 1;
	params.options = alt_options;

	skadi_thread_create(&params);
#else

	k_thread_create(&start_thread, start_stack,
			K_THREAD_STACK_SIZEOF(start_stack),
			start_thread_entry,
			(void *)(uintptr_t)num_iterations, NULL, NULL,
			priority - 2, start_options, K_FOREVER);

	k_thread_create(&alt_thread, alt_stack,
			K_THREAD_STACK_SIZEOF(alt_stack),
			alt_thread_entry,
			(void *)(uintptr_t)num_iterations, NULL, NULL,
			priority - 1, alt_options, K_FOREVER);
#endif

	k_thread_access_grant(&start_thread, &sem, &alt_thread);

	k_thread_access_grant(&alt_thread, &sem);

	/* Start the test threads */

#ifdef SKADI_SUBSYSTEM
	skadi_thread_start(&start_thread);
#else
	k_thread_start(&start_thread);
#endif

	/* Retrieve the number of cycles spent taking the semaphore */

	cycles = timestamp.cycles;
	cycles -= timestamp_overhead_adjustment(start_options, alt_options);

	snprintf(tag, sizeof(tag),
		 "semaphore.take.blocking.%c_to_%c",
		 ((start_options & K_USER) == K_USER) ? 'u' : 'k',
		 ((alt_options & K_USER) == K_USER) ? 'u' : 'k');
	snprintf(description, sizeof(description),
		 "%-40s - Take a semaphore (context switch)", tag);
	PRINT_STATS_AVG(description, (uint32_t)cycles,
			num_iterations, false, "");
	skadi_benchmark_evaluate_samples(sema_samples_1, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

	/* Unblock <start_thread> */
#ifdef SKADI_SUBSYSTEM
	skadi_sem_give(&sem);
#else
	k_sem_give(&sem);
#endif

	/* Retrieve the number of cycles spent taking the semaphore */

	cycles = timestamp.cycles;
	cycles -= timestamp_overhead_adjustment(start_options, alt_options);

	snprintf(tag, sizeof(tag),
		 "semaphore.give.wake+ctx.%c_to_%c",
		 ((alt_options & K_USER) == K_USER) ? 'u' : 'k',
		 ((start_options & K_USER) == K_USER) ? 'u' : 'k');
	snprintf(description, sizeof(description),
		 "%-40s - Give a semaphore (context switch)", tag);
	PRINT_STATS_AVG(description, (uint32_t)cycles,
			num_iterations, false, "");
	skadi_benchmark_evaluate_samples(sema_samples_2, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

#ifdef SKADI_SUBSYSTEM
	skadi_thread_join(&start_thread, K_FOREVER);
	skadi_thread_cleanup(&start_thread);
#else
	k_thread_join(&start_thread, K_FOREVER);
#endif

	timing_stop();

	return;
}

/**
 * This is the entry point for the test that performs uncontested operations
 * on the semaphore. It gives the semaphore many times, takes the semaphore
 * many times and then sends the results back to the main thread.
 */
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, immediate_give_take, void *p1, void *p2, void *p3)
#else
static void immediate_give_take(void *p1, void *p2, void *p3)
#endif
{
	uint32_t   num_iterations = (uint32_t)(uintptr_t)p1;
	timing_t   start, start_inner;
	timing_t   finish, finish_inner;
	uint64_t   give_cycles;
	uint64_t   take_cycles;

	ARG_UNUSED(p2);
	ARG_UNUSED(p3);

	/* 1. Give a semaphore. No threads are waiting on it */

	start = timing_timestamp_get();

	for (uint32_t i = 0; i < num_iterations; i++) {
		skadi_benchmark_prepare_sample(&sema_samples_3[i]);
		start_inner = timing_timestamp_get();
#ifdef SKADI_SUBSYSTEM
		skadi_sem_give(&sem);
#else
		k_sem_give(&sem);
#endif
		finish_inner = timing_timestamp_get();
		skadi_benchmark_add_sample(&sema_samples_3[i], timing_cycles_to_ns(timing_cycles_get(&start_inner, &finish_inner)));
	}

	finish = timing_timestamp_get();
	give_cycles = timing_cycles_get(&start, &finish);

	/* 2. Take a semaphore--no contention */

	start = timing_timestamp_get();

	for (uint32_t i = 0; i < num_iterations; i++) {
		skadi_benchmark_prepare_sample(&sema_samples_4[i]);
		start_inner = timing_timestamp_get();
#ifdef SKADI_SUBSYSTEM
		skadi_sem_take(&sem, K_NO_WAIT);
#else
		k_sem_take(&sem, K_NO_WAIT);
#endif
		finish_inner = timing_timestamp_get();
		skadi_benchmark_add_sample(&sema_samples_4[i], timing_cycles_to_ns(timing_cycles_get(&start_inner, &finish_inner)));
	}

	finish = timing_timestamp_get();
	take_cycles = timing_cycles_get(&start, &finish);

	/* 3. Post the number of cycles spent giving the semaphore */

	timestamp.cycles = give_cycles;

	/* 4. Wait for the main thread to retrieve the data */

#ifdef SKADI_SUBSYSTEM
	skadi_sem_take(&sem, K_FOREVER);
#else
	k_sem_take(&sem, K_FOREVER);
#endif

	/* 7. Post the number of cycles spent taking the semaphore */

	timestamp.cycles = take_cycles;
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(immediate_give_take)
#endif


/**
 *
 * @brief The function tests semaphore test/signal time
 *
 * The routine performs unlock the quite amount of semaphores and then
 * acquires them in order to measure the necessary time.
 *
 * @return 0 on success
 */
int sema_test_signal(uint32_t num_iterations, uint32_t options)
{
	uint64_t cycles;
	int priority;
	char tag[50];
	char description[120];

	timing_start();
#ifdef SKADI_SUBSYSTEM
	skadi_sem_init(&sem, 0, num_iterations);
#else
	k_sem_init(&sem, 0, num_iterations);
#endif

#ifdef SKADI_SUBSYSTEM
	struct skadi_thread_create_params params;

	priority = skadi_thread_priority_get(skadi_current_get());
#else
	priority = k_thread_priority_get(k_current_get());
#endif

#ifdef SKADI_SUBSYSTEM
	params.new_thread = &start_thread;
	params.stack = start_stack;
	params.stack_size = K_THREAD_STACK_SIZEOF(start_stack);
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(immediate_give_take);

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
			immediate_give_take,
			(void *)(uintptr_t)num_iterations, NULL, NULL,
			priority - 1, options, K_FOREVER);
#endif
	k_thread_access_grant(&start_thread, &sem);
#ifdef SKADI_SUBSYSTEM
	skadi_thread_start(&start_thread);
#else
	k_thread_start(&start_thread);
#endif

	/* 5. Retrieve the number of cycles spent giving the semaphore */

	cycles = timestamp.cycles;

	snprintf(tag, sizeof(tag),
		 "semaphore.give.immediate.%s",
		 (options & K_USER) == K_USER ? "user" : "kernel");
	snprintf(description, sizeof(description),
		 "%-40s - Give a semaphore (no waiters)", tag);

	PRINT_STATS_AVG(description, (uint32_t)cycles,
			num_iterations, false, "");
	skadi_benchmark_evaluate_samples(sema_samples_3, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

	/* 6. Unblock <start_thread> */
#ifdef SKADI_SUBSYSTEM
	skadi_sem_give(&sem);
#else
	k_sem_give(&sem);
#endif

	/* 8. Wait for <start_thread> to finish */
#ifdef SKADI_SUBSYSTEM
	skadi_thread_join(&start_thread, K_FOREVER);
	skadi_thread_cleanup(&start_thread);
#else
	k_thread_join(&start_thread, K_FOREVER);
#endif

	/* 9. Retrieve the number of cycles spent taking the semaphore */

	cycles = timestamp.cycles;

	snprintf(tag, sizeof(tag),
		 "semaphore.take.immediate.%s",
		 (options & K_USER) == K_USER ? "user" : "kernel");
	snprintf(description, sizeof(description),
		 "%-40s - Take a semaphore (no blocking)", tag);

	PRINT_STATS_AVG(description, (uint32_t)cycles,
			num_iterations, false, "");
	skadi_benchmark_evaluate_samples(sema_samples_4, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

	timing_stop();

	return 0;
}
