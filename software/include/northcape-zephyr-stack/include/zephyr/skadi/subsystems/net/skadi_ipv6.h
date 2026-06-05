#ifndef SKADI_IPV6_H
#define SKADI_IPV6_H
    #include <zephyr/skadi/skadi_subsystem.h>

#ifdef CONFIG_NET_IPV6_MLD
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_net_ipv6_mld_join, struct net_if *iface, const struct in6_addr *addr);
    
    static inline int _skadi_net_ipv6_mld_join(struct net_if *iface, const struct in6_addr *addr){
        // iface is opaque
        const struct in6_addr *addr_token = skadi_cap_ops_derive_arg_ro(addr, sizeof(*addr));
        int ret;

        __ASSERT_NO_MSG(addr_token);

        if(!addr_token){
            return -ENOMEM;
        }
        ret = __skadi_net_ipv6_mld_join(iface, addr_token);

        if(addr_token){
            skadi_cap_ops_drop(addr_token);
        }

        return ret;
    }

    #define skadi_net_ipv6_mld_join(IFACE, ADDR) _skadi_net_ipv6_mld_join(IFACE, ADDR)

    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_net_ipv6_mld_leave, struct net_if *iface, const struct in6_addr *addr);
    
    static inline int _skadi_net_ipv6_mld_leave(struct net_if *iface, const struct in6_addr *addr){
        // iface is opaque
        const struct in6_addr *addr_token = skadi_cap_ops_derive_arg_ro(addr, sizeof(*addr));
        int ret;

        __ASSERT_NO_MSG(addr_token);

        if(!addr_token){
            return -ENOMEM;
        }

        ret = __skadi_net_ipv6_mld_leave(iface, addr_token);

        if(addr_token){
            skadi_cap_ops_drop(addr_token);
        }

        return ret;
    }

    #define skadi_net_ipv6_mld_leave(IFACE, ADDR) _skadi_net_ipv6_mld_leave(IFACE, ADDR)
#else
    static inline int skadi_net_ipv6_mld_join(struct net_if *iface, const struct in6_addr *addr){
        ARG_UNUSED(face);
        ARG_UNUSED(addr);
        return -ENOTSUP;
    }

    static inline int skadi_net_ipv6_mld_leave(struct net_if *iface, const struct in6_addr *addr){
        ARG_UNUSED(face);
        ARG_UNUSED(addr);
        return -ENOTSUP;
    }
#endif


#endif
