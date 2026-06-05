/*
 * Copyright (c) 2018 Linaro Limited
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file
 * @brief File descriptor table
 *
 * This file provides generic file descriptor table implementation, suitable
 * for any I/O object implementing POSIX I/O semantics (i.e. read/write +
 * aux operations).
 */

#include <errno.h>
#include <string.h>

#include <zephyr/posix/fcntl.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/fdtable.h>
#include <zephyr/sys/speculation.h>
#include <zephyr/internal/syscall_handler.h>
#include <zephyr/sys/atomic.h>

#include <zephyr/skadi/skadi_mutex.h>
#include <zephyr/skadi/skadi_condvar.h>
#include <zephyr/skadi/sys/skadi_fdtable.h>

struct stat;

struct fd_entry {
	void *obj;
	const struct fd_op_vtable *vtable;
	atomic_t refcount;
	struct k_mutex *lock;
	struct k_condvar *cond;
	size_t offset;
	uint32_t mode;
};

#if defined(CONFIG_POSIX_DEVICE_IO)
static struct fd_op_vtable stdinout_fd_op_vtable;

BUILD_ASSERT(CONFIG_ZVFS_OPEN_MAX >= 3, "CONFIG_ZVFS_OPEN_MAX >= 3 for CONFIG_POSIX_DEVICE_IO");
#endif /* defined(CONFIG_POSIX_DEVICE_IO) */

static struct fd_entry fdtable[CONFIG_ZVFS_OPEN_MAX] = {
#if defined(CONFIG_POSIX_DEVICE_IO)
	/*
	 * Predefine entries for stdin/stdout/stderr.
	 */
	{
		/* STDIN */
		.vtable = &stdinout_fd_op_vtable,
		.refcount = ATOMIC_INIT(1),
		.lock = NULL,
		.cond = NULL,
	},
	{
		/* STDOUT */
		.vtable = &stdinout_fd_op_vtable,
		.refcount = ATOMIC_INIT(1),
		.lock = NULL,
		.cond = NULL,
	},
	{
		/* STDERR */
		.vtable = &stdinout_fd_op_vtable,
		.refcount = ATOMIC_INIT(1),
		.lock = NULL,
		.cond = NULL,
	},
#else
	{0},
#endif
};

static struct k_mutex *fdtable_lock;

static int z_fd_ref(int fd)
{
	return atomic_inc(&fdtable[fd].refcount) + 1;
}

static int z_fd_unref(int fd)
{
	atomic_val_t old_rc;

	/* Reference counter must be checked to avoid decrement refcount below
	 * zero causing file descriptor leak. Loop statement below executes
	 * atomic decrement if refcount value is grater than zero. Otherwise,
	 * refcount is not going to be written.
	 */
	do {
		old_rc = atomic_get(&fdtable[fd].refcount);
		if (!old_rc) {
			return 0;
		}
	} while (!atomic_cas(&fdtable[fd].refcount, old_rc, old_rc - 1));

	if (old_rc != 1) {
		return old_rc - 1;
	}

	fdtable[fd].obj = NULL;
	fdtable[fd].vtable = NULL;

#ifdef CONFIG_SKADI_OS
	if(fdtable[fd].cond){
		skadi_condvar_cleanup(fdtable[fd].cond);
	}
	if(fdtable[fd].lock){
		skadi_mutex_cleanup(fdtable[fd].lock);
	}
#endif

	return 0;
}

static int _find_fd_entry(void)
{
	int fd;

	for (fd = 0; fd < ARRAY_SIZE(fdtable); fd++) {
		if (!atomic_get(&fdtable[fd].refcount)) {
			return fd;
		}
	}

	errno = ENFILE;
	return -1;
}

static int _check_fd(int fd)
{
	if ((fd < 0) || (fd >= ARRAY_SIZE(fdtable))) {
		errno = EBADF;
		return -1;
	}

	fd = k_array_index_sanitize(fd, ARRAY_SIZE(fdtable));

	if (!atomic_get(&fdtable[fd].refcount)) {
		errno = EBADF;
		return -1;
	}

	return 0;
}

#ifdef CONFIG_ZTEST
bool fdtable_fd_is_initialized(int fd)
{
	struct k_mutex ref_lock;
	struct k_condvar ref_cond;

	if (fd < 0 || fd >= ARRAY_SIZE(fdtable)) {
		return false;
	}

	if(!fdtable[fd].lock || !fdtable[fd].cond){
		return false;
	}

	ref_lock = (struct k_mutex)Z_MUTEX_INITIALIZER(*fdtable[fd].lock);
	if (memcmp(&ref_lock, fdtable[fd].lock, sizeof(ref_lock)) != 0) {
		return false;
	}

	ref_cond = (struct k_condvar)Z_CONDVAR_INITIALIZER(*fdtable[fd].cond);
	if (memcmp(&ref_cond, fdtable[fd].cond, sizeof(ref_cond)) != 0) {
		return false;
	}

	return true;
}
#endif /* CONFIG_ZTEST */

void *zvfs_get_fd_obj(int fd, const struct fd_op_vtable *vtable, int err)
{
	struct fd_entry *entry;

	if (_check_fd(fd) < 0) {
		return NULL;
	}

	entry = &fdtable[fd];

	if ((vtable != NULL) && (entry->vtable != vtable)) {
		errno = err;
		return NULL;
	}

	return entry->obj;
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void*, __skadi_zvfs_get_fd_obj, int fd, const struct fd_op_vtable *vtable, int err)
	return zvfs_get_fd_obj(fd, vtable, err);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zvfs_get_fd_obj)

static int z_get_fd_by_obj_and_vtable(void *obj, const struct fd_op_vtable *vtable)
{
	int fd;

	for (fd = 0; fd < ARRAY_SIZE(fdtable); fd++) {
		if (fdtable[fd].obj == obj && fdtable[fd].vtable == vtable) {
			return fd;
		}
	}

	errno = ENFILE;
	return -1;
}

bool zvfs_get_obj_lock_and_cond(void *obj, const struct fd_op_vtable *vtable, struct k_mutex **lock,
			     struct k_condvar **cond)
{
	int fd;
	struct fd_entry *entry;

	fd = z_get_fd_by_obj_and_vtable(obj, vtable);
	if (_check_fd(fd) < 0) {
		return false;
	}

	entry = &fdtable[fd];

	if (lock) {
		*lock = entry->lock;
	}

	if (cond) {
		*cond = entry->cond;
	}

	return true;
}

void *zvfs_get_fd_obj_and_vtable(int fd, const struct fd_op_vtable **vtable,
			      struct k_mutex **lock)
{
	struct fd_entry *entry;

	if (_check_fd(fd) < 0) {
		return NULL;
	}

	entry = &fdtable[fd];
	*vtable = entry->vtable;

	if (lock != NULL) {
		*lock = entry->lock;
	}

	return entry->obj;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void *, __skadi_zvfs_get_fd_obj_and_vtable, int fd, const struct fd_op_vtable **vtable, struct k_mutex **lock)
	__ASSERT_NO_MSG(vtable);
	__ASSERT_NO_MSG(lock);
	return zvfs_get_fd_obj_and_vtable(fd, vtable, lock);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zvfs_get_fd_obj_and_vtable)

int zvfs_reserve_fd(void)
{
	int fd;

	(void)skadi_mutex_lock(fdtable_lock, K_FOREVER);

	fd = _find_fd_entry();
	if (fd >= 0) {
		/* Mark entry as used, zvfs_finalize_fd() will fill it in. */
		(void)z_fd_ref(fd);
		fdtable[fd].obj = NULL;
		fdtable[fd].vtable = NULL;
		if(!fdtable[fd].lock){
			fdtable[fd].lock = skadi_allocator_alloc_rw(sizeof(*fdtable[fd].lock));
			if(!fdtable[fd].lock){
				return -ENOMEM;
			}
		}
		skadi_mutex_init(fdtable[fd].lock);
		if(!fdtable[fd].cond){
			fdtable[fd].cond = skadi_allocator_alloc_rw(sizeof(*fdtable[fd].cond));
			if(!fdtable[fd].cond){
				return -ENOMEM;
			}
		}
		skadi_condvar_init(fdtable[fd].cond);
	}

	skadi_mutex_unlock(fdtable_lock);

	return fd;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_zvfs_reserve_fd)
	return zvfs_reserve_fd();
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zvfs_reserve_fd)


void zvfs_finalize_typed_fd(int fd, void *obj, const struct fd_op_vtable *vtable, uint32_t mode)
{
	/* Assumes fd was already bounds-checked. */
#ifdef CONFIG_USERSPACE
	/* descriptor context objects are inserted into the table when they
	 * are ready for use. Mark the object as initialized and grant the
	 * caller (and only the caller) access.
	 *
	 * This call is a no-op if obj is invalid or points to something
	 * not a kernel object.
	 */
	k_object_recycle(obj);
#endif
	fdtable[fd].obj = obj;
	fdtable[fd].vtable = vtable;
	fdtable[fd].mode = mode;

	/* Let the object know about the lock just in case it needs it
	 * for something. For BSD sockets, the lock is used with condition
	 * variables to avoid keeping the lock for a long period of time.
	 */
	if (vtable && vtable->ioctl) {
		(void)skadi_zvfs_fdtable_call_ioctl(vtable, obj, ZFD_IOCTL_SET_LOCK, fdtable[fd].lock);
	}
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, __skadi_zvfs_finalize_typed_fd, int fd, void *obj, const struct fd_op_vtable *vtable, uint32_t mode)
	zvfs_finalize_typed_fd(fd, obj, vtable, mode);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zvfs_finalize_typed_fd)


void zvfs_free_fd(int fd)
{
	/* Assumes fd was already bounds-checked. */
	(void)z_fd_unref(fd);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, __skadi_zvfs_free_fd, int fd)
	zvfs_free_fd(fd);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zvfs_free_fd)

int zvfs_alloc_fd(void *obj, const struct fd_op_vtable *vtable)
{
	int fd;

	fd = zvfs_reserve_fd();
	if (fd >= 0) {
		zvfs_finalize_fd(fd, obj, vtable);
	}

	return fd;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_zvfs_alloc_fd, void *obj, const struct fd_op_vtable *vtable)
	return zvfs_alloc_fd(obj, vtable);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zvfs_alloc_fd)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(ssize_t, skadi_fd_read_offset, void *obj, void *buf, size_t sz, size_t offset);

ssize_t zvfs_read(int fd, void *buf, size_t sz)
{
	ssize_t res;

	if (_check_fd(fd) < 0) {
		return -1;
	}

	(void)skadi_mutex_lock(fdtable[fd].lock, K_FOREVER);
	res = skadi_fd_read_offset(fdtable[fd].obj, buf, sz, fdtable[fd].offset, fdtable[fd].vtable->read_offs);
	if (res > 0) {
		switch (fdtable[fd].mode & ZVFS_MODE_IFMT) {
		case ZVFS_MODE_IFDIR:
		case ZVFS_MODE_IFBLK:
		case ZVFS_MODE_IFSHM:
		case ZVFS_MODE_IFREG:
			fdtable[fd].offset += res;
			break;
		default:
			break;
		}
	}
	skadi_mutex_unlock(fdtable[fd].lock);

	return res;
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(ssize_t, __skadi_zvfs_read, int fd, void *buf, size_t sz)
	return zvfs_read(fd, buf, sz);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zvfs_read)


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(ssize_t, skadi_fd_write_offset, void *obj, const void *buf, size_t sz, size_t offset);

ssize_t zvfs_write(int fd, const void *buf, size_t sz)
{
	ssize_t res;

	if (_check_fd(fd) < 0) {
		return -1;
	}

	(void)skadi_mutex_lock(fdtable[fd].lock, K_FOREVER);
	res = skadi_fd_write_offset(fdtable[fd].obj, buf, sz, fdtable[fd].offset, fdtable[fd].vtable->write_offs);
	if (res > 0) {
		switch (fdtable[fd].mode & ZVFS_MODE_IFMT) {
		case ZVFS_MODE_IFDIR:
		case ZVFS_MODE_IFBLK:
		case ZVFS_MODE_IFSHM:
		case ZVFS_MODE_IFREG:
			fdtable[fd].offset += res;
			break;
		default:
			break;
		}
	}
	skadi_mutex_unlock(fdtable[fd].lock);

	return res;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(ssize_t, __skadi_zvfs_write, int fd, const void *buf, size_t sz)
	return zvfs_write(fd, buf, sz);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zvfs_write)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, skadi_fd_close, void *obj);

int zvfs_close(int fd)
{
	int res;

	if (_check_fd(fd) < 0) {
		return -1;
	}

	(void)skadi_mutex_lock(fdtable[fd].lock, K_FOREVER);

	res = skadi_fd_close(fdtable[fd].obj, fdtable[fd].vtable->close);

	skadi_mutex_unlock(fdtable[fd].lock);

	zvfs_free_fd(fd);

	return res;
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_zvfs_close, int fd)
	return zvfs_close(fd);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zvfs_close)

int zvfs_fstat(int fd, struct stat *buf)
{
	if (_check_fd(fd) < 0) {
		return -1;
	}

	return skadi_zvfs_fdtable_call_ioctl(fdtable[fd].vtable, fdtable[fd].obj, ZFD_IOCTL_STAT, buf);
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_zvfs_fstat, int fd, struct stat *buf)
	return zvfs_fstat(fd, buf);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zvfs_fstat)

int zvfs_fsync(int fd)
{
	if (_check_fd(fd) < 0) {
		return -1;
	}

	return skadi_zvfs_fdtable_call_ioctl(fdtable[fd].vtable, fdtable[fd].obj, ZFD_IOCTL_FSYNC);
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_zvfs_fsync, int fd)
	return zvfs_fsync(fd);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zvfs_fsync)


static inline off_t zvfs_lseek_wrap(int fd, int cmd, size_t offset, int whence, size_t fd_offset)
{
	off_t res;

	__ASSERT_NO_MSG(fd < ARRAY_SIZE(fdtable));

	(void)skadi_mutex_lock(fdtable[fd].lock, K_FOREVER);
	
	res = skadi_zvfs_fdtable_call_ioctl(fdtable[fd].vtable, fdtable[fd].obj, cmd, offset, whence, fd_offset);
	
	if (res >= 0) {
		switch (fdtable[fd].mode & ZVFS_MODE_IFMT) {
		case ZVFS_MODE_IFDIR:
		case ZVFS_MODE_IFBLK:
		case ZVFS_MODE_IFSHM:
		case ZVFS_MODE_IFREG:
			fdtable[fd].offset = res;
			break;
		default:
			break;
		}
	}
	skadi_mutex_unlock(fdtable[fd].lock);

	return res;
}

off_t zvfs_lseek(int fd, off_t offset, int whence)
{
	if (_check_fd(fd) < 0) {
		return -1;
	}

	return zvfs_lseek_wrap(fd, ZFD_IOCTL_LSEEK, offset, whence, fdtable[fd].offset);
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(off_t, __skadi_zvfs_lseek, int fd, off_t offset, int whence)
	return zvfs_lseek(fd, offset, whence);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zvfs_lseek)


SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, skadi_zvfs_fcntl, int fd, int cmd, va_list args)
{
	int res;

	if (_check_fd(fd) < 0) {
		return -1;
	}

	/* The rest of commands are per-fd, handled by ioctl vmethod. */
	skadi_subsystem_check_function_pointer(fdtable[fd].vtable->ioctl, false, true);
	res = __skadi_zvfs_fdtable_call_ioctl_valist(fdtable[fd].vtable, fdtable[fd].obj, cmd, args);

	return res;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(skadi_zvfs_fcntl)

static inline int zvfs_ftruncate_wrap(int fd, int cmd, off_t length)
{
	int res;

	__ASSERT_NO_MSG(fd < ARRAY_SIZE(fdtable));

	(void)skadi_mutex_lock(fdtable[fd].lock, K_FOREVER);
	
	res = skadi_zvfs_fdtable_call_ioctl(fdtable[fd].vtable, fdtable[fd].obj, cmd, length);
	
	skadi_mutex_unlock(fdtable[fd].lock);

	return res;
}

int zvfs_ftruncate(int fd, off_t length)
{
	if (_check_fd(fd) < 0) {
		return -1;
	}

	return zvfs_ftruncate_wrap(fd, ZFD_IOCTL_TRUNCATE, length);
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_zvfs_ftruncate, int fd, off_t length)
	return zvfs_ftruncate(fd, length);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zvfs_ftruncate)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_zvfs_ioctl, int fd, unsigned long request, va_list args)
{
	if (_check_fd(fd) < 0) {
		return -1;
	}
	skadi_subsystem_check_function_pointer(fdtable[fd].vtable->ioctl, false, true);
	return __skadi_zvfs_fdtable_call_ioctl_valist(fdtable[fd].vtable, fdtable[fd].obj, request, args);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zvfs_ioctl)


#if defined(CONFIG_POSIX_DEVICE_IO)
/*
 * fd operations for stdio/stdout/stderr
 */

int z_impl_zephyr_write_stdout(const char *buf, int nbytes);

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(ssize_t, stdinout_read_vmeth, void *obj, void *buffer, size_t count)
{
	return 0;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(stdinout_read_vmeth)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(ssize_t, stdinout_write_vmeth, void *obj, const void *buffer, size_t count)
{
#if defined(CONFIG_BOARD_NATIVE_POSIX)
	return zvfs_write(1, buffer, count);
#elif defined(CONFIG_NEWLIB_LIBC) || defined(CONFIG_ARCMWDT_LIBC)
	return z_impl_zephyr_write_stdout(buffer, count);
#else
	return 0;
#endif
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(stdinout_write_vmeth)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, stdinout_ioctl_vmeth, void *obj, unsigned int request, va_list args)
{
	errno = EINVAL;
	return -1;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(stdinout_ioctl_vmeth)


static struct fd_op_vtable stdinout_fd_op_vtable = {
	0x0
};

static bool skadi_fdtable_init(void){

	stdinout_fd_op_vtable.read = SKADI_SUBSYSTEM_FUNCTION_POINTER(stdinout_read_vmeth);
	stdinout_fd_op_vtable.write = SKADI_SUBSYSTEM_FUNCTION_POINTER(stdinout_write_vmeth);
	stdinout_fd_op_vtable.ioctl = SKADI_SUBSYSTEM_FUNCTION_POINTER(stdinout_ioctl_vmeth);

	fdtable_lock = skadi_allocator_alloc_rw(sizeof(*fdtable_lock));

	fdtable[0].vtable = skadi_cap_ops_derive_arg(fdtable[0].vtable, sizeof(fdtable[0].vtable));
	fdtable[1].vtable = skadi_cap_ops_derive_arg(fdtable[1].vtable, sizeof(fdtable[1].vtable));
	fdtable[2].vtable = skadi_cap_ops_derive_arg(fdtable[2].vtable, sizeof(fdtable[1].vtable));

	__ASSERT_NO_MSG(fdtable[0].vtable);
	__ASSERT_NO_MSG(fdtable[1].vtable);
	__ASSERT_NO_MSG(fdtable[2].vtable);

	fdtable[0].lock = skadi_allocator_alloc_rw(sizeof(*fdtable[0].lock));
	fdtable[1].lock = skadi_allocator_alloc_rw(sizeof(*fdtable[1].lock));
	fdtable[2].lock = skadi_allocator_alloc_rw(sizeof(*fdtable[2].lock));

	fdtable[0].cond = skadi_allocator_alloc_rw(sizeof(*fdtable[0].cond));
	fdtable[1].cond = skadi_allocator_alloc_rw(sizeof(*fdtable[1].cond));
	fdtable[2].cond = skadi_allocator_alloc_rw(sizeof(*fdtable[2].cond));

	if(!fdtable_lock || !fdtable[0].lock || !fdtable[1].lock || !fdtable[2].lock || !fdtable[0].cond || !fdtable[1].cond || !fdtable[2].cond || !fdtable[0].vtable || !fdtable[1].vtable || !fdtable[2].vtable){
		__ASSERT(false, "Expected to be able to init locks and condvars!");
		return false;
	}

	skadi_mutex_init(fdtable_lock);
	skadi_mutex_init(fdtable[0].lock);
	skadi_mutex_init(fdtable[1].lock);
	skadi_mutex_init(fdtable[2].lock);

	skadi_condvar_init(fdtable[0].cond);
	skadi_condvar_init(fdtable[1].cond);
	skadi_condvar_init(fdtable[2].cond);

	return true;
}
SKADI_SUBSYSTEM_INIT_FUNCTIONS(skadi_fdtable_init);

#endif /* defined(CONFIG_POSIX_DEVICE_IO) */
