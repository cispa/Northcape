/*
 * Copyright (c) 2024, Tenstorrent AI ULC
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stddef.h>
#include <stdint.h>

#include <zephyr/posix/poll.h>
#include <zephyr/posix/unistd.h>
#include <zephyr/posix/sys/select.h>
#include <zephyr/posix/sys/socket.h>

#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/net/skadi_socket.h>
#include <zephyr/skadi/sys/skadi_fdtable.h>

/* this is also a function of the POSIX subsystem */
extern int zvfs_open(const char *name, int flags);

int close(int fd)
{
	return skadi_zvfs_close(fd);
}
#ifdef CONFIG_POSIX_DEVICE_IO_ALIAS_CLOSE
FUNC_ALIAS(close, _close, int);
#endif

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_close, int fd)
	return close(fd);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_close)


int open(const char *name, int flags, ...)
{
	/* FIXME: necessarily need to check for O_CREAT and unpack ... if set */
	return zvfs_open(name, flags);
}
#ifdef CONFIG_POSIX_DEVICE_IO_ALIAS_OPEN
FUNC_ALIAS(open, _open, int);
#endif

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_VARIADIC(int, __skadi_open, const char *name, int flags)
	return zvfs_open(name, flags);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_open)

/* TODO this causes a dependency cycle ...*/
int poll(struct pollfd *fds, int nfds, int timeout)
{
	/* TODO: create  zvfs_poll() and dispatch to subsystems based on file type */
	return skadi_zsock_poll(fds, nfds, timeout);
}

ssize_t read(int fd, void *buf, size_t sz)
{
	return skadi_zvfs_read(fd, buf, sz);
}
#ifdef CONFIG_POSIX_DEVICE_IO_ALIAS_READ
FUNC_ALIAS(read, _read, ssize_t);
#endif

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(ssize_t, __skadi_read, int fd, void *buf, size_t sz)
	return read(fd, buf, sz);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_read)

int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout)
{
	/* TODO: create  zvfs_select() and dispatch to subsystems based on file type */
	return skadi_zsock_select(nfds, readfds, writefds, exceptfds, (struct zsock_timeval *)timeout);
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(ssize_t, __skadi_select, int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout)
	return select(nfds, readfds, writefds, exceptfds, timeout);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_select)


ssize_t write(int fd, const void *buf, size_t sz)
{
	return skadi_zvfs_write(fd, buf, sz);
}
#ifdef CONFIG_POSIX_DEVICE_IO_ALIAS_WRITE
FUNC_ALIAS(write, _write, ssize_t);
#endif

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(ssize_t, __skadi_write, int fd, const void *buf, size_t sz)
	return write(fd, buf, sz);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_write)


