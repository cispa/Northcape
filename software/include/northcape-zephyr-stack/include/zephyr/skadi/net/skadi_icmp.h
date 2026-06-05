#ifndef SKADI_ICMP_H
#define SKADI_ICMP_H

#include <zephyr/net/icmp.h>
#include <zephyr/skadi/skadi_subsystem.h>

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_net_icmp_init_ctx, struct net_icmp_ctx *ctx, uint8_t type, uint8_t code, net_icmp_handler_t handler);

static inline int _skadi_net_icmp_init_ctx(struct net_icmp_ctx *ctx, uint8_t type, uint8_t code, net_icmp_handler_t handler){
    struct net_icmp_ctx *ctx_token = skadi_cap_ops_derive_arg(ctx, sizeof(*ctx));
    int ret;

    __ASSERT_NO_MSG(ctx_token);

    if(!ctx_token){
        return -ENOMEM;
    }

    ret = __skadi_net_icmp_init_ctx(ctx_token, type, code, handler);

    ctx->ctx_token = ctx_token;

    return ret;
}


#define skadi_net_icmp_init_ctx(CTX, TYPE, CODE, HANDLER) _skadi_net_icmp_init_ctx(CTX, TYPE, CODE, HANDLER)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_net_icmp_cleanup_ctx, struct net_icmp_ctx *ctx);

static inline int _skadi_net_icmp_cleanup_ctx(struct net_icmp_ctx *ctx){
    int ret;

    __ASSERT_NO_MSG(ctx->ctx_token);

    ret = __skadi_net_icmp_cleanup_ctx(ctx->ctx_token);

    skadi_cap_ops_drop(ctx->ctx_token);

    return ret;
}


#define skadi_net_icmp_cleanup_ctx(CTX) _skadi_net_icmp_cleanup_ctx(CTX)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_net_icmp_send_echo_request, struct net_icmp_ctx *ctx, struct net_if *iface, struct sockaddr *dst, struct net_icmp_ping_params *params, void *user_data);

static inline int _skadi_net_icmp_send_echo_request(struct net_icmp_ctx *ctx, struct net_if *iface, struct sockaddr *dst, struct net_icmp_ping_params *params, void *user_data){
    int ret;
    struct sockaddr *dst_token = skadi_cap_ops_derive_arg(dst, sizeof(*dst));
    struct net_icmp_ping_params *params_token = params ? skadi_cap_ops_derive_arg(params, sizeof(*params)) : params;

    __ASSERT_NO_MSG(ctx->ctx_token);
    __ASSERT_NO_MSG(dst_token);
    __ASSERT_NO_MSG(!params || params_token);

    if(!dst_token || (params && !params_token)){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_net_icmp_send_echo_request(ctx->ctx_token, iface, dst_token, params_token, user_data);

    out:

    if(dst_token){
        skadi_cap_ops_drop(dst_token);
    }

    if(params_token){
        skadi_cap_ops_drop(params_token);
    }

    return ret;
}


#define skadi_net_icmp_send_echo_request(CTX, IFACE, DST, PARAMS, USER_DATA) _skadi_net_icmp_send_echo_request(CTX, IFACE, DST, PARAMS, USER_DATA)

#endif /* SKADI_ICMP_H*/
