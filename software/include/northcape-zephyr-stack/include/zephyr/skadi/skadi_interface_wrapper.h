#ifndef SKADI_INTERFACE_WRAPPER_H
#define SKADI_INTERFACE_WRAPPER_H

#include <zephyr/sys/__assert.h>
#include <zephyr/sys/hash_map.h>
#include <zephyr/skadi/skadi_allocator.h>

#define SKADI_INTERFACE_WRAPPER_INIT(INSTANCE_NAME) SYS_HASHMAP_DEFINE_STATIC(INSTANCE_NAME##_map)

#define SKADI_INTERFACE_WRAPPER_INIT_GLOBAL(INSTANCE_NAME) SYS_HASHMAP_DEFINE(INSTANCE_NAME##_map)

#define SKADI_INTERFACE_WRAPPER_DECLARE(INSTANCE_NAME) extern struct sys_hashmap INSTANCE_NAME##_map

#define SKADI_INTERFACE_WRAPPER_REGISTER_NOALLOC(INSTANCE_NAME, TYPE, INIT_FN, FREE_FN, OBJECT, LOCAL_OBJ)      \
    {                                                                                                           \
        uint64_t old_value = 0;                                                                                 \
        int success;                                                                                            \
        success = sys_hashmap_insert(                                                                           \
            &INSTANCE_NAME##_map,                                                                               \
            (uint64_t)(uintptr_t)OBJECT,                                                                        \
            (uint64_t)(uintptr_t)LOCAL_OBJ,                                                                     \
            &old_value                                                                                          \
        );                                                                                                      \
        if(success < 0){                                                                                        \
            k_panic();                                                                                          \
        }                                                                                                       \
        if(success == 0){                                                                                       \
            FREE_FN((void*)(uintptr_t)old_value);                                                               \
        }                                                                                                       \
        INIT_FN(LOCAL_OBJ);                                                                                     \
    }

#define SKADI_INTERFACE_WRAPPER_REGISTER_ARRAY(INSTANCE_NAME, TYPE, INIT_FN, FREE_FN, OBJECT, SIZE)     \
    {                                                                                                   \
        TYPE *local_obj = skadi_allocator_alloc_rw_lockable(sizeof(TYPE) * SIZE);                       \
        uint64_t old_value = 0;                                                                         \
        int success;                                                                                    \
        __ASSERT_NO_MSG(local_obj);                                                                     \
        if(!local_obj){                                                                                 \
            k_panic();                                                                                  \
        }                                                                                               \
        success = sys_hashmap_insert(                                                                   \
            &INSTANCE_NAME##_map,                                                                       \
            (uint64_t)(uintptr_t)OBJECT,                                                                \
            (uint64_t)(uintptr_t)local_obj,                                                             \
            &old_value                                                                                  \
        );                                                                                              \
        if(success < 0){                                                                                \
            k_panic();                                                                                  \
        }                                                                                               \
        if(success == 0){                                                                               \
            FREE_FN((void*)(uintptr_t)old_value);                                                       \
            skadi_allocator_free((void*)(uintptr_t)old_value);                                          \
        }                                                                                               \
        INIT_FN(local_obj);                                                                             \
    }

#define SKADI_INTERFACE_WRAPPER_REGISTER(INSTANCE_NAME, TYPE, INIT_FN, FREE_FN, OBJECT)                 \
    SKADI_INTERFACE_WRAPPER_REGISTER_ARRAY(INSTANCE_NAME, TYPE, INIT_FN, FREE_FN, OBJECT, 1)

static inline void *skadi_sys_hash_map_get_assert(const struct sys_hashmap *map, void *key, const char *file, const int line){
    bool ok;
    uint64_t val;
    ok = sys_hashmap_get(map, (uint64_t)(uintptr_t)key, &val);
    __ASSERT(ok, "Mapping error at %s:%d for key %p", file, line, key);
    if(!ok){
        k_panic();
    }
    return (void*)(uintptr_t)val;
}

#define SKADI_INTERFACE_WRAPPER_TRANSLATE(INSTANCE_NAME, TYPE, OBJECT)  \
    ((TYPE*)skadi_sys_hash_map_get_assert(&INSTANCE_NAME##_map, OBJECT, __FILE__, __LINE__))

#define SKADI_INTERFACE_WRAPPER_TRANSLATE_CONST(INSTANCE_NAME, TYPE, OBJECT)  \
    ((TYPE*)skadi_sys_hash_map_get_assert(&INSTANCE_NAME##_map, (void*)OBJECT, __FILE__, __LINE__))

#define SKADI_INTERFACE_WRAPPER_REMOVE(INSTANCE_NAME, OBJECT)           \
    {                                                                   \
        bool ok;                                                        \
        uint64_t val;                                                   \
        ok = sys_hashmap_remove(                                        \
            &INSTANCE_NAME##_map,                                       \
            (uint64_t)(uintptr_t)OBJECT,                                \
            &val                                                        \
        );                                                              \
        __ASSERT_NO_MSG(ok);                                            \
        if(ok){                                                         \
            ok = skadi_allocator_free((void*)(uintptr_t)val);           \
            __ASSERT_NO_MSG(ok);                                        \
        }                                                               \
    }

#endif
