# pragma once

#ifndef SKADI_OPS_DRIVER_H
#define SKADI_OPS_DRIVER_H
    #include <stdbool.h>
    #include <stdint.h>
    #include <stdatomic.h>
    #include <stddef.h>
    #include <zephyr/arch/cache.h>
    #include <zephyr/sys/atomic.h>

    #include "skadi_ops_constants.h"

    #define DRIVER_LOG_MODULE_NAME skadi_cap_ops_driver
    
    
    static inline uint64_t skadi_encode_restriction(skadi_restriction_t restriction){
        if(restriction.restriction_type == SKADI_RESRICTIONS_DEVICE_INTERPRETED){
            return restriction.restriction_body.device_interpreted;
        }
        return (((uint64_t)restriction.restriction_body.task_id_body.restriction_device) << SKADI_CAP_OPS_RESTRICTION_REGISTER_DEVICE_ID_SHIFT_BITS) | (uint64_t) restriction.restriction_body.task_id_body.restriction_task;
    }


    static inline bool skadi_cap_ops_inspect(const void *input_token_ptr, skadi_inspect_metadata_t *metadata_out);

    static inline size_t skadi_cap_ops_inspect_get_base(const void *input_token_ptr){
        skadi_inspect_metadata_t metadata;
        bool ok;

        ok = skadi_cap_ops_inspect(input_token_ptr, &metadata);
        __ASSERT_NO_MSG(ok);

        return ok ? metadata.capability_base : 0;
    }

    static inline size_t skadi_cap_ops_inspect_get_length(const void *input_token_ptr){
        skadi_inspect_metadata_t metadata;
        bool ok;

        ok = skadi_cap_ops_inspect(input_token_ptr, &metadata);
        __ASSERT_NO_MSG(ok);

        return ok ? metadata.capability_length : 0;
    }

    static inline skadi_task_id_t skadi_cap_ops_inspect_get_tid(const void *input_token_ptr){
        skadi_inspect_metadata_t metadata;
        bool ok;

        ok = skadi_cap_ops_inspect(input_token_ptr, &metadata);
        __ASSERT_NO_MSG(ok);
        __ASSERT_NO_MSG(metadata.restriction_type == SKADI_RESTRICTIONS_SET_TASK_ID);

        return ok ? metadata.restriction_body.task_restriction.restriction_task_id : 0;
    }



    static inline bool skadi_cap_ops_create(const void *input_token_ptr, skadi_restriction_t restriction,
                                                const bool at_end, const uint32_t new_segment_length, skadi_permission_type_t permissions, void **output);
        

    static inline bool skadi_cap_ops_create_simple(const void *input_token_ptr, const bool at_end, const uint32_t new_segment_length, void **output){
        skadi_restriction_t restriction =  SKADI_NO_RESTRICTION;
        return skadi_cap_ops_create(input_token_ptr, restriction, at_end, new_segment_length, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, output);
    }


    static inline bool skadi_cap_ops_derive(const void *input_token_ptr, skadi_restriction_t restriction, const uint32_t new_segment_length, const uint32_t parent_offset,
                                            skadi_permission_type_t permissions, void **output);
    
    static inline bool skadi_cap_ops_derive_min_cap_type(const void *input_token_ptr, skadi_restriction_t restriction, const uint32_t new_segment_length, const uint32_t parent_offset,
    skadi_permission_type_t permissions, skadi_capability_type_t min_type, void **output);


    static inline bool skadi_cap_ops_derive_simple(const void *input_token_ptr, const uint32_t new_segment_length, const uint32_t parent_offset, void **output){
        skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
        return skadi_cap_ops_derive(input_token_ptr, restriction, new_segment_length, parent_offset, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, output);
    }

    static inline void *__skadi_cap_ops_derive_arg(const void* input, const uint32_t length, const char *file, const int line);

    #define skadi_cap_ops_derive_arg(INPUT, LENGTH) __skadi_cap_ops_derive_arg(INPUT, LENGTH, __FILE__, __LINE__)

    static inline void *__skadi_cap_ops_derive_arg_allperm(const void* input, const uint32_t length, const char *file, const int line);

    #define skadi_cap_ops_derive_arg_allperm(INPUT, LENGTH) __skadi_cap_ops_derive_arg_allperm(INPUT, LENGTH, __FILE__, __LINE__)


    /* simplified versions of derive for passing known-size arguments, e.g., from data segment, through subsystem calls */
    static inline void *__skadi_cap_ops_derive_arg_tid(const void* input, const uint32_t length, skadi_task_id_t task_id, const char *file, const int line);

    #define skadi_cap_ops_derive_arg_tid(INPUT, LENGTH, TID) __skadi_cap_ops_derive_arg_tid(INPUT, LENGTH, TID, __FILE__, __LINE__)

    static inline const void *__skadi_cap_ops_derive_arg_ro(const void* input, const uint32_t length, const char *file, const int line);

    #define skadi_cap_ops_derive_arg_ro(INPUT, LENGTH) __skadi_cap_ops_derive_arg_ro(INPUT, LENGTH, __FILE__, __LINE__)

    __attribute__ ((access (write_only, 1))) static inline void *__skadi_cap_ops_derive_arg_wo(void* input, const uint32_t length, const char *file, const int line);

    #define skadi_cap_ops_derive_arg_wo(INPUT, LENGTH) __skadi_cap_ops_derive_arg_wo(INPUT, LENGTH, __FILE__, __LINE__)

    static inline bool skadi_cap_ops_drop(const void *input_token_ptr);
    
    static inline bool skadi_cap_ops_merge_noinspect(const void *input_token_left_ptr, const void *input_token_right_ptr, skadi_restriction_t restriction,
        skadi_permission_type_t permissions, skadi_capability_type_t capability_type, void **output);

    static inline bool skadi_cap_ops_merge(const void *input_token_left_ptr, const void *input_token_right_ptr, skadi_restriction_t restriction,
                                                skadi_permission_type_t permissions, void **output);

    static inline bool skadi_cap_ops_merge_simple(const void *input_token_left_ptr, const void *input_token_right_ptr, void **output){
        skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
        return skadi_cap_ops_merge(input_token_left_ptr, input_token_right_ptr, restriction, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, output);
    }

    static inline bool skadi_cap_ops_clone(const void *input_token_ptr, skadi_restriction_t restriction, skadi_permission_type_t permissions, void **output);

    static inline bool skadi_cap_ops_clone_simple(const void *input_token_ptr, void **output){
        skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
        return skadi_cap_ops_clone(input_token_ptr, restriction, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, output);
    }


    static inline bool skadi_cap_ops_revoke(const void *input_token_ptr, skadi_restriction_t restriction, skadi_permission_type_t permissions, void **output);
    
    static inline bool skadi_cap_ops_revoke_simple(const void *input_token_ptr, void **output){
        skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
        return skadi_cap_ops_revoke(input_token_ptr, restriction, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, output);
    }

    static inline bool skadi_cap_ops_lock(const void *input_token_ptr, skadi_restriction_t restriction, skadi_permission_type_t permissions, void **output);

    static inline bool skadi_cap_ops_lock_simple(const void *input_token_ptr, void **output){
        skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
        return skadi_cap_ops_lock(input_token_ptr, restriction, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, output);
    }

    static inline bool skadi_cap_ops_lock_simple_noirq(const void *input_token_ptr, void **output){
        skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
        return skadi_cap_ops_lock(input_token_ptr, restriction, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, output);
    }

    static inline bool skadi_cap_ops_restrict(const void *input_token_ptr, skadi_restriction_t restriction, const uint32_t segment_length_subtrahend, const uint32_t offset_addend, skadi_permission_type_t permissions);

    static inline bool skadi_cap_ops_sweep(void);

    static inline uint64_t skadi_cap_ops_get_capability_count(void);

    static inline bool skadi_cap_ops_get_northcape_enabled(void);

    static inline void skadi_cap_ops_set_northcape_enabled(void);

    static inline uint64_t skadi_cap_ops_get_trng_bits(void);

    /** 
     * Checks whether calling a function pointer leads to us losing control over the execution 
     * without changing sphere of protection. This would be a security violation.
     */
    static inline bool skadi_subsystem_can_accept_function_pointer(uint64_t function_pointer, const char **reason, uint32_t my_task_id, bool is_irq, bool accept_own_task_id);

    #define SKADI_MB() atomic_thread_fence(memory_order_seq_cst)

#if defined(SKADI_SUBSYSTEM)
    /* statistics - imported from libc */
    extern atomic_t skadi_cycles_create;
    extern atomic_t skadi_cycles_derive;
    extern atomic_t skadi_cycles_drop;
    extern atomic_t skadi_cycles_merge;
    extern atomic_t skadi_cycles_clone;
    extern atomic_t skadi_cycles_revoke;
    extern atomic_t skadi_cycles_lock;
    extern atomic_t skadi_cycles_inspect;
    extern atomic_t skadi_cycles_restrict;
    extern atomic_t skadi_cycles_sweep;

    extern atomic_t skadi_cycles_create_ops;
    extern atomic_t skadi_cycles_derive_ops;
    extern atomic_t skadi_cycles_drop_ops;
    extern atomic_t skadi_cycles_merge_ops;
    extern atomic_t skadi_cycles_clone_ops;
    extern atomic_t skadi_cycles_revoke_ops;
    extern atomic_t skadi_cycles_lock_ops;
    extern atomic_t skadi_cycles_inspect_ops;
    extern atomic_t skadi_cycles_restrict_ops;
    extern atomic_t skadi_cycles_sweep_ops;

    extern atomic_t skadi_failed_occupied_checks_create_ops;
    extern atomic_t skadi_failed_occupied_checks_derive_ops;
    extern atomic_t skadi_failed_occupied_checks_drop_ops;
    extern atomic_t skadi_failed_occupied_checks_merge_ops;
    extern atomic_t skadi_failed_occupied_checks_clone_ops;
    extern atomic_t skadi_failed_occupied_checks_revoke_ops;
    extern atomic_t skadi_failed_occupied_checks_lock_ops;
    extern atomic_t skadi_failed_occupied_checks_inspect_ops;
    extern atomic_t skadi_failed_occupied_checks_restrict_ops;
    extern atomic_t skadi_failed_occupied_checks_sweep_ops;
#endif /* SKADI_SUBSYSTEM */

#ifdef CONFIG_SKADI_OPS_MODULE_CSRS
    #include "ops/skadi_ops_driver_csr.h"
#elif defined(CONFIG_SKADI_OPS_MODULE_MMIO)
    #include "ops/skadi_ops_driver_mmio.h"
#else
    #error Choice for CONFIG_SKADI_OPS_MODULE_ACCESS_MECHANISM missing!
#endif

#endif
