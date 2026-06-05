#ifndef SKADI_INIT_H
#define SKADI_INIT_H

#include <stdbool.h>
#include <zephyr/sys/dlist.h>

struct skadi_subsystem_init_callback_registration;

typedef void (*subsys_init_cb_t)(const struct skadi_subsystem_init_callback_registration *registration);

struct skadi_subsystem_init_callback_registration {
    sys_dnode_t node;
    const char *subsys_name;
    subsys_init_cb_t callback;
    void *user_data;
};

extern void skadi_subsystem_init_register_callback(struct skadi_subsystem_init_callback_registration *registration);


#endif
