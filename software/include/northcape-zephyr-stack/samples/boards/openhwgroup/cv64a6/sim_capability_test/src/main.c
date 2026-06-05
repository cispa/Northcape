/*
 * 
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include <cv64a6.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>

#include <zephyr/arch/cache.h>
#include <zephyr/sys/barrier.h>

#include <zephyr/skadi/skadi_ariane_genesysii.h>
#include <zephyr/skadi/skadi_allocator.h>
#include <zephyr/skadi/skadi_init_alloc.h>
#include <zephyr/skadi/skadi_ops_driver.h>

#include <zephyr/random/random.h>

#include <zephyr/llext/llext.h>

#include <zephyr/logging/log.h>


#include <zephyr/drivers/timer/pulp_apb_timer.h>

#include <zephyr/timing/timing.h>

#include <zephyr/skadi/skadi_benchmark.h>

#include <zephyr/skadi/skadi_subsystem.h>

LOG_MODULE_REGISTER(skadi_capability_test, CONFIG_LOG_DEFAULT_LEVEL);

#define CAPABILITY_TEST_PATTERN_LENGTH_BYTES 64
// offset for derive
#define CAPABILITY_TEST_PATTERN_OFFSET_BYTES 32

static uint8_t *compute_test_pattern_start_root_cap(){
	uint8_t * ret = (uint8_t*) (SKADI_ARIANE_RESERVED_BASE_BYTES - CAPABILITY_TEST_PATTERN_LENGTH_BYTES);

	LOG_DBG("Test pattern start: %p\n",ret);

	return ret;
}

static void prepare_test_pattern(){
	uint8_t *test_pattern = compute_test_pattern_start_root_cap();

	LOG_INF("Step 1: Fill end-of-DRAM with a test pattern!\n");

	for(size_t i = 0; i < CAPABILITY_TEST_PATTERN_LENGTH_BYTES; i++){
		test_pattern[i] = (uint8_t)i;
	}

	LOG_INF("Step 1 success!\n");
}

static uint8_t* create_cap_test_pattern(void){
	void *test_pattern_ptr;
	bool success;
	skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

	test_pattern_ptr = 0;
	
	LOG_INF("Step 2: Create direct capability for test pattern!\n");
	// deliberately uncached such that we can a) test if cacheable works and b) do a simple test where the cache is bypassed
	success = skadi_cap_ops_create(SKADI_ROOT_CAP_TOKEN, restriction, 1, CAPABILITY_TEST_PATTERN_LENGTH_BYTES, SKADI_ALL_PERMISSIONS, &test_pattern_ptr);

	if(success && test_pattern_ptr){
		LOG_INF("Step 2 success - created test pattern capability %p!\n",test_pattern_ptr);
	}
	else{
		LOG_ERR("Step 2 error!\n");
		z_cv64a6_finish_test(1);
	}

	return (uint8_t*) test_pattern_ptr;
}

static uint8_t* derive_cap_test_pattern(const uint8_t *direct_cap){
	void *test_pattern_ptr;
	bool success;
	skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

	test_pattern_ptr = 0;
	
	LOG_INF("Step 5: Derive indirect capability for test pattern starting at %u!\n",CAPABILITY_TEST_PATTERN_OFFSET_BYTES);
	// uncached so we can test cache management
	success = skadi_cap_ops_derive(direct_cap, restriction, CAPABILITY_TEST_PATTERN_LENGTH_BYTES-CAPABILITY_TEST_PATTERN_OFFSET_BYTES, CAPABILITY_TEST_PATTERN_OFFSET_BYTES, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_EXECUTE,  &test_pattern_ptr);

	if(success){
		LOG_INF("Step 5 success - derived test pattern capability %p!\n",test_pattern_ptr);
	}
	else{
		LOG_ERR("Step 5 error!\n");
		z_cv64a6_finish_test(1);
	}

	return (uint8_t*) test_pattern_ptr;
}

static void check_cap_test_pattern_before_overwrite(const uint8_t *test_pattern_cap){

	LOG_INF("Step 3: Do check reads for test pattern!\n");

	for(size_t i = 0; i < CAPABILITY_TEST_PATTERN_LENGTH_BYTES; i++){
		if(test_pattern_cap[i] != (uint8_t) i){
			LOG_ERR("Step 3 error - byte offset %zu expected %"PRIx8" real %"PRIx8"!\n",i,(uint8_t)i,test_pattern_cap[i]);
			z_cv64a6_finish_test(1);

		}
	}

	LOG_INF("Step 3 complete!\n");
}

// starts the PATTERN at the offset (always at beginning of capability)
static void overwrite_test_cap_pattern_offset(uint8_t *test_pattern_cap, unsigned int step_num, size_t length, size_t offset){

	LOG_INF("Step %u: Overwrite test pattern!\n",step_num);

	for(size_t i = 0; i < length; i++){
		test_pattern_cap[i] = (uint8_t) (UINT8_MAX - i - offset);
	}

	LOG_INF("Step %u complete!\n",step_num);
}

static void overwrite_test_cap_pattern(uint8_t *test_pattern_cap, unsigned int step_num, size_t length){

	overwrite_test_cap_pattern_offset(test_pattern_cap, step_num, length, 0);
}

static void check_cap_test_pattern_after_overwrite(const uint8_t *test_pattern_cap, unsigned int step_num, size_t offset, size_t length){

	LOG_INF("Step %u: Do check reads for test pattern after overwrite!\n",step_num);

	for(size_t i = 0; i < length; i++){
		if(test_pattern_cap[i] != (uint8_t) (UINT8_MAX - (i+offset))){
			LOG_ERR("Step %u error - byte offset %zu expected %"PRIx8" real %"PRIx8"!\n",step_num,i,(uint8_t)(UINT8_MAX - (i+offset)),test_pattern_cap[i]);
			z_cv64a6_finish_test(1);
		}
	}

	LOG_INF("Step %u complete!\n",step_num);
}

static void check_cap_test_pattern_after_revoke(const uint8_t *test_pattern_cap, unsigned int step_num, size_t offset, size_t length){

	LOG_INF("Step %u: Do check reads for zeros after revoke!\n",step_num);

	for(size_t i = 0; i < length; i++){
		if(test_pattern_cap[i] != 0){
			LOG_ERR("Step %u error - byte offset %zu expected %"PRIx8" real %"PRIx8"!\n",step_num,i,0,test_pattern_cap[i]);
			z_cv64a6_finish_test(1);
		}
	}

	LOG_INF("Step %u complete!\n",step_num);
}

static uint8_t *allocate_capability(uint32_t size){
	/* deliberately not IRQ accessible */
	return (uint8_t *) skadi_allocator_alloc(size, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS);
}

static uint8_t *allocate_capability_init(uint32_t size){
	/* deliberately not IRQ accessible */
	return (uint8_t *) skadi_init_alloc_allocate(size, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, true);
}

#define TEST_STACK_ARRAY_SIZE_BYTES 16
static void test_on_stack_byte_array(int *step_num){
	uint8_t *test_array;
	void *test_capabilities[TEST_STACK_ARRAY_SIZE_BYTES] = {};

	*step_num = *step_num+1;

	LOG_INF("Step %d - allocating capabilities for bytes of on-stack array!", *step_num);

	test_array = skadi_allocator_alloc_rw(TEST_STACK_ARRAY_SIZE_BYTES);

	if(!test_array){
		LOG_ERR("Step %d error - could not allocate test array!", *step_num);
		z_cv64a6_finish_test(1);
	}

	for(int i = 0; i < TEST_STACK_ARRAY_SIZE_BYTES; i++){
		test_capabilities[i] = skadi_cap_ops_derive_arg(&test_array[i], sizeof(test_array[i]));

		if(!test_capabilities[i]){
			LOG_ERR("Step %d error - could not allocate capability %d!", *step_num, i);
			z_cv64a6_finish_test(1);
		}
	}

	*step_num = *step_num+1;

	LOG_INF("Step %d - reading and writing via stack capabilities!", *step_num);

	for(int i = 0; i < TEST_STACK_ARRAY_SIZE_BYTES; i++){
		uint8_t test_in = i+1, test_out = 0;

		test_array[i] = UINT8_MAX - test_in;
		memcpy(&test_out, test_capabilities[i], sizeof(test_out));
		
		// force write to complete
		barrier_dmem_fence_full();

		if(test_out != test_array[i]){
			LOG_ERR("Step %d error - wrote value %"PRIu8" to test array (%p) but read %"PRIu8" back!\n", *step_num, test_array[i], &test_array[i], test_out);
			z_cv64a6_finish_test(1);
		}

		memcpy(test_capabilities[i], &test_in, sizeof(test_in));

		// force write to complete
		barrier_dmem_fence_full();

		if(test_array[i] != test_in){
			LOG_ERR("Step %d error - wrote value %"PRIu8" to capability (%p) but read %"PRIu8" back from array!\n", *step_num, test_in, &test_capabilities[i], test_array[i]);
			z_cv64a6_finish_test(1);
		}
	}

	*step_num = *step_num + 1;

	LOG_INF("Step %d - dropping dummy capabilities!", *step_num);

	for(int i = 0; i < TEST_STACK_ARRAY_SIZE_BYTES; i++){
		skadi_cap_ops_drop(test_capabilities[i]);
	}

	skadi_allocator_free(test_array);

	*step_num = *step_num + 1;
}

extern int sim_capability_test_code_seg(int arg);
extern int sim_capability_test_code_seg_end(void);
extern int sim_capability_test_large_code_seg(int arg);
extern int sim_capability_test_large_code_seg_end(void);
extern int sim_capability_test_xlarge_code_seg(int arg);
extern int sim_capability_test_xlarge_code_seg_end(void);

static int (*sim_capability_test)(int arg);
static int (*sim_capability_test_ld_check)(int arg, long *data_addr);

#define NUMBER_INTERRUPTS 100
#define NUMBER_SUBSYSTEM_CALLS 100
volatile int timer_callback_called = 0;

static void timer_callback(const void *cookie){
	ARG_UNUSED(cookie);
	timer_callback_called++;
}

void *sim_capability_test_dummy_subsystem_callee_token;
void *sim_capability_test_dummy_subsystem_ret_token;

void *sim_capability_test_dummy_subsystem_callee_token_scall;
void *sim_capability_test_dummy_subsystem_ret_token_scall;

void *sim_capability_test_dummy_subsystem_callee_token_scalls;
void *sim_capability_test_dummy_subsystem_ret_token_scalls;

void *sim_capability_test_dummy_subsystem_call_token_invalid;

extern void sim_capability_test_dummy_subsystem_caller(long arg);
extern void sim_capability_test_dummy_subsystem_callee_end(void);
extern void sim_capability_test_dummy_subsystem_callee(long arg);
extern void sim_capability_test_dummy_subsystem_caller_return_trampoline(void);
extern void sim_capability_test_dummy_subsystem_caller_return_trampoline_end(void);

extern void sim_capability_test_dummy_subsystem_caller_scall(void);
extern void sim_capability_test_dummy_subsystem_callee_end_scall(void);
extern void sim_capability_test_dummy_subsystem_callee_scall();
extern void sim_capability_test_dummy_subsystem_caller_return_trampoline_scall(void);
extern void sim_capability_test_dummy_subsystem_caller_return_trampoline_end_scall(void);


extern void sim_capability_test_dummy_subsystem_caller_scalls(void);
extern void sim_capability_test_dummy_subsystem_callee_end_scalls(void);
extern void sim_capability_test_dummy_subsystem_callee_scalls();
extern void sim_capability_test_dummy_subsystem_caller_return_trampoline_scalls(void);
extern void sim_capability_test_dummy_subsystem_caller_return_trampoline_end_scalls(void);

extern bool sim_capability_test_test_failing_subsystem_call(void *addr);

static long perf_ctr_l1_instr_miss;
static long perf_ctr_l1_data_miss;
static long perf_ctr_l2_resolver_miss;
static long perf_ctr_l2_ops_miss;
static long perf_extra_icache_cycles;
static long perf_missunit_stall_cycles;
static long perf_l2_full_wipe_cycles;

static void reset_performance_counters(void){
	perf_ctr_l1_instr_miss = SKADI_PERF_COUNTER_READ_L1_INSTR_MISS();
	perf_ctr_l1_data_miss = SKADI_PERF_COUNTER_READ_L1_DATA_MISS();
	perf_ctr_l2_resolver_miss = SKADI_PERF_COUNTER_READ_L2_RESOLVER_MISS();
	perf_ctr_l2_ops_miss = SKADI_PERF_COUNTER_READ_L2_OPS_MISS();
	perf_extra_icache_cycles = SKADI_PERF_COUNTER_READ_EXTRA_ICACHE_DELAY();
	perf_missunit_stall_cycles = SKADI_PERF_COUNTER_READ_MISSUNIT_STALL();
	perf_l2_full_wipe_cycles = SKADI_PERF_COUNTER_READ_L2_FULL_WIPE();
}

static void read_performance_counters(int step){
	long diff_l1_instr, diff_l1_data, diff_l2_resolver, diff_l2_ops, diff_extra_cycles, diff_missunit_stall_cycles, diff_l2_full_wipe_cycles;

	diff_l1_instr = SKADI_PERF_COUNTER_READ_L1_INSTR_MISS() - perf_ctr_l1_instr_miss;
	diff_l1_data = SKADI_PERF_COUNTER_READ_L1_DATA_MISS() - perf_ctr_l1_data_miss;
	diff_l2_resolver = SKADI_PERF_COUNTER_READ_L2_RESOLVER_MISS() - perf_ctr_l2_resolver_miss;
	diff_l2_ops = SKADI_PERF_COUNTER_READ_L2_OPS_MISS() - perf_ctr_l2_ops_miss;
	diff_extra_cycles = SKADI_PERF_COUNTER_READ_EXTRA_ICACHE_DELAY() - perf_extra_icache_cycles;
	diff_missunit_stall_cycles = SKADI_PERF_COUNTER_READ_MISSUNIT_STALL() - perf_missunit_stall_cycles;
	diff_l2_full_wipe_cycles = SKADI_PERF_COUNTER_READ_L2_FULL_WIPE() - perf_l2_full_wipe_cycles;

	LOG_INF("Step %d - L1 instruction misses %ld L1 data misses %ld L2 resolver misses %ld L2 ops misses %ld extra icache cycles %ld missunit stall cycles %ld ops write stall cycles %ld", step, diff_l1_instr, diff_l1_data, diff_l2_resolver, diff_l2_ops, diff_extra_cycles, diff_missunit_stall_cycles, diff_l2_full_wipe_cycles);
}

typedef void(*cva6_nonstandard_isr_t)(void);
extern void skadi_init_register_exception_handler(cva6_nonstandard_isr_t exception_isr);

extern void _isr_wrapper(void);
extern void _expect_exception(void);
extern void _invalid_subsystem_call_target(void);
extern void _invalid_subsystem_call_target_end(void);

extern bool sim_capability_test_test_callee_zero(void);

#define MICRO_BENCHMARK_REPETITIONS 100

static struct skadi_benchmark_state
		create_benchmarks[MICRO_BENCHMARK_REPETITIONS], 
		derive_benchmarks[MICRO_BENCHMARK_REPETITIONS],
		drop_benchmarks[MICRO_BENCHMARK_REPETITIONS],
		unlock_benchmarks[MICRO_BENCHMARK_REPETITIONS],
		merge_benchmarks[MICRO_BENCHMARK_REPETITIONS],
		clone_benchmarks[MICRO_BENCHMARK_REPETITIONS],
		revoke_benchmarks[MICRO_BENCHMARK_REPETITIONS],
		lock_benchmarks[MICRO_BENCHMARK_REPETITIONS],
		inspect_benchmarks[MICRO_BENCHMARK_REPETITIONS],
		restrict_benchmarks[MICRO_BENCHMARK_REPETITIONS],
		subsys_call_benchmarks_half[MICRO_BENCHMARK_REPETITIONS],
		subsys_call_benchmarks_full[MICRO_BENCHMARK_REPETITIONS],
		subsys_call_instret_half[MICRO_BENCHMARK_REPETITIONS],
		subsys_call_instret_full[MICRO_BENCHMARK_REPETITIONS];

static struct skadi_benchmark_state
		create_benchmarks_cycles[MICRO_BENCHMARK_REPETITIONS], 
		derive_benchmarks_cycles[MICRO_BENCHMARK_REPETITIONS],
		drop_benchmarks_cycles[MICRO_BENCHMARK_REPETITIONS],
		unlock_benchmarks_cycles[MICRO_BENCHMARK_REPETITIONS],
		merge_benchmarks_cycles[MICRO_BENCHMARK_REPETITIONS],
		clone_benchmarks_cycles[MICRO_BENCHMARK_REPETITIONS],
		revoke_benchmarks_cycles[MICRO_BENCHMARK_REPETITIONS],
		lock_benchmarks_cycles[MICRO_BENCHMARK_REPETITIONS],
		inspect_benchmarks_cycles[MICRO_BENCHMARK_REPETITIONS],
		restrict_benchmarks_cycles[MICRO_BENCHMARK_REPETITIONS];
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS_ALLOW_SELF(void*, skadi_subsystem_benchmark, struct skadi_benchmark_state *half_benchmark, struct skadi_benchmark_state *half_benchmark_instret);
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_IMPL_ALLOW_SELF(void*, skadi_subsystem_benchmark, 2, struct skadi_benchmark_state *half_benchmark, struct skadi_benchmark_state *half_benchmark_instret);

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ALLOW_SELF(void*, skadi_subsystem_benchmark_callee, struct skadi_benchmark_state *half_benchmark, struct skadi_benchmark_state *half_benchmark_instret)
	long current_cycles = csr_read(mcycle);
	long current_instret = csr_read(minstret);
	/* we are trying NOT to have the cycle read overhead in here */
	half_benchmark->sample = current_cycles - half_benchmark->sample;
	half_benchmark_instret->sample = current_instret - half_benchmark_instret->sample;
	/* the same thing our reference benchmark does */
	//return k_current_get();
	// TODO remove
	return create_benchmarks_cycles;
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(skadi_subsystem_benchmark_callee)


#ifdef CONFIG_SKADI_TRACK_CYCLES_OPS
	#define READ_OPS_CYCLES(CYCLES) 	atomic_get(CYCLES)
#else
	#define READ_OPS_CYCLES(CYCLES)		0
#endif

/* normally part of init.c or supplied by loader */
uintptr_t *const skadi_sched_current_reloc;

#define ONE_MIB_BYTES 1024*1024

#define ALLOCATOR_REPETITIONS 16
#define RNG_REPETITIONS 16
#define NUMBER_RESTRICT_CALLS 100
int main(void)
{
	int step_num = 0;
	uint8_t *test_pattern_cap, *test_pattern_derived_cap, *allocated_caps[ALLOCATOR_REPETITIONS], *allocated_caps_init[ALLOCATOR_REPETITIONS];
	uint32_t allocated_sizes[ALLOCATOR_REPETITIONS];
	uint64_t rng_last;
	size_t test_code_seg_length = (uintptr_t)sim_capability_test_code_seg_end - (uintptr_t) sim_capability_test_code_seg;
	size_t test_code_seg_large_length = (uintptr_t)sim_capability_test_large_code_seg_end - (uintptr_t) sim_capability_test_large_code_seg;
	size_t test_code_seg_xlarge_length = (uintptr_t)sim_capability_test_xlarge_code_seg_end - (uintptr_t) sim_capability_test_xlarge_code_seg;
	size_t callee_trampoline_length = (uintptr_t) sim_capability_test_dummy_subsystem_callee_end - (uintptr_t) sim_capability_test_dummy_subsystem_callee;
	size_t caller_trampoline_length = (uintptr_t) sim_capability_test_dummy_subsystem_caller_return_trampoline_end - (uintptr_t) sim_capability_test_dummy_subsystem_caller_return_trampoline;
	size_t callee_trampoline_length_scall = (uintptr_t) sim_capability_test_dummy_subsystem_callee_end_scall - (uintptr_t) sim_capability_test_dummy_subsystem_callee_scall;
	size_t caller_trampoline_length_scall = (uintptr_t) sim_capability_test_dummy_subsystem_caller_return_trampoline_end_scall - (uintptr_t) sim_capability_test_dummy_subsystem_caller_return_trampoline_scall;
	size_t callee_trampoline_length_scalls = (uintptr_t) sim_capability_test_dummy_subsystem_callee_end_scalls - (uintptr_t) sim_capability_test_dummy_subsystem_callee_scalls;
	size_t caller_trampoline_length_scalls = (uintptr_t) sim_capability_test_dummy_subsystem_caller_return_trampoline_end_scalls - (uintptr_t) sim_capability_test_dummy_subsystem_caller_return_trampoline_scalls;
	size_t invalid_subsystem_call_target_trampoline_length = (uintptr_t)_invalid_subsystem_call_target_end - (uintptr_t)_invalid_subsystem_call_target;
	size_t callee_trampoline_length_benchmark = (uintptr_t) skadi_subsystem_benchmark_callee_callee_trampoline_end - (uintptr_t) skadi_subsystem_benchmark_callee_callee_trampoline;

	skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
	skadi_restriction_t set_task_id_restriction_1 = SKADI_TASK_ID_RESTRICTION(SKADI_TASK_ID_LOADER + 0x2, SKADI_DEVICE_ID_CPU, SKADI_RESTRICTIONS_SET_TASK_ID);
	skadi_restriction_t set_task_id_restriction_0 = SKADI_TASK_ID_RESTRICTION(SKADI_TASK_ID_LOADER, SKADI_DEVICE_ID_CPU, SKADI_RESTRICTIONS_SET_TASK_ID);
	skadi_restriction_t loader_restriction = SKADI_TASK_ID_BOUND_RESTRICTION(SKADI_TASK_ID_LOADER, SKADI_DEVICE_ID_CPU);
	uint8_t large_buf[100*CONFIG_DCACHE_LINE_SIZE];
	long test_long, *test_long_ptr;
	void *large_cap_for_revoke;

	void* (*benchmark_callee_trampoline)(struct skadi_benchmark_state *half_benchmark, struct skadi_benchmark_state *half_benchmark_instret);

	(void)invalid_subsystem_call_target_trampoline_length;
	(void)caller_trampoline_length_scalls;
	(void)callee_trampoline_length_scalls;
	(void)caller_trampoline_length_scall;
	(void)callee_trampoline_length_scall;

	LOG_INF("Hello World! %s\n", CONFIG_BOARD_TARGET);

	LOG_INF("Testing Dcache flush!");

	// TODO remove
	memset(large_buf, 0xff, sizeof(large_buf));
	arch_dcache_flush_range(large_buf, sizeof(large_buf));

	LOG_INF("At test start - %"PRIu64" capabilities exist in the system!", skadi_cap_ops_get_capability_count());

	LOG_INF("Testing IRQs!");

	for(int i = 0; i < NUMBER_INTERRUPTS; i++){
		irq_offload(timer_callback, NULL);
		LOG_INF("IRQ %d!", i+1);
	}

	LOG_INF("Saw %d interrupts!", timer_callback_called);

	__ASSERT(timer_callback_called == NUMBER_INTERRUPTS, "Interrupt offload should be synchronous!");
	prepare_test_pattern();

	test_pattern_cap = create_cap_test_pattern();

	check_cap_test_pattern_before_overwrite(test_pattern_cap);

	step_num = 3;

	overwrite_test_cap_pattern(test_pattern_cap, step_num, CAPABILITY_TEST_PATTERN_LENGTH_BYTES);

	step_num++;

	check_cap_test_pattern_after_overwrite(test_pattern_cap, step_num, 0, CAPABILITY_TEST_PATTERN_LENGTH_BYTES);

	test_pattern_derived_cap = derive_cap_test_pattern(test_pattern_cap);

	step_num += 2;

	arch_dcache_flush_range(test_pattern_cap, CAPABILITY_TEST_PATTERN_LENGTH_BYTES);
	
	// checking via derived capability - need to start with the appropriate offset into the pattern
	check_cap_test_pattern_after_overwrite(test_pattern_derived_cap, step_num, CAPABILITY_TEST_PATTERN_OFFSET_BYTES, CAPABILITY_TEST_PATTERN_OFFSET_BYTES);

	step_num++;

	// checking via direct capability - no offset
	check_cap_test_pattern_after_overwrite(test_pattern_cap, step_num, 0, CAPABILITY_TEST_PATTERN_LENGTH_BYTES);

	step_num++;

	overwrite_test_cap_pattern(test_pattern_derived_cap, step_num, CAPABILITY_TEST_PATTERN_OFFSET_BYTES);

	step_num++;

	// re-started the pattern
	check_cap_test_pattern_after_overwrite(test_pattern_derived_cap, step_num, 0, CAPABILITY_TEST_PATTERN_OFFSET_BYTES);

	step_num++;

	// first half unchanged
	arch_dcache_invd_range(test_pattern_cap, CAPABILITY_TEST_PATTERN_LENGTH_BYTES);
	check_cap_test_pattern_after_overwrite(test_pattern_cap, step_num, 0, CAPABILITY_TEST_PATTERN_OFFSET_BYTES);

	(void)skadi_cap_ops_drop(test_pattern_cap);
	test_on_stack_byte_array(&step_num);

	for(int i = 0; i < ALLOCATOR_REPETITIONS; i++){
		// with a larger size this takes too long in the simulator
		// but need min. 4 as we divide by 4 later
		do {
			allocated_sizes[i] = sys_rand8_get();
		} while(allocated_sizes[i] < 4);

		step_num++;

		LOG_INF("Step %d: Allocate capability using skadi allocator!\n",step_num);

		allocated_caps[i] = allocate_capability(allocated_sizes[i]);

		if(allocated_caps[i]){
			LOG_INF("Step %d complete - allocated capability %p!",step_num,allocated_caps[i]);
		}
		else{
			LOG_ERR("Step %d failed - Could not allocate capability!",step_num);
			z_cv64a6_finish_test(1);
		}

		LOG_INF("Step %d: Allocate capability using skadi initial allocator!\n",step_num);

		step_num++;

		allocated_caps_init[i] = allocate_capability_init(allocated_sizes[i]);

		if(allocated_caps[i]){
			LOG_INF("Step %d complete - allocated capability %p from init alloc!",step_num,allocated_caps_init[i]);
		}
		else{
			LOG_ERR("Step %d failed - Could not allocate capability with init alloc!",step_num);
			z_cv64a6_finish_test(1);
		}
	}
	for(int i = 0; i < ALLOCATOR_REPETITIONS; i++){
		const uint8_t *cloned_capability;
		uint8_t *locked_capability;
		uint8_t *derived_capability, *double_locked_capability, *double_derived_capability;
		void *cloned_capability_out, *locked_capability_out;
		skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
		long lock_start, lock_end;

		cloned_capability_out = 0;

		locked_capability_out = 0;

		step_num++;

		overwrite_test_cap_pattern(allocated_caps[i], step_num, allocated_sizes[i]);

		step_num++;

		check_cap_test_pattern_after_overwrite(allocated_caps[i], step_num, 0, allocated_sizes[i]);

		if(!skadi_cap_ops_clone(allocated_caps[i], restriction, SKADI_PERMISSION_READ | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &cloned_capability_out)){
			LOG_ERR("Could not clone allocated capability!");
			z_cv64a6_finish_test(1);
		}

		cloned_capability = (uint8_t *) cloned_capability_out;

		step_num++;

		// RO capability, same segment
		check_cap_test_pattern_after_overwrite(allocated_caps[i], step_num, 0, allocated_sizes[i]);

		step_num++;

		LOG_INF("Step %d - locking capability %p!", step_num, allocated_caps[i]);
		
		lock_start = csr_read(mcycle);
		if(skadi_cap_ops_lock_simple_noirq(allocated_caps[i], &locked_capability_out) != 1){
			LOG_ERR("Step %d failure!",step_num);
			z_cv64a6_finish_test(1);
		}
		lock_end = csr_read(mcycle);

		LOG_INF("Locking took %ld cycles!", lock_end - lock_start);

		locked_capability = (uint8_t*) locked_capability_out;

		step_num++;

		overwrite_test_cap_pattern_offset(locked_capability, step_num, allocated_sizes[i], CAPABILITY_TEST_PATTERN_OFFSET_BYTES);

		check_cap_test_pattern_after_overwrite(locked_capability, step_num, CAPABILITY_TEST_PATTERN_OFFSET_BYTES, allocated_sizes[i]);

		if(!skadi_cap_ops_drop(locked_capability_out)){
			LOG_ERR("Could not drop locked capability!");
			z_cv64a6_finish_test(1);
		}

		step_num++;
		check_cap_test_pattern_after_overwrite(allocated_caps[i], step_num, CAPABILITY_TEST_PATTERN_OFFSET_BYTES, allocated_sizes[i]);
		
		step_num++;
		check_cap_test_pattern_after_overwrite(cloned_capability, step_num, CAPABILITY_TEST_PATTERN_OFFSET_BYTES, allocated_sizes[i]);

		step_num++;

		if(skadi_cap_ops_lock_simple_noirq(allocated_caps[i], &locked_capability_out) != 1){
			LOG_ERR("Step %d failure!",step_num);
			z_cv64a6_finish_test(1);
		}

		locked_capability = (uint8_t*) locked_capability_out;

		if(!skadi_cap_ops_derive(locked_capability, restriction, allocated_sizes[i]/2, 0, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, (void**) &derived_capability)){
			LOG_ERR("Could not derive from locked capability!");
			z_cv64a6_finish_test(1);
		}

		step_num++;

		/* both exist independently now */
		check_cap_test_pattern_after_overwrite(locked_capability, step_num, CAPABILITY_TEST_PATTERN_OFFSET_BYTES, allocated_sizes[i]);
		check_cap_test_pattern_after_overwrite(derived_capability, step_num, CAPABILITY_TEST_PATTERN_OFFSET_BYTES, allocated_sizes[i]/2);

		lock_start = csr_read(mcycle);
		if(skadi_cap_ops_lock_simple_noirq(derived_capability, (void**) &double_locked_capability) != 1){
			LOG_ERR("Step %d failure!",step_num);
			z_cv64a6_finish_test(1);
		}
		lock_end = csr_read(mcycle);

		LOG_INF("Locking took %ld cycles!", lock_end - lock_start);

		step_num++;
		
		check_cap_test_pattern_after_overwrite(double_locked_capability, step_num, CAPABILITY_TEST_PATTERN_OFFSET_BYTES, allocated_sizes[i]/2);

		if(!skadi_cap_ops_derive(double_locked_capability, restriction, allocated_sizes[i]/4, 0, SKADI_PERMISSION_READ | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, (void**)&double_derived_capability)){
			LOG_ERR("Could not derive from locked capability!");
			z_cv64a6_finish_test(1);
		}

		step_num++;

		check_cap_test_pattern_after_overwrite(double_locked_capability, step_num, CAPABILITY_TEST_PATTERN_OFFSET_BYTES, allocated_sizes[i]/2);		
		check_cap_test_pattern_after_overwrite(double_derived_capability, step_num, CAPABILITY_TEST_PATTERN_OFFSET_BYTES, allocated_sizes[i]/4);

		step_num++;

		if(!skadi_cap_ops_drop(double_derived_capability)){
			LOG_ERR("Could not drop locked capability!");
			z_cv64a6_finish_test(1);
		}

		if(!skadi_cap_ops_drop(double_locked_capability)){
			LOG_ERR("Could not drop locked capability!");
			z_cv64a6_finish_test(1);
		}

		if(!skadi_cap_ops_drop(derived_capability)){
			LOG_ERR("Could not drop locked capability!");
			z_cv64a6_finish_test(1);
		}

		if(!skadi_cap_ops_drop(locked_capability_out)){
			LOG_ERR("Could not drop locked capability!");
			z_cv64a6_finish_test(1);
		}

		if(!skadi_cap_ops_drop(cloned_capability_out)){
			LOG_ERR("Could not drop cloned capability!");
			z_cv64a6_finish_test(1);
		}

		if(!skadi_allocator_free(allocated_caps[i])){
			LOG_ERR("Could not free the allocated capability!");
			z_cv64a6_finish_test(1);
		}

		LOG_INF("Step %d complete - dropped and freed capability %d!",step_num, i);

		overwrite_test_cap_pattern(allocated_caps_init[i], step_num, allocated_sizes[i]);

		step_num++;

		check_cap_test_pattern_after_overwrite(allocated_caps_init[i], step_num, 0, allocated_sizes[i]);

		skadi_init_alloc_free(allocated_caps_init[i]);
	}

	step_num++;
	LOG_INF("Step %d: revoke test pattern capability %p!",step_num,test_pattern_cap);


	if(!skadi_cap_ops_revoke_simple(test_pattern_cap, (void**) &test_pattern_cap)){
		LOG_ERR("Could not revoke the allocated capability!");
		z_cv64a6_finish_test(1);
	}

	step_num++;	

	check_cap_test_pattern_after_revoke(test_pattern_cap, step_num, 0, CAPABILITY_TEST_PATTERN_LENGTH_BYTES);

	step_num++;

	overwrite_test_cap_pattern(test_pattern_cap, step_num, CAPABILITY_TEST_PATTERN_LENGTH_BYTES);

	step_num++;
	check_cap_test_pattern_after_overwrite(test_pattern_cap, step_num, 0, CAPABILITY_TEST_PATTERN_LENGTH_BYTES);
	step_num++;
	LOG_INF("Step %d: Check RNG!", step_num);
	for(int i = 0; i < RNG_REPETITIONS; i++){
		uint64_t rng = skadi_cap_ops_get_trng_bits();
		if(!rng){
			LOG_ERR("Got 0 value from RNG!");
			z_cv64a6_finish_test(1);
		}
		if(i && rng == rng_last){
			LOG_ERR("Got repeat value %"PRIx64, rng);
			z_cv64a6_finish_test(1);
		}
		LOG_INF("Got RNG %"PRIx64, rng);
		rng_last = rng;
	}

	LOG_INF("Preparing execute call!");
	
	if(!skadi_cap_ops_derive(sim_capability_test_code_seg, restriction, test_code_seg_length, skadi_get_capability_offset(sim_capability_test_code_seg), SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, (void*)&sim_capability_test_ld_check)){
		LOG_ERR("Could not derive executable capability!");
		z_cv64a6_finish_test(1);
	}

	test_long_ptr = skadi_cap_ops_derive_arg(&test_long, sizeof(test_long));

	__ASSERT_NO_MSG(test_long_ptr);

	LOG_INF("Doing execute call at %p", sim_capability_test_ld_check);

	reset_performance_counters();
	if(sim_capability_test_ld_check(42, test_long_ptr) != 2*42){
		LOG_ERR("Incorrect result from execute call!");
		z_cv64a6_finish_test(1);
	}
	read_performance_counters(step_num++);

	(void) skadi_cap_ops_drop(test_long_ptr);

	LOG_INF("Good execute call!");

	if(!skadi_cap_ops_derive(sim_capability_test_large_code_seg, restriction, test_code_seg_large_length, skadi_get_capability_offset(sim_capability_test_large_code_seg), SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, (void*)&sim_capability_test)){
		LOG_ERR("Could not derive executable capability!");
		z_cv64a6_finish_test(1);
	}

	LOG_INF("Doing large execute call at %p", sim_capability_test);

	reset_performance_counters();
	if(sim_capability_test(42) != 42+200){
		LOG_ERR("Incorrect result from large execute call!");
		z_cv64a6_finish_test(1);
	}
	read_performance_counters(step_num++);

	LOG_INF("Good large execute call!");

	if(!skadi_cap_ops_derive(sim_capability_test_xlarge_code_seg, restriction, test_code_seg_xlarge_length, skadi_get_capability_offset(sim_capability_test_xlarge_code_seg), SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, (void*)&sim_capability_test)){
		LOG_ERR("Could not derive executable capability!");
		z_cv64a6_finish_test(1);
	}

	LOG_INF("Doing extra large execute call at %p", sim_capability_test);

	reset_performance_counters();
	if(sim_capability_test(42) != 42+20000){
		LOG_ERR("Incorrect result from large execute call!");
		z_cv64a6_finish_test(1);
	}
	read_performance_counters(step_num++);

	LOG_INF("Good extra large execute call!");

	LOG_INF("Preparing dummy subsytem call!");

	if(!skadi_cap_ops_derive(sim_capability_test_dummy_subsystem_callee, set_task_id_restriction_1, callee_trampoline_length, skadi_get_capability_offset(sim_capability_test_dummy_subsystem_callee), SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, (void*)&sim_capability_test_dummy_subsystem_callee_token)){
		LOG_ERR("Could not derive set-task ID capability for callee!");
		z_cv64a6_finish_test(1);
	}

	if(!skadi_cap_ops_derive(sim_capability_test_dummy_subsystem_caller_return_trampoline, set_task_id_restriction_0, caller_trampoline_length, skadi_get_capability_offset(sim_capability_test_dummy_subsystem_caller_return_trampoline), SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, (void*)&sim_capability_test_dummy_subsystem_ret_token)){
		LOG_ERR("Could not derive set-task ID capability for caller!");
		z_cv64a6_finish_test(1);
	}

	LOG_INF("Doing subsystem call with callee trampoline %p return trampoline %p!", sim_capability_test_dummy_subsystem_callee_token, sim_capability_test_dummy_subsystem_ret_token);


	reset_performance_counters();
	for(int i = 0; i < NUMBER_SUBSYSTEM_CALLS; i++){
		int key = arch_irq_lock();
		(void)sim_capability_test_dummy_subsystem_caller(skadi_cap_ops_get_trng_bits());
		arch_irq_unlock(key);
	}
	read_performance_counters(step_num++);

	test_pattern_derived_cap = allocate_capability_init(sizeof(uint8_t));

	LOG_INF("Doing lock calls on test pattern cap %p",test_pattern_derived_cap);

	if(!test_pattern_derived_cap){
		LOG_ERR("Could not allocate test pattern capability!");
		z_cv64a6_finish_test(1);
	}
	
	reset_performance_counters();
	for(int i = 0; i < NUMBER_RESTRICT_CALLS; i++){
		void *locked_cap=NULL;
		// this serves as a stress test for the ops writeback unit
		(void)skadi_cap_ops_lock_simple_noirq(test_pattern_derived_cap, &locked_cap);
		(void)skadi_cap_ops_drop(locked_cap);
	}
	read_performance_counters(step_num++);

	skadi_init_alloc_free(test_pattern_derived_cap);

#ifdef CONFIG_SKADI_SUBSYSTEM_CALL_INSTRUCTIONS

	LOG_INF("Preparing dummy subsytem call with scall!");

	if(!skadi_cap_ops_derive(sim_capability_test_dummy_subsystem_callee_scall, set_task_id_restriction_1, callee_trampoline_length_scall, skadi_get_capability_offset(sim_capability_test_dummy_subsystem_callee_scall), SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, (void*)&sim_capability_test_dummy_subsystem_callee_token_scall)){
		LOG_ERR("Could not derive set-task ID capability for scall callee!");
		z_cv64a6_finish_test(1);
	}

	if(!skadi_cap_ops_derive(sim_capability_test_dummy_subsystem_caller_return_trampoline_scall, set_task_id_restriction_0, caller_trampoline_length_scall, skadi_get_capability_offset(sim_capability_test_dummy_subsystem_caller_return_trampoline_scall), SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, (void*)&sim_capability_test_dummy_subsystem_ret_token_scall)){
		LOG_ERR("Could not derive set-task ID capability for scall caller!");
		z_cv64a6_finish_test(1);
	}

	LOG_INF("Doing subsystem call with scall and callee trampoline %p return trampoline %p!", sim_capability_test_dummy_subsystem_callee_token_scall, sim_capability_test_dummy_subsystem_ret_token_scall);

	reset_performance_counters();
	for(int i = 0; i < NUMBER_SUBSYSTEM_CALLS; i++){
		int key = arch_irq_lock();
		(void)sim_capability_test_dummy_subsystem_caller_scall();
		arch_irq_unlock(key);
	}
	read_performance_counters(step_num++);

	
	LOG_INF("Preparing dummy subsytem call with scalls!");

	if(!skadi_cap_ops_derive(sim_capability_test_dummy_subsystem_callee_scalls, set_task_id_restriction_0, callee_trampoline_length_scalls, skadi_get_capability_offset(sim_capability_test_dummy_subsystem_callee_scalls), SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, (void*)&sim_capability_test_dummy_subsystem_callee_token_scalls)){
		LOG_ERR("Could not derive set-task ID capability for scall callee!");
		z_cv64a6_finish_test(1);
	}

	if(!skadi_cap_ops_derive(sim_capability_test_dummy_subsystem_caller_return_trampoline_scalls, set_task_id_restriction_0, caller_trampoline_length_scalls, skadi_get_capability_offset(sim_capability_test_dummy_subsystem_caller_return_trampoline_scalls), SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, (void*)&sim_capability_test_dummy_subsystem_ret_token_scalls)){
		LOG_ERR("Could not derive set-task ID capability for scall caller!");
		z_cv64a6_finish_test(1);
	}

	LOG_INF("Doing subsystem call with scall and callee trampoline %p return trampoline %p!", sim_capability_test_dummy_subsystem_callee_token_scalls, sim_capability_test_dummy_subsystem_ret_token_scalls);

	reset_performance_counters();
	for(int i = 0; i < NUMBER_SUBSYSTEM_CALLS; i++){
		int key = arch_irq_lock();
		(void)sim_capability_test_dummy_subsystem_caller_scalls();
		arch_irq_unlock(key);
	}
	read_performance_counters(step_num++);

	LOG_INF("Testing failing subsystem call!");

	skadi_init_register_exception_handler(_expect_exception);
	/* this is a completely invalid endpoint */
	if(!sim_capability_test_test_failing_subsystem_call(_invalid_subsystem_call_target)){
		LOG_ERR("Unexpectedly did not fail on subsystem call!");
		z_cv64a6_finish_test(1);
	}

	/* this is task-ID restricted to us - fails with scall */
	if(!sim_capability_test_test_failing_subsystem_call(sim_capability_test_dummy_subsystem_callee_scalls)){
		LOG_ERR("Unexpectedly did not fail on subsystem call!");
		z_cv64a6_finish_test(1);
	}

	LOG_INF("Preparing subsystem call with offset!");

	if(!skadi_cap_ops_derive(_invalid_subsystem_call_target, set_task_id_restriction_1, invalid_subsystem_call_target_trampoline_length, skadi_get_capability_offset(_invalid_subsystem_call_target), SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, (void*)&sim_capability_test_dummy_subsystem_call_token_invalid)){
		LOG_ERR("Could not derive set-task ID capability for scall callee!");
		z_cv64a6_finish_test(1);
	}

	/* a subsystem call with an offset; trampoline can handle +4 offset */
	if(!sim_capability_test_test_failing_subsystem_call((char*)sim_capability_test_dummy_subsystem_call_token_invalid + 4)){
		LOG_ERR("Unexpectedly did not fail on subsystem call!");
		z_cv64a6_finish_test(1);
	}


	skadi_init_register_exception_handler(_isr_wrapper);

#endif

#ifdef CONFIG_SKADI_FAST_REG_ZERO_INSTRUCTION
	LOG_INF("Preparing zero reg instruction test!");

	if(!sim_capability_test_test_callee_zero()){
		LOG_ERR("Zeroing out the regs using specialized instruction failed!");
		z_cv64a6_finish_test(1);
	}
#endif

	LOG_INF("Beginning micro benchmarks!");

	large_cap_for_revoke = skadi_init_alloc_allocate(ONE_MIB_BYTES, SKADI_PERMISSION_READ, true);

	if(!large_cap_for_revoke){
		LOG_ERR("Could not allocate 1 MiB for revoke!");
		z_cv64a6_finish_test(1);
	}

#ifndef CONFIG_SKADI_TRACK_CYCLES_OPS
	LOG_WRN("Cycle tracking for ops disabled - all cycles will be reported as zero!");
#endif

	for(int i = 0; i < MICRO_BENCHMARK_REPETITIONS; i++){
		bool op_ok;
		void *create_output;
		void *derive_output;
		void *clone_output;
		void *lock_output;
		int64_t start_time, end_time;
		skadi_inspect_metadata_t inspect_metadata;
		atomic_val_t start_cycles = 0, end_cycles = 0;

		skadi_benchmark_prepare_sample(&create_benchmarks_cycles[i]);
		skadi_benchmark_prepare_sample(&create_benchmarks[i]);

		start_cycles = READ_OPS_CYCLES(&skadi_cycles_create_ops);
		start_time = csr_read(mcycle);
		op_ok = skadi_cap_ops_create(test_pattern_cap, loader_restriction, true, CAPABILITY_TEST_PATTERN_LENGTH_BYTES/2, SKADI_ALL_PERMISSIONS, &create_output);
		end_time = csr_read(mcycle);
		end_cycles = READ_OPS_CYCLES(&skadi_cycles_create_ops);

		if(!op_ok){
			LOG_ERR("Create failed!");
			z_cv64a6_finish_test(1);
		}

		skadi_benchmark_add_sample(&create_benchmarks[i], end_time - start_time);
		skadi_benchmark_add_sample(&create_benchmarks_cycles[i], end_cycles - start_cycles);


		skadi_benchmark_prepare_sample(&derive_benchmarks_cycles[i]);
		skadi_benchmark_prepare_sample(&derive_benchmarks[i]);

		start_cycles = READ_OPS_CYCLES(&skadi_cycles_derive_ops);

		start_time = csr_read(mcycle);
		op_ok = skadi_cap_ops_derive(create_output, loader_restriction, CAPABILITY_TEST_PATTERN_LENGTH_BYTES/4, CAPABILITY_TEST_PATTERN_LENGTH_BYTES/4, SKADI_ALL_PERMISSIONS, &derive_output);
		end_time = csr_read(mcycle);
		end_cycles = READ_OPS_CYCLES(&skadi_cycles_derive_ops);

		if(!op_ok){
			LOG_ERR("derive failed!");
			z_cv64a6_finish_test(1);
		}
		
		skadi_benchmark_add_sample(&derive_benchmarks[i], end_time - start_time);
		skadi_benchmark_add_sample(&derive_benchmarks_cycles[i], end_cycles - start_cycles);

		skadi_benchmark_prepare_sample(&clone_benchmarks_cycles[i]);
		skadi_benchmark_prepare_sample(&clone_benchmarks[i]);
		
		start_cycles = READ_OPS_CYCLES(&skadi_cycles_clone_ops);
		start_time = csr_read(mcycle);
		op_ok = skadi_cap_ops_clone(derive_output, loader_restriction, SKADI_ALL_PERMISSIONS, &clone_output);
		end_time = csr_read(mcycle);
		end_cycles = READ_OPS_CYCLES(&skadi_cycles_clone_ops);
		
		if(!op_ok){
			LOG_ERR("clone failed!");
			z_cv64a6_finish_test(1);
		}

		skadi_benchmark_add_sample(&clone_benchmarks[i], end_time - start_time);
		skadi_benchmark_add_sample(&clone_benchmarks_cycles[i], end_cycles - start_cycles);

		skadi_benchmark_prepare_sample(&drop_benchmarks_cycles[i]);
		skadi_benchmark_prepare_sample(&drop_benchmarks[i]);

		start_cycles = READ_OPS_CYCLES(&skadi_cycles_drop_ops);
		start_time = csr_read(mcycle);
		op_ok = skadi_cap_ops_drop(clone_output);
		end_time = csr_read(mcycle);
		end_cycles = READ_OPS_CYCLES(&skadi_cycles_drop_ops);
		
		if(!op_ok){
			LOG_ERR("drop failed!");
			z_cv64a6_finish_test(1);
		}

		skadi_benchmark_add_sample(&drop_benchmarks[i], end_time - start_time);
		skadi_benchmark_add_sample(&drop_benchmarks_cycles[i], end_cycles - start_cycles);

		skadi_benchmark_prepare_sample(&lock_benchmarks_cycles[i]);
		skadi_benchmark_prepare_sample(&lock_benchmarks[i]);

		start_cycles = READ_OPS_CYCLES(&skadi_cycles_lock_ops);
		start_time = csr_read(mcycle);
		op_ok = skadi_cap_ops_lock(derive_output, loader_restriction, SKADI_ALL_PERMISSIONS, &lock_output);
		end_time = csr_read(mcycle);
		end_cycles = READ_OPS_CYCLES(&skadi_cycles_lock_ops);

		if(!op_ok){
			LOG_ERR("lock failed!");
			z_cv64a6_finish_test(1);
		}

		skadi_benchmark_add_sample(&lock_benchmarks[i], end_time - start_time);
		skadi_benchmark_add_sample(&lock_benchmarks_cycles[i], end_cycles - start_cycles);

		skadi_benchmark_prepare_sample(&unlock_benchmarks_cycles[i]);
		skadi_benchmark_prepare_sample(&unlock_benchmarks[i]);

		start_cycles = READ_OPS_CYCLES(&skadi_cycles_drop_ops);
		start_time = csr_read(mcycle);
		op_ok = skadi_cap_ops_drop(lock_output);
		end_time = csr_read(mcycle);
		end_cycles = READ_OPS_CYCLES(&skadi_cycles_drop_ops);

		if(!op_ok){
			LOG_ERR("unlock failed!");
			z_cv64a6_finish_test(1);	
		}

		skadi_benchmark_add_sample(&unlock_benchmarks[i], end_time - start_time);
		skadi_benchmark_add_sample(&unlock_benchmarks_cycles[i], end_cycles - start_cycles);

		skadi_benchmark_prepare_sample(&inspect_benchmarks_cycles[i]);
		skadi_benchmark_prepare_sample(&inspect_benchmarks[i]);

		start_cycles = READ_OPS_CYCLES(&skadi_cycles_inspect_ops);
		start_time = csr_read(mcycle);
		op_ok = skadi_cap_ops_inspect(derive_output, &inspect_metadata);
		end_time = csr_read(mcycle);
		end_cycles = READ_OPS_CYCLES(&skadi_cycles_inspect_ops);

		if(!op_ok){
			LOG_ERR("inspect failed!");
			z_cv64a6_finish_test(1);	
		}

		if(!inspect_metadata.read_permission || !inspect_metadata.write_permission || !inspect_metadata.execute_permission || !inspect_metadata.lockable_permission || !inspect_metadata.irq_accessible_permission){
			LOG_ERR("inspect incorrect permissions!");
			z_cv64a6_finish_test(1);
		}

		if(inspect_metadata.restriction_type != SKADI_RESTRICTIONS_TASK_ID_BOUND || inspect_metadata.restriction_body.task_restriction.restriction_task_id != SKADI_TASK_ID_LOADER || inspect_metadata.restriction_body.task_restriction.restriction_device_id != SKADI_DEVICE_ID_CPU){
			LOG_ERR("inspect incorrect restriction!");
			z_cv64a6_finish_test(1);
		}

		if(inspect_metadata.capability_length !=  CAPABILITY_TEST_PATTERN_LENGTH_BYTES/4){
			LOG_ERR("inspect incorrect length!");
			z_cv64a6_finish_test(1);
		}

		if(inspect_metadata.capability_base == 0){
			LOG_ERR("inspect implausible base!");
			z_cv64a6_finish_test(1);
		}

		skadi_benchmark_add_sample(&inspect_benchmarks[i], end_time - start_time);
		skadi_benchmark_add_sample(&inspect_benchmarks_cycles[i], end_cycles - start_cycles);

		skadi_benchmark_prepare_sample(&restrict_benchmarks_cycles[i]);
		skadi_benchmark_prepare_sample(&restrict_benchmarks[i]);

		start_cycles = READ_OPS_CYCLES(&skadi_cycles_restrict_ops);
		start_time = csr_read(mcycle);
		op_ok = skadi_cap_ops_restrict(derive_output, restriction, 1, 1, SKADI_PERMISSION_READ);
		end_time = csr_read(mcycle);
		end_cycles = READ_OPS_CYCLES(&skadi_cycles_restrict_ops);

		skadi_benchmark_add_sample(&restrict_benchmarks[i], end_time - start_time);
		skadi_benchmark_add_sample(&restrict_benchmarks_cycles[i], end_cycles - start_cycles);

		if(!op_ok){
			LOG_ERR("restrict failed!");
			z_cv64a6_finish_test(1);	
		}

		/* do not leak CMT entries */
		(void)skadi_cap_ops_drop(derive_output);

		skadi_benchmark_prepare_sample(&revoke_benchmarks_cycles[i]);
		skadi_benchmark_prepare_sample(&revoke_benchmarks[i]);

		start_cycles = READ_OPS_CYCLES(&skadi_cycles_revoke_ops);
		start_time = csr_read(mcycle);
		op_ok = skadi_cap_ops_revoke(large_cap_for_revoke, loader_restriction, SKADI_ALL_PERMISSIONS, &large_cap_for_revoke);
		end_time = csr_read(mcycle);
		end_cycles = READ_OPS_CYCLES(&skadi_cycles_revoke_ops);

		if(!op_ok){
			LOG_ERR("revoke failed!");
			z_cv64a6_finish_test(1);
		}

		skadi_benchmark_add_sample(&revoke_benchmarks[i], end_time - start_time);
		skadi_benchmark_add_sample(&revoke_benchmarks_cycles[i], end_cycles - start_cycles);

		skadi_benchmark_prepare_sample(&merge_benchmarks_cycles[i]);
		skadi_benchmark_prepare_sample(&merge_benchmarks[i]);

		/* want merge without inspect so we only get the op we care about */
		start_cycles = READ_OPS_CYCLES(&skadi_cycles_merge_ops);
		start_time = csr_read(mcycle);
		op_ok = skadi_cap_ops_merge_noinspect(test_pattern_cap, create_output, loader_restriction, SKADI_ALL_PERMISSIONS, SKADI_CAPABILITY_TYPE_OFFSET_16_BIT, (void**)&test_pattern_cap);
		end_time = csr_read(mcycle);
		end_cycles = READ_OPS_CYCLES(&skadi_cycles_merge_ops);

		if(!op_ok){
			LOG_ERR("merge failed!");
			z_cv64a6_finish_test(1);
		}

		skadi_benchmark_add_sample(&merge_benchmarks[i], end_time - start_time);
		skadi_benchmark_add_sample(&merge_benchmarks_cycles[i], end_cycles - start_cycles);

		LOG_INF("Completed micro benchmark round %d!", (i+1));
	}

	LOG_INF("Units are lies - these are CYCLES!");
	skadi_benchmark_evaluate_samples(create_benchmarks, MICRO_BENCHMARK_REPETITIONS, 0, "create microbenchmarks");
	skadi_benchmark_evaluate_samples(create_benchmarks_cycles, MICRO_BENCHMARK_REPETITIONS, 0, "create microbenchmarks (ops only)");
	skadi_benchmark_evaluate_samples(derive_benchmarks, MICRO_BENCHMARK_REPETITIONS, 0, "derive microbenchmarks");
	skadi_benchmark_evaluate_samples(derive_benchmarks_cycles, MICRO_BENCHMARK_REPETITIONS, 0, "derive microbenchmarks (ops only)");
	skadi_benchmark_evaluate_samples(drop_benchmarks, MICRO_BENCHMARK_REPETITIONS, 0, "drop microbenchmarks");
	skadi_benchmark_evaluate_samples(drop_benchmarks_cycles, MICRO_BENCHMARK_REPETITIONS, 0, "drop microbenchmarks (ops only)");
	skadi_benchmark_evaluate_samples(unlock_benchmarks, MICRO_BENCHMARK_REPETITIONS, 0, "unlock microbenchmarks");
	skadi_benchmark_evaluate_samples(unlock_benchmarks_cycles, MICRO_BENCHMARK_REPETITIONS, 0, "unlock microbenchmarks (ops only)");
	skadi_benchmark_evaluate_samples(merge_benchmarks, MICRO_BENCHMARK_REPETITIONS, 0, "merge microbenchmarks");
	skadi_benchmark_evaluate_samples(merge_benchmarks_cycles, MICRO_BENCHMARK_REPETITIONS, 0, "merge microbenchmarks (ops only)");
	skadi_benchmark_evaluate_samples(clone_benchmarks, MICRO_BENCHMARK_REPETITIONS, 0, "clone microbenchmarks");
	skadi_benchmark_evaluate_samples(clone_benchmarks_cycles, MICRO_BENCHMARK_REPETITIONS, 0, "clone microbenchmarks (ops only)");
	skadi_benchmark_evaluate_samples(revoke_benchmarks, MICRO_BENCHMARK_REPETITIONS, 0, "revoke microbenchmarks");
	skadi_benchmark_evaluate_samples(revoke_benchmarks_cycles, MICRO_BENCHMARK_REPETITIONS, 0, "revoke microbenchmarks (ops only)");
	skadi_benchmark_evaluate_samples(lock_benchmarks, MICRO_BENCHMARK_REPETITIONS, 0, "lock microbenchmarks");
	skadi_benchmark_evaluate_samples(lock_benchmarks_cycles, MICRO_BENCHMARK_REPETITIONS, 0, "lock microbenchmarks (ops only)");
	skadi_benchmark_evaluate_samples(inspect_benchmarks, MICRO_BENCHMARK_REPETITIONS, 0, "inspect microbenchmarks");
	skadi_benchmark_evaluate_samples(inspect_benchmarks_cycles, MICRO_BENCHMARK_REPETITIONS, 0, "inspect microbenchmarks (ops only)");
	skadi_benchmark_evaluate_samples(restrict_benchmarks, MICRO_BENCHMARK_REPETITIONS, 0, "restrict microbenchmarks");
	skadi_benchmark_evaluate_samples(restrict_benchmarks_cycles, MICRO_BENCHMARK_REPETITIONS, 0, "restrict microbenchmarks (ops only)");

	LOG_INF("Finished micro benchmarks!");

	LOG_INF("Preparing subsystem call benchmark!");

	SKADI_SUBSYSTEM_INITIALIZE_CALLER_TRAMPOLINE(skadi_subsystem_benchmark);
	skadi_subsystem_benchmark_callee_register_init_function();

	if(!skadi_cap_ops_derive_min_cap_type(skadi_subsystem_benchmark_callee_callee_trampoline, set_task_id_restriction_0, callee_trampoline_length_benchmark, skadi_get_capability_offset(skadi_subsystem_benchmark_callee_callee_trampoline), SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, IS_ENABLED(CONFIG_SKADI_TEXT_ALIGN_12_BIT) ? SKADI_CAPABILITY_TYPE_OFFSET_16_BIT : SKADI_CAPABILITY_TYPE_OFFSET_8_BIT, (void**)&benchmark_callee_trampoline)){
		LOG_ERR("Could not derive set-task ID capability for benchmark trampoline!");
		z_cv64a6_finish_test(1);
	}

	LOG_INF("Doing subystem call benchmark!");

	for(int i = 0; i < MICRO_BENCHMARK_REPETITIONS; i++){
		long start_cycles, end_cycles;
		long start_instret, end_instret;

		void *ret;
		skadi_benchmark_prepare_sample(&subsys_call_benchmarks_full[i]);
		skadi_benchmark_prepare_sample(&subsys_call_benchmarks_half[i]);
		skadi_benchmark_prepare_sample(&subsys_call_instret_full[i]);
		skadi_benchmark_prepare_sample(&subsys_call_instret_half[i]);

		start_instret = csr_read(minstret);

		subsys_call_instret_half[i].sample = start_instret;
		
		start_cycles = csr_read(mcycle);

		subsys_call_benchmarks_half[i].sample = start_cycles;

		ret = skadi_subsystem_benchmark(&subsys_call_benchmarks_half[i], &subsys_call_instret_half[i], benchmark_callee_trampoline);

		end_cycles = csr_read(mcycle);
		end_instret = csr_read(minstret);

		if(!ret){
			LOG_ERR("Subsystem call failed!");
			z_cv64a6_finish_test(1);
		}
		skadi_benchmark_add_sample(&subsys_call_benchmarks_full[i], end_cycles - start_cycles);
		skadi_benchmark_add_sample(&subsys_call_instret_full[i], end_instret - start_instret);

	}

	skadi_benchmark_evaluate_samples(subsys_call_instret_half, MICRO_BENCHMARK_REPETITIONS, 0, "subsystem call instructions retired (half) benchmarks");
	skadi_benchmark_evaluate_samples(subsys_call_instret_full, MICRO_BENCHMARK_REPETITIONS, 0, "subsystem call instructions retired (full) benchmarks");

	skadi_benchmark_evaluate_samples(subsys_call_benchmarks_half, MICRO_BENCHMARK_REPETITIONS, 0, "half subsys call benchmarks");
	skadi_benchmark_evaluate_samples(subsys_call_benchmarks_full, MICRO_BENCHMARK_REPETITIONS, 0, "full subsys call benchmarks");

	LOG_INF("At test end - %"PRIu64" capabilities exist in the system!", skadi_cap_ops_get_capability_count());

	LOG_INF("Test succcess :-)\n");

	z_cv64a6_finish_test(0);

	return 0;
}
