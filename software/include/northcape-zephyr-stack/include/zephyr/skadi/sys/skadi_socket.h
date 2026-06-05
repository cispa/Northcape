#ifndef SKADI_SYS_SOCKET_H
#define SKADI_SYS_SOCKET_H

#include <zephyr/net/socket.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/net/skadi_socket.h>

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_socket, int family, int type, int proto);

static inline int _skadi_socket(int family, int type, int proto){
    return __skadi_socket(family, type, proto);
}

#define skadi_socket(FAMILY, TYPE, PROTO) _skadi_socket(FAMILY, TYPE, PROTO)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_bind, int sock, const struct sockaddr *addr, socklen_t addrlen);

static inline int _skadi_bind(int sock, const struct sockaddr *addr, socklen_t addrlen){
    int ret;
    const struct sockaddr *addr_token = skadi_cap_ops_derive_arg_ro(addr, addrlen);

    __ASSERT_NO_MSG(addr_token);

    if(!addr_token){
        return -ENOMEM;
    }

    ret = __skadi_bind(sock, addr_token, addrlen);

    skadi_cap_ops_drop(addr_token);

    return ret;
}

#define skadi_bind(SOCK, ADDR, ADDRLEN) _skadi_bind(SOCK, ADDR, ADDRLEN)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_listen, int sock, int backlog);

static inline int _skadi_listen(int sock, int backlog){
    return __skadi_listen(sock, backlog);
}

#define skadi_listen(SOCK, BACKLOG) _skadi_listen(SOCK, BACKLOG)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_accept, int sock,  struct sockaddr *addr, socklen_t *addrlen);

static inline int _skadi_accept(int sock, struct sockaddr *addr, socklen_t *addrlen){
    int ret;
    struct sockaddr *addr_token = skadi_cap_ops_derive_arg(addr, *addrlen);
    socklen_t *addrlen_token = skadi_cap_ops_derive_arg(addrlen, sizeof(*addrlen));

    __ASSERT_NO_MSG(addr_token);

    __ASSERT_NO_MSG(addrlen_token);

    if(!addr_token || !addrlen_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_accept(sock, addr_token, addrlen_token);

out:

    if(addr_token){
        skadi_cap_ops_drop(addr_token);
    }

    if(addrlen_token){
        skadi_cap_ops_drop(addrlen_token);
    }

    return ret;
}

#define skadi_accept(SOCK, ADDR, ADDRLEN) _skadi_accept(SOCK, ADDR, ADDRLEN)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(ssize_t, __skadi_recv, int sock, void *buf, size_t max_len, int flags);

static inline int _skadi_recv(ssize_t sock, void *buf, size_t max_len, int flags){
    ssize_t ret;
    void *buf_token = skadi_cap_ops_derive_arg(buf, max_len);

    __ASSERT_NO_MSG(buf_token);

    if(!buf_token){
        return -ENOMEM;
    }

    ret = __skadi_recv(sock, buf_token, max_len, flags);

    skadi_cap_ops_drop(buf_token);

    return ret;
}

#define skadi_recv(SOCK, BUF, BUF_LEN, FLAGS) _skadi_recv(SOCK, BUF, BUF_LEN, FLAGS)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(ssize_t, __skadi_send, int sock, const void *buf, size_t len, int flags);

static inline ssize_t _skadi_send(int sock, const void *buf, size_t len, int flags){
    ssize_t ret;
    const void *buf_token = skadi_cap_ops_derive_arg_ro(buf, len);

    __ASSERT_NO_MSG(buf_token);

    if(!buf_token){
        return -ENOMEM;
    }

    ret = __skadi_send(sock, buf_token, len, flags);

    skadi_cap_ops_drop(buf_token);

    return ret;
}

#define skadi_send(SOCK, BUF, BUF_LEN, FLAGS) _skadi_send(SOCK, BUF, BUF_LEN, FLAGS)


#define skadi_setsockopt(...) skadi_zsock_setsockopt(__VA_ARGS__)
#define skadi_getsockopt(...) skadi_zsock_getsockopt(__VA_ARGS__)


#endif /* SKADI_SOCKET_H */
