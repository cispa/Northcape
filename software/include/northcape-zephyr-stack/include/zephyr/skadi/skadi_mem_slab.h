#ifndef SKADI_MEM_SLAB_H
#define SKADI_MEM_SLAB_H

#include <zephyr/kernel.h>
#include <zephyr/skadi/skadi_subsystem.h>


#ifdef SKADI_SUBSYSTEM
/* in the loader, use the z_impl_* variants directly */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mem_slab_alloc, struct k_mem_slab *slab, void **mem, k_timeout_t timeout);

static inline int skadi_mem_slab_alloc(struct k_mem_slab *slab, void **mem, k_timeout_t timeout){
    int ret;
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wmaybe-uninitialized"
    void *mem_wrapper = skadi_cap_ops_derive_arg(mem, sizeof(*mem));
#pragma GCC diagnostic pop
    __ASSERT_NO_MSG(mem_wrapper);

    ret = __skadi_mem_slab_alloc(slab, mem_wrapper, timeout);

    skadi_cap_ops_drop(mem_wrapper);

    return ret;
}

/* alternative slab allocator - directly returns result or NULL */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void *, __skadi_mem_slab_alloc_alt, struct k_mem_slab *slab, k_timeout_t timeout);

static inline void* skadi_mem_slab_alloc_alt(struct k_mem_slab *slab, k_timeout_t timeout){
    __ASSERT_NO_MSG(slab);

    return __skadi_mem_slab_alloc_alt(slab, timeout);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mem_slab_free, struct k_mem_slab *slab, void *mem);

static inline void skadi_mem_slab_free(struct k_mem_slab *slab, void *mem){

    __ASSERT_NO_MSG(slab);

    __skadi_mem_slab_free(slab, mem);
}

/* static initialization of blocks DOES NOT CURRENTLY WORK PROPERLY in Skadi subsystems due to separation declaration/initialization across subsystems */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mem_slab_init, struct k_mem_slab *slab, void *buffer, size_t block_size, uint32_t num_blocks);

static inline int skadi_mem_slab_init(struct k_mem_slab *slab, void *buffer, size_t block_size, uint32_t num_blocks){
    void *buffer_wrapper = skadi_cap_ops_derive_arg(buffer, num_blocks * WB_UP(block_size));

    __ASSERT_NO_MSG(buffer_wrapper);

    return __skadi_mem_slab_init(slab, buffer_wrapper, block_size, num_blocks);
}

/* static inlines */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint32_t, __skadi_mem_slab_num_free_get, struct k_mem_slab *slab);
#define skadi_mem_slab_num_free_get(ARG) __skadi_mem_slab_num_free_get(ARG)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mem_slab_cleanup, struct k_mem_slab *slab);

static inline void skadi_mem_slab_cleanup(struct k_mem_slab *slab){
    /* TODO cleanup buffer */
    __skadi_mem_slab_cleanup(slab);
}

#endif /* SKADI_SUBSYSTEM */


#endif /* SKADI_MEM_SLAB_H */
