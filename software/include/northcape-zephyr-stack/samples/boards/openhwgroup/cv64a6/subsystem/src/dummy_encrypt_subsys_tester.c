/**
 * Provides a subsytem that tests the dummy encrypt subsystem.
 */

#include <stdio.h>

#include <zephyr/logging/log.h>
#include <zephyr/kernel.h>
#include <zephyr/llext/symbol.h>

LOG_MODULE_REGISTER(skadi_dummy_subsystem_consumer, CONFIG_LOG_DEFAULT_LEVEL);

#include <cv64a6.h>

#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_sched.h>
#include <zephyr/skadi/skadi_benchmark.h>
#include <zephyr/timing/timing.h>

#include "dummy_encrypt_subsys.h"

#define DUMMY_SUBSYSTEM_PLAINTEXT 0xdeaddeadbeefbeef

#define DUMMY_SUBSYSTEM_EXPECTED_RETURN ((DUMMY_SUBSYSTEM_PLAINTEXT) ^ (DUMMY_SUBSYSTEM_OTP_KEY))

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint64_t, dummy_subsystem_encrypt, uint64_t plaintext);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint64_t, dummy_subsystem_encrypt_8_args, uint64_t plaintext, long a1, long a2, long a3, long a4, long a5, long a6, long a7);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VALIST(uint64_t, dummy_subsystem_encrypt_valist, SKADI_SUBSYSTEM_REMOVE_PARENTHESIS(plaintext), uint64_t plaintext);

extern uint8_t test_ok;

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void, dummy_subsystem_benchmark);

extern struct skadi_benchmark_state benchmark_durations_half[CONFIG_BENCHMARK_DURATIONS];
static struct skadi_benchmark_state baseline_durations_half[CONFIG_BENCHMARK_DURATIONS], baseline_durations_full[CONFIG_BENCHMARK_DURATIONS];

static size_t baseline_iterator;

struct skadi_benchmark_state benchmark_durations_full[CONFIG_BENCHMARK_DURATIONS];

extern timing_t benchmark_tstart;

void subsystem_call_baseline(void) __attribute__((noinline));
void subsystem_call_baseline(void) {
	timing_t current_time = timing_counter_get();
	/* do NOT optimize this away! */
	__asm__ ("");
	skadi_benchmark_add_sample(&baseline_durations_half[baseline_iterator++], timing_cycles_to_ns(timing_cycles_get(&benchmark_tstart, &current_time)));
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void, skadi_subsystem_test_test_ok, bool val);

static void check_subsystem(void){
	uint64_t ciphertext;
	size_t benchmark_iterator = 0;
	unsigned int key;
	timing_t current_time;

	long perf_ctr_l1_instr_miss;
	long perf_ctr_l1_data_miss;
	long perf_ctr_l2_resolver_miss;
	long perf_ctr_l2_ops_miss;
	long perf_extra_icache_cycles;
	long perf_missunit_stall_cycles;
	long perf_l2_full_wipe_cycles;
	long diff_l1_instr, diff_l1_data, diff_l2_resolver, diff_l2_ops, diff_extra_cycles, diff_missunit_stall_cycles, diff_l2_full_wipe_cycles;

	printf("Printf() of string %s works too!\n", "foo");

	// simple check to make sure that we do not run out of stacks
	for(int i = 0; i < 2 * CONFIG_SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NUM_STACKS; i++){
		
		ciphertext = dummy_subsystem_encrypt(DUMMY_SUBSYSTEM_PLAINTEXT);

		if(ciphertext == DUMMY_SUBSYSTEM_EXPECTED_RETURN){
			LOG_INF("Got expected ciphertext from subsystem!");
		}
		else{
			LOG_ERR("Subsystem error: got ciphertext %"PRIx64" but expected %"PRIx64"!", ciphertext, (uint64_t)DUMMY_SUBSYSTEM_EXPECTED_RETURN);
			
			z_cv64a6_finish_test(1);
		}
		

		ciphertext = dummy_subsystem_encrypt_valist(DUMMY_SUBSYSTEM_PLAINTEXT, (uintptr_t) DUMMY_SUBSYSTEM_VARIADIC_1, (int) DUMMY_SUBSYSTEM_VARIADIC_2, (uint16_t) DUMMY_SUBSYSTEM_VARIADIC_3);

		if(ciphertext == DUMMY_SUBSYSTEM_EXPECTED_RETURN){
			LOG_INF("Got expected ciphertext from subsystem for valist function!");
		}
		else{
			LOG_ERR("Subsystem error: got ciphertext %"PRIx64" but expected %"PRIx64" for variadic function!", ciphertext, (uint64_t)DUMMY_SUBSYSTEM_EXPECTED_RETURN);
			
			z_cv64a6_finish_test(1);
		}

		ciphertext = dummy_subsystem_encrypt_8_args(DUMMY_SUBSYSTEM_PLAINTEXT, 1, 2, 3, 4, 5, 6, 7);

		if(ciphertext == DUMMY_SUBSYSTEM_EXPECTED_RETURN){
			LOG_INF("Got expected ciphertext from subsystem for 8-arg function!");
		}
		else{
			LOG_ERR("Subsystem error: got ciphertext %"PRIx64" but expected %"PRIx64" for 8-arg function!", ciphertext, (uint64_t)DUMMY_SUBSYSTEM_EXPECTED_RETURN);
			
			z_cv64a6_finish_test(1);
		}
	}

	key = irq_lock();

	perf_ctr_l1_instr_miss = SKADI_PERF_COUNTER_READ_L1_INSTR_MISS();
	perf_ctr_l1_data_miss = SKADI_PERF_COUNTER_READ_L1_DATA_MISS();
	perf_ctr_l2_resolver_miss = SKADI_PERF_COUNTER_READ_L2_RESOLVER_MISS();
	perf_ctr_l2_ops_miss = SKADI_PERF_COUNTER_READ_L2_OPS_MISS();
	perf_extra_icache_cycles = SKADI_PERF_COUNTER_READ_EXTRA_ICACHE_DELAY();
	perf_missunit_stall_cycles = SKADI_PERF_COUNTER_READ_MISSUNIT_STALL();
	perf_l2_full_wipe_cycles = SKADI_PERF_COUNTER_READ_L2_FULL_WIPE();

	for(int i = 0; i < CONFIG_BENCHMARK_DURATIONS; i++){
		skadi_benchmark_prepare_sample(&benchmark_durations_full[benchmark_iterator]);
		skadi_benchmark_prepare_sample(&benchmark_durations_half[benchmark_iterator]);
		benchmark_tstart = timing_counter_get();

		dummy_subsystem_benchmark();

		current_time = timing_counter_get();

		skadi_benchmark_add_sample(&benchmark_durations_full[benchmark_iterator], timing_cycles_to_ns(timing_cycles_get(&benchmark_tstart, &current_time)));

		skadi_benchmark_prepare_sample(&baseline_durations_full[benchmark_iterator]);
		skadi_benchmark_prepare_sample(&baseline_durations_half[benchmark_iterator]);

		benchmark_tstart = timing_counter_get();

		subsystem_call_baseline();

		current_time = timing_counter_get();
		
		skadi_benchmark_add_sample(&baseline_durations_full[benchmark_iterator++], timing_cycles_to_ns(timing_cycles_get(&benchmark_tstart, &current_time)));
	}

	diff_l1_instr = SKADI_PERF_COUNTER_READ_L1_INSTR_MISS() - perf_ctr_l1_instr_miss;
	diff_l1_data = SKADI_PERF_COUNTER_READ_L1_DATA_MISS() - perf_ctr_l1_data_miss;
	diff_l2_resolver = SKADI_PERF_COUNTER_READ_L2_RESOLVER_MISS() - perf_ctr_l2_resolver_miss;
	diff_l2_ops = SKADI_PERF_COUNTER_READ_L2_OPS_MISS() - perf_ctr_l2_ops_miss;
	diff_extra_cycles = SKADI_PERF_COUNTER_READ_EXTRA_ICACHE_DELAY() - perf_extra_icache_cycles;
	diff_missunit_stall_cycles = SKADI_PERF_COUNTER_READ_MISSUNIT_STALL() - perf_missunit_stall_cycles;
	diff_l2_full_wipe_cycles = SKADI_PERF_COUNTER_READ_L2_FULL_WIPE() - perf_l2_full_wipe_cycles;

	irq_unlock(key);

	printf("Northcape statistics: L1 instruction misses %ld L1 data misses %ld L2 resolver misses %ld L2 ops misses %ld extra icache cycles %ld  missunit stall cycles %ld diff ops stall cycles %ld\n", diff_l1_instr, diff_l1_data, diff_l2_resolver, diff_l2_ops, diff_extra_cycles, diff_missunit_stall_cycles, diff_l2_full_wipe_cycles);

	/* ignore the first one, which will always have to contend with cache misses and be a lot slower */
	skadi_benchmark_evaluate_samples(benchmark_durations_half, CONFIG_BENCHMARK_DURATIONS-1, 0, "Subsystem call benchmark results half-way");
	skadi_benchmark_evaluate_samples(benchmark_durations_full, CONFIG_BENCHMARK_DURATIONS-1, 0, "Subsystem call benchmark results full");
	skadi_benchmark_evaluate_samples(baseline_durations_half, CONFIG_BENCHMARK_DURATIONS-1, 0, "Function call benchmark results half-way");
	skadi_benchmark_evaluate_samples(baseline_durations_full, CONFIG_BENCHMARK_DURATIONS-1, 0, "Function call benchmark results full");

	skadi_subsystem_test_test_ok(true);
}

static bool early_init_fn_called;

/* some subsystems like POSIX run init functions at a very early init level */
static int dummy_super_early_init_fn(void){
	early_init_fn_called = true;
	LOG_INF("PRE_KERNEL_1 init function called!");
	
	return 0;
}
SYS_INIT(dummy_super_early_init_fn, PRE_KERNEL_1, 0);

static int dummy_subsystem_encrypt_init(void){
	SKADI_INSTALL_TIME_INTERRUPT_HOOK;

	if(!early_init_fn_called){
		LOG_ERR("Early init function was skipped!");
		z_cv64a6_finish_test(1);
	}

    // imported calls should be available immediately
    check_subsystem();

	return 0;
}

SYS_INIT(dummy_subsystem_encrypt_init, APPLICATION, 0);
