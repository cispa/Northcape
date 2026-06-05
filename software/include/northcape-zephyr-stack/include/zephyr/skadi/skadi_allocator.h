#ifndef SKADI_ALLOCATOR_H
#define SKADI_ALLOCATOR_H

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include <zephyr/sys/byteorder.h>

#include "skadi_ops_constants.h"
#include "skadi_ops_driver.h"
#include "skadi_subsystem.h"
#include "skadi_init_alloc.h"

/* these are found via their well-known names */
extern void *__skadi_allocator_arena;
extern uintptr_t __skadi_allocator_arena_start;
extern uint32_t __skadi_allocator_arena_size_bytes;

#ifdef CONFIG_SKADI_LIBC_INLINE
#define skadi_allocator_local_memzero(CAP, SIZE) memset(CAP, 0, SIZE)
#else
// we have to do this inline - memset assumes cacheable if no inlined libc!
static inline void skadi_allocator_local_memzero(volatile void *capability, size_t size){
    volatile uint8_t *iterator = capability;
    volatile uint64_t *iterator_u64 = capability;

    if(capability){
        /* base alignment to 64-bit is guaranteed, length is not */
        while(size > sizeof(uint64_t)){
            *iterator_u64++ = 0;
            size -= sizeof(uint64_t);
        }
        iterator = (uint8_t*)iterator_u64;
        for(size_t i = 0; i < size; i++){
            *iterator++ = 0;
        }
    }
}
#endif


#if (defined(SKADI_SUBSYSTEM)) && !defined(SKADI_SUBSYSTEM_ALLOCATOR)

/* this allocator is not suitable for use in the loader! */


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void *, __skadi_allocator_alloc, uint32_t requested_size, uint32_t align, skadi_permission_type_t permissions);
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(bool, __skadi_allocator_free, void *token);

static inline void *skadi_allocator_alloc_wrapper(uint32_t requested_size, uint32_t align, skadi_permission_type_t permissions){
    /* need to actively insist on lockable */
    void **ret = __skadi_allocator_alloc(requested_size + sizeof(void*), align, permissions | SKADI_PERMISSION_LOCKABLE);
    void *ret_locked;
    uint8_t *ret_bytes = (void*)ret;
    bool lock_ok;
    uint64_t ret_num = (uintptr_t)(void*)ret;

    skadi_restriction_t restriction = SKADI_TASK_ID_BOUND_RESTRICTION(SKADI_CURRENT_TASK_ID, SKADI_DEVICE_ID_CPU);

    __ASSERT_NO_MSG(permissions & SKADI_PERMISSION_WRITE);
    /* 
     * for faster de-allocation
     * pick any byte order to remain functional independent of system byte order
     * also, unaligned stores - size could be anything
     */
    ret_num = sys_cpu_to_le64(ret_num);
    for(int i = requested_size; i < requested_size + sizeof(void*); i++){
        ret_bytes[i] = (ret_num >> (i-requested_size)*8) & 0xff;
    }
    /* untrusted allocator - gain exclusive access */
    lock_ok = skadi_cap_ops_lock(ret, restriction, permissions, &ret_locked);
    __ASSERT_NO_MSG(lock_ok);
    if(!lock_ok){
        __skadi_allocator_free(ret);
        return NULL;
    }
    return ret_locked;
}

static bool skadi_allocator_free_wrapper(void *token, uint32_t capability_length){
    bool ret;
    void *original_token;
    const uint8_t* alloc_mem;
    uintptr_t original_token_num = 0;
    /* assume original token is at beginning of segment */
    alloc_mem  = ((uint8_t*)token - skadi_get_capability_offset(token));
    
    for(int i = 0; i < sizeof(void*); i++){
        original_token_num |= ((uintptr_t)alloc_mem[capability_length - sizeof(void*) + i])<<i*8;
    }
    original_token_num = sys_le64_to_cpu(original_token_num);
    original_token = (void*)original_token_num;

    __ASSERT((uintptr_t)original_token > SKADI_ROOT_CAP_UPPER_LIMIT, "Invalid original token %p", (void*)original_token);

    ret = skadi_cap_ops_drop(token);

    __ASSERT_NO_MSG(ret);

    ret &= __skadi_allocator_free(original_token);

    __ASSERT_NO_MSG(ret);

    return ret;
}


#if defined(CONFIG_SKADI_LIBRARY_LOCAL_ALLOCATOR) && !defined(NO_SKADI_LOCAL_ALLOCATOR)

extern void* skadi_local_alloc(uint32_t requested_size, skadi_permission_type_t permissions);
extern bool skadi_local_free(void *capability, uint32_t capability_base);
extern bool skadi_phys_address_is_in_heap(uint32_t capability_base);

static inline void *skadi_allocator_alloc_aligned(uint32_t requested_size, uint32_t align, skadi_permission_type_t permissions){
    void *local_alloc_ret;
    /* we cannot use the local allocator for capabilities that we wish to lock, as their direct capability is our entire .bss segment */
    if(requested_size <= CONFIG_SKADI_LIBRARY_LOCAL_ALLOCATOR_CHUNK_SIZE && !(permissions & SKADI_PERMISSION_LOCKABLE) && align == 0){
        local_alloc_ret = skadi_local_alloc(requested_size, permissions);

        if(local_alloc_ret){
            return local_alloc_ret;
        }
    }
    return skadi_allocator_alloc_wrapper(requested_size, align, permissions);
}

static inline void *skadi_allocator_alloc(uint32_t requested_size, skadi_permission_type_t permissions){
    return skadi_allocator_alloc_aligned(requested_size, 0, permissions);
}

static inline void *skadi_allocator_alloc_bypass_aligned(uint32_t requested_size, uint32_t align, skadi_permission_type_t permissions){
    return skadi_allocator_alloc_wrapper(requested_size, align, permissions);
}

static inline void *skadi_allocator_alloc_bypass(uint32_t requested_size, skadi_permission_type_t permissions){
    return skadi_allocator_alloc_bypass_aligned(requested_size, 0, permissions);
}

static inline bool skadi_allocator_free(void *token){
    bool ret;
    skadi_inspect_metadata_t metadata = {};
    ret = skadi_cap_ops_inspect(token, &metadata);

    
    ret = skadi_local_free(token, metadata.capability_base);

    if(ret){
        return ret;
    }

    /* do not leak information to allocator subsystem*/
    skadi_allocator_local_memzero(token, metadata.capability_length - sizeof(void*));

    return skadi_allocator_free_wrapper(token, metadata.capability_length);
}

static inline bool skadi_allocator_free_bypass(void *token){
    uint32_t capability_length = skadi_cap_ops_inspect_get_length(token);

    /* do not leak information to allocator subsystem*/
    skadi_allocator_local_memzero(token, capability_length - sizeof(void*));
    return skadi_allocator_free_wrapper(token, capability_length);
}

#else

static inline void *skadi_allocator_alloc_aligned(uint32_t requested_size, uint32_t align, skadi_permission_type_t permissions){
    void *ret = skadi_allocator_alloc_wrapper(requested_size, align, permissions);
    // TODO not strictly needed, but breaks the dummy HTTP server sample if omitted...
    skadi_allocator_local_memzero(ret, requested_size);
    return ret;
}

static inline void *skadi_allocator_alloc(uint32_t requested_size, skadi_permission_type_t permissions){
    return skadi_allocator_alloc_aligned(requested_size, 0, permissions);
}

#define skadi_allocator_alloc_bypass skadi_allocator_alloc
#define skadi_allocator_alloc_bypass_aligned skadi_allocator_alloc_aligned

static inline bool skadi_allocator_free(void *token){
    /* do not leak information to allocator subsystem*/
    const uint32_t capability_length = skadi_cap_ops_inspect_get_length(token);
    skadi_allocator_local_memzero(token, capability_length - sizeof(void*));
    return skadi_allocator_free_wrapper(token, capability_length);
}

#define skadi_allocator_free_bypass skadi_allocator_free

#endif /* CONFIG_SKADI_LIBRARY_LOCAL_ALLOCATOR && !NO_SKADI_LOCAL_ALLOCATOR */


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(atomic_val_t, __skadi_allocator_allocated_chunks);

static inline atomic_val_t skadi_allocator_allocated_chunks(void){
    return __skadi_allocator_allocated_chunks();
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_allocator_add_heap, uintptr_t token);

#ifdef CONFIG_SKADI_ALLOCATOR_PRINT_FREE_MEM
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_allocator_print_free_mem);
#endif

#elif !defined(SKADI_SUBSYSTEM)
/* some generic functions in the loader use the convenience wrappers around these methods, so defer to initial allocator explicitly */
static inline void *skadi_allocator_alloc(uint32_t requested_size, skadi_permission_type_t permissions){
    return (void*)skadi_init_alloc_allocate(requested_size, permissions, true);
}

static inline void *skadi_allocator_alloc_aligned(uint32_t requested_size, uint32_t align, skadi_permission_type_t permissions){
    return (void*)skadi_init_alloc_allocate_aligned(requested_size, permissions, true, align);
}

static inline bool skadi_allocator_free(void *token){
    skadi_init_alloc_free(token);
    return true;
}

#else

void *skadi_allocator_alloc_aligned(uint32_t requested_size, uint32_t align, skadi_permission_type_t permissions);

static inline void *skadi_allocator_alloc(uint32_t requested_size, skadi_permission_type_t permissions){
    return skadi_allocator_alloc_aligned(requested_size, 0, permissions);
}
bool skadi_allocator_free(void *token);

#endif /* SKADI_SUBSYSTEM */

static inline void *skadi_allocator_alloc_rw(uint32_t requested_size){
    return skadi_allocator_alloc(requested_size, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS);
}

static inline void *skadi_allocator_calloc_rw(uint32_t nmembers, uint32_t requested_size){
    void *ret;
    size_t final_size;

    if(__builtin_mul_overflow(nmembers, requested_size, &final_size)){
        return NULL;
    }

    ret = skadi_allocator_alloc(final_size, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS);
    if(!ret){
        return ret;
    }
    memset(ret, 0, final_size);
    return ret;
}

static inline void *skadi_allocator_alloc_rw_non_cacheable(uint32_t requested_size){
    return skadi_allocator_alloc(requested_size, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE);
}

static inline void *skadi_allocator_alloc_rw_lockable(uint32_t requested_size){
    return skadi_allocator_alloc(requested_size, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS);
}

static inline void *skadi_allocator_alloc_rw_lockable_aligned(uint32_t requested_size, uint32_t align){
    return skadi_allocator_alloc_aligned(requested_size, align, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS);
}


static inline void *skadi_allocator_alloc_rw_lockable_non_cacheable(uint32_t requested_size){
    return skadi_allocator_alloc(requested_size, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE);
}

#if defined(SKADI_SUBSYSTEM) && !defined(SKADI_SUBSYSTEM_ALLOCATOR) && defined(CONFIG_SKADI_LIBRARY_LOCAL_ALLOCATOR) && !defined(NO_SKADI_LOCAL_ALLOCATOR)
static inline void *skadi_allocator_realloc(void *ptr, size_t size){
    skadi_inspect_metadata_t metadata_out;
    /* restrict does not allow multi-adding the same restriction */
    skadi_restriction_t no_restriction = SKADI_NO_RESTRICTION;
    skadi_restriction_t restriction = SKADI_TASK_ID_BOUND_RESTRICTION(SKADI_CURRENT_TASK_ID, SKADI_DEVICE_ID_CPU);

    if(ptr == NULL){
        /* like malloc */
        return skadi_allocator_alloc_rw(size);
    }
    if(ptr && !size){
        /* like free */
        skadi_allocator_free(ptr);
        return NULL;
    }
    if(skadi_cap_ops_inspect(ptr, &metadata_out) == false){
        return NULL;
    }
    if(size < metadata_out.capability_length - sizeof(void*)){
        uint8_t *ptr_it = ptr;
        if(skadi_phys_address_is_in_heap(metadata_out.capability_base)){
            /* shrink w/o accounting for extra token */
            if(skadi_cap_ops_restrict(ptr, no_restriction, metadata_out.capability_length - size, 0, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS )){
                return ptr;
            }
            else{
                return NULL;
            }
        }
        else{
            uintptr_t original_pointer_num = 0;
            void *ind_cap;
            bool op_ok;
            int mask;

            /* prevent allocator interference */
            mask = irq_lock();

            /* need to copy the release token */
            for(int i = 0; i < sizeof(void*); i++){
                uint8_t curr_byte = ptr_it[metadata_out.capability_length - sizeof(void*) + i];
                original_pointer_num |= ((uintptr_t)curr_byte) << (i*8);
                /* relocated token - at the end of the shorter capability */
                ptr_it[size + i] = curr_byte;
            }
            __ASSERT_NO_MSG(original_pointer_num);
            original_pointer_num = sys_le64_to_cpu(original_pointer_num);
            ind_cap = (void*)original_pointer_num;
             
            /* get rid of lock-holder*/
            op_ok = skadi_cap_ops_drop(ptr);
            __ASSERT_NO_MSG(op_ok);

            /* shrink indirect capability - not possible for lock-holder currently */
            op_ok &= skadi_cap_ops_restrict(ind_cap, no_restriction, metadata_out.capability_length - size - sizeof(void*), 0, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS );
            
            __ASSERT_NO_MSG(op_ok);
            ptr = NULL;
            /* re-gain exclusive access */
            op_ok = skadi_cap_ops_lock(ind_cap, restriction, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, &ptr);
            
            __ASSERT_NO_MSG(op_ok);

            irq_unlock(mask);

            return ptr;
        }
    }
    else{
        /* grow */
        void *ret = (void*) skadi_allocator_alloc_rw(size);
        if(ret){
            if(skadi_phys_address_is_in_heap(metadata_out.capability_base)){
                /* everything needs to be copied - no extra void* at the end */
                memcpy(ret, ptr, metadata_out.capability_length);
            }
            else{
                memcpy(ret, ptr, metadata_out.capability_length-sizeof(void*));
            }
            skadi_allocator_free(ptr);
        }
        return ret;
    }
}
#else
/* save to assume that the extra space for the void* exists */
static inline void *skadi_allocator_realloc(void *ptr, size_t size){
    skadi_inspect_metadata_t metadata_out;
    skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

    if(ptr == NULL){
        /* like malloc */
        return skadi_allocator_alloc_rw(size);
    }
    if(ptr && !size){
        /* like free */
        skadi_allocator_free(ptr);
        return NULL;
    }
    if(skadi_cap_ops_inspect(ptr, &metadata_out) == false){
        return NULL;
    }
    if(size < metadata_out.capability_length - sizeof(void*)){
        uintptr_t original_pointer_num = 0;
        void *ind_cap;
        bool op_ok;
        int mask;
        uint8_t *ptr_it = ptr;
        skadi_restriction_t no_restriction = SKADI_NO_RESTRICTION;

        /* prevent allocator interference */
        mask = irq_lock();

        /* need to copy the release token */
        for(int i = 0; i < sizeof(void*); i++){
            uint8_t curr_byte = ptr_it[metadata_out.capability_length - sizeof(void*) + i];
            original_pointer_num |= ((uintptr_t)curr_byte) << (i*8);
            /* relocated token - at the end of the shorter capability */
            ptr_it[size + i] = curr_byte;
        }
        __ASSERT_NO_MSG(original_pointer_num);
        original_pointer_num = sys_le64_to_cpu(original_pointer_num);
        ind_cap = (void*)original_pointer_num;
            
        /* get rid of lock-holder*/
        op_ok = skadi_cap_ops_drop(ptr);
        __ASSERT_NO_MSG(op_ok);

        /* shrink indirect capability - not possible for lock-holder currently */
        op_ok &= skadi_cap_ops_restrict(ind_cap, no_restriction, metadata_out.capability_length - size - sizeof(void*), 0, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS );
        
        __ASSERT_NO_MSG(op_ok);
        ptr = NULL;
        /* re-gain exclusive access */
        op_ok = skadi_cap_ops_lock(ind_cap, restriction, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, &ptr);
        
        __ASSERT_NO_MSG(op_ok);

        irq_unlock(mask);

        return ptr;
    }
    else{
        /* grow */
        void *ret = (void*) skadi_allocator_alloc_rw(size + sizeof(void*));
        if(ret){
            memcpy(ret, ptr, metadata_out.capability_length-sizeof(void*));
            skadi_allocator_free(ptr);
        }
        return ret;
    }
}
#endif

static inline void *skadi_allocator_calloc_rw_non_cacheable(size_t nmemb, size_t size){
    size_t final_size;
    void *ret;

    if(__builtin_mul_overflow(nmemb, size, &final_size)){
        return NULL;
    }
    ret = skadi_allocator_alloc_rw_non_cacheable(final_size);
    
    memset(ret, 0, final_size);

    return ret;
}

static inline void *skadi_allocator_calloc_rw_lockable(size_t nmemb, size_t size){
    size_t final_size;
    void *ret;

    if(__builtin_mul_overflow(nmemb, size, &final_size)){
        return NULL;
    }
    ret = skadi_allocator_alloc_rw_lockable(final_size);
    
    memset(ret, 0, final_size);

    return ret;
}

static inline void *skadi_allocator_calloc_rw_lockable_aligned(size_t nmemb, size_t size, size_t align){
    size_t final_size;
    void *ret;

    if(__builtin_mul_overflow(nmemb, size, &final_size)){
        return NULL;
    }
    ret = skadi_allocator_alloc_rw_lockable_aligned(final_size, align);
    
    memset(ret, 0, final_size);

    return ret;
}

static inline void *skadi_allocator_calloc_rw_lockable_non_cacheable(size_t nmemb, size_t size){
    size_t final_size;
    void *ret;

    if(__builtin_mul_overflow(nmemb, size, &final_size)){
        return NULL;
    }
    ret = skadi_allocator_alloc_rw_lockable_non_cacheable(final_size);
    /* memset assumes cacheable! */
    skadi_allocator_local_memzero((uint8_t*)ret, final_size);

    return ret;
}

#endif /* SKADI_ALLOCATOR_H */
