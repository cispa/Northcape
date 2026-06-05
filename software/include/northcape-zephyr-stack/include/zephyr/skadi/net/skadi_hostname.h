#ifndef SKADI_HOSTNAME_H
#define SKADI_HOSTNAME_H

#include <zephyr/kernel.h>
#include <zephyr/skadi/skadi_subsystem.h>

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(const char *, skadi_net_hostname_get);

#endif /* SKADI_SUBSYTEM*/

#endif /* SKADI_HOST_NAME_H */
