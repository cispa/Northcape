/*
 * Copyright (c) 2012-2014 Wind River Systems, Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdio.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_benchmark.h>

SKADI_SUBSYSTEM_MAIN(void)
{

	skadi_evaluate_boot_time();

	return 0;
}
SKADI_SUBSYSTEM_MAIN_END
