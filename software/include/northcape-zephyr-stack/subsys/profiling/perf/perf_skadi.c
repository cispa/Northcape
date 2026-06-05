/*
 *  Copyright (c) 2023 KNS Group LLC (YADRO)
 *  Copyright (c) 2020 Yonatan Goldschmidt <yon.goldschmidt@gmail.com>
 *
 *  SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/kernel.h>
#include <zephyr/init.h>
#include <zephyr/arch/cpu.h>
#include <zephyr/shell/shell.h>
#include <zephyr/shell/shell_uart.h>
#include <zephyr/logging/log.h>
#include <stdio.h>
#include <stdlib.h>

#include <zephyr/skadi/skadi_timer.h>
#include <zephyr/skadi/skadi_work.h>


LOG_MODULE_REGISTER(skadi_perf, CONFIG_SKADI_LOG_LEVEL);

size_t arch_perf_current_stack_trace(uintptr_t *buf, size_t size);

struct perf_data_t {
	struct k_timer timer;

	struct k_work_delayable dwork;
	size_t failed_traces;
	size_t idx;
	uintptr_t buf[CONFIG_PROFILING_PERF_BUFFER_SIZE];
	bool buf_full;
};



static struct perf_data_t perf_data = {};

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, perf_tracer, struct k_timer *timer)
{
	struct perf_data_t *perf_data_ptr =
		(struct perf_data_t *)skadi_timer_user_data_get(timer);

	size_t trace_length = 0;

	if (++perf_data_ptr->idx < CONFIG_PROFILING_PERF_BUFFER_SIZE) {
		trace_length = arch_perf_current_stack_trace(
					perf_data_ptr->buf + perf_data_ptr->idx,
					CONFIG_PROFILING_PERF_BUFFER_SIZE - perf_data_ptr->idx);
	}

	if (trace_length != 0) {
		perf_data_ptr->buf[perf_data_ptr->idx - 1] = trace_length;
		perf_data_ptr->idx += trace_length;
	} else {
		--perf_data_ptr->idx;
		perf_data_ptr->failed_traces++;
		perf_data_ptr->buf_full = true;
		skadi_work_reschedule(&perf_data_ptr->dwork, K_NO_WAIT);
	}
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(perf_tracer)

static inline void skadi_perf_print(const struct perf_data_t *perf_data_ptr){
	LOG_INF("%zu Traces lost!", perf_data_ptr->failed_traces);
	printk("--- SKADI PERF START ---\n");
	for (size_t i = 0; i < perf_data_ptr->idx; i++) {
		printk("%016lx\n", perf_data_ptr->buf[i]);
	}
	printk("--- SKADI PERF END ---\n");
}


static inline void skadi_perf_cancel(struct perf_data_t *perf_data_ptr){
	skadi_timer_stop(&perf_data_ptr->timer);
	if (perf_data_ptr->buf_full) {
		LOG_ERR("Perf buf overflow!");
	} else {
	}
	LOG_INF("Perf done!");
	skadi_perf_print(perf_data_ptr);
	perf_data_ptr->buf_full = false;
	perf_data_ptr->failed_traces = 0;
	perf_data_ptr->idx = 0;
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, perf_dwork_handler, struct k_work *work)
{
	struct k_work_delayable *dwork = k_work_delayable_from_work(work);
	struct perf_data_t *perf_data_ptr = dwork->work.user_data;

	skadi_perf_cancel(perf_data_ptr);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(perf_dwork_handler)

static inline bool skadi_perf_init_function(void){
	skadi_timer_init(&perf_data.timer, SKADI_SUBSYSTEM_FUNCTION_POINTER(perf_tracer), NULL);
	skadi_work_init_delayable(&perf_data.dwork, SKADI_SUBSYSTEM_FUNCTION_POINTER(perf_dwork_handler));
	perf_data.dwork.work.user_data = &perf_data;

	return true;
}
SKADI_SUBSYSTEM_INIT_FUNCTIONS(skadi_perf_init_function);

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_perf_start, int frequency_hz){
	k_timeout_t period = K_NSEC(1000000000 / frequency_hz);
	if (skadi_work_delayable_is_pending(&perf_data.dwork)) {
		LOG_WRN("Perf is running");
		return -EINPROGRESS;
	}

	if (perf_data.buf_full) {
		LOG_WRN("Perf buffer is full");
		return -ENOBUFS;
	}

	skadi_timer_user_data_set(&perf_data.timer, &perf_data);
	skadi_timer_start(&perf_data.timer, K_NO_WAIT, period);
	
	/* needs to be stopped manually using __skadi_perf_cancel */

	LOG_INF("Enabled perf");

	return 0;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_perf_start)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, __skadi_perf_cancel)
	skadi_perf_cancel(&perf_data);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_perf_cancel)

