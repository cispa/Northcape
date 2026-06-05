#ifndef SKADI_BENCHMARK_H
#define SKADI_BENCHMARK_H

#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <zephyr/sys/__assert.h>
#include <math.h>
#include <errno.h>

#include <zephyr/arch/riscv/csr.h>

#if defined(SKADI_SUBSYSTEM) || (defined(CONFIG_SKADI_OS) && !defined(CONFIG_SKADI_LOADER))
#include <zephyr/skadi/skadi_subsystem.h>
#endif


/*
 * Represents the measurements taken for one iteration of the Skadi benchmark (time, performance counters, etc.)
 */
struct skadi_benchmark_state {
	int64_t sample;
#if defined(SKADI_SUBSYSTEM) || (defined(CONFIG_SKADI_OS) && !defined(CONFIG_SKADI_LOADER))
	/* Skadi performance counters in hardware */
	long perf_ctr_l1_instr_miss;
	long perf_ctr_l1_data_miss;
	long perf_ctr_l2_resolver_miss;
	long perf_ctr_l2_ops_miss;
	long perf_extra_icache_cycles;
	long perf_missunit_stall_cycles;
	long perf_l2_full_wipe_cycles;
#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS
	long perf_subsystem_calls;
#endif /* CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS */
#endif
};

/* 
 *
 * TODO I have experienced gcc optimize saving/restoring values in floating poing argument registers before/after printf() away.
 * I am not sure if it is allowed to do this.
 * Disabling optimizations for this function fixes this.
 */
static inline void skadi_benchmark_evaluate_samples(const struct skadi_benchmark_state *benchmark, size_t samples_num, size_t errors, const char *name)  __attribute__ ((optimize(0)));

#define SKADI_BENCHMARK_DISCARD_FIRST 5

#ifdef CONFIG_PROFILING_PERF
static inline void skadi_benchmark_evaluate_samples_real(const int64_t *samples, size_t samples_num, size_t errors, const char *name_token, const char *category_token){
	ARG_UNUSED(benchmark);
	ARG_UNUSED(samples_num);
	ARG_UNUSED(errors);
	ARG_UNUSED(name_token);
	ARG_UNUSED(category_token);
}
static inline void skadi_benchmark_evaluate_samples(const struct skadi_benchmark_state *benchmark, size_t samples_num, size_t errors, const char *name){
	ARG_UNUSED(benchmark);
	ARG_UNUSED(samples_num);
	ARG_UNUSED(errors);
	ARG_UNUSED(name);
}
#else
static inline void skadi_benchmark_evaluate_samples_real(const int64_t *samples, size_t samples_num, size_t errors, const char *name_token, const char *category){
	int64_t min_diff, max_diff, sum_diff = 0;
	double mean_diff, variance_diff=0, stddev_diff;
	const char *category_token;
	
	int less_than_0 = 0;

#if defined(SKADI_SUBSYSTEM) || (defined(CONFIG_SKADI_OS) && !defined(CONFIG_SKADI_LOADER))
	category_token = skadi_cap_ops_derive_arg_ro(category, strlen(category)+1);
#else
	category_token = category;
#endif

	// always discard first samples (warmup / caches still cold)
	if(samples_num > SKADI_BENCHMARK_DISCARD_FIRST){
		samples_num -= SKADI_BENCHMARK_DISCARD_FIRST;
		samples += SKADI_BENCHMARK_DISCARD_FIRST;
	}

	min_diff = samples[0];
	max_diff = samples[0];

	for(size_t num_sync = 0; num_sync < samples_num; num_sync ++){
		// invalid sample
		if(samples[num_sync] < 0){
			less_than_0++;
			continue;
		}
		if(min_diff > samples[num_sync]){
			min_diff = samples[num_sync];
		}
		if(max_diff < samples[num_sync]){
			max_diff = samples[num_sync];
		}
		sum_diff += samples[num_sync];
	}

	mean_diff = (double)sum_diff / (samples_num - less_than_0);
	for(size_t num_sync = 0; num_sync < samples_num; num_sync ++){
		if(samples[num_sync] >= 0){
			variance_diff += (mean_diff - samples[num_sync]) * (mean_diff - samples[num_sync]);
		}
	}

	errors += less_than_0;
	samples_num -= less_than_0;

	variance_diff /= samples_num;

	stddev_diff = sqrt(variance_diff);

	printf("%s (%s) discarded/min/max/avg/stddev ns: %zu/%"PRId64"/%"PRId64"/%f/%f\n", name_token, category_token, errors, min_diff, max_diff,mean_diff, stddev_diff);

#if defined(SKADI_SUBSYSTEM) || (defined(CONFIG_SKADI_OS) && !defined(CONFIG_SKADI_LOADER))
	if(category_token){
		skadi_cap_ops_drop(category_token);
	}
#endif
}


static inline void skadi_benchmark_evaluate_samples(const struct skadi_benchmark_state *benchmark, size_t samples_num, size_t errors, const char *name){
#if defined(SKADI_SUBSYSTEM)
	int64_t *benchmark_buffer = malloc(sizeof(int64_t) * samples_num);
#else
	int64_t benchmark_buffer[sizeof(int64_t) * samples_num];
#endif
	const char *name_token;

#if defined(SKADI_SUBSYSTEM)
	name_token = skadi_cap_ops_derive_arg_ro(name, strlen(name)+1);

	__ASSERT_NO_MSG(name_token);

	if(!benchmark_buffer){
		printf("Error: ENOMEM!\n");
		return;
	}
#else
	name_token = name;
#endif

	printf("======================\n");
	printf("Raw %s:\n", name_token);
	printf("Sample/L1 instr/L1 data/L2 res/L2 ops/extra icache/missunit stall/ops write stall/subsystem calls\n");

	for(int i = 0; i < samples_num; i++){
		long perf_ctr_l1_instr_miss = -1;
		long perf_ctr_l1_data_miss = -1;
		long perf_ctr_l2_resolver_miss = -1;
		long perf_ctr_l2_ops_miss = -1;
		long perf_extra_icache_cycles = -1;
		long perf_missunit_stall_cycles = -1;
		long perf_l2_full_wipe_cycles = -1;
		long perf_subsystem_calls = -1;
#if defined(SKADI_SUBSYSTEM) || (defined(CONFIG_SKADI_OS) && !defined(CONFIG_SKADI_LOADER))
		perf_ctr_l1_instr_miss =  benchmark[i].perf_ctr_l1_instr_miss;
		perf_ctr_l1_data_miss =  benchmark[i].perf_ctr_l1_data_miss;
		perf_ctr_l2_resolver_miss =  benchmark[i].perf_ctr_l2_resolver_miss;
		perf_ctr_l2_ops_miss =  benchmark[i].perf_ctr_l2_ops_miss;
		perf_extra_icache_cycles =  benchmark[i].perf_extra_icache_cycles;
		perf_missunit_stall_cycles =  benchmark[i].perf_missunit_stall_cycles;
		perf_l2_full_wipe_cycles =  benchmark[i].perf_l2_full_wipe_cycles;
#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS
		perf_subsystem_calls =  benchmark[i].perf_subsystem_calls;
#endif /* CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS */
#endif

		benchmark_buffer[i] = benchmark[i].sample;
		printf("%"PRIu64"/%ld/%ld/%ld/%ld/%ld/%ld/%ld/%ld\n",  benchmark[i].sample, perf_ctr_l1_instr_miss, perf_ctr_l1_data_miss, perf_ctr_l2_resolver_miss, perf_ctr_l2_ops_miss, perf_extra_icache_cycles, perf_missunit_stall_cycles, perf_l2_full_wipe_cycles, perf_subsystem_calls);
	}

	skadi_benchmark_evaluate_samples_real(benchmark_buffer, samples_num, errors, name_token, "Samples");

#if defined(SKADI_SUBSYSTEM) || (defined(CONFIG_SKADI_OS) && !defined(CONFIG_SKADI_LOADER))
	for(int i = 0; i < samples_num; i++){
		benchmark_buffer[i] =  benchmark[i].perf_ctr_l1_instr_miss;
	}
	skadi_benchmark_evaluate_samples_real(benchmark_buffer, samples_num, errors, name_token, "NTLB L1 instr misses");

	for(int i = 0; i < samples_num; i++){
		benchmark_buffer[i] =  benchmark[i].perf_ctr_l1_data_miss;
	}
	skadi_benchmark_evaluate_samples_real(benchmark_buffer, samples_num, errors, name_token, "NTLB L1 data misses");

	for(int i = 0; i < samples_num; i++){
		benchmark_buffer[i] =  benchmark[i].perf_ctr_l2_resolver_miss;
	}
	skadi_benchmark_evaluate_samples_real(benchmark_buffer, samples_num, errors, name_token, "NTLB L2 resolver misses");

	for(int i = 0; i < samples_num; i++){
		benchmark_buffer[i] =  benchmark[i].perf_ctr_l2_ops_miss;
	}
	skadi_benchmark_evaluate_samples_real(benchmark_buffer, samples_num, errors, name_token, "NTLB L2 ops misses");

	for(int i = 0; i < samples_num; i++){
		benchmark_buffer[i] =  benchmark[i].perf_extra_icache_cycles;
	}
	skadi_benchmark_evaluate_samples_real(benchmark_buffer, samples_num, errors, name_token, "CPU extra icache cycles");

	for(int i = 0; i < samples_num; i++){
		benchmark_buffer[i] =  benchmark[i].perf_missunit_stall_cycles;
	}
	skadi_benchmark_evaluate_samples_real(benchmark_buffer, samples_num, errors, name_token, "NTLB L2 missunit stall cycles");

	for(int i = 0; i < samples_num; i++){
		benchmark_buffer[i] =  benchmark[i].perf_l2_full_wipe_cycles;
	}
	skadi_benchmark_evaluate_samples_real(benchmark_buffer, samples_num, errors, name_token, "NTLB L2 ops write cycles");
#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS
	for(int i = 0; i < samples_num; i++){
		benchmark_buffer[i] =  benchmark[i].perf_subsystem_calls;
	}
	skadi_benchmark_evaluate_samples_real(benchmark_buffer, samples_num, errors, name_token, "Number of subsystem calls");
#endif /* CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS */
#endif


	printf("======================\n");

#if defined(SKADI_SUBSYSTEM) || (defined(CONFIG_SKADI_OS) && !defined(CONFIG_SKADI_LOADER))
	(void)skadi_cap_ops_drop(name_token);
#endif

#if defined(SKADI_SUBSYSTEM)
	free(benchmark_buffer);
#endif
}
#endif

static inline void skadi_benchmark_prepare_sample(struct skadi_benchmark_state *benchmark){
#if defined(SKADI_SUBSYSTEM) || (defined(CONFIG_SKADI_OS) && !defined(CONFIG_SKADI_LOADER))
	benchmark->perf_ctr_l1_instr_miss = SKADI_PERF_COUNTER_READ_L1_INSTR_MISS();
	benchmark->perf_ctr_l1_data_miss = SKADI_PERF_COUNTER_READ_L1_DATA_MISS();
	benchmark->perf_ctr_l2_resolver_miss = SKADI_PERF_COUNTER_READ_L2_RESOLVER_MISS();
	benchmark->perf_ctr_l2_ops_miss = SKADI_PERF_COUNTER_READ_L2_OPS_MISS();
	benchmark->perf_extra_icache_cycles = SKADI_PERF_COUNTER_READ_EXTRA_ICACHE_DELAY();
	benchmark->perf_missunit_stall_cycles = SKADI_PERF_COUNTER_READ_MISSUNIT_STALL();
	benchmark->perf_l2_full_wipe_cycles = SKADI_PERF_COUNTER_READ_L2_FULL_WIPE();
#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS
	benchmark->perf_subsystem_calls = atomic_get(&skadi_num_subsystem_calls);
#endif /* CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS */
#endif
}

static inline void skadi_benchmark_add_sample(struct skadi_benchmark_state *benchmark, int64_t sample){
#if defined(SKADI_SUBSYSTEM) || (defined(CONFIG_SKADI_OS) && !defined(CONFIG_SKADI_LOADER))
	benchmark->perf_ctr_l1_instr_miss = SKADI_PERF_COUNTER_READ_L1_INSTR_MISS() - benchmark->perf_ctr_l1_instr_miss;
	benchmark->perf_ctr_l1_data_miss = SKADI_PERF_COUNTER_READ_L1_DATA_MISS() - benchmark->perf_ctr_l1_data_miss;
	benchmark->perf_ctr_l2_resolver_miss = SKADI_PERF_COUNTER_READ_L2_RESOLVER_MISS() - benchmark->perf_ctr_l2_resolver_miss;
	benchmark->perf_ctr_l2_ops_miss = SKADI_PERF_COUNTER_READ_L2_OPS_MISS() - benchmark->perf_ctr_l2_ops_miss;
	benchmark->perf_extra_icache_cycles = SKADI_PERF_COUNTER_READ_EXTRA_ICACHE_DELAY() - benchmark->perf_extra_icache_cycles;
	benchmark->perf_missunit_stall_cycles = SKADI_PERF_COUNTER_READ_MISSUNIT_STALL() - benchmark->perf_missunit_stall_cycles;
	benchmark->perf_l2_full_wipe_cycles = SKADI_PERF_COUNTER_READ_L2_FULL_WIPE() - benchmark->perf_l2_full_wipe_cycles;
#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS
	benchmark->perf_subsystem_calls = atomic_get(&skadi_num_subsystem_calls) - benchmark->perf_subsystem_calls;
#endif /* CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS */
#endif
	benchmark->sample = sample;
}

#if defined(CONFIG_PROFILING_PERF) && defined(SKADI_SUBSYSTEM)

	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_perf_start, int frequency_hz);

	#define skadi_perf_start(FREQUENCY_HZ) __skadi_perf_start(FREQUENCY_HZ)

	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_perf_cancel);

	#define skadi_perf_cancel __skadi_perf_cancel

#else
	static inline int skadi_perf_start(int frequency_hz){
		ARG_UNUSED(frequency_hz);
		return -EOPNOTSUPP;
	}

	static inline void skadi_perf_cancel(void){

	}
#endif

#ifdef SKADI_SUBSYSTEM
/* pointer is actually the value - easiest for Skadi loader */
extern void *__skadi_boot_time;
#else
extern uint64_t z_start_time;
#endif

static inline void skadi_evaluate_boot_time(void){
	uint64_t current_time = csr_read(mcycle);
#ifdef SKADI_SUBSYSTEM
	uint64_t start_time = (uint64_t)(uintptr_t)&__skadi_boot_time;
#else
	const uint64_t start_time = z_start_time;
#endif
	uint64_t boot_time = current_time - start_time;
	double boot_time_genesys = boot_time * 20, boot_time_arty = boot_time * 40;

	boot_time_genesys /= 1000000000;
	boot_time_arty /= 1000000000;

	printf("======================\n");
	printf("Boot time: %"PRIu64" cycles (Genesys: %f ns, Arty: %f ns)!\n", boot_time, boot_time_genesys, boot_time_arty);
	printf("======================\n");
}

#endif
