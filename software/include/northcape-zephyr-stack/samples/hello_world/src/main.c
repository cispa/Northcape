/*
 * Copyright (c) 2012-2014 Wind River Systems, Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdio.h>
#ifdef SKADI_SUBSYSTEM
#include <zephyr/skadi/skadi_subsystem.h>
#endif
#include <zephyr/skadi/skadi_benchmark.h>


#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_MAIN(void)
#else
int main(void)
#endif
{
	skadi_evaluate_boot_time();
	printf("Hello World! %s\n", CONFIG_BOARD_TARGET);

	return 0;
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_MAIN_END
#endif
