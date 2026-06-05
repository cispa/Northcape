#ifndef SKADI_NET_IP_H
#define SKADI_NET_IP_H

#include <zephyr/net/net_ip.h>
#include <zephyr/skadi/skadi_subsystem.h>

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_net_addr_pton, sa_family_t family, const char *src, void *dst);

static inline int _skadi_net_addr_pton(sa_family_t family, const char *src, void *dst){
    const void *src_token = skadi_cap_ops_derive_arg_ro(src, strlen(src)+1);
    size_t size = (family == AF_INET6) ? sizeof(struct in6_addr) : sizeof(struct in_addr);
    void *dst_token = skadi_cap_ops_derive_arg(dst, size);
    int ret;

    __ASSERT_NO_MSG(family == AF_INET6 || family == AF_INET);

    __ASSERT_NO_MSG(src_token);
    __ASSERT_NO_MSG(dst_token);

    if(!src_token || !dst_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_net_addr_pton(family, src_token, dst_token);

out:
    if(src_token){
        skadi_cap_ops_drop(src_token);
    }

    if(dst_token){
        skadi_cap_ops_drop(dst_token);
    }
    
    return ret;
}


#define skadi_net_addr_pton(FAMILY, SRC, DST) _skadi_net_addr_pton(FAMILY, SRC, DST)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(bool, __skadi_net_ipaddr_parse, const char *str, size_t str_len, struct sockaddr *addr);

static inline int _skadi_net_ipaddr_parse(const char *str, size_t str_len, struct sockaddr *addr){
    const void *src_token = skadi_cap_ops_derive_arg_ro(str, str_len + 1);
    void *addr_token = skadi_cap_ops_derive_arg(addr, sizeof(*addr));
    int ret;

    __ASSERT_NO_MSG(src_token);
    __ASSERT_NO_MSG(addr_token);

    if(!src_token || !addr_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_net_ipaddr_parse(src_token, str_len, addr_token);

out:
    if(src_token){
        skadi_cap_ops_drop(src_token);
    }

    if(addr_token){
        skadi_cap_ops_drop(addr_token);
    }
    
    return ret;
}


#define skadi_net_ipaddr_parse(STR, STR_LEN, ADDR) _skadi_net_ipaddr_parse(STR, STR_LEN, ADDR)


#endif /* SKADI_NET_IP_H*/
