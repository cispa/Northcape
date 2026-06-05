#include <zephyr/llext/llext.h>
#include <zephyr/skadi/skadi_ariane_genesysii.h>
#include <zephyr/skadi/skadi_ops_driver.h>
#include <zephyr/skadi/skadi_init_alloc.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_loader.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(skadi_init_alloc, CONFIG_SKADI_LOG_LEVEL);

static sys_slist_t skadi_init_alloc_free_list;
static sys_slist_t skadi_init_alloc_indirect_allocated_list;

void skadi_init_alloc_set_heap(void* private_heap){
    struct skadi_init_alloc_list_entry *entry = (struct skadi_init_alloc_list_entry *) private_heap;

    sys_slist_init(&skadi_init_alloc_free_list);
    sys_slist_init(&skadi_init_alloc_indirect_allocated_list);

    entry->chunk.capability_token = private_heap;
    entry->chunk.segment_base = SKADI_ARIANE_RESERVED_BASE_BYTES;
    entry->chunk.segment_length = CONFIG_SKADI_INIT_ALLOC_HEAP_SIZE;

    __ASSERT(CONFIG_SKADI_INIT_ALLOC_HEAP_SIZE >= sizeof(*entry), "CONFIG_SKADI_INIT_ALLOC_HEAP_SIZE must be at least %zu!",sizeof(*entry));

    sys_slist_append(&skadi_init_alloc_free_list, &entry->node);
}

/**
  * @brief Ultra-basic memory allocator for the loader's use, intended for allocating code and data segments for applications.
  * There is no way of returning allocated constructs, they are leaked deliberately such that subsystems need not fear untrusted processes accessing their data.
  */
void* skadi_init_alloc_allocate_task_id(uint32_t requested_size, skadi_permission_type_t permissions, bool is_restricted, skadi_task_id_t task_id){
    bool success;
    void *ret=NULL;
    struct skadi_init_alloc_list_entry *entry, *it, tmp;
    skadi_restriction_t task_id_restriction = SKADI_TASK_ID_RESTRICTION(task_id, SKADI_DEVICE_ID_CPU, is_restricted ? SKADI_RESTRICTIONS_TASK_ID_BOUND : SKADI_RESTRICTIONS_NONE);


    if(requested_size < sizeof(*entry)){
        // need to be able to re-insert chunk
        requested_size = sizeof(*entry);
    }
    
    // need 8-byte alignment for performance
    if(requested_size % 8 != 0){
        requested_size += 8 - requested_size % 8;
    }

    SYS_SLIST_FOR_EACH_CONTAINER_SAFE(&skadi_init_alloc_free_list, entry, it, node){

        /* the remainder (if any) should not be smaller than an entry */
        if(entry->chunk.segment_length < requested_size + sizeof(*entry) && entry->chunk.segment_length != requested_size){
            continue;
        }

        if(sys_slist_find_and_remove(&skadi_init_alloc_free_list, &entry->node) != true){
            LOG_WRN("Could not remove entry from list!");
        }

        tmp = *entry;

        __ASSERT(!skadi_token_is_root_capability(tmp.chunk.capability_token), "Should not perform create on root capability here!");

        success = skadi_cap_ops_create(entry->chunk.capability_token, task_id_restriction, 0, requested_size, permissions, &ret);

        if(!success || ret == 0){
            LOG_ERR("Could not create direct capability for allocation request!");
            return NULL;
        }

        tmp.chunk.segment_length -= requested_size;
        tmp.chunk.segment_base = (((uintptr_t) tmp.chunk.segment_base) + requested_size);
        
        /* if the chunk is exactly as big as the entry, there is no remainder */
        if(tmp.chunk.segment_length){

            entry = (struct skadi_init_alloc_list_entry *)tmp.chunk.capability_token;

            __ASSERT(tmp.chunk.segment_length >= sizeof(*entry), "Chunk is too small to fit entry!");

            *entry = tmp;

            /* pointer has changed */
            sys_slist_append(&skadi_init_alloc_free_list, &entry->node);
        }

        return (void*) ret;
    }

    LOG_ERR("Out of memory - cannot satisfy allocation request of %u byte!", requested_size);
    return NULL;
}

/**
  * @brief Ultra-basic memory allocator for the loader's use, intended for allocating code and data segments for applications.
  * There is no way of returning allocated constructs, they are leaked deliberately such that subsystems need not fear untrusted processes accessing their data.
  * This implementation of alloc() also enforces an alignment to the power-of-two provided.
  */
void* skadi_init_alloc_allocate_task_id_aligned(uint32_t requested_size, skadi_permission_type_t permissions, bool is_restricted, skadi_task_id_t task_id, size_t alignment){
    bool success;
    void *ret=NULL;
    struct skadi_init_alloc_list_entry *entry, *it, tmp;
    skadi_restriction_t task_id_restriction = SKADI_TASK_ID_RESTRICTION(task_id, SKADI_DEVICE_ID_CPU, is_restricted ? SKADI_RESTRICTIONS_TASK_ID_BOUND : SKADI_RESTRICTIONS_NONE);
    skadi_restriction_t no_restriction = SKADI_NO_RESTRICTION;
    bool leak_memory = false;


    if(requested_size < sizeof(*entry)){
        // need to be able to re-insert chunk
        requested_size = sizeof(*entry);
    }
    
    // need 8-byte alignment for performance
    if(requested_size % sizeof(uintptr_t) != 0){
        requested_size += sizeof(uintptr_t) - requested_size % sizeof(uintptr_t);
    }

    SYS_SLIST_FOR_EACH_CONTAINER_SAFE(&skadi_init_alloc_free_list, entry, it, node){
        size_t start_offset = 0;

        if(alignment > 3 && (entry->chunk.segment_base % (1<<alignment))){
            uintptr_t aligned_start;
            
            aligned_start = entry->chunk.segment_base;
            aligned_start |= (1<<alignment) - 1;
            aligned_start ++;
            start_offset = aligned_start - entry->chunk.segment_base;
        }

        /* the remainder (if any) should not be smaller than an entry */
        if(entry->chunk.segment_length < requested_size + sizeof(*entry) + start_offset && entry->chunk.segment_length != requested_size + start_offset){
            continue;
        }
        /* the second dummy chunk created by the offset should be big enough to go back into the free list*/
        if(start_offset < sizeof(*entry) && start_offset != 0){
            if(entry->chunk.segment_length >= requested_size + sizeof(*entry) + start_offset + (1<<alignment)){
                /* increase the allocation such that the start offset-sized chunk is not wasted */
                start_offset += (1<<alignment);
            }
            else{
                /* 
                 * TODO there should be a proper solution here
                 * However, not using this memory can cause issues too...
                 */
                LOG_WRN("Leaking %zu bytes of memory in init alloc!", start_offset);
                leak_memory = true;
            }
        }


        if(sys_slist_find_and_remove(&skadi_init_alloc_free_list, &entry->node) != true){
            LOG_WRN("Could not remove entry from list!");
        }

        memcpy(&tmp, entry, sizeof(tmp));

        __ASSERT(!skadi_token_is_root_capability(tmp.chunk.capability_token), "Should not perform create on root capability here!");
        /* will remove excess permissions using restrict() later */
        success = skadi_cap_ops_create(entry->chunk.capability_token, no_restriction, 0, requested_size + start_offset, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, &ret);

        if(!success || ret == 0){
            LOG_ERR("Could not create direct capability for allocation request!");
            return NULL;
        }

        tmp.chunk.segment_length -= requested_size + start_offset;
        tmp.chunk.segment_base = (((uintptr_t) tmp.chunk.segment_base) + requested_size + start_offset);
        
        /* if the chunk is exactly as big as the entry, there is no remainder */
        if(tmp.chunk.segment_length){

            entry = (struct skadi_init_alloc_list_entry *)tmp.chunk.capability_token;

            __ASSERT(tmp.chunk.segment_length >= sizeof(*entry), "Chunk is too small to fit entry!");

            memcpy(entry, &tmp, sizeof(*entry));

            /* pointer has changed */
            sys_slist_append(&skadi_init_alloc_free_list, &entry->node);
        }

        if(start_offset){
            void *excess_alignment = NULL;
            // need to cut off the start alignment part of the buffer and put it back into the free list
            success = skadi_cap_ops_create(ret, no_restriction, 0, start_offset, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, &excess_alignment);

            if(!success || excess_alignment == 0){
                LOG_ERR("Could not create direct capability for alignment excess bits!");
                return NULL;
            }

            if(!leak_memory){
                entry = (struct skadi_init_alloc_list_entry *)excess_alignment;
                tmp.chunk.segment_length = start_offset;
                tmp.chunk.segment_base -= requested_size + start_offset;
                tmp.chunk.capability_token = excess_alignment;
                memcpy(entry, &tmp, sizeof(*entry));
                /* do not waste the memory */
                sys_slist_append(&skadi_init_alloc_free_list, &entry->node);
            }
        }
        /* retval should not be over-permissioned */
        success = skadi_cap_ops_restrict(ret, task_id_restriction, 0, 0, permissions);

        if(!success){
            LOG_ERR("Could not restrict capability token!");
            return NULL;
        }

        __ASSERT((skadi_cap_ops_inspect_get_base(ret) & ((1<<alignment)-1)) == 0, "Token %p is not aligned properly - base %zu with alignment %zu!", ret, skadi_cap_ops_inspect_get_base(ret), alignment);

        return (void*) ret;
    }

    LOG_ERR("Out of memory - cannot satisfy allocation request of %u byte!", requested_size);
    return NULL;
}

void* skadi_init_alloc_allocate(uint32_t requested_size, skadi_permission_type_t permissions, bool is_restricted_to_loader){
    return skadi_init_alloc_allocate_task_id(requested_size, permissions, is_restricted_to_loader, SKADI_TASK_ID_LOADER);
}

void* skadi_init_alloc_allocate_aligned(uint32_t requested_size, skadi_permission_type_t permissions, bool is_restricted_to_loader, size_t alignment){
    return skadi_init_alloc_allocate_task_id_aligned(requested_size, permissions, is_restricted_to_loader, SKADI_TASK_ID_LOADER, alignment);
}

void skadi_init_alloc_free(void* capability){
    struct skadi_init_alloc_list_entry *entry, *it, tmp_left, tmp_right;
    skadi_inspect_metadata_t metadata;
    void* new_capability = NULL;
    skadi_restriction_t task_id_restriction = SKADI_TASK_ID_BOUND_RESTRICTION(SKADI_TASK_ID_LOADER, SKADI_DEVICE_ID_CPU);
    skadi_capability_type_t capability_type;

    entry = (struct skadi_init_alloc_list_entry *) capability;

    if(skadi_cap_ops_inspect(capability, &metadata) == false){
        LOG_ERR("Could not free capability %p: Inspect error!", (void*) capability);
        return;
    }

    /* to prevent fragmentation, merge with adjacent chunk if possible */
    SYS_SLIST_FOR_EACH_CONTAINER_SAFE(&skadi_init_alloc_free_list, entry, it, node){
        
        if(entry->chunk.segment_base + entry->chunk.segment_length == metadata.capability_base){
            /* left-adjacent */
            tmp_left = *entry;

            tmp_right.chunk.capability_token = capability;
            tmp_right.chunk.segment_base = metadata.capability_base;
            tmp_right.chunk.segment_length = metadata.capability_length;
        }
        else if(metadata.capability_base + metadata.capability_length == (uintptr_t) entry->chunk.segment_base){
            /* right-adjacent */
            tmp_right = *entry;

            tmp_left.chunk.capability_token = capability;
            tmp_left.chunk.segment_base = metadata.capability_base;
            tmp_left.chunk.segment_length = metadata.capability_length;
        }
        else{
            continue;
        }
        

        if(sys_slist_find_and_remove(&skadi_init_alloc_free_list, &entry->node) != true){
                LOG_WRN("Could not remove entry from list!");
        }

        capability_type = skadi_allocator_appropriate_capability_type_for_size(tmp_left.chunk.segment_length + tmp_right.chunk.segment_length);

        if(skadi_cap_ops_merge_noinspect(tmp_left.chunk.capability_token, tmp_right.chunk.capability_token, task_id_restriction, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, capability_type, &new_capability) != true || new_capability == 0){
            LOG_ERR("Could not merge capabilities!");
            return;
        }

        entry = (struct skadi_init_alloc_list_entry *) new_capability;
        entry->chunk.capability_token = new_capability;
        entry->chunk.segment_base = tmp_left.chunk.segment_base;
        entry->chunk.segment_length = tmp_left.chunk.segment_length + tmp_right.chunk.segment_length;

        sys_slist_append(&skadi_init_alloc_free_list, &entry->node);

        /* found - merged */
        return;
    }

    /* not found - add a new entry to free list */

    /* for temporal safety and restoring permissions */
    if(!capability || skadi_cap_ops_revoke(capability, task_id_restriction, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, &new_capability) == false || !new_capability){
        LOG_ERR("Could not free capability %p: Could not revoke direct capability!", (void*) capability);
        return;
    }

    entry = (struct skadi_init_alloc_list_entry *) new_capability;
    entry->chunk.capability_token = new_capability;
    entry->chunk.segment_base = metadata.capability_base;
    entry->chunk.segment_length = metadata.capability_length;

    sys_slist_append(&skadi_init_alloc_free_list, &entry->node);
}

void *skadi_init_alloc_allocate_section(uintptr_t sect_size, enum llext_mem mem_idx){
    void *ret;
    bool derive_ok;
    skadi_permission_type_t permission;
    skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
    /* cacheline-alinged to avoid certain problems with flushing */
    size_t alignment = CONFIG_DCACHE_LINE_SIZE;
    
    if(sect_size > UINT32_MAX){
        LOG_ERR("Section size %lu too much (max %u)!", sect_size, UINT32_MAX);
        return NULL;
    }

    switch(mem_idx){
        case LLEXT_MEM_TEXT:
            permission = SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS;
            if(IS_ENABLED(CONFIG_SKADI_TEXT_ALIGN_12_BIT)){
                alignment = 12;
            }
            break;
        // strings are unmodifieable (or they ought to be)
        // we need to allocate them as writable initially for relocation
        // we will drop this permission later, when we are done copying
        // data and BSS remain writable
        case LLEXT_MEM_DATA:
        case LLEXT_MEM_SHSTRTAB:
        case LLEXT_MEM_STRTAB:
        case LLEXT_MEM_RODATA:
        case LLEXT_MEM_BSS:
        case LLEXT_MEM_EXPORT:
        case LLEXT_MEM_SYMTAB:
        case LLEXT_MEM_PREINIT:
        case LLEXT_MEM_INIT:
        case LLEXT_MEM_FINI:
            permission = SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS;
            break;
        default:
            LOG_ERR("Unknown section type %u!",mem_idx);
            return NULL;
    }

    if(alignment){
        ret = skadi_init_alloc_allocate_aligned((uint32_t) sect_size, permission | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, true, alignment);
    }
    else{
        ret = skadi_init_alloc_allocate((uint32_t) sect_size, permission | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, true);
    }

    if(ret == 0){
        LOG_ERR("Could not allocate for section type %u: OOM!", mem_idx);
        return NULL;
    }

    /* cannot immediately add task-id restriction, as we (the loader) need to access the segment for relocation */
    derive_ok = skadi_cap_ops_derive(ret, restriction, sect_size, 0, permission | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, &ret);

    if(!derive_ok || !ret){
        LOG_ERR("Could not derive indirect capability for section type %u!", mem_idx);
        return NULL;
    }

    return ret;
}

void*  __attribute__ ((alloc_size (1))) __attribute__ ((malloc, malloc (skadi_init_alloc_free, 1))) skadi_init_alloc_allocate_aligned_indirect(uint32_t requested_size, skadi_permission_type_t permissions, bool is_restricted_to_loader, size_t alignment){
    /* need R+W for co-located metadata struct */
    void *direct_cap = skadi_init_alloc_allocate_aligned(requested_size + sizeof(struct skadi_init_alloc_list_entry), permissions | SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE, is_restricted_to_loader, alignment);
    struct skadi_init_alloc_list_entry *list_entry;
    bool create_ok, derive_ok;
    skadi_restriction_t task_id_restriction = SKADI_TASK_ID_BOUND_RESTRICTION(SKADI_TASK_ID_LOADER, SKADI_DEVICE_ID_CPU);
    skadi_restriction_t no_restriction = SKADI_NO_RESTRICTION;
    void *indirect_cap = NULL;


    if(!direct_cap){
        return direct_cap;
    }
    /* separate from direct cap as we expect direct cap to be locked */
    create_ok = skadi_cap_ops_create(direct_cap, task_id_restriction, true, sizeof(*list_entry), permissions | SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE, (void**)&list_entry);

    if(!create_ok){
        skadi_init_alloc_free(direct_cap);
        return NULL;
    }
    list_entry->chunk.capability_token = direct_cap;
    list_entry->chunk.segment_base = skadi_cap_ops_inspect_get_base(direct_cap);
    list_entry->chunk.segment_length = skadi_cap_ops_inspect_get_length(direct_cap);

    sys_slist_append(&skadi_init_alloc_indirect_allocated_list, &list_entry->node);

    derive_ok = skadi_cap_ops_derive(direct_cap, no_restriction, requested_size, 0, permissions, &indirect_cap);

    __ASSERT_NO_MSG(derive_ok);

    return indirect_cap;
}
void skadi_init_alloc_free_indirect(void* capability){
    uint32_t cap_base = skadi_cap_ops_inspect_get_base(capability);
    struct skadi_init_alloc_list_entry *entry, *it;
    skadi_restriction_t task_id_restriction = SKADI_TASK_ID_BOUND_RESTRICTION(SKADI_TASK_ID_LOADER, SKADI_DEVICE_ID_CPU);
    bool merge_ok;

    SYS_SLIST_FOR_EACH_CONTAINER_SAFE(&skadi_init_alloc_indirect_allocated_list, entry, it, node){
        if(entry->chunk.segment_base == cap_base){
            void *merged_cap;
            sys_slist_find_and_remove(&skadi_init_alloc_indirect_allocated_list, &entry->node);
            (void)skadi_cap_ops_drop(capability);
            merge_ok = skadi_cap_ops_merge_noinspect(entry->chunk.capability_token, entry, task_id_restriction, SKADI_ALL_PERMISSIONS, skadi_allocator_appropriate_capability_type_for_size(entry->chunk.segment_length + sizeof(*entry)), &merged_cap);
            if(merge_ok){
                skadi_init_alloc_free(merged_cap);
            }
            return;
        }
    }
}

uint8_t* skadi_init_alloc_allocate_subsystem_stack(struct skadi_subsystem_stack ** allocator_out, void **lock_holder_out, skadi_task_id_t current_task_id){
    struct skadi_subsystem_stack *subsystem_stack;
    /* ephemeral - disappears after load time */
    subsystem_stack = (struct skadi_subsystem_stack *) skadi_init_alloc_allocate(sizeof(*subsystem_stack), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, false);

    if(allocator_out){
        *allocator_out = subsystem_stack;
    }

    if(!subsystem_stack){
        k_panic();
    }

    return skadi_subsystem_prepare_allocated_stack(subsystem_stack, current_task_id, lock_holder_out);
}

#ifdef CONFIG_SKADI_LOADER

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS(__skadi_allocator_add_heap, uintptr_t token);
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_IMPL(__skadi_allocator_add_heap, 1, uintptr_t token);

/* called just before nuuk-ing - the remaining free list can be forwarded to allocator subsystem */
void skadi_init_alloc_relese_unused_heap(void){
    void *heap_free_fn = (void*)skadi_loader_get_symbol("__skadi_allocator_add_heap_callee_trampoline");
    struct skadi_init_alloc_list_entry *entry, *it;

    __ASSERT(heap_free_fn, "Heap free function not found!");

    if(!heap_free_fn){
        LOG_WRN("Could not find heap free function - leaking loader's init alloc heap!");
        return;
    }

    SYS_SLIST_FOR_EACH_CONTAINER_SAFE(&skadi_init_alloc_free_list, entry, it, node){
        bool ret = sys_slist_find_and_remove(&skadi_init_alloc_free_list, &entry->node);
        void* param = entry;
        __ASSERT_NO_MSG(ret);
        
        ret = skadi_cap_ops_revoke_simple(param, &param);

        __ASSERT_NO_MSG(ret);

        if(!ret){
            LOG_WRN("Leaking capability %p!", (void*)param);
            continue;
        }

        __skadi_allocator_add_heap((uintptr_t)param, heap_free_fn);

    }

}
#endif
