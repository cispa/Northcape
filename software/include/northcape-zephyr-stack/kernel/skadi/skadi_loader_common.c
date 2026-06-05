#include <zephyr/skadi/skadi_init_alloc.h>
#include <zephyr/skadi/skadi_loader.h>
#include <zephyr/skadi/skadi_ops_driver.h>
#include <zephyr/skadi/skadi_subsystem.h>

#include <zephyr/skadi/skadi_ariane_genesysii.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(skadi_loader_common, CONFIG_SKADI_LOG_LEVEL);

struct skadi_loader_cached_mmio_dev {
    sys_dlist_t list;

    long mmio_base;
    long mmio_size;

    void *cached_capability;
};

static sys_dlist_t skadi_loader_cached_mmio_dev_list = SYS_DLIST_STATIC_INIT(&skadi_loader_cached_mmio_dev_list);


static struct skadi_loader_cached_mmio_dev *find_cached_mmio_device(long mmio_base){
    struct skadi_loader_cached_mmio_dev *ret = NULL;


    SYS_DLIST_FOR_EACH_CONTAINER(&skadi_loader_cached_mmio_dev_list, ret, list){
        if(ret->mmio_base == mmio_base){
            return ret;
        }
    }

    return NULL;
}

void skadi_loader_cleanup_mmio_device_list(void){
    struct skadi_loader_cached_mmio_dev *to_del, *tmp;
    SYS_DLIST_FOR_EACH_CONTAINER_SAFE(&skadi_loader_cached_mmio_dev_list, to_del, tmp, list){
        sys_dlist_remove(&to_del->list);
        skadi_init_alloc_free(to_del);
    }
}

/* from skadi_init.c */
extern void (***skadi_subsystem_mtimer_sched_hook_loader)(void);

#if defined(CONFIG_SOC_SERIES_CV64A6_PROVIDE_TEST_POWEROFF)
// defined in soc_poweroff.c
extern volatile int tohost;
static volatile int *tohost_capability = NULL;
static void* handle_tohost(void){
    if(!tohost_capability){
        tohost_capability = skadi_cap_ops_derive_arg_wo((void*)&tohost, sizeof(tohost));
    }

    __ASSERT_NO_MSG(tohost_capability);

    if(!tohost_capability){
        LOG_ERR("Could not derive for tohost!");
        return 0;
    }

    LOG_DBG("Returning capability %p for tohost!", (void*)tohost_capability);
    
    return (void*)tohost_capability;
}
#else
static void* handle_tohost(void){
    LOG_ERR("CONFIG_SOC_SERIES_CV64A6_PROVIDE_TEST_POWEROFF disabled - tohost not resolved!");
    return NULL;
}
#endif

#if defined(CONFIG_SKADI_LIBRARY_LOCAL_CLOCK)
static const uint64_t *mtime_capability = NULL;

#define DT_DRV_COMPAT sifive_clint0
static void* handle_mtime(void){
    uint64_t *mtime_reg = (uint64_t*)(uintptr_t)(DT_INST_REG_ADDR(0) + 0xbff8U);

    BUILD_ASSERT(DT_HAS_COMPAT_STATUS_OKAY(sifive_clint0));

    if(!mtime_capability){
        mtime_capability = skadi_cap_ops_derive_arg_ro(mtime_reg, sizeof(*mtime_reg));
    }

    __ASSERT_NO_MSG(mtime_capability);

    if(!mtime_capability){
        LOG_ERR("Could not derive mtime reg!");
    }

    LOG_INF("Returning capability %p for mtime reg at %p!", mtime_capability, mtime_reg);

    return (void*)mtime_capability;
}
#else
static void* handle_mtime(void){
    LOG_ERR("CONFIG_SKADI_LIBRARY_LOCAL_CLOCK disabled - mtime not resolved!");
    return NULL;
}
#endif
extern uint64_t z_start_time;
void *skadi_resolve_special_symbol(const char *symbol_name, const char *ext_name, skadi_task_id_t skadi_loader_current_subsystem_id){
    int  reg_index;
    long mmio_base, mmio_size;
    bool skadi_loader_current_subsystem_is_libc = strcmp("libc", ext_name)==0;

    /* ext->name has not yet been set */
    if(strcmp(ext_name,"allocator") == 0){
        
        if(strcmp(symbol_name, "__skadi_allocator_arena_start") == 0){
            void *symbol_addr = skadi_cap_ops_derive_arg_tid(&__skadi_allocator_arena_start, sizeof(__skadi_allocator_arena_start), skadi_loader_current_subsystem_id);
            LOG_INF("Resolved special symbol __skadi_allocator_arena_start for subsystem allocator to %p!", symbol_addr);
            __ASSERT_NO_MSG(symbol_addr);
            return symbol_addr;
        }

        if(strcmp(symbol_name, "__skadi_allocator_arena") == 0){
            void *symbol_addr = skadi_cap_ops_derive_arg_tid(&__skadi_allocator_arena, sizeof(__skadi_allocator_arena), skadi_loader_current_subsystem_id);
            LOG_INF("Resolved special symbol __skadi_allocator_arena for subsystem allocator to %p!", symbol_addr);
            __ASSERT_NO_MSG(symbol_addr);
            return symbol_addr;
        }

        if(strcmp(symbol_name, "__skadi_allocator_arena_size_bytes") == 0){
            void *symbol_addr = skadi_cap_ops_derive_arg_tid(&__skadi_allocator_arena_size_bytes, sizeof(__skadi_allocator_arena_size_bytes), skadi_loader_current_subsystem_id);
            LOG_INF("Resolved special symbol __skadi_allocator_arena_size_bytes for subsystem allocator to %p!", symbol_addr);
            __ASSERT_NO_MSG(symbol_addr);
            return symbol_addr;
        }
    }

    if(sscanf(symbol_name, "__skadi_mmio_%u_%lu_%lu", &reg_index, &mmio_base, &mmio_size) == 3){
        void *symbol_addr;
        const struct skadi_loader_cached_mmio_dev *cached_dev = find_cached_mmio_device(mmio_base);
        struct skadi_loader_cached_mmio_dev *new_dev;
        const size_t ops_base = DT_REG_ADDR(DT_COMPAT_GET_ANY_STATUS_OKAY(northcape_ops_module_1_0_0));
        const size_t ops_size = DT_REG_SIZE(DT_COMPAT_GET_ANY_STATUS_OKAY(northcape_ops_module_1_0_0));

        __ASSERT(!cached_dev || cached_dev->mmio_size == mmio_size, "Cached MMIO size %ld does not match requested MMIO size %ld!", cached_dev->mmio_size, mmio_size);

        if(mmio_base >= SKADI_ARIANE_DRAM_BASE_BYTES || mmio_size >= SKADI_ARIANE_DRAM_BASE_BYTES || mmio_base + mmio_size >= SKADI_ARIANE_DRAM_BASE_BYTES){
            LOG_ERR("Found special MMIO symbol %s and parsed register index %u MMIO base %lx MMIO size %lx, task ID %"PRIu32" but this is outside MMIO range!", symbol_name, reg_index, mmio_base, mmio_size, skadi_loader_current_subsystem_id);
            return 0;
        }

        if(cached_dev){
            symbol_addr = cached_dev->cached_capability;

            LOG_DBG("Found CACHED special MMIO symbol %s - resolved register index %u MMIO base %lx MMIO size %lx to capability %p", symbol_name, reg_index, mmio_base, mmio_size, symbol_addr);

            return symbol_addr;
        }
        /* TODO clean this up */
        new_dev = (void*)skadi_init_alloc_allocate(sizeof(*new_dev), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, true);

        __ASSERT_NO_MSG(new_dev);

        if(!new_dev){
            return 0;
        }

        if((mmio_base >= ops_base && mmio_base < ops_base + ops_size) || (ops_base <= mmio_base && ops_base + ops_size >= mmio_base)){
            bool derive_ok;
            skadi_restriction_t no_restriction = SKADI_NO_RESTRICTION;
            skadi_restriction_t task_restriction = SKADI_TASK_ID_BOUND_RESTRICTION(skadi_loader_current_subsystem_id, SKADI_DEVICE_ID_CPU);
            skadi_restriction_t restriction_to_use;

            if(IS_ENABLED(CONFIG_SKADI_LIBC_HAS_NO_TID_PROTECTION) && skadi_loader_current_subsystem_is_libc){
                restriction_to_use = no_restriction;
            }
            else{
                restriction_to_use = task_restriction;
            }

            LOG_INF("Relocating operations module - making inaccessible in IRQ!");

            derive_ok = skadi_cap_ops_derive((void*) ops_base, restriction_to_use, ops_size, ops_base, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, &symbol_addr);

            __ASSERT_NO_MSG(derive_ok);
            if(!derive_ok){
                LOG_ERR("Could not derive ops!");
                return 0;
            }

        }
        else{

            if(IS_ENABLED(CONFIG_SKADI_LIBC_HAS_NO_TID_PROTECTION) && skadi_loader_current_subsystem_is_libc){
                /* the libc subsystem can only request the ops module, and because it may be called with different task IDs, the token for the ops module needs to be unrestricted */
                symbol_addr = skadi_cap_ops_derive_arg((void*)mmio_base, mmio_size);
            }
            else{
                symbol_addr = skadi_cap_ops_derive_arg_tid((void*)mmio_base, mmio_size, skadi_loader_current_subsystem_id);
            }
        }

        new_dev->mmio_base = mmio_base;
        new_dev->mmio_size = mmio_size;
        new_dev->cached_capability = symbol_addr;

        sys_dlist_append(&skadi_loader_cached_mmio_dev_list, &new_dev->list);

        LOG_INF("Found special MMIO symbol %s - resolved register index %u MMIO base %lx MMIO size %lx to capability %p", symbol_name, reg_index, mmio_base, mmio_size, symbol_addr);

        __ASSERT_NO_MSG(symbol_addr);

        return  symbol_addr;

    }

    if(strcmp(symbol_name, "skadi_subsystem_mtimer_sched_hook") == 0){
        void *symbol_addr;

        LOG_DBG("Found special sched hook symbol %s!", symbol_name);
        symbol_addr = skadi_subsystem_mtimer_sched_hook_loader;

        __ASSERT_NO_MSG(symbol_addr);
        
        return  symbol_addr;
    }

    if(strcmp(symbol_name, "tohost") == 0){
        LOG_DBG("Found special tohost symbol for termination!");
        return handle_tohost();
    }

    if(strcmp(symbol_name, "__skadi_subsystem_mtime_reg_capability") == 0){
        LOG_INF("Found special symbol for mtime reg!");
        return handle_mtime();
    }

    if(strcmp(symbol_name, "__skadi_boot_time") == 0){
        LOG_INF("Found special symbol for boot time!");
        return (void*)(uintptr_t)z_start_time;
    }


    LOG_DBG("Could not find special symbol %s for subsystem %s!", symbol_name, ext_name);
    return 0;
}
