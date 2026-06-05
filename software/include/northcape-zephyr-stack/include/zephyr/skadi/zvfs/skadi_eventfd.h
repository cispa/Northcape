#ifndef SKADI_EVENTFD_H
#define SKADI_EVENTFD_H

#include <zephyr/zvfs/eventfd.h>
#include <zephyr/skadi/skadi_subsystem.h>

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zvfs_eventfd, unsigned int initval, int flags);

#define skadi_zvfs_eventfd(INITVAL, FLAGS) __skadi_zvfs_eventfd(INITVAL, FLAGS)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zvfs_eventfd_read, int fd, zvfs_eventfd_t *value);

static inline int skadi_zvfs_eventfd_read(int fd, zvfs_eventfd_t *value){
    zvfs_eventfd_t *value_clone = skadi_cap_ops_derive_arg_wo(value, sizeof(*value));
    int ret;

    __ASSERT_NO_MSG(value_clone);

    if(!value_clone){
        return -ENOMEM;
    }

    ret = __skadi_zvfs_eventfd_read(fd, value_clone);

    skadi_cap_ops_drop(value_clone);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zvfs_eventfd_write, int fd, zvfs_eventfd_t value);

#define skadi_zvfs_eventfd_write(FD, VALUE) __skadi_zvfs_eventfd_write(FD, VALUE)

#endif /* SKADI_EVENTFD_H */
