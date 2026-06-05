#ifndef SKADI_STACK_H
#define SKADI_STACK_H

#include <zephyr/kernel.h>
#include <zephyr/skadi/skadi_subsystem.h>


#ifdef SKADI_SUBSYSTEM
/* in the loader, use the z_impl_* variants directly */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_stack_init, struct k_stack *s, stack_data_t *buffer, uint32_t num_entries);

static inline void skadi_stack_init(struct k_stack *s, stack_data_t *buffer, uint32_t num_entries){
    stack_data_t *mem_wrapper = skadi_cap_ops_derive_arg(buffer, num_entries * sizeof(stack_data_t));

    __ASSERT_NO_MSG(s);

    __ASSERT_NO_MSG(mem_wrapper);

    __skadi_stack_init(s, mem_wrapper, num_entries);

    s->alloc_mem = mem_wrapper;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int32_t, __skadi_stack_alloc_init, struct k_stack *s, uint32_t num_entries);

static inline int32_t skadi_stack_alloc_init(struct k_stack *s, uint32_t num_entries){
    int32_t ret;

    __ASSERT_NO_MSG(s);


    ret = __skadi_stack_alloc_init(s, num_entries);

    s->alloc_mem = NULL;

    return ret;
}



SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_stack_cleanup, struct k_stack *s);

static inline int skadi_stack_cleanup(struct k_stack *s){
    int ret;

    __ASSERT_NO_MSG(s);


    ret = __skadi_stack_cleanup(s);

    if(!ret){
        if(s->alloc_mem){
            skadi_cap_ops_drop(s->alloc_mem);
        }
        s->alloc_mem = 0;
    }

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_stack_push, struct k_stack *s, stack_data_t data);

static inline int skadi_stack_push(struct k_stack *s, stack_data_t data){
    __ASSERT_NO_MSG(s);

    return __skadi_stack_push(s, data);
}


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_stack_pop, struct k_stack *s, stack_data_t *data, k_timeout_t timeout);

static inline int skadi_stack_pop(struct k_stack *s, stack_data_t *data, k_timeout_t timeout){
    int ret;
    stack_data_t *data_wr = skadi_cap_ops_derive_arg_wo(data, sizeof(*data));

    __ASSERT_NO_MSG(data_wr);

    if(!data_wr){
        return -ENOMEM;
    }

    __ASSERT_NO_MSG(s);

    ret = __skadi_stack_pop(s, data_wr, timeout);

    (void)skadi_cap_ops_drop(data_wr);

    return ret;
}

#endif /* SKADI_SUBSYSTEM */


#endif /* SKADI_STACK_H */
