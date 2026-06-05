/*
 * Copyright (c) 2018 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file
 * @brief Thread entry
 *
 * This file provides the common thread entry function
 */

#include <zephyr/kernel.h>

#ifdef CONFIG_SKADI_LOADER
#include <zephyr/skadi/skadi_subsystem.h>
#endif

#ifdef CONFIG_CURRENT_THREAD_USE_TLS
#include <zephyr/random/random.h>

__thread k_tid_t z_tls_current;
#endif

#ifdef CONFIG_STACK_CANARIES_TLS
extern __thread volatile uintptr_t __stack_chk_guard;
#endif /* CONFIG_STACK_CANARIES_TLS */

#ifdef CONFIG_SKADI_LOADER
	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS(skadi_thread_entry_wrapper, void *p1, void *p2, void *p3);
	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_IMPL(skadi_thread_entry_wrapper, 3, void *p1, void *p2, void *p3);
	extern void (**skadi_subsystem_mtimer_sched_hook)(void);
	extern void _skadi_subsystem_yield_stub(void);
#endif

/*
 * Common thread entry point function (used by all threads)
 *
 * This routine invokes the actual thread entry point function and passes
 * it three arguments. It also handles graceful termination of the thread
 * if the entry point function ever returns.
 *
 * This routine does not return, and is marked as such so the compiler won't
 * generate preamble code that is only used by functions that actually return.
 */
FUNC_NORETURN void z_thread_entry(k_thread_entry_t entry,
				 void *p1, void *p2, void *p3)
{
#ifdef CONFIG_CURRENT_THREAD_USE_TLS
	z_tls_current = k_sched_current_thread_query();
#endif
#ifdef CONFIG_STACK_CANARIES_TLS
	uintptr_t stack_guard;

	sys_rand_get((uint8_t *)&stack_guard, sizeof(stack_guard));
	__stack_chk_guard = stack_guard;
	__stack_chk_guard <<= 8;
#endif	/* CONFIG_STACK_CANARIES */
#ifdef CONFIG_SKADI_LOADER
		/* stay in scheduler (for now) - re-enable interrupts */
		*skadi_subsystem_mtimer_sched_hook = _skadi_subsystem_yield_stub;
		csr_set(mstatus, MSTATUS_MIE);
		if(!skadi_token_is_in_our_text(entry)){
			/* subsystem call needed, we probably jump into other subsystem */
			skadi_thread_entry_wrapper(p1, p2, p3, entry);
		}
		else{
			entry(p1, p2, p3);
		}
#else
		entry(p1, p2, p3);
#endif

	k_thread_abort(k_current_get());

	/*
	 * Compiler can't tell that k_thread_abort() won't return and issues a
	 * warning unless we tell it that control never gets this far.
	 */

	CODE_UNREACHABLE; /* LCOV_EXCL_LINE */
}

#if defined(CONFIG_SKADI_LOADER) && !defined(SKADI_SUBSYSTEM)

/* not compiled into subsystem - need to manually init the trampolines */
__boot_func static int thread_entry_init_trampolines(void){
    bool init_ok = true;

	init_ok &= SKADI_SUBSYSTEM_INITIALIZE_CALLER_TRAMPOLINE(skadi_thread_entry_wrapper);
    
    return init_ok == true ? 0 : -ENOMEM;
}

SYS_INIT(thread_entry_init_trampolines, POST_KERNEL, 0);

#endif
