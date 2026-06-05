#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_ariane_genesysii.h>


#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(skadi_nuuk, CONFIG_SKADI_LOG_LEVEL);

extern FUNC_NORETURN void nuuk_final_jump(uintptr_t where);

static inline FUNC_NORETURN void nuuk(uintptr_t return_address){
    bool success;
    void* output_cap;
#ifndef CONFIG_SKADI_DEBUG_UNRESTRICTED_ROOT_CAP
    /* at this point, it IS already restricted */
    skadi_restriction_t loader_restriction = SKADI_NO_RESTRICTION;
#endif

    LOG_INF("Nuuk destroying root capability!");

    /* capability covers loader's private memory area, leaving MMIO untouched; relies on "partial create" exception */

    success = skadi_cap_ops_create_simple(SKADI_ROOT_CAP_TOKEN, 1, SKADI_ARIANE_RESERVED_BASE_BYTES - SKADI_ARIANE_DRAM_BASE_BYTES, &output_cap);
    
    __ASSERT(success, "Failed to create capability for loader's memory!");

    if(success){
        LOG_INF("Revoking loader's memory!");

        /* primary purpose is to zero-out the memory using HW support */
        success = skadi_cap_ops_revoke_simple(output_cap, &output_cap);

        __ASSERT(success, "Failed to revoke capability for loader's memory!");

        if(success){
            __skadi_allocator_add_heap((uintptr_t)output_cap);
        }
    }

#ifndef CONFIG_SKADI_DEBUG_UNRESTRICTED_ROOT_CAP
    LOG_INF("Dropping ALL permissions from root capability!");

    /* capability can be accessed indirectly through the MMIO capabilities, if any */
    success = skadi_cap_ops_restrict(SKADI_ROOT_CAP_TOKEN, loader_restriction, 0, 0, 0);
#else
    LOG_WRN("Unrestricted root capability enabled - retaining permissions!");
#endif

    LOG_INF("Final jump from nuuk!");

    nuuk_final_jump(return_address);
}

/* despite nuuk and loader being in the same subsystem ID, we need to wrap this into a subsystem call such that we do not share the stack */
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ_ALLOW_SELF(void, __skadi_nuuk, uintptr_t return_address)
    nuuk(return_address);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_nuuk)
