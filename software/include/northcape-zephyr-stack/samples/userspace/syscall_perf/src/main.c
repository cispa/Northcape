/*
 * Copyright (c) 2020 BayLibre, SAS
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/kernel.h>
#include <zephyr/internal/syscall_handler.h>
#include <stdio.h>

#include "thread_def.h"

#include <cv64a6.h>

void z_impl_k_current_cycle_instr_get(unsigned long *cycle_half, unsigned long *instr_half){
	*instr_half = csr_read(0xC02);
	*cycle_half = csr_read(0xC00);
}

static inline void z_vrfy_k_current_cycle_instr_get(unsigned long *cycle_half, unsigned long *instr_half){
	K_OOPS(K_SYSCALL_MEMORY_WRITE(cycle_half, sizeof(*cycle_half)));
	K_OOPS(K_SYSCALL_MEMORY_WRITE(instr_half, sizeof(*instr_half)));
	z_impl_k_current_cycle_instr_get(cycle_half, instr_half);
}
#include <zephyr/syscalls/k_current_cycle_instr_get_mrsh.c>


int main(void)
{
	printf("Main Thread started; %s\n", CONFIG_BOARD);
	/* enable performance counters */
	csr_set(mcounteren, 0x1 | (0x1 << 2));
	csr_set(scounteren, 0x1 | (0x1 << 2));

	/* TODO do not want this to be runnable */
	/*
	k_thread_create(&supervisor_thread, supervisor_stack, THREAD_STACKSIZE,
			supervisor_thread_function, NULL, NULL, NULL,
			-1, K_INHERIT_PERMS, K_NO_WAIT);

	k_sleep(K_MSEC(1000));
	*/

	k_thread_create(&user_thread, user_stack, THREAD_STACKSIZE,
			user_thread_function, NULL, NULL, NULL,
			-1, K_USER | K_INHERIT_PERMS, K_NO_WAIT);

	k_thread_join(&user_thread, K_FOREVER);
	z_cv64a6_finish_test(0);

	return 0;
}
