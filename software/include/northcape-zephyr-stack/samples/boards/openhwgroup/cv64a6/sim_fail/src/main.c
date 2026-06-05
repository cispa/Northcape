/*
 * Copyright (c) 2012-2014 Wind River Systems, Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include <cv64a6.h>
#include <stdio.h>

#include <zephyr/skadi/skadi_subsystem.h>



SKADI_SUBSYSTEM_MAIN(void)
{
	printf("I'm a goner! %s\n", CONFIG_BOARD_TARGET);

	z_cv64a6_finish_test(0xdead);

	return 0;
}
SKADI_SUBSYSTEM_MAIN_END
