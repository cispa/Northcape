#ifndef SKADI_IGMP_H
#define SKADI_IGMP_H
    #include <zephyr/net/igmp.h>
    #include <zephyr/skadi/skadi_subsystem.h>

    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_net_ipv4_igmp_join, struct net_if *iface, const struct in_addr *addr, const struct igmp_param *param);
    
    static inline int _skadi_net_ipv4_igmp_join(struct net_if *iface, const struct in_addr *addr, const struct igmp_param *param){
        // iface is opaque
        const struct in_addr *addr_token = skadi_cap_ops_derive_arg_ro(addr, sizeof(*addr));
        const struct igmp_param *param_token = param ? skadi_cap_ops_derive_arg_ro(param, sizeof(*param)) : NULL;
        int ret;

        __ASSERT_NO_MSG(addr_token);
        __ASSERT_NO_MSG(!param || param_token);

        if(!addr_token || (param && !param_token)){
            ret = -ENOMEM;
            goto out;
        }

        ret = __skadi_net_ipv4_igmp_join(iface, addr_token, param_token);

        out:
        if(addr_token){
            skadi_cap_ops_drop(addr_token);
        }

        if(param_token){
            skadi_cap_ops_drop(param_token);
        }

        return ret;
    }

    #define skadi_net_ipv4_igmp_join(IFACE, ADDR, PARAM) _skadi_net_ipv4_igmp_join(IFACE, ADDR, PARAM)

    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_net_ipv4_igmp_leave, struct net_if *iface, const struct in_addr *addr);
    
    static inline int _skadi_net_ipv4_igmp_leave(struct net_if *iface, const struct in_addr *addr){
        // iface is opaque
        const struct in_addr *addr_token = skadi_cap_ops_derive_arg_ro(addr, sizeof(*addr));
        int ret;

        __ASSERT_NO_MSG(addr_token);

        if(!addr_token){
            return -ENOMEM;
        }

        ret = __skadi_net_ipv4_igmp_leave(iface, addr_token);

        if(addr_token){
            skadi_cap_ops_drop(addr_token);
        }

        return ret;
    }

    #define skadi_net_ipv4_igmp_leave(IFACE, ADDR) _skadi_net_ipv4_igmp_leave(IFACE, ADDR)

#endif
