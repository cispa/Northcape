#ifndef SKADI_HEAP_H
#define SKADI_HEAP_H

#include <zephyr/kernel.h>
#include <zephyr/skadi/skadi_subsystem.h>


#ifdef SKADI_SUBSYSTEM
/* in the loader, use the z_impl_* variants directly */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_heap_init, struct k_heap *h, void *mem, size_t bytes);

static inline void skadi_heap_init(struct k_heap *h, void *mem, size_t bytes){
    void *mem_wrapper = skadi_cap_ops_derive_arg(mem, bytes);

    __ASSERT_NO_MSG(h);

    __ASSERT_NO_MSG(mem_wrapper);

    __skadi_heap_init(h, mem_wrapper, bytes);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void *, __skadi_heap_aligned_alloc, struct k_heap *h, size_t align, size_t bytes, k_timeout_t timeout);

static inline void *skadi_heap_aligned_alloc(struct k_heap *h, size_t align, size_t bytes, k_timeout_t timeout){
    __ASSERT_NO_MSG(h);

    return __skadi_heap_aligned_alloc(h, align, bytes, timeout);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void *, __skadi_heap_alloc, struct k_heap *h, size_t bytes, k_timeout_t timeout);

static inline void *skadi_heap_alloc(struct k_heap *h,  size_t bytes, k_timeout_t timeout){
    __ASSERT_NO_MSG(h);

    return __skadi_heap_alloc(h, bytes, timeout);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void *, __skadi_heap_realloc, struct k_heap *h, void *ptr, size_t bytes, k_timeout_t timeout);

static inline void *skadi_heap_realloc(struct k_heap *h,  void *ptr, size_t bytes, k_timeout_t timeout){
    __ASSERT_NO_MSG(h);

    return __skadi_heap_realloc(h, ptr, bytes, timeout);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_heap_free, struct k_heap *h, void *mem);

static inline void skadi_heap_free(struct k_heap *h, void *mem){
    __ASSERT_NO_MSG(h);

    return __skadi_heap_free(h, mem);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_heap_cleanup, struct k_heap *h);

#define skadi_heap_cleanup(heap) __skadi_heap_cleanup(heap)


#endif /* SKADI_SUBSYSTEM */


#endif /* SKADI_HEAP_H */
