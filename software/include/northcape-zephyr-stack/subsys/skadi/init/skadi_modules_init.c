#include <zephyr/skadi_subsystems_init.h>

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/skadi/skadi_ariane_genesysii.h>

#include <zephyr/skadi/skadi_init.h>


LOG_MODULE_REGISTER(skadi_submodule_init, CONFIG_SKADI_LOG_LEVEL);

#include <zephyr/init.h>
#include <zephyr/skadi/skadi_subsystem.h>

static sys_dlist_t callback_list = SYS_DLIST_STATIC_INIT(&callback_list);

void skadi_subsystem_init_register_callback(struct skadi_subsystem_init_callback_registration *registration){
    sys_dlist_append(&callback_list, &registration->node);
}

static void skadi_subsystem_loaded(const char *subsystem_name){
    struct skadi_subsystem_init_callback_registration *callback, *tmp;
    SYS_DLIST_FOR_EACH_CONTAINER_SAFE(&callback_list, callback, tmp, node){
        if(!strcmp(subsystem_name, callback->subsys_name)){
            LOG_DBG("Invoking callback %p for subsystem %s!", callback, subsystem_name);
            callback->callback(callback);
            sys_dlist_remove(&callback->node); /* cannot match multiple - remove for speed */
        }
    }
}

#ifndef CONFIG_SKADI_LOADER_INLINE
    /* load next subsystem. Return positive value to continue. */
    extern int skadi_init_load_next_subsystem(void (*skadi_subsystem_loaded)(const char *subsystem_name));
#endif

#ifdef CONFIG_PROFILING_PERF
extern void skadi_loader_provide_perf_metadata(void);
#endif

__boot_func static int skadi_init_modules(void){
    LOG_INF("Memory information:\nDRAM base: %"PRIx64"\nDRAM size: %"PRIx64"\nReserved base: %"PRIx64"\nReserved size: %"PRIx64, (uint64_t)SKADI_ARIANE_DRAM_BASE_BYTES, (uint64_t)SKADI_ARIANE_DRAM_LENGTH_BYTES, (uint64_t)SKADI_ARIANE_RESERVED_BASE_BYTES, (uint64_t)SKADI_ARIANE_RESERVED_LENGTH_BYTES);
#ifdef CONFIG_SKADI_LOADER_INLINE
    if(skadi_init_load_subsystems_in_order() == false){
        LOG_ERR("Could not load subsystems!");
        k_panic();
    }
#else
    while(skadi_init_load_next_subsystem(skadi_subsystem_loaded) > 0);
#endif /* CONFIG_SKADI_LOADER_INLINE */

    if(IS_ENABLED(CONFIG_SKADI_LOADER_PRINT_SECT_SIZES)){
        skadi_loader_print_memory_summary();
    }
#ifdef CONFIG_PROFILING_PERF
    skadi_loader_provide_perf_metadata();
#endif
    return 0;
}

SYS_INIT(skadi_init_modules, PRE_KERNEL_1, CONFIG_SKADI_MODULES_INIT_PRIO);
