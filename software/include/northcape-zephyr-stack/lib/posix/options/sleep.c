/*
 * Copyright (c) 2018 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <errno.h>

#include <zephyr/kernel.h>
#include <zephyr/posix/unistd.h>

#ifdef CONFIG_SKADI_OS
#include <zephyr/skadi/skadi_sched.h>
#endif

/**
 * @brief Sleep for a specified number of seconds.
 *
 * See IEEE 1003.1
 */
unsigned sleep(unsigned int seconds)
{
	int rem;

#ifdef CONFIG_SKADI_OS
	rem = skadi_sleep(K_SECONDS(seconds));
#else
	rem = k_sleep(K_SECONDS(seconds));
#endif
	__ASSERT_NO_MSG(rem >= 0);

	return rem / MSEC_PER_SEC;
}
