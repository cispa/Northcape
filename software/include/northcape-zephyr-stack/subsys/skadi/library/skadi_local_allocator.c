#include <stdint.h>
#include <zephyr/sys/atomic.h>

#include <zephyr/skadi/skadi_ops_driver.h>


static ATOMIC_DEFINE(local_alloc_array_bitmap, CONFIG_SKADI_LIBRARY_LOCAL_ALLOCATOR_NUM_CHUNKS);

typedef struct {
    uint8_t data[CONFIG_SKADI_LIBRARY_LOCAL_ALLOCATOR_CHUNK_SIZE];
} __attribute__((__packed__)) skadi_local_alloc_chunk_t;
/* if this is not aligned, there will be a mismatch between the physical address and token, which will cause R/W errors */
BUILD_ASSERT(CONFIG_SKADI_LIBRARY_LOCAL_ALLOCATOR_CHUNK_SIZE % sizeof(void*) == 0);

static skadi_local_alloc_chunk_t local_alloc_array[CONFIG_SKADI_LIBRARY_LOCAL_ALLOCATOR_NUM_CHUNKS];

static uint32_t local_alloc_array_physical_lower_bound;

static bool init_complete;

static bool skadi_local_alloc_set_lower_bound(void){
    skadi_inspect_metadata_t metadata = {};
    bool ret;

    ret = skadi_cap_ops_inspect(local_alloc_array, &metadata);

    __ASSERT_NO_MSG(ret);

    local_alloc_array_physical_lower_bound = metadata.capability_base + skadi_get_capability_offset(local_alloc_array);

    init_complete = false;

    return ret;
}

SKADI_SUBSYSTEM_INIT_FUNCTIONS(skadi_local_alloc_set_lower_bound);

int skadi_init_complete(void){
    init_complete = true;

    return 0;
}

SYS_INIT(skadi_init_complete, APPLICATION, CONFIG_SKADI_LOADER_DISABLE_INIT_PRIORITY);

void* skadi_local_alloc(uint32_t requested_size, skadi_permission_type_t permissions){
    void *ret;
    bool derive_ok;
    skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

    if(!init_complete){
        /* allocations at init time probably long-lived - recuse ourselves for now */
        return NULL;
    }

    for(int i = 0; i < CONFIG_SKADI_LIBRARY_LOCAL_ALLOCATOR_NUM_CHUNKS; i++){

        if(!atomic_test_and_set_bit(local_alloc_array_bitmap, i)){
            /* was clear and is now set - we have just allocated this chunk */
            ret = &local_alloc_array[i];
            derive_ok = skadi_cap_ops_derive(ret, restriction, requested_size, skadi_get_capability_offset(ret), permissions, &ret);

            __ASSERT_NO_MSG(ret);
            __ASSERT_NO_MSG(derive_ok);

            if(!derive_ok){
                /* no longer "allocated" - cannot do anything with the memory */
                atomic_clear_bit(local_alloc_array_bitmap, i);
            }

            return ret;

        }
    }
    /* no memory... */
    return NULL;
}

bool skadi_phys_address_is_in_heap(uint32_t capability_base){
    return capability_base >= local_alloc_array_physical_lower_bound && capability_base < local_alloc_array_physical_lower_bound + sizeof(local_alloc_array);
}

bool skadi_local_free(void *capability, uint32_t capability_base){
    bool ret;

    /* free in early boot */
    if(!local_alloc_array_physical_lower_bound){
        return false;
    }

    if(skadi_phys_address_is_in_heap(capability_base)){
        size_t chunk_number = capability_base - local_alloc_array_physical_lower_bound;
        chunk_number = chunk_number / sizeof(skadi_local_alloc_chunk_t);

        __ASSERT_NO_MSG(chunk_number < CONFIG_SKADI_LIBRARY_LOCAL_ALLOCATOR_NUM_CHUNKS);

        atomic_clear_bit(local_alloc_array_bitmap, chunk_number);
        
        ret = skadi_cap_ops_drop(capability);

        __ASSERT_NO_MSG(ret);

        return ret;
    }
    return false;
}
