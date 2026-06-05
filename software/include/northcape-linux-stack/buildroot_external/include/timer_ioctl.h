#ifndef TIMER_IOCTL_H
#define TIMER_IOCTL_H

#define IOCTL_BASE 'W'
#define IOCTL_TO_NS _IOWR(IOCTL_BASE, 1, uint64_t)

#endif
