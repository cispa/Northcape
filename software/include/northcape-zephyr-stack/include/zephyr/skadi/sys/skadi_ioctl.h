#ifndef SKADI_IOCTL_H
#define SKADI_IOCTL_H

#include <zephyr/posix/sys/ioctl.h>
#include <zephyr/skadi/skadi_subsystem.h>

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VALIST(int, skadi_zvfs_ioctl, SKADI_SUBSYSTEM_REMOVE_PARENTHESIS(fd, request), int fd, long request);

#define skadi_ioctl(FD, REQUEST, ...) skadi_zvfs_ioctl(FD, REQUEST __VA_OPT__(,) __VA_ARGS__)


#endif /* SKADI_IOCTL_H */
