#include <inttypes.h>


#include <zephyr/init.h>
#include <zephyr/irq.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/atomic.h>
#include <zephyr/sys/rb.h>
#include <zephyr/sys/util.h>

#include <zephyr/arch/cache.h>

#ifdef CONFIG_SKADI_GENESYSII
#include <zephyr/skadi/skadi_ariane_genesysii.h>
#else
#error "Need CONFIG_SKADI_GENESYSII to be defined!"
#endif

#include <zephyr/skadi/skadi_ops_driver.h>

#include <zephyr/skadi/skadi_allocator.h>

#include <zephyr/llext/symbol.h>


LOG_MODULE_REGISTER(skadi_allocator, CONFIG_SKADI_LOG_LEVEL);

#ifdef CONFIG_SKADI_ALLOCATOR_DEBUG
    /* it is easier to debug the allocator if we are able to see the chunks from other subsystems */
    #define SKADI_ALLOCATOR_RESTRICTION SKADI_NO_RESTRICTION
#else
    #define SKADI_ALLOCATOR_RESTRICTION SKADI_TASK_ID_BOUND_RESTRICTION(SKADI_CURRENT_TASK_ID, SKADI_DEVICE_ID_CPU)
#endif

/* only for debugging memory leaks - number of currently allocated chunks */
static atomic_t number_allocated_chunks;

struct skadi_free_list_chunk;

// used to track free segments that we can allocate
struct skadi_free_list_chunk {
    // rbtrees, sorted by physical base and chunk size respectively
    struct rbnode tree_base, tree_size;
    // size of the chunk incl. header
    uint32_t chunk_size;
    // physical location of the chunk in memory
    // used to determine whether we can merge two chunks
    uint32_t physical_location_base;
} __aligned(sizeof(void*));

// used to track allocated segments that we can free
struct skadi_allocated_list_chunk {
    // rbtree, sorted by indirect capability
    struct rbnode tree;
    // to identify the chunk
    void* indirect_capability;
    // direct capability for the actual data (separate but always physically contiguous, such that we can traverse list when data locked)
    void *direct_capability;
    // to identify whether two adjacent chunks can be merged
    uint32_t physical_location_base;
    uint32_t chunk_size;
} __aligned(sizeof(void*));

#define SKADI_ALLOC_DIRECT_CAPABILITY_MIN_SIZE MAX(sizeof(struct skadi_free_list_chunk), sizeof(struct skadi_allocated_list_chunk))
BUILD_ASSERT(SKADI_ALLOC_DIRECT_CAPABILITY_MIN_SIZE % sizeof(void*) == 0);
BUILD_ASSERT(sizeof(struct skadi_free_list_chunk) == sizeof(struct skadi_allocated_list_chunk));

static bool allocated_list_lessthan(struct rbnode *a, struct rbnode *b){
    const struct skadi_allocated_list_chunk *a_chunk = CONTAINER_OF(a, struct skadi_allocated_list_chunk, tree);
    const struct skadi_allocated_list_chunk *b_chunk = CONTAINER_OF(b, struct skadi_allocated_list_chunk, tree);

    __ASSERT_NO_MSG(a_chunk);
    __ASSERT_NO_MSG(b_chunk);

    return a_chunk->indirect_capability < b_chunk->indirect_capability;
}

static bool allocated_list_equal(const struct rbnode *a, const struct rbnode *b, void *cookie){
    const struct skadi_allocated_list_chunk *a_chunk = CONTAINER_OF(a, struct skadi_allocated_list_chunk, tree);
    const struct skadi_allocated_list_chunk *b_chunk = CONTAINER_OF(b, struct skadi_allocated_list_chunk, tree);;

    ARG_UNUSED(cookie);

    __ASSERT_NO_MSG(a_chunk);
    __ASSERT_NO_MSG(b_chunk);

    return a_chunk->indirect_capability == b_chunk->indirect_capability;
}

static bool free_list_lessthan_base(struct rbnode *a, struct rbnode *b){
    const struct skadi_free_list_chunk *a_chunk = CONTAINER_OF(a, struct skadi_free_list_chunk, tree_base);
    const struct skadi_free_list_chunk *b_chunk = CONTAINER_OF(b, struct skadi_free_list_chunk, tree_base);

    __ASSERT_NO_MSG(a_chunk);
    __ASSERT_NO_MSG(b_chunk);

    return a_chunk->physical_location_base < b_chunk->physical_location_base;
}

static bool free_list_lessthan_size(struct rbnode *a, struct rbnode *b){
    const struct skadi_free_list_chunk *a_chunk = CONTAINER_OF(a, struct skadi_free_list_chunk, tree_size);
    const struct skadi_free_list_chunk *b_chunk = CONTAINER_OF(b, struct skadi_free_list_chunk, tree_size);

    __ASSERT_NO_MSG(a_chunk);
    __ASSERT_NO_MSG(b_chunk);

    if(a_chunk->chunk_size != b_chunk->chunk_size){
        return a_chunk->chunk_size < b_chunk->chunk_size;
    }
    /* rbtree does not allow equal - use unique location as a tie breaker */
    return a_chunk->physical_location_base < b_chunk->physical_location_base;
}

static bool free_list_adjacent(const struct rbnode *a, const struct rbnode *b, void *cookie){
    const struct skadi_free_list_chunk *a_chunk = CONTAINER_OF(a, struct skadi_free_list_chunk, tree_base);
    const struct skadi_free_list_chunk *b_chunk = CONTAINER_OF(b, struct skadi_free_list_chunk, tree_base);

    ARG_UNUSED(cookie);

    if(a_chunk->physical_location_base == b_chunk->physical_location_base + b_chunk->chunk_size){
        // ret is right-adjacent
        return true;
    }
    if(b_chunk->physical_location_base == a_chunk->physical_location_base + a_chunk->chunk_size){
        // ret is left-adjacent
        return true;
    }

    return false;
}

typedef bool (*rb_search_t)(const struct rbnode *node, const struct rbnode *search_node, void *cookie);

/*
 * Lookup function for rbtrees, as missing in API.
 * @param tree red-black tree
 * @param node that we are looking for, needs to be comparable to nodes in tree with the user-specified lessthan function
 * @param returns true when found, false otherwise
 * @param cookie cookie forwarded to search function
 */
static struct rbnode *rb_lookup(struct rbtree *tree, struct rbnode *dummy_node_container, rb_search_t search, void *cookie){
    struct rbnode *n = tree->root;

	while ((n != NULL) && !search(n, dummy_node_container, cookie)) {
		n = z_rb_child(n, tree->lessthan_fn(n, dummy_node_container));
	}
    /* n is null or found the node */
	return n;
}

/**
 * Direct capabilities that are currently allocated, sorted by indirect capability for fast retrieval.
 * The list only contains direct capabilities with the metadata for each chunk.
 * The actual data are separate and immediately FOLLOW the metadata, with the chunk being linked in the metadata to alloc traversing list when some data is locked.
 */
static struct rbtree skadi_arena_allocated_list = {.lessthan_fn = allocated_list_lessthan};
/**
 * Direct capabilitiest that are currently free, sorted by base.
 * Free list capabilities are physically contiguous with the data buffer.
 */
static struct rbtree skadi_arena_free_list_by_base = {.lessthan_fn = free_list_lessthan_base};
/**
 * Direct capabilitiest that are currently free, sorted by chunk size. Kept for faster allocation by size.
 */
static struct rbtree skadi_arena_free_list_by_size = {.lessthan_fn = free_list_lessthan_size};

static inline void create_free_list_chunk(struct skadi_free_list_chunk *chunk, uint32_t chunk_size, uintptr_t physical_location_base){
    chunk->chunk_size = chunk_size;
    chunk->physical_location_base = physical_location_base;

    rb_insert(&skadi_arena_free_list_by_base, &chunk->tree_base);
    rb_insert(&skadi_arena_free_list_by_size, &chunk->tree_size);
}

const skadi_permission_type_t full_permissions = SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS;

static inline struct skadi_allocated_list_chunk *create_allocated_list_chunk(void* direct_capability, uintptr_t physical_location_base, uint32_t chunk_size){
    bool ok;
    void *ret;
    struct skadi_allocated_list_chunk *allocated_chunk;
    const skadi_restriction_t allocator_restriction = SKADI_ALLOCATOR_RESTRICTION;
    /* not lockable - not needed for metadata; at the END of the chunk */
    ok = skadi_cap_ops_create(direct_capability, allocator_restriction, true, SKADI_ALLOC_DIRECT_CAPABILITY_MIN_SIZE, full_permissions, &ret);
    
    __ASSERT_NO_MSG(ok);

    if(!ok){
        return NULL;
    }

    allocated_chunk = ret;

    allocated_chunk->direct_capability = direct_capability;
    allocated_chunk->physical_location_base = physical_location_base;
    allocated_chunk->chunk_size = chunk_size;

    return allocated_chunk;
}

static inline struct skadi_allocated_list_chunk* find_allocated_list_chunk(void* indirect_capability){
    struct skadi_allocated_list_chunk dummy_chunk = { .indirect_capability = indirect_capability };
    struct rbnode *ret = rb_lookup(&skadi_arena_allocated_list, &dummy_chunk.tree, allocated_list_equal, NULL);
    return ret ? CONTAINER_OF(ret, struct skadi_allocated_list_chunk, tree) : NULL;
}

#ifdef CONFIG_SKADI_ALLOCATOR_FIRST_FIT
static inline struct skadi_free_list_chunk* find_suitable_free_chunk(uint32_t requested_size){
    struct rbnode *n = skadi_arena_free_list_by_size.root;
    /* as size is compared first, once the size is equal, the base does not interest - can use base 0 */
    struct skadi_free_list_chunk *free_chunk;

	while ((n != NULL)) {
        free_chunk = CONTAINER_OF(n, struct skadi_free_list_chunk, tree_size);

        if(free_chunk->chunk_size > requested_size + sizeof(*free_chunk) || free_chunk->chunk_size == requested_size){
            return free_chunk;
        }
        /* first fit - go with larger child as current is definitely too small */
        n = z_rb_child(n, 1);
	}

    /* nothing found... */
    LOG_WRN("Could not find free list chunk with size %"PRIu32, requested_size);

    return NULL;
}
#elif CONFIG_SKADI_ALLOCATOR_BEST_FIT
static inline struct skadi_free_list_chunk* find_suitable_free_chunk(uint32_t requested_size){
    struct rbnode *n = skadi_arena_free_list_by_size.root, *smaller_child, *larger_child;
    /* as size is compared first, once the size is equal, the base does not interest - can use base 0 */
    struct skadi_free_list_chunk *free_chunk, *small_chunk, *large_chunk;

	while ((n != NULL)) {
        int diff_small, diff_large, diff_current;

        free_chunk = CONTAINER_OF(n, struct skadi_free_list_chunk, tree_size);

        if(free_chunk->chunk_size == requested_size){
            __ASSERT(free_chunk->chunk_size == requested_size || free_chunk->chunk_size >= requested_size + sizeof(*free_chunk), "Invalid chunk size %"PRIu32" returned for requested %"PRIu32"!", free_chunk->chunk_size, requested_size);
            /* perfect match - we always use this chunk irregardless */
            return free_chunk;
        }

        diff_current = (int) free_chunk->chunk_size - (int) requested_size;

        larger_child = z_rb_child(n, 1);
        smaller_child = z_rb_child(n, 0);

        large_chunk = CONTAINER_OF(larger_child, struct skadi_free_list_chunk, tree_size);
        small_chunk = CONTAINER_OF(smaller_child, struct skadi_free_list_chunk, tree_size);

        LOG_DBG("Crossroads - requested size %"PRIu32" larger child size %"PRIu32" current size %"PRIu32" smaller child size %"PRIu32"!\n", requested_size, larger_child ? large_chunk->chunk_size : 0, free_chunk->chunk_size, smaller_child ? small_chunk->chunk_size : 0);

        if(!larger_child){
            diff_large = INT_MAX;
        }
        else{
            diff_large = (int) large_chunk->chunk_size - (int) requested_size;
        }
        if(!smaller_child){
            diff_small = -INT_MAX;
        }
        else{
            diff_small = (int) small_chunk->chunk_size - (int) requested_size;
        }

        if(diff_current < 0 && diff_small < 0 && diff_large == INT_MAX){
            LOG_DBG("Did not find suitable chunk!\n");
            return NULL;
        }

        if(diff_small < 0){
            /* small child is too small - perfect chunk is parent or larger child, depending on which is closer*/
            if(diff_current >= 0 && diff_current < diff_large && (diff_current == 0 || diff_current >= sizeof(struct skadi_free_list_chunk))){
                LOG_DBG("Small is 0 - returning current!\n");
                __ASSERT(free_chunk->chunk_size == requested_size || free_chunk->chunk_size >= requested_size + sizeof(*free_chunk), "Invalid chunk size %"PRIu32" returned for requested %"PRIu32" diff current %d!", free_chunk->chunk_size, requested_size, diff_current);
                return free_chunk;
            }
            if(diff_large == 0){
                /* larger child is the first chunk to be big enough - must be best fit due to order */
                LOG_DBG("Small is 0 - returning large!\n");
                __ASSERT(large_chunk->chunk_size == requested_size, "Invalid chunk size %"PRIu32" returned for requested %"PRIu32" diff current %d diff large %d!", large_chunk->chunk_size, requested_size, diff_current, diff_large);
                return large_chunk;
            }
            if(diff_large > 0 && diff_large >= sizeof(struct skadi_free_list_chunk)){
                LOG_DBG("Small is 0 - returning large!\n");
                __ASSERT(large_chunk->chunk_size >= requested_size + sizeof(*large_chunk), "Invalid chunk size %"PRIu32" returned for requested %"PRIu32" diff current %d diff large %d!", large_chunk->chunk_size, requested_size, diff_current, diff_large);
                return large_chunk;
            }
            /* larger child is too small - need to check its larger child if any*/
            n = larger_child;
            continue;
        }

        if(diff_large == INT_MAX){
            /* large child does not exist - perfect chunk is parent or smaller (grand)-child, depending on which is closer */
            if(diff_current >= 0 && (diff_current < diff_small || diff_small < sizeof(struct skadi_free_list_chunk)) && (diff_current == 0 || diff_current >= sizeof(struct skadi_free_list_chunk))){
                LOG_DBG("Large is 0 - returning current!\n");
                __ASSERT(free_chunk->chunk_size == requested_size || free_chunk->chunk_size >= requested_size + sizeof(*free_chunk), "Invalid chunk size %"PRIu32" returned for requested %"PRIu32" diff current %d!", free_chunk->chunk_size, requested_size, diff_current);
                /* this is not always correct - a child of the smaller child could be closer; however, should work as approximation */
                return free_chunk;
            }
            else{
                LOG_DBG("Large is 0 - iterating!\n");
                __ASSERT_NO_MSG(diff_small == 0 || diff_small >= sizeof(struct skadi_free_list_chunk));
                /* continue to iterate - the best fit must be somewhere to the left */
                n = smaller_child;
                continue;
            }
        }

        /* continue to iterate depending on which child is closer - again, approximation! */
        if((diff_small == 0 || diff_small >= sizeof(struct skadi_free_list_chunk)) && diff_small < diff_large){
            LOG_DBG("Iterating small!\n");
            n = smaller_child;
            __ASSERT_NO_MSG(diff_small == 0 || diff_small >= sizeof(struct skadi_free_list_chunk));
        }
        else{
            LOG_DBG("Iterating large!\n");
            __ASSERT_NO_MSG(diff_large == 0 || diff_large >= sizeof(struct skadi_free_list_chunk));
            n = larger_child;
        }

	}
    
    /* nothing found... */
    LOG_WRN("Could not find free list chunk with size %"PRIu32, requested_size);

    return NULL;
}
#else
#error "No allocation strategy selected!"
#endif /* SKADI_ALLOCATOR_FIRST_FIT */

static inline struct skadi_free_list_chunk* find_adjacent_free_list_chunk(struct skadi_allocated_list_chunk *allocated_chunk){
    // free list sorted by location
    struct skadi_free_list_chunk dummy_chunk = {
        .physical_location_base = allocated_chunk->physical_location_base,
        .chunk_size = allocated_chunk->chunk_size
    };
    struct rbnode *ret = rb_lookup(&skadi_arena_free_list_by_base, &dummy_chunk.tree_base, free_list_adjacent, NULL);
    return ret ? CONTAINER_OF(ret, struct skadi_free_list_chunk, tree_base) : NULL;
}

// alignment to 8 byte allows to potentially run DMA and other peripheral devices without having to support the full subset of masking/shifting in the MMU, saving chip area
#define DEFAULT_SKADI_ALLOCATOR_ALIGNMENT_BYTES 8

void *to_indirect_cap(void* returned_cap, size_t requested_size, uint32_t align, uintptr_t direct_capability_physical_base, skadi_permission_type_t permissions){
    bool success;
    void* ret;
    const uint32_t final_align = (align > DEFAULT_SKADI_ALLOCATOR_ALIGNMENT_BYTES) ? align : DEFAULT_SKADI_ALLOCATOR_ALIGNMENT_BYTES;
    uint32_t offset = final_align - (direct_capability_physical_base % final_align);
    skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

    LOG_DBG("Direct capability has base %p so I need offset %"PRIu32" to align at %u bytes boundary!",(void*)direct_capability_physical_base,offset,final_align);
    /* metadata has already been removed */
    success = skadi_cap_ops_derive(returned_cap, restriction, requested_size, offset, permissions, &ret);

    if(success){
        return ret;
    }
    else{
        LOG_WRN("Could not create indirect capability!");
        return NULL;
    }
}

void *skadi_allocator_alloc_aligned(uint32_t requested_size, uint32_t align, skadi_permission_type_t permissions){
    struct skadi_free_list_chunk *chunk,  chunk_tmp;
    bool success;
    void* ret = 0, *indirect_capability;
    unsigned int irq_key;
    uint32_t original_requested_size;
    uintptr_t chunk_physical_base;
    const skadi_restriction_t allocator_restriction = SKADI_ALLOCATOR_RESTRICTION;
    struct skadi_allocated_list_chunk *allocated_chunk;
    const uint32_t final_align = (align > DEFAULT_SKADI_ALLOCATOR_ALIGNMENT_BYTES) ? align : DEFAULT_SKADI_ALLOCATOR_ALIGNMENT_BYTES;

    original_requested_size = requested_size;

    // prevent concurrent modification of data structures
    irq_key = irq_lock();

    // such that we can increment the base address if needed
    requested_size = requested_size + final_align;
    // maintain void* alignment to prevent misaligned exceptions in the allocator
    requested_size += (DEFAULT_SKADI_ALLOCATOR_ALIGNMENT_BYTES - (requested_size % DEFAULT_SKADI_ALLOCATOR_ALIGNMENT_BYTES)) % DEFAULT_SKADI_ALLOCATOR_ALIGNMENT_BYTES;
    // we need to be able to mark the direct capability as free list entry again once freed - need space for header chunk
    requested_size += SKADI_ALLOC_DIRECT_CAPABILITY_MIN_SIZE;

    chunk = find_suitable_free_chunk(requested_size);
    if(chunk == NULL){
        irq_unlock(irq_key);
        LOG_WRN("No memory left to satisfy allocation request for %"PRIu32" bytes!",requested_size);
        return NULL;
    }
    __ASSERT(chunk->chunk_size == requested_size || chunk->chunk_size >= requested_size + sizeof(*chunk), "Invalid chunk size %"PRIu32" returned!", chunk->chunk_size);

    chunk_physical_base = chunk->physical_location_base;

    // will be moved or overwritten
    chunk_tmp = *chunk;

    /* will add again if space left */
    rb_remove(&skadi_arena_free_list_by_base, &chunk->tree_base);
    rb_remove(&skadi_arena_free_list_by_size, &chunk->tree_size);

    // by convention, chunks are direct capabilities
    // direction = 0 --> start of capability
    // direct capabilities are owned by the allocator so memory cannot be stolen
    success = skadi_cap_ops_create(chunk, allocator_restriction, 0, requested_size, full_permissions, &ret);

    // 0-token cannot be the output of create
    // this is reserved for root capability
    if(!success || ret == 0){
        irq_unlock(irq_key);
        LOG_ERR("Could not create return capability!");
        return NULL;
    }

    if(requested_size != chunk_tmp.chunk_size){
        /* otherwise already removed */
        LOG_DBG("Updating chunk %p from size %"PRIu32" base %p to size %"PRIu32" base %p",chunk,chunk_tmp.chunk_size,(void *)(uintptr_t)chunk_tmp.physical_location_base,chunk_tmp.chunk_size - requested_size,(void *)(uintptr_t)(chunk_tmp.physical_location_base + requested_size));
        // chunk remains, but the pointer now points somewhere else in the struct
        // need to re-initialize metadata
        create_free_list_chunk(chunk,chunk_tmp.chunk_size - requested_size, chunk_tmp.physical_location_base + requested_size);
    }

    irq_unlock(irq_key);

    /* otherwise, will fail due to refcount */
    allocated_chunk = create_allocated_list_chunk(ret, chunk_tmp.physical_location_base, requested_size);

    __ASSERT_NO_MSG(allocated_chunk);

    indirect_capability = to_indirect_cap(ret, original_requested_size, align, chunk_physical_base, permissions);

    __ASSERT_NO_MSG(indirect_capability);
    allocated_chunk->indirect_capability = indirect_capability;

    rb_insert(&skadi_arena_allocated_list, &allocated_chunk->tree);

    atomic_inc(&number_allocated_chunks);

    if(IS_ENABLED(CONFIG_SKADI_ALLOC_ZERO_MEMORY)){
        memset(indirect_capability, 0, original_requested_size);
    }

    return indirect_capability;

}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void *, __skadi_allocator_alloc, uint32_t requested_size, uint32_t align, skadi_permission_type_t permissions)
    return skadi_allocator_alloc_aligned(requested_size, align, permissions);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_allocator_alloc)

bool skadi_allocator_free(void *token){
    struct skadi_allocated_list_chunk* list_chunk, allocated_chunk_tmp;
    struct skadi_free_list_chunk *free_list_chunk, tmp_chunk, *new_free_list_chunk;
    bool merged;
    unsigned int irq_key;
    const skadi_restriction_t allocator_restriction = SKADI_ALLOCATOR_RESTRICTION;
    skadi_capability_type_t capability_type;

    irq_key = irq_lock();


    list_chunk = find_allocated_list_chunk(token);

    if(!list_chunk){
        LOG_ERR("Could not find allocated list entry for indirect capability %p",token);
        irq_unlock(irq_key);
        return false;
    }

    if(skadi_cap_ops_drop(token) == false){
        LOG_ERR("Drop failed!");
        irq_unlock(irq_key);
        return false;
    }

    __ASSERT(list_chunk->indirect_capability == token, "Found incorrect list chunk %p!", list_chunk);

    // need to remove before merging
    rb_remove(&skadi_arena_allocated_list, &list_chunk->tree);

    free_list_chunk = find_adjacent_free_list_chunk(list_chunk);

    allocated_chunk_tmp = *list_chunk;

    capability_type = skadi_allocator_appropriate_capability_type_for_size(list_chunk->chunk_size);

    // need to re-merge data and metadata - always left-adjacent
    merged = skadi_cap_ops_merge_noinspect(list_chunk->direct_capability, list_chunk, allocator_restriction, full_permissions, capability_type, (void**) &list_chunk);

    __ASSERT_NO_MSG(merged);

    if(!merged){
        return false;
    }

    if(!free_list_chunk){
        LOG_DBG("Could not find adjacent free list chunk!");
        merged=false;
    }
    else{

        tmp_chunk = *free_list_chunk;
        new_free_list_chunk = NULL;
        // need to remove before merging
        rb_remove(&skadi_arena_free_list_by_base, &free_list_chunk->tree_base);
        rb_remove(&skadi_arena_free_list_by_size, &free_list_chunk->tree_size);

        capability_type = skadi_allocator_appropriate_capability_type_for_size(list_chunk->chunk_size + free_list_chunk->chunk_size);

        if(allocated_chunk_tmp.physical_location_base <= free_list_chunk->physical_location_base){
            LOG_DBG("Doing a left-adjacent merge with left chunk base 0x%p size 0x%"PRIx32" right chunk base 0x%p",(void*)(uintptr_t)allocated_chunk_tmp.physical_location_base,allocated_chunk_tmp.chunk_size,(void*)(uintptr_t)free_list_chunk->physical_location_base);

            // prevent leaking metadata inline
            memset(list_chunk, 0, sizeof(*list_chunk));
            memset(free_list_chunk, 0, sizeof(*free_list_chunk));

            // left-adjacent
            merged = skadi_cap_ops_merge_noinspect(list_chunk, free_list_chunk, allocator_restriction, full_permissions, capability_type, (void**) &new_free_list_chunk);
            __ASSERT_NO_MSG(merged);
        }
        else{
            LOG_DBG("Doing a right-adjacent merge with left chunk base 0x%p size 0x%"PRIx32" right chunk base 0x%p",(void*)(uintptr_t)free_list_chunk->physical_location_base,free_list_chunk->chunk_size,(void*)(uintptr_t)allocated_chunk_tmp.physical_location_base);
            
            // prevent leaking metadata inline
            memset(list_chunk, 0, sizeof(*list_chunk));
            memset(free_list_chunk, 0, sizeof(*free_list_chunk));

            // right-adjacent
            merged = skadi_cap_ops_merge_noinspect(free_list_chunk, list_chunk, allocator_restriction, full_permissions, capability_type, (void**) &new_free_list_chunk);
            __ASSERT_NO_MSG(merged);
        }
        __ASSERT(new_free_list_chunk, "Have no free list chunk! Failed to merge chunks %p and %p",free_list_chunk, (void*)allocated_chunk_tmp.direct_capability);
    }

    if(merged){
        // need to adjust metadata

        LOG_DBG("Merged previously allocated chunk %p with free list chunk %p",(void*)allocated_chunk_tmp.direct_capability,free_list_chunk);

        allocated_chunk_tmp.chunk_size += tmp_chunk.chunk_size;
        allocated_chunk_tmp.physical_location_base = MIN(allocated_chunk_tmp.physical_location_base,tmp_chunk.physical_location_base);
    }
    else{
        LOG_DBG("Could not merge previously allocated chunk %p with free list chunk %p",(void *)allocated_chunk_tmp.direct_capability,free_list_chunk);
        // token has not changed, metadata will be updated accordingly below
        new_free_list_chunk = (struct skadi_free_list_chunk* )list_chunk;
    }

    create_free_list_chunk(new_free_list_chunk, allocated_chunk_tmp.chunk_size, allocated_chunk_tmp.physical_location_base);


    irq_unlock(irq_key);

    atomic_dec(&number_allocated_chunks);

    return true;
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(bool, __skadi_allocator_free, void *token)
    return skadi_allocator_free(token);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_allocator_free)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(atomic_val_t, __skadi_allocator_allocated_chunks)
    return atomic_get(&number_allocated_chunks);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_allocator_allocated_chunks)

static inline void skadi_allocator_add_heap(void *token){
    skadi_inspect_metadata_t inspect_metadata;
    bool ret = skadi_cap_ops_inspect(token, &inspect_metadata);
    struct skadi_free_list_chunk *new_free_list_chunk;
    unsigned int irq_key = irq_lock();
    const skadi_restriction_t allocator_restriction = SKADI_ALLOCATOR_RESTRICTION;

    __ASSERT(ret, "Expected token %p to be accessible!", token);

    if(!ret){
        irq_unlock(irq_key);
        return;
    }

    ret = skadi_cap_ops_restrict(token, allocator_restriction, 0, 0, full_permissions);

    __ASSERT(ret, "Could not add task-id restriction to new chunk!");

    new_free_list_chunk = token;

    ret = false;

    if(inspect_metadata.capability_length >= sizeof(*new_free_list_chunk)){
        create_free_list_chunk(new_free_list_chunk, inspect_metadata.capability_length, inspect_metadata.capability_base);
        ret = true;
    }

    irq_unlock(irq_key);

    if(ret){
        LOG_INF("Allocator added chunk from %"PRIx32" with length %"PRIu32, inspect_metadata.capability_base, inspect_metadata.capability_length);
    }
    else{
        LOG_INF("Allocator skipped chunk from %"PRIx32" with length %"PRIu32, inspect_metadata.capability_base, inspect_metadata.capability_length);
    }
}
// called by nuuk - inserts direct capability sliced off from the loader into capability list
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, __skadi_allocator_add_heap, uintptr_t token)
    skadi_allocator_add_heap((void*)token);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_allocator_add_heap)

#define SKADI_ALLOCATOR_MAX_USABLE_DRAM (SKADI_ARIANE_DRAM_LENGTH_BYTES - SKADI_CMT_LENGTH_BYTES)

#ifdef CONFIG_SKADI_ALLOCATOR_PRINT_FREE_MEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, __skadi_allocator_print_free_mem)
    struct skadi_free_list_chunk *iterator;
    size_t free_mem = 0;
    unsigned int blocks = 0;

    RB_FOR_EACH_CONTAINER(&skadi_arena_free_list_by_base, iterator, tree_base){
        free_mem += (size_t) iterator->chunk_size;
        blocks++;
    }

    LOG_INF("Allocator has %zu of %u free bytes (accordingly: %zu used bytes) in %u blocks!", free_mem, SKADI_ALLOCATOR_MAX_USABLE_DRAM, SKADI_ALLOCATOR_MAX_USABLE_DRAM - free_mem, blocks);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_allocator_print_free_mem)
#endif

// called by the skadi loader
static bool skadi_allocator_init_free_list(void){
    void *skadi_allocator_arena = NULL;
    const skadi_restriction_t allocator_restriction = SKADI_ALLOCATOR_RESTRICTION;

    __ASSERT_NO_MSG(__skadi_allocator_arena);
    __ASSERT_NO_MSG(__skadi_allocator_arena_start);
    __ASSERT_NO_MSG(__skadi_allocator_arena_size_bytes);

    LOG_DBG("Initial chunk has size %"PRIu32" base %p", __skadi_allocator_arena_size_bytes, (void *)__skadi_allocator_arena_start);
    
    if(!skadi_cap_ops_revoke(__skadi_allocator_arena, allocator_restriction, full_permissions, &skadi_allocator_arena) || !skadi_allocator_arena){
        return false;
    }

    create_free_list_chunk((struct skadi_free_list_chunk *) skadi_allocator_arena ,__skadi_allocator_arena_size_bytes, __skadi_allocator_arena_start);

    return true;
}

static const void *const preinit_functions[] __used Z_GENERIC_SECTION(".preinit_array") = {
    skadi_allocator_init_free_list
};
