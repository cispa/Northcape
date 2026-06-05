#ifndef SKADI_SOCKET_SERVICE_H
#define SKADI_SOCKET_SERVICE_H

#include <zephyr/net/socket_service.h>
#include <zephyr/skadi/skadi_subsystem.h>

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_net_socket_service_register, const struct net_socket_service_desc *service, struct zsock_pollfd *fds, int len, void *user_data);

static inline int _skadi_net_socket_service_register(struct net_socket_service_desc *service, struct zsock_pollfd *fds, int len, void *user_data){
    /* need to be writable for response */
    struct zsock_pollfd *fds_token = len ? skadi_cap_ops_derive_arg(fds, sizeof(*fds) * len) : NULL;
    struct net_socket_service_desc *service_token;
    int ret;
    const bool is_unregister = (fds == NULL);

    service_token = service->is_initialized ?  service->service_token : skadi_cap_ops_derive_arg(service, sizeof(*service));

#if CONFIG_NET_SOCKETS_LOG_LEVEL >= LOG_LEVEL_DBG
    if(!service->is_initialized){
        service->owner = skadi_cap_ops_derive_arg_ro(service->owner, strlen(service->owner) + 1);

        __ASSERT_NO_MSG(service->owner);
    }
#endif

    if(!is_unregister){
        service->pev = skadi_cap_ops_derive_arg(service->pev, sizeof(*service->pev) * service->pev_len);
    }

    __ASSERT_NO_MSG(service->pev);

    if(!is_unregister){
        for(int i = 0; i < len; i++){
            // socket service needs a back reference to the descriptor
            // we restore this later (out)
            service->pev[i].svc = service_token;
        }
    }

    if(!service->is_initialized){
        service->idx = skadi_cap_ops_derive_arg(service->idx, sizeof(*service->idx));
    }

    __ASSERT_NO_MSG(service->idx);

    if(!service->pev || !service->idx || !service_token){
        ret = -ENOMEM;
        goto out;
    }

    service->is_initialized = true;

    ret = __skadi_net_socket_service_register(service_token, fds_token, len, user_data);

    service->service_token = service_token;

    out:

    /* this is ephemeral, can only be read during the call */
    if(fds_token){
        skadi_cap_ops_drop(fds_token);
    }


    return ret;    
}



#define skadi_net_socket_service_register(SERVICE, FDS, LEN, USER_DATA) _skadi_net_socket_service_register(SERVICE, FDS, LEN, USER_DATA)
#define skadi_net_socket_service_unregister(SERVICE) skadi_net_socket_service_register(SERVICE, NULL, 0, NULL)

static inline void skadi_net_socket_service_cleanup(struct net_socket_service_desc *service){
    __ASSERT_NO_MSG(service->is_initialized);
    __ASSERT_NO_MSG(service->service_token);

    if(service->pev){
        skadi_cap_ops_drop(service->pev);
    }

    if(service->idx){
        skadi_cap_ops_drop(service->idx);
    }

#if CONFIG_NET_SOCKETS_LOG_LEVEL >= LOG_LEVEL_DBG
    if(service->owner){
        skadi_cap_ops_drop(service->owner);
    }
#endif

    if(service->service_token){
        skadi_cap_ops_drop(service->service_token);
    }
}

#endif /* SKADI_SUBSYSTEM */

#endif /* SKADI_SOCKET_SERVICE_H */
