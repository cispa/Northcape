/*
 *  Copyright (c) 2023 KNS Group LLC (YADRO)
 *
 *  SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/kernel.h>
#include <zephyr/llext/symbol.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_sched.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(skadi_perf_backend, CONFIG_SKADI_LOG_LEVEL);

struct {
	uintptr_t mepc;
	uintptr_t fp;
	uintptr_t ra;
	uintptr_t valid;
} skadi_profiling_current_isr_state = {};

EXPORT_SYMBOL(skadi_profiling_current_isr_state);

/* from libc - used to circumvent a circular dependency */
extern void *skadi_profiling_current_isr_state_reloc;

static bool skadi_riscv_perf_setup_libc_reloc(void){
	skadi_profiling_current_isr_state_reloc = skadi_cap_ops_derive_arg_wo(&skadi_profiling_current_isr_state, sizeof(skadi_profiling_current_isr_state));
	return skadi_profiling_current_isr_state_reloc;
}
SKADI_SUBSYSTEM_INIT_FUNCTIONS(skadi_riscv_perf_setup_libc_reloc);

static bool valid_stack(uintptr_t addr, k_tid_t current)
{
	skadi_inspect_metadata_t metadata;
    bool ok;

    ok = skadi_cap_ops_inspect((void*)addr, &metadata);
	
	uintptr_t cap_length = metadata.capability_length;
	uint32_t offset = skadi_get_capability_offset((void*)addr);

	/* skadi subsystem call stack */
	if(ok && cap_length == sizeof(struct skadi_subsystem_stack) && offset < cap_length){
		return true;
	}

	LOG_DBG("Current %p vs stack start %p length %zd\n", (void*) addr, (void*)current->stack_info.start, current->stack_info.size);

	/* scheduler stack */
	if(skadi_thread_addr_in_stack(current, addr)){
		return true;
	}

	return false;
}

static uintptr_t text_region_starts[SKADI_NUM_SUBSYSTEMS];
static size_t text_region_lengths[SKADI_NUM_SUBSYSTEMS];
static size_t number_subsystems;

static inline bool in_text_region(uintptr_t addr)
{
	__ASSERT_NO_MSG(number_subsystems);

	for(size_t subsystem = 0; subsystem < number_subsystems; subsystem++){
		if(addr >= text_region_starts[subsystem] && addr < text_region_starts[subsystem] + text_region_lengths[subsystem]){
			return true;
		}
	}
	/* could be return address of callee trampoline */
	return skadi_subsystem_can_accept_function_pointer((uintptr_t)addr, NULL, SKADI_CURRENT_TASK_ID, true, true);
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, __skadi_perf_add_text_region, uintptr_t text_region_start, size_t text_region_length)
	text_region_starts[number_subsystems] = text_region_start;
	text_region_lengths[number_subsystems] = text_region_length;

	__ASSERT_NO_MSG(number_subsystems < SKADI_NUM_SUBSYSTEMS);

	if(number_subsystems < SKADI_NUM_SUBSYSTEMS){
		number_subsystems++;
	}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_perf_add_text_region)

/*
 * This function use frame pointers to unwind stack and get trace of return addresses.
 * Return addresses are translated in corresponding function's names using .elf file.
 * So we get function call trace
 */
size_t arch_perf_current_stack_trace(uintptr_t *buf, size_t size)
{
	if (size < 2U) {
		return 0;
	}

	size_t idx = 0;

	/* supposed to be saved by timer ISR */
	// TODO libc __ASSERT_NO_MSG(skadi_profiling_current_isr_state.valid);

	/* supposed to have been set up by loader */
	__ASSERT_NO_MSG(number_subsystems == SKADI_NUM_SUBSYSTEMS);

	if(!skadi_profiling_current_isr_state.valid){
		return 0;
	}
	/* ensure values not reused */
	skadi_profiling_current_isr_state.valid = 0x0;

	/*
	 * $s0 is used as frame pointer.
	 *
	 * stack frame in memory (commonly):
	 * (addresses growth up)
	 *  ....
	 *  [-] <- $fp($s0) (curr)
	 *  $ra
	 *  $fp($s0) (next)
	 *  ....
	 *
	 * If function do not call any other function, compiller may not save $ra,
	 * then stack frame will be:
	 *  ....
	 *  [-] <- $fp($s0) (curr)
	 *  $fp($s0) (next)
	 *  ....
	 *
	 */
	void **fp = (void **)skadi_profiling_current_isr_state.fp;
	if(!fp){
		return 0;
	}
	void **new_fp = (void **)fp[-1];

	buf[idx++] = (uintptr_t)skadi_profiling_current_isr_state.mepc;

	/*
	 * During function prologue and epilogue fp is equal to fp of
	 * previous function stack frame, it looks like second function
	 * from top is missed.
	 * So saving $ra will help in case when irq occurred in
	 * function prologue or epilogue.
	 */
	buf[idx++] = skadi_profiling_current_isr_state.ra;
	if (valid_stack((uintptr_t)new_fp, skadi_current_get())) {
		fp = new_fp;
	}
	while (valid_stack((uintptr_t)fp, skadi_current_get())) {
		LOG_DBG("Loop %zu\n",idx-2);
		if (idx >= size) {
			LOG_DBG("Break 1!\n");
			return 0;
		}

		if (!in_text_region((uintptr_t)fp[-1])) {
			LOG_DBG("Break 2 - function pointer %p!\n", fp[-1]);
			break;
		}

		buf[idx++] = (uintptr_t)fp[-1];
		new_fp = (void **)fp[-2];

		/*
		 * anti-infinity-loop if
		 * new_fp can't be smaller than fp, cause the stack is growing down
		 * and trace moves deeper into the stack
		 */
		if (skadi_get_capability_offset((void*)new_fp) <= skadi_get_capability_offset((void*)fp) && skadi_is_same_capability((void*)new_fp, (void*)fp)) {
			LOG_DBG("Break 3! new %p old %p\n", (void*)new_fp, (void*)fp);
			break;
		}
		fp = new_fp;
	}
	LOG_DBG("Break loop! Last stack %p\n", fp);

	return idx;
}
