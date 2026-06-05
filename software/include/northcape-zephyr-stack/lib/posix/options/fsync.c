/*
 * Copyright (c) 2024 Tenstorrent AI ULC
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/posix/unistd.h>

#ifdef CONFIG_SKADI_OS
#include <zephyr/skadi/sys/skadi_fdtable.h>
#else
/* prototypes for external, not-yet-public, functions in fdtable.c */
int zvfs_fsync(int fd);
#endif

int fsync(int fd)
{

#ifdef CONFIG_SKADI_OS
	return skadi_zvfs_fsync(fd);
#else
	return zvfs_fsync(fd);
#endif
}
#ifdef CONFIG_POSIX_FILE_SYSTEM_ALIAS_FSYNC
FUNC_ALIAS(fsync, _fsync, int);
#endif

#ifdef CONFIG_POSIX_SYNCHRONIZED_IO
int fdatasync(int fd)
{
	return fsync(fd);
}
#endif /* CONFIG_POSIX_SYNCHRONIZED_IO */
