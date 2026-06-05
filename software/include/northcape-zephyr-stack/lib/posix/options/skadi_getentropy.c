/*
 * Copyright (c) 2024 Google LLC
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <errno.h>

#include <zephyr/drivers/entropy.h>
#include <zephyr/kernel.h>
#include <zephyr/posix/unistd.h>

#include <zephyr/skadi/random/skadi_random.h>

int getentropy(void *buffer, size_t length)
{
	skadi_sys_csrand_get(buffer, length);
	return 0;	
}
