/*
 * Copyright (c) 2024, Tenstorrent AI ULC
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/posix/sys/eventfd.h>
#include <zephyr/zvfs/eventfd.h>
#include <zephyr/skadi/zvfs/skadi_eventfd.h>

int eventfd(unsigned int initval, int flags)
{
	return skadi_zvfs_eventfd(initval, flags);
}

int eventfd_read(int fd, eventfd_t *value)
{
	return skadi_zvfs_eventfd_read(fd, value);
}

int eventfd_write(int fd, eventfd_t value)
{
	return skadi_zvfs_eventfd_write(fd, value);
}
