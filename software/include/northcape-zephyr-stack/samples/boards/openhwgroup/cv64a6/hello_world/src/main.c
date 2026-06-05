/*
 * Copyright (c) 2012-2014 Wind River Systems, Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdio.h>
#include <zephyr/skadi/skadi_subsystem.h>

SKADI_SUBSYSTEM_MAIN(void)
{
	printf("Hello World! %s\n", CONFIG_BOARD_TARGET);

	return 0;
}
SKADI_SUBSYSTEM_MAIN_END
