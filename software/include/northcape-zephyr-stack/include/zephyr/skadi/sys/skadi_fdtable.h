#ifndef SKADI_FDTABLE_H
#define SKADI_FDTABLE_H

#include <zephyr/sys/fdtable.h>
#include <zephyr/skadi/skadi_subsystem.h>

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void *, __skadi_zvfs_get_fd_obj_and_vtable, int fd, const struct fd_op_vtable **vtable, struct k_mutex **lock);

static inline void * skadi_zvfs_get_fd_obj_and_vtable(int fd, const struct fd_op_vtable **vtable, struct k_mutex **lock){
    void *vtable_ptr, *lock_ptr, *ret;
    vtable_ptr = skadi_cap_ops_derive_arg_wo(vtable, sizeof(*vtable));
    lock_ptr = skadi_cap_ops_derive_arg_wo(lock, sizeof(*lock));

    if(!vtable_ptr || !lock_ptr){
        return NULL;
    }

    ret = __skadi_zvfs_get_fd_obj_and_vtable(fd, vtable_ptr, lock_ptr);

    skadi_cap_ops_drop(vtable_ptr);
    skadi_cap_ops_drop(lock_ptr);

    return ret;    
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_zvfs_free_fd, int fd);

#define skadi_zvfs_free_fd(FD) __skadi_zvfs_free_fd(FD)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_zvfs_finalize_typed_fd, int fd, void *obj, const struct fd_op_vtable *vtable, uint32_t mode);

#define skadi_zvfs_finalize_typed_fd(FD, OBJ, VTABLE, MODE) __skadi_zvfs_finalize_typed_fd(FD, OBJ, VTABLE, MODE)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void*, __skadi_zvfs_get_fd_obj, int fd, const struct fd_op_vtable *vtable, int err);

#define skadi_zvfs_get_fd_obj(FD, VTABLE, ERR) __skadi_zvfs_get_fd_obj(FD, VTABLE, ERR)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zvfs_alloc_fd, void *obj, const struct fd_op_vtable *vtable);

#define skadi_zvfs_alloc_fd(OBJ, VTABLE) __skadi_zvfs_alloc_fd(OBJ, VTABLE)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(ssize_t, __skadi_zvfs_read, int fd, void *buf, size_t sz);

#define skadi_zvfs_read(FD, BUF, SZ) __skadi_zvfs_read(FD, BUF, SZ)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(ssize_t, __skadi_zvfs_write, int fd, const void *buf, size_t sz);

#define skadi_zvfs_write(FD, BUF, SZ) __skadi_zvfs_write(FD, BUF, SZ)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ALLOW_SELF(int, __skadi_zvfs_close, int fd);

#define skadi_zvfs_close(FD) __skadi_zvfs_close(FD)

struct stat;

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zvfs_fstat, int fd, struct stat *buf);

#define skadi_zvfs_fstat(FD, BUF) __skadi_zvfs_fstat(FD, BUF)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zvfs_fsync, int fd);

#define skadi_zvfs_fsync(FD) __skadi_zvfs_fsync(FD)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(off_t, __skadi_zvfs_lseek, int fd, off_t offset, int whence);

#define skadi_zvfs_lseek(FD, OFFSET, WHENCE) __skadi_zvfs_lseek(FD, OFFSET, WHENCE)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zvfs_ftruncate, int fd, off_t length);

#define skadi_zvfs_ftruncate(FD, LENGTH) __skadi_zvfs_ftruncate(FD, LENGTH)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS_VALIST_ALLOW_SELF(int, __skadi_zvfs_fdtable_call_ioctl, SKADI_SUBSYSTEM_REMOVE_PARENTHESIS(obj, request), void *obj, unsigned int request);

#define skadi_zvfs_fdtable_call_ioctl(VTABLE, OBJ, REQUEST, ...) __skadi_zvfs_fdtable_call_ioctl((OBJ), (REQUEST), (void*) (VTABLE)->ioctl  __VA_OPT__(,) __VA_ARGS__)

/* use with extreme caution - need callee-readable valist here! */
#define __skadi_zvfs_fdtable_call_ioctl_valist(VTABLE, OBJ, REQUEST, VA_LIST)                                   \
    CONCAT(__skadi_caller_trampoline_fn_ptr_va_retval_allow_self__, 2, __, __skadi_zvfs_fdtable_call_ioctl) (   \
            (OBJ), (REQUEST), (VA_LIST), (void*) (VTABLE)->ioctl                                                \
    )

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zvfs_reserve_fd);

#define skadi_zvfs_reserve_fd __skadi_zvfs_reserve_fd

/* inlines */
static inline void skadi_zvfs_finalize_fd(int fd, void *obj, const struct fd_op_vtable *vtable)
{
	skadi_zvfs_finalize_typed_fd(fd, obj, vtable, ZVFS_MODE_UNSPEC);
}

#define skadi_fs_dir_t_init(ARG) fs_dir_t_init(ARG)

#endif /* SKADI_FDTABLE_H */
