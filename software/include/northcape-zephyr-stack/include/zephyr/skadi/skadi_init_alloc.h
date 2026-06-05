#ifndef SKADI_INIT_ALLOC_H
#define SKADI_INIT_ALLOC_H

    #include <stdint.h>
    #include <zephyr/llext/llext.h>

    #include "skadi_ops_constants.h"

    struct skadi_init_alloc_chunk {
        void *capability_token;
        uintptr_t segment_base;
        uint32_t segment_length;
    };

    struct __attribute__((aligned(8))) skadi_init_alloc_list_entry {
        sys_snode_t node;
        struct skadi_init_alloc_chunk chunk;
    };

    void skadi_init_alloc_set_heap(void* private_heap);
    
    void skadi_init_alloc_free(void* capability);

    void skadi_init_alloc_free_indirect(void* capability);

    void*  __attribute__ ((alloc_size (1))) __attribute__ ((malloc, malloc (skadi_init_alloc_free, 1))) skadi_init_alloc_allocate(uint32_t requested_size, skadi_permission_type_t permissions, bool is_restricted_to_loader);

    void*  __attribute__ ((alloc_size (1))) __attribute__ ((malloc, malloc (skadi_init_alloc_free, 1))) skadi_init_alloc_allocate_task_id(uint32_t requested_size, skadi_permission_type_t permissions, bool is_restricted, skadi_task_id_t task_id);

    void*  __attribute__ ((alloc_size (1))) __attribute__ ((malloc, malloc (skadi_init_alloc_free, 1))) skadi_init_alloc_allocate_task_id_aligned(uint32_t requested_size, skadi_permission_type_t permissions, bool is_restricted, skadi_task_id_t task_id, size_t alignment);

    void*  __attribute__ ((alloc_size (1))) __attribute__ ((malloc, malloc (skadi_init_alloc_free, 1))) skadi_init_alloc_allocate_aligned(uint32_t requested_size, skadi_permission_type_t permissions, bool is_restricted_to_loader, size_t alignment);

    void*  __attribute__ ((alloc_size (1))) __attribute__ ((malloc, malloc (skadi_init_alloc_free, 1))) skadi_init_alloc_allocate_aligned_indirect(uint32_t requested_size, skadi_permission_type_t permissions, bool is_restricted_to_loader, size_t alignment);

    void __attribute__ ((malloc, malloc (skadi_init_alloc_free, 1))) *skadi_init_alloc_allocate_section(uintptr_t sect_size, enum llext_mem mem_idx);

    uint8_t* __attribute__ ((malloc, malloc (skadi_init_alloc_free, 1))) skadi_init_alloc_allocate_subsystem_stack(struct skadi_subsystem_stack ** allocator_out, void **lock_holder_out, skadi_task_id_t current_task_id);
#ifdef CONFIG_SKADI_LOADER
    void skadi_init_alloc_relese_unused_heap(void);
#endif /* CONFIG_SKADI_LOADER */

#endif
