#ifndef SKADI_MSG_QUEUE_H
#define SKADI_MSG_QUEUE_H

#include <zephyr/kernel.h>
#include <zephyr/skadi/skadi_subsystem.h>

#ifdef SKADI_SUBSYSTEM
/* in the loader, use the z_impl_* variants directly */

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_msgq_init, struct k_msgq *msgq, char *buffer, size_t msg_size, uint32_t max_msgs);

static inline void skadi_msgq_init(struct k_msgq *msgq, char *buffer, size_t msg_size, uint32_t max_msgs){
    char *buffer_wrapper = skadi_cap_ops_derive_arg(buffer, msg_size*max_msgs);

    __ASSERT_NO_MSG(buffer_wrapper);

    __skadi_msgq_init(msgq, buffer_wrapper, msg_size, max_msgs);
    /* value used down below*/
    msgq->msg_size = msg_size;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_msgq_alloc_init, struct k_msgq *msgq, size_t msg_size, uint32_t max_msgs);

static inline int skadi_msgq_alloc_init(struct k_msgq *msgq, size_t msg_size, uint32_t max_msgs){
    return __skadi_msgq_alloc_init(msgq, msg_size, max_msgs);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_msgq_cleanup, struct k_msgq *msgq);

static inline int skadi_msgq_cleanup(struct k_msgq *msgq){
    return __skadi_msgq_cleanup(msgq);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_msgq_put, struct k_msgq *msgq, const void *data, k_timeout_t timeout);

static inline int skadi_msgq_put(struct k_msgq *msgq, const void *data, k_timeout_t timeout){
    const void *data_token = skadi_cap_ops_derive_arg_ro(data, msgq->msg_size);
    int ret;
    __ASSERT_NO_MSG(data_token);

    if(!data_token){
        return -ENOMEM;
    }

    ret = __skadi_msgq_put(msgq, data_token, timeout);

    skadi_cap_ops_drop(data_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_msgq_get, struct k_msgq *msgq, void *data, k_timeout_t timeout);

static inline int skadi_msgq_get(struct k_msgq *msgq, void *data, k_timeout_t timeout){
    void *data_wrapper = skadi_cap_ops_derive_arg(data, msgq->msg_size);
    int ret;

    __ASSERT_NO_MSG(data_wrapper);

    ret = __skadi_msgq_get(msgq, data_wrapper, timeout);

    skadi_cap_ops_drop(data_wrapper);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_msgq_peek, struct k_msgq *msgq, void *data);

static inline int skadi_msgq_peek(struct k_msgq *msgq, void *data){
    void *data_wrapper = skadi_cap_ops_derive_arg(data, msgq->msg_size);
    int ret;

    __ASSERT_NO_MSG(data_wrapper);

    ret = __skadi_msgq_peek(msgq, data_wrapper);

    skadi_cap_ops_drop(data_wrapper);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_msgq_peek_at, struct k_msgq *msgq, void *data, uint32_t idx);

static inline int skadi_msgq_peek_at(struct k_msgq *msgq, void *data, uint32_t idx){
    void *data_wrapper = skadi_cap_ops_derive_arg(data, msgq->msg_size);
    int ret;

    __ASSERT_NO_MSG(data_wrapper);

    ret = __skadi_msgq_peek_at(msgq, data_wrapper, idx);

    skadi_cap_ops_drop(data_wrapper);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_msgq_purge, struct k_msgq *msgq);

static inline void skadi_msgq_purge(struct k_msgq *msgq){

    __ASSERT_NO_MSG(msgq);

    __skadi_msgq_purge(msgq);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_msgq_get_attrs, struct k_msgq *msgq, struct k_msgq_attrs *attrs);

static inline void skadi_msgq_get_attrs(struct k_msgq *msgq, struct k_msgq_attrs *attrs)
{
    struct k_msgq_attrs *attrs_wrapper = skadi_cap_ops_derive_arg_wo(attrs, sizeof(*attrs));

    __ASSERT_NO_MSG(attrs_wrapper);

    if(!attrs_wrapper){
        return;
    }

    __skadi_msgq_get_attrs(msgq, attrs_wrapper);

    (void)skadi_cap_ops_drop(attrs_wrapper);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint32_t, __skadi_msgq_num_used_get, struct k_msgq *msgq);

#define skadi_msgq_num_used_get(QUEUE) __skadi_msgq_num_used_get(QUEUE)

#endif /* SKADI_SUBSYSTEM */

extern void skadi_subsystem_yield(void);
#endif /* SKADI_MSG_QUEUE_H */
