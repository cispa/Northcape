#ifndef SKADI_NET_SOCKET_H
#define SKADI_NET_SOCKET_H

#include <zephyr/kernel.h>
#include <zephyr/skadi/skadi_subsystem.h>

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_poll, struct zsock_pollfd *fds, int nfds, int timeout);

static inline int _skadi_zsock_poll(struct zsock_pollfd *fds, int nfds, int timeout){
    /* need to be writable for response */
    struct zsock_pollfd *fds_token = nfds ? skadi_cap_ops_derive_arg(fds, sizeof(*fds) * nfds) : NULL;
    int ret;

    __ASSERT_NO_MSG(fds_token || !nfds);

    if(!fds_token && nfds){
        return -ENOMEM;
    }

    ret = __skadi_zsock_poll(fds_token, nfds, timeout);

    if(fds_token){
        skadi_cap_ops_drop(fds_token);
    }

    return ret;

    
}

#define skadi_zsock_poll(FDS, NFDS, TIMEOUT) _skadi_zsock_poll(FDS, NFDS, TIMEOUT)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_select, int nfds, zsock_fd_set *readfds, zsock_fd_set *writefds, zsock_fd_set *exceptfds, struct zsock_timeval *timeout);

static inline int _skadi_zsock_select(int nfds, zsock_fd_set *readfds, zsock_fd_set *writefds, zsock_fd_set *exceptfds, struct zsock_timeval *timeout){
    /* fixed-size types, writable for response */
    struct zsock_fd_set *readfds_token = skadi_cap_ops_derive_arg(readfds, sizeof(*readfds)), *writefds_token = skadi_cap_ops_derive_arg(writefds, sizeof(*writefds));
    struct zsock_fd_set *exceptfds_token = skadi_cap_ops_derive_arg(exceptfds, sizeof(*exceptfds));
    struct zsock_timeval *timeout_token = skadi_cap_ops_derive_arg(timeout, sizeof(*timeout));

    int ret;

    __ASSERT_NO_MSG(readfds_token && writefds_token && exceptfds_token && timeout_token);

    if(!(readfds_token && writefds_token && exceptfds_token && timeout_token)){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_zsock_select(nfds, readfds_token, writefds_token, exceptfds_token, timeout_token);

    out:

    if(readfds_token){
        skadi_cap_ops_drop(readfds_token);
    }

    if(writefds_token){
        skadi_cap_ops_drop(writefds_token);
    }

    if(exceptfds_token){
        skadi_cap_ops_drop(exceptfds_token);
    }

    if(timeout_token){
        skadi_cap_ops_drop(timeout_token);
    }

    return ret;

    
}

#define skadi_zsock_select(NFDS, READFDS, WRITEFDS, EXCEPTFDS, TIMEOUT) _skadi_zsock_select(NFDS, READFDS, WRITEFDS, EXCEPTFDS, TIMEOUT)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_net_if_get_name, struct net_if *iface, char *buf, int len);

static inline int _skadi_net_if_get_name(struct net_if *iface, char *buf, int len){
    /* fixed-size types, writable for response */
    char *buf_token = skadi_cap_ops_derive_arg_wo(buf, len);
    int ret;

    __ASSERT_NO_MSG(buf_token);

    if(!buf_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_net_if_get_name(iface, buf, len);

    out:

    if(buf_token){
        skadi_cap_ops_drop(buf_token);
    }

    return ret;

    
}

#define skadi_net_if_get_name(IFACE, BUF, LEN) _skadi_net_if_get_name(IFACE, BUF, LEN)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(struct net_if *, __skadi_net_if_get_by_index, int index);

static inline struct net_if* _skadi_net_if_get_by_index(int index){

    return __skadi_net_if_get_by_index(index);
}

#define skadi_net_if_get_by_index(INDEX) _skadi_net_if_get_by_index(INDEX)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_net_if_get_by_name, const char *name);

static inline int _skadi_net_if_get_by_name(const char *name){
    /* fixed-size types, writable for response */
    const char *name_token = skadi_cap_ops_derive_arg_ro(name, strlen(name) + 1);
    int ret;

    __ASSERT_NO_MSG(name_token);

    if(!name_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_net_if_get_by_name(name_token);

    out:

    if(name_token){
        skadi_cap_ops_drop(name_token);
    }

    return ret;

    
}

#define skadi_net_if_get_by_name(NAME) _skadi_net_if_get_by_name(NAME)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(struct net_if *, __skadi_net_if_get_default);

static inline struct net_if* _skadi_net_if_get_default(void){
    return __skadi_net_if_get_default();
}

#define skadi_net_if_get_default _skadi_net_if_get_default

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_getaddrinfo, const char *host, const char *service, const struct zsock_addrinfo *hints, struct zsock_addrinfo **res);

static inline int _skadi_zsock_getaddrinfo(const char *host, const char *service, const struct zsock_addrinfo *hints, struct zsock_addrinfo **res){
    const char *host_token = skadi_cap_ops_derive_arg_ro(host, strlen(host) + 1);
    const char *service_token = skadi_cap_ops_derive_arg_ro(service, strlen(service) + 1);
    const struct zsock_addrinfo *hints_token = skadi_cap_ops_derive_arg_ro(hints, sizeof(*hints));
    struct zsock_addrinfo **res_token = skadi_cap_ops_derive_arg(res, sizeof(*res));

    int ret;

    __ASSERT_NO_MSG(host_token);
    __ASSERT_NO_MSG(service_token);
    __ASSERT_NO_MSG(hints_token);
    __ASSERT_NO_MSG(res_token);

    if(!host_token || !service_token || !hints_token || !res_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_zsock_getaddrinfo(host_token, service_token, hints_token, res_token);

    out:

    if(host_token){
        skadi_cap_ops_drop(host_token);
    }

    if(service_token){
        skadi_cap_ops_drop(service_token);
    }

    if(hints_token){
        skadi_cap_ops_drop(hints_token);
    }

    if(res_token){
        skadi_cap_ops_drop(res_token);
    }

    return ret;

    
}

#define skadi_zsock_getaddrinfo(HOST_TOKEN, SERVICE_TOKEN, HINTS_TOKEN, RES_TOKEN) _skadi_zsock_getaddrinfo(HOST_TOKEN, SERVICE_TOKEN, HINTS_TOKEN, RES_TOKEN)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_getnameinfo, const struct sockaddr *addr, socklen_t addrlen, char *host, socklen_t hostlen, char *serv, socklen_t servlen, int flags);

static inline int _skadi_zsock_getnameinfo(const struct sockaddr *addr, socklen_t addrlen, char *host, socklen_t hostlen, char *serv, socklen_t servlen, int flags){
    const struct sockaddr *addr_token = skadi_cap_ops_derive_arg_ro(addr, addrlen);
    char *host_token = skadi_cap_ops_derive_arg(host, hostlen);
    char *serv_token = skadi_cap_ops_derive_arg(serv, servlen);

    int ret;

    __ASSERT_NO_MSG(addr_token);
    __ASSERT_NO_MSG(host_token);
    __ASSERT_NO_MSG(serv_token);

    if(!addr_token || !host_token || !serv_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_zsock_getnameinfo(addr_token, addrlen, host_token, hostlen, serv_token, servlen, flags);

    out:

    if(addr_token){
        skadi_cap_ops_drop(addr_token);
    }

    if(host_token){
        skadi_cap_ops_drop(host_token);
    }

    if(serv_token){
        skadi_cap_ops_drop(serv_token);
    }

    return ret;

    
}

#define skadi_zsock_getnameinfo(ADDR, ADDRLEN, HOST, HOSTLEN, SERV, SERVLEN, FLAGS) _skadi_zsock_getnameinfo(ADDR, ADDRLEN, HOST, HOSTLEN, SERV, SERVLEN, FLAGS)


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_getpeername, int sock, struct sockaddr *addr, socklen_t *addrlen);

static inline int _skadi_zsock_getpeername(int sock, struct sockaddr *addr, socklen_t *addrlen){
    struct sockaddr *addr_token = skadi_cap_ops_derive_arg(addr, *addrlen);
    socklen_t *addrlen_token = skadi_cap_ops_derive_arg(addrlen, sizeof(*addrlen));

    int ret;

    __ASSERT_NO_MSG(addr_token);
    __ASSERT_NO_MSG(addrlen_token);

    if(!addr_token || !addrlen_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_zsock_getpeername(sock, addr_token, addrlen_token);

    out:

    if(addr_token){
        skadi_cap_ops_drop(addr_token);
    }

    if(addrlen_token){
        skadi_cap_ops_drop(addrlen_token);
    }

    return ret;

    
}

#define skadi_zsock_getpeername(SOCK, ADDR, ADDRLEN) _skadi_zsock_getpeername(SOCK, ADDR, ADDRLEN)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_accept, int sock, struct sockaddr *addr, socklen_t *addrlen);

static inline int _skadi_zsock_accept(int sock, struct sockaddr *addr, socklen_t *addrlen){
    struct sockaddr *addr_token = skadi_cap_ops_derive_arg(addr, *addrlen);
    socklen_t *addrlen_token = skadi_cap_ops_derive_arg(addrlen, sizeof(*addrlen));

    int ret;

    __ASSERT_NO_MSG(addr_token);
    __ASSERT_NO_MSG(addrlen_token);

    if(!addr_token || !addrlen_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_zsock_accept(sock, addr_token, addrlen_token);

    out:

    if(addr_token){
        skadi_cap_ops_drop(addr_token);
    }

    if(addrlen_token){
        skadi_cap_ops_drop(addrlen_token);
    }

    return ret;

    
}

#define skadi_zsock_accept(SOCK, ADDR, ADDRLEN) _skadi_zsock_accept(SOCK, ADDR, ADDRLEN)


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_bind, int sock, const struct sockaddr *addr, socklen_t addrlen);

static inline int _skadi_zsock_bind(int sock, const struct sockaddr *addr, socklen_t addrlen){
    const struct sockaddr *addr_token = skadi_cap_ops_derive_arg_ro(addr, addrlen);

    int ret;

    __ASSERT_NO_MSG(addr_token);

    if(!addr_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_zsock_bind(sock, addr_token, addrlen);

    out:

    if(addr_token){
        skadi_cap_ops_drop(addr_token);
    }

    return ret;  
}

#define skadi_zsock_bind(SOCK, ADDR, ADDRLEN) _skadi_zsock_bind(SOCK, ADDR, ADDRLEN)


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_connect, int sock, const struct sockaddr *addr, socklen_t addrlen);

static inline int _skadi_zsock_connect(int sock, const struct sockaddr *addr, socklen_t addrlen){
    const struct sockaddr *addr_token = skadi_cap_ops_derive_arg_ro(addr, addrlen);

    int ret;

    __ASSERT_NO_MSG(addr_token);

    if(!addr_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_zsock_connect(sock, addr_token, addrlen);

    out:

    if(addr_token){
        skadi_cap_ops_drop(addr_token);
    }

    return ret;  
}

#define skadi_zsock_connect(SOCK, ADDR, ADDRLEN) _skadi_zsock_connect(SOCK, ADDR, ADDRLEN)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_getsockname, int sock, struct sockaddr *addr, socklen_t *addrlen);

static inline int _skadi_zsock_getsockname(int sock, struct sockaddr *addr, socklen_t *addrlen){
    struct sockaddr *addr_token = skadi_cap_ops_derive_arg(addr, *addrlen);
    socklen_t *addrlen_token = skadi_cap_ops_derive_arg(addrlen, sizeof(*addrlen));

    int ret;

    __ASSERT_NO_MSG(addr_token);
    __ASSERT_NO_MSG(addrlen_token);

    if(!addr_token || !addrlen_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_zsock_getsockname(sock, addr_token, addrlen_token);

    out:

    if(addr_token){
        skadi_cap_ops_drop(addr_token);
    }

    if(addrlen_token){
        skadi_cap_ops_drop(addrlen_token);
    }

    return ret;

    
}

#define skadi_zsock_getsockname(SOCK, ADDR, ADDRLEN) _skadi_zsock_getsockname(SOCK, ADDR, ADDRLEN)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_getsockopt, int sock, int level, int optname, void *optval, socklen_t *optlen);

static inline int _skadi_zsock_getsockopt(int sock, int level, int optname, void *optval, socklen_t *optlen){
    void *optval_token = skadi_cap_ops_derive_arg(optval, *optlen);
    socklen_t *optlen_token = skadi_cap_ops_derive_arg(optlen, sizeof(*optlen));

    int ret;

    __ASSERT_NO_MSG(optval_token);
    __ASSERT_NO_MSG(optlen_token);

    if(!optval_token || !optlen_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_zsock_getsockopt(sock, level, optname, optval_token, optlen_token);

    out:

    if(optval_token){
        skadi_cap_ops_drop(optval_token);
    }

    if(optlen_token){
        skadi_cap_ops_drop(optlen_token);
    }

    return ret;

    
}

#define skadi_zsock_getsockopt(SOCK, LEVEL, OPTNAME, OPTVAL, OPTLEN) _skadi_zsock_getsockopt(SOCK, LEVEL, OPTNAME, OPTVAL, OPTLEN)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_setsockopt, int sock, int level, int optname, const void *optval, socklen_t optlen);

static inline int _skadi_zsock_setsockopt(int sock, int level, int optname, const void *optval, socklen_t optlen){
    const void *optval_token = skadi_cap_ops_derive_arg_ro(optval, optlen);

    int ret;

    __ASSERT_NO_MSG(optval_token);

    if(!optval_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_zsock_setsockopt(sock, level, optname, optval_token, optlen);

    out:

    if(optval_token){
        skadi_cap_ops_drop(optval_token);
    }

    return ret;

    
}

#define skadi_zsock_setsockopt(SOCK, LEVEL, OPTNAME, OPTVAL, OPTLEN) _skadi_zsock_setsockopt(SOCK, LEVEL, OPTNAME, OPTVAL, OPTLEN)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_shutdown, int sock, int how);

static inline int _skadi_zsock_shutdown(int sock, int how){
    return __skadi_zsock_shutdown(sock, how);
}

#define skadi_zsock_shutdown(SOCK, HOW) _skadi_zsock_shutdown(SOCK, HOW)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_socket, int family, int type, int proto);

static inline int _skadi_zsock_socket(int family, int type, int proto){
    return __skadi_zsock_socket(family, type, proto);
}

#define skadi_zsock_socket(FAMILY, TYPE, PROTO) _skadi_zsock_socket(FAMILY, TYPE, PROTO)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_socketpair, int family, int type, int proto, int sv[2]);

static inline int _skadi_zsock_socketpair(int family, int type, int proto, int sv[2]){
    int *sv_token = skadi_cap_ops_derive_arg_wo(sv, 2*sizeof(int));
    int ret;

    __ASSERT_NO_MSG(sv_token);

    if(!sv_token){
        return -ENOMEM;
    }

    ret = __skadi_zsock_socketpair(family, type, proto, sv_token);

    skadi_cap_ops_drop(sv_token);

    return ret;
}

#define skadi_zsock_socketpair(FAMILY, TYPE, PROTO, SV) _skadi_zsock_socketpair(FAMILY, TYPE, PROTO, SV)


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_recvfrom, int sock, void *buf, size_t max_len, int flags, struct sockaddr *src_addr, socklen_t *addrlen);

static inline int _skadi_zsock_recvfrom(int sock, void *buf, size_t max_len, int flags, struct sockaddr *src_addr, socklen_t *addrlen){
    void *buf_token = skadi_cap_ops_derive_arg(buf, max_len);
    struct sockaddr *src_addr_token = src_addr ? skadi_cap_ops_derive_arg(src_addr, *addrlen) : NULL;
    socklen_t *addrlen_token = src_addr ? skadi_cap_ops_derive_arg(addrlen, sizeof(*addrlen)) : NULL;

    int ret;

    __ASSERT_NO_MSG(buf_token);
    if(src_addr){
        __ASSERT_NO_MSG(src_addr_token);
    }
    if(addrlen){
        __ASSERT_NO_MSG(addrlen_token);
    }

    if(!buf_token || (src_addr && !src_addr_token) || (addrlen && !addrlen_token)){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_zsock_recvfrom(sock, buf_token, max_len, flags, src_addr_token, addrlen_token);

    out:

    if(buf_token){
        skadi_cap_ops_drop(buf_token);
    }

    if(src_addr_token){
        skadi_cap_ops_drop(src_addr_token);
    }

    if(addrlen_token){
        skadi_cap_ops_drop(addrlen_token);
    }

    return ret;

    
}
#define skadi_zsock_recv(SOCK, BUF, MAX_LEN, FLAGS) _skadi_zsock_recvfrom(SOCK, BUF, MAX_LEN, FLAGS, NULL, NULL)
#define skadi_zsock_recvfrom(SOCK, BUF, MAX_LEN, FLAGS, SOCKADDR, SOCKLEN) _skadi_zsock_recvfrom(SOCK, BUF, MAX_LEN, FLAGS, SOCKADDR, SOCKLEN)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(ssize_t, __skadi_zsock_sendto, int sock, const void *buf, size_t len, int flags, const struct sockaddr *dst_addr, socklen_t addrlen);

static inline ssize_t _skadi_zsock_sendto(int sock, const void *buf, size_t len, int flags, const struct sockaddr *dst_addr, socklen_t addrlen){
    const void *buf_token = skadi_cap_ops_derive_arg_ro(buf, len);
    const struct sockaddr *dst_addr_token = dst_addr ? skadi_cap_ops_derive_arg_ro(dst_addr, addrlen) : NULL;

    ssize_t ret;

    __ASSERT_NO_MSG(buf_token);
    
    if(dst_addr){
        __ASSERT_NO_MSG(dst_addr_token);
    }

    if(!buf_token || (!dst_addr_token && dst_addr)){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_zsock_sendto(sock, buf_token, len, flags, dst_addr_token, addrlen);

    out:

    if(buf_token){
        skadi_cap_ops_drop(buf_token);
    }

    if(dst_addr_token){
        skadi_cap_ops_drop(dst_addr_token);
    }

    return ret;

    
}
#define skadi_zsock_send(SOCK, BUF, LEN, FLAGS) _skadi_zsock_sendto(SOCK, BUF, LEN, FLAGS, NULL, 0)
#define skadi_zsock_sendto(SOCK, BUF, LEN, FLAGS, SOCKADDR, SOCKLEN) _skadi_zsock_sendto(SOCK, BUF, LEN, FLAGS, SOCKADDR, SOCKLEN)

static inline ssize_t _skadi_zsock_sendto_0copy(int sock, const void *buf, size_t len, int flags, const struct sockaddr *dst_addr, socklen_t addrlen){
    const struct sockaddr *dst_addr_token = dst_addr ? skadi_cap_ops_derive_arg_ro(dst_addr, addrlen) : NULL;
    ssize_t ret;
    
    if(dst_addr){
        __ASSERT_NO_MSG(dst_addr_token);
    }

    if((!dst_addr_token && dst_addr)){
        return -ENOMEM;
    }
    /* nothing special on the callee side - handled via setsockopt */
    ret = __skadi_zsock_sendto(sock, buf, len, flags, dst_addr_token, addrlen);


    if(dst_addr_token){
        skadi_cap_ops_drop(dst_addr_token);
    }

    return ret;

    
}
/**
 * @brief Send a message without copying it.
 * Imposes additional restrictions on the buffer:
 * - buffer must have read permission, no restriction
 * - buffer needs to be alive until the completion interrupt is called with it
 * - buffer must have reference count of 0 at the time of call, will be leaked otherwise
 * - buffer must be small enough to fit into a single packet (for now)
 */
#define skadi_zsock_send_0copy(SOCK, BUF, LEN, FLAGS) _skadi_zsock_sendto_0copy(SOCK, BUF, LEN, FLAGS, NULL, 0)
#define skadi_zsock_sendto_0copy(SOCK, BUF, LEN, FLAGS, SOCKADDR, SOCKLEN) _skadi_zsock_sendto_0copy(SOCK, BUF, LEN, FLAGS, SOCKADDR, SOCKLEN)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_recvmsg, int sock, struct msghdr *msg, int flags);

static inline int _skadi_zsock_recvmsg(int sock, struct msghdr *msg, int flags){
    struct msghdr *msg_token = skadi_cap_ops_derive_arg(msg, sizeof(*msg));
    
    int ret;

    __ASSERT_NO_MSG(msg_token);
    
    if(!msg_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_zsock_recvmsg(sock, msg, flags);

    out:

    if(msg_token){
        skadi_cap_ops_drop(msg_token);
    }

    return ret;

    
}
#define skadi_zsock_recvmsg(SOCK, MSGHDR, FLAGS) _skadi_zsock_recvmsg(SOCK, MSGHDR, FLAGS)

static inline size_t skadi_get_addr_size_for_family(sa_family_t family){
    __ASSERT_NO_MSG(family == AF_INET || family == AF_INET6);
    switch(family){
        case AF_INET:
            return NET_IPV4_ADDR_SIZE;
        case AF_INET6:
            return NET_IPV6_ADDR_SIZE;
        default: return -1;
    }
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(char*, __skadi_zsock_inet_ntop, sa_family_t family, const void *src, char *dst, size_t size);

static inline char* _skadi_zsock_inet_ntop(sa_family_t family, const void *src, char *dst, size_t size){
    const void *src_token = skadi_cap_ops_derive_arg_ro(src, skadi_get_addr_size_for_family(family));
    void *dst_token = skadi_cap_ops_derive_arg(dst, size);
    char* ret;

    __ASSERT_NO_MSG(src_token);
    __ASSERT_NO_MSG(dst_token);
    
    if(!src_token || !dst_token){
        ret = NULL;
        goto out;
    }

    ret = __skadi_zsock_inet_ntop(family, src_token, dst_token, size);

    out:

    if(src_token){
        skadi_cap_ops_drop(src_token);
    }

    if(dst_token){
        skadi_cap_ops_drop(dst_token);
    }

    return ret;

    
}

#define skadi_zsock_inet_ntop(FAMILY, SRC, DST, SIZE) _skadi_zsock_inet_ntop(FAMILY, SRC, DST, SIZE) 

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_inet_pton, sa_family_t family, const char *src, void *dst);

static inline int _skadi_zsock_inet_pton(sa_family_t family, const char *src, void *dst){
    const size_t size = strlen(src) + 1;
    const char *src_token = skadi_cap_ops_derive_arg_ro(src, size);
    void *dst_token = skadi_cap_ops_derive_arg(dst, skadi_get_addr_size_for_family(family));
    int ret;

    __ASSERT_NO_MSG(src_token);
    __ASSERT_NO_MSG(dst_token);
    
    if(!src_token || !dst_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_zsock_inet_pton(family, src_token, dst_token);

    out:

    if(src_token){
        skadi_cap_ops_drop(src_token);
    }

    if(dst_token){
        skadi_cap_ops_drop(dst_token);
    }


    return ret;

    
}

#define skadi_zsock_inet_pton(FAMILY, SRC, DST) _skadi_zsock_inet_pton(FAMILY, SRC, DST) 

#define skadi_inet_pton(FAMILY, SRC, DST) _skadi_zsock_inet_pton(FAMILY, SRC, DST) 




SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_close, int sock);

static inline int _skadi_zsock_close(int sock){
    return __skadi_zsock_close(sock);
}

#define skadi_zsock_close(SOCK) _skadi_zsock_close(SOCK)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(ssize_t, __skadi_zsock_sendmsg, int sock, const struct msghdr *msg, int flags);

static inline ssize_t skadi_zsock_sendmsg(int sock, const struct msghdr *msg, int flags){
    struct msghdr tmp_header = {};
    const struct msghdr *msg_token = skadi_cap_ops_derive_arg_ro(&tmp_header, sizeof(tmp_header));
    ssize_t ret;

    __ASSERT_NO_MSG(msg_token);

    if(!msg_token){
        ret = -ENOMEM;
        goto out;
    }

    if(msg->msg_namelen){
        tmp_header.msg_name = skadi_cap_ops_derive_arg_wo(msg->msg_name, msg->msg_namelen);
        __ASSERT_NO_MSG(tmp_header.msg_name);
        if(!tmp_header.msg_name){
            ret = -ENOMEM;
            goto out;
        }
        tmp_header.msg_namelen = msg->msg_namelen;
    }

    if(msg->msg_iovlen){
        tmp_header.msg_iov = skadi_allocator_calloc_rw(msg->msg_iovlen, sizeof(tmp_header.msg_iov[0]));
        if(!tmp_header.msg_iov){
            ret = -ENOMEM;
            goto out;
        }

        for(size_t i = 0; i < msg->msg_iovlen; i++){
            tmp_header.msg_iov[i].iov_len = msg->msg_iov[i].iov_len;
            tmp_header.msg_iov[i].iov_base = (void*)skadi_cap_ops_derive_arg_ro(msg->msg_iov[i].iov_base, msg->msg_iov[i].iov_len);
            __ASSERT_NO_MSG(tmp_header.msg_iov[i].iov_base);
            if(!tmp_header.msg_iov[i].iov_base){
                ret = -ENOMEM;
                goto out;
            }
        }

        tmp_header.msg_iovlen = msg->msg_iovlen;
    }

    if(msg->msg_controllen){
        tmp_header.msg_control = (void*)skadi_cap_ops_derive_arg_ro(msg->msg_control, msg->msg_controllen);
        __ASSERT_NO_MSG(tmp_header.msg_control);
        if(!tmp_header.msg_control){
            ret = -ENOMEM;
            goto out;
        }
        tmp_header.msg_controllen = msg->msg_controllen;
    }

    tmp_header.msg_flags = msg->msg_flags;

    ret = __skadi_zsock_sendmsg(sock, msg_token, flags);

    out:

    if(msg_token){
        (void)skadi_cap_ops_drop(msg_token);
    }

    if(tmp_header.msg_name){
        (void)skadi_cap_ops_drop(tmp_header.msg_name);
    }

    if(tmp_header.msg_iov){
        for(size_t i = 0; i < msg->msg_iovlen; i++){
            if(tmp_header.msg_iov[i].iov_base){
                (void)skadi_cap_ops_drop(tmp_header.msg_iov[i].iov_base);
            }
            else{
                break;
            }
        }
        skadi_allocator_free(tmp_header.msg_iov);
    }

    if(tmp_header.msg_control){
        (void)skadi_cap_ops_drop(tmp_header.msg_control);
    }

    return ret;
    
}


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(const char *, __skadi_zsock_gai_strerror, int errcode);

static inline const char* _skadi_zsock_gai_strerror(int errcode){
   return  __skadi_zsock_gai_strerror(errcode);
}

#define skadi_zsock_gai_strerror(ERRCODE) _skadi_zsock_gai_strerror(ERRCODE)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zsock_listen, int sock, int backlog);

static inline int _skadi_zsock_listen(int sock, int backlog){
   return __skadi_zsock_listen(sock, backlog);
}

#define skadi_zsock_listen(SOCK, BACKLOG) _skadi_zsock_listen(SOCK, BACKLOG)

static inline void skadi_zsock_freeaddrinfo(struct zsock_addrinfo *ai){
    skadi_allocator_free(ai);
}

#endif /* SKADI_SUBSYSTEM */

#endif /* SKADI_SOCKET_H */
