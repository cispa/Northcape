#ifndef SKADI_STDLIB_H
#define SKADI_STDLIB_H

#include <stdlib.h>
#include <zephyr/skadi/skadi_subsystem.h>

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_exit, int fd);

static inline int _skadi_exit(int fd){
    return __skadi_exit(fd);
}

#define skadi_exit(FD) _skadi_exit(FD)

#endif /* SKADI_STDLIB_H */
