/*
 * Copyright (c) 2012-2014 Wind River Systems, Inc.
 * Copyright (c) 2017, 2023 Intel Corporation.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file
 *
 * @brief Measure time from ISR back to interrupted thread
 *
 * This file covers three interrupt to threads scenarios:
 *  1. ISR returning to the interrupted kernel thread
 *  2. ISR returning to a different (kernel) thread
 *  3. ISR returning to a different (user) thread
 *
 * In all three scenarios, the source of the ISR is a software generated
 * interrupt originating from a kernel thread. Ideally, these tests would
 * also cover the scenarios where the interrupted thread is a user thread.
 * However, some implementations of the irq_offload() routine lock interrupts,
 * which is not allowed in userspace.
 */

#include <zephyr/kernel.h>
#include "utils.h"
#include "timing_sc.h"

#include <zephyr/irq_offload.h>

#ifdef SKADI_SUBSYSTEM
#include <zephyr/skadi/skadi_irq_offload.h>
#endif

static K_SEM_DEFINE(isr_sem, 0, 1);

static struct skadi_benchmark_state int_thread_samples_1[CONFIG_BENCHMARK_NUM_ITERATIONS], int_thread_samples_2[CONFIG_BENCHMARK_NUM_ITERATIONS];

/**
 * @brief Test ISR used to measure time to return to thread
 *
 * The interrupt handler gets the first timestamp used in the test.
 * It then copies the timetsamp into a message queue and returns.
 */
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, test_isr, const void *arg)
#else
static void test_isr(const void *arg)
#endif
{
	struct k_sem *sem = (struct k_sem *)arg;

	if (arg != NULL) {
#ifdef SKADI_SUBSYSTEM
		skadi_sem_give(sem);
#else
		k_sem_give(sem);
#endif
	}

	timestamp.sample = timing_timestamp_get();
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(test_isr)
#endif

/**
 * @brief Measure time to return from interrupt
 *
 * This function is used to measure the time it takes to return from an
 * interrupt.
 */
static void int_to_interrupted_thread(uint32_t num_iterations, uint64_t *sum)
{
	timing_t  start;
	timing_t  finish;

	*sum = 0ull;

	for (uint32_t i = 0; i < num_iterations; i++) {
		skadi_benchmark_prepare_sample(&int_thread_samples_1[i]);
#ifdef SKADI_SUBSYSTEM
		skadi_irq_offload(SKADI_SUBSYSTEM_FUNCTION_POINTER(test_isr), NULL);
#else
		irq_offload(test_isr, NULL);
#endif
		finish = timing_timestamp_get();
		start = timestamp.sample;

		*sum += timing_cycles_get(&start, &finish);
		skadi_benchmark_add_sample(&int_thread_samples_1[i], timing_cycles_to_ns(timing_cycles_get(&start, &finish)));
	}
}

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, int_start_thread_entry, void *p1, void *p2, void *p3)
#else
static void start_thread_entry(void *p1, void *p2, void *p3)
#endif
{
	uint32_t      num_iterations = (uint32_t)(uintptr_t)p1;
	struct k_sem *sem = p2;

	ARG_UNUSED(p3);

	uint64_t  sum = 0ull;
	timing_t  start;
	timing_t  finish;

	/* Ensure that <isr_sem> is unavailable */
#ifdef SKADI_SUBSYSTEM
	(void) skadi_sem_take(sem, K_NO_WAIT);
	skadi_thread_start(&alt_thread);
#else
	(void) k_sem_take(sem, K_NO_WAIT);
	k_thread_start(&alt_thread);
#endif

	for (uint32_t i = 0; i < num_iterations; i++) {
		skadi_benchmark_prepare_sample(&int_thread_samples_2[i]);

		/* 1. Wait on an unavailable semaphore */
#ifdef SKADI_SUBSYSTEM
		skadi_sem_take(sem, K_FOREVER);
#else
		k_sem_take(sem, K_FOREVER);
#endif

		/* 3. Obtain the start and finish timestamps */

		finish = timing_timestamp_get();
		start = timestamp.sample;

		sum += timing_cycles_get(&start, &finish);
		skadi_benchmark_add_sample(&int_thread_samples_2[i], timing_cycles_to_ns(timing_cycles_get(&start, &finish)));
	}

	timestamp.cycles = sum;
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(int_start_thread_entry)
#endif

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, int_alt_thread_entry, void *p1, void *p2, void *p3)
#else
static void alt_thread_entry(void *p1, void *p2, void *p3)
#endif
{
	uint32_t      num_iterations = (uint32_t)(uintptr_t)p1;
	struct k_sem *sem = p2;

	ARG_UNUSED(p3);

	for (uint32_t i = 0; i < num_iterations; i++) {

		/* 2. Trigger the test_isr() to execute */

#ifdef SKADI_SUBSYSTEM
		skadi_irq_offload(SKADI_SUBSYSTEM_FUNCTION_POINTER(test_isr), sem);
#else
		irq_offload(test_isr, sem);
#endif

		/*
		 * ISR expected to have awakened higher priority start_thread
		 * thereby preempting alt_thread.
		 */
	}

#ifdef SKADI_SUBSYSTEM
	skadi_thread_join(&start_thread, K_FOREVER);
	skadi_thread_cleanup(&start_thread);
#else
	k_thread_join(&start_thread, K_FOREVER);
#endif
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(int_alt_thread_entry)
#endif

static void int_to_another_thread(uint32_t num_iterations, uint64_t *sum,
				  uint32_t options)
{
	int  priority;
	*sum = 0ull;


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
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(int_start_thread_entry);

	params.p1 = (void *)(uintptr_t)num_iterations;
	params.p2 = &isr_sem;
	params.p3 = NULL;
	params.prio = priority - 2;
	params.options = options;
	params.delay = K_FOREVER;

	skadi_thread_create(&params);

	params.new_thread = &alt_thread;
	params.stack = alt_stack;
	params.stack_size = K_THREAD_STACK_SIZEOF(alt_stack);
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(int_alt_thread_entry);

	params.prio = priority - 1;
	params.options = 0;

	skadi_thread_create(&params);
#else
	k_thread_create(&start_thread, start_stack,
			K_THREAD_STACK_SIZEOF(start_stack),
			start_thread_entry,
			(void *)(uintptr_t)num_iterations, &isr_sem, NULL,
			priority - 2, options, K_FOREVER);

	k_thread_create(&alt_thread, alt_stack,
			K_THREAD_STACK_SIZEOF(alt_stack),
			alt_thread_entry,
			(void *)(uintptr_t)num_iterations, &isr_sem, NULL,
			priority - 1, 0, K_FOREVER);
#endif

#if CONFIG_USERSPACE
	if (options != 0) {
		k_thread_access_grant(&start_thread, &isr_sem, &alt_thread);
	}
#endif

#ifdef SKADI_SUBSYSTEM
	skadi_thread_start(&start_thread);

	skadi_thread_join(&alt_thread, K_FOREVER);
	skadi_thread_cleanup(&alt_thread);
#else
	k_thread_start(&start_thread);

	k_thread_join(&alt_thread, K_FOREVER);
#endif

	*sum = timestamp.cycles;
}

/**
 *
 * @brief The test main function
 *
 * @return 0 on success
 */
int int_to_thread(uint32_t num_iterations)
{
	uint64_t sum;
	char description[120];

	timing_start();
	TICK_SYNCH();

#ifdef SKADI_SUBSYSTEM
	skadi_sem_init(&isr_sem, 0, 1);
#endif

	int_to_interrupted_thread(num_iterations, &sum);

	sum -= timestamp_overhead_adjustment(0, 0);

	snprintf(description, sizeof(description),
		 "%-40s - Return from ISR to interrupted thread",
		 "isr.resume.interrupted.thread.kernel");
	PRINT_STATS_AVG(description, (uint32_t)sum, num_iterations, false, "");
	skadi_benchmark_evaluate_samples(int_thread_samples_1, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

	/* ************** */

	int_to_another_thread(num_iterations, &sum, 0);

	sum -= timestamp_overhead_adjustment(0, 0);

	snprintf(description, sizeof(description),
		 "%-40s - Return from ISR to another thread",
		 "isr.resume.different.thread.kernel");
	PRINT_STATS_AVG(description, (uint32_t)sum, num_iterations, false, "");
	skadi_benchmark_evaluate_samples(int_thread_samples_2, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);

	/* ************** */

#if CONFIG_USERSPACE
	int_to_another_thread(num_iterations, &sum, K_USER);

	sum -= timestamp_overhead_adjustment(0, K_USER);

	snprintf(description, sizeof(description),
		 "%-40s - Return from ISR to another thread",
		 "isr.resume.different.thread.user");
	PRINT_STATS_AVG(description, (uint32_t)sum, num_iterations, false, "");
	skadi_benchmark_evaluate_samples(int_thread_samples_2, CONFIG_BENCHMARK_NUM_ITERATIONS, 0, description);
#endif

	timing_stop();
	return 0;
}
