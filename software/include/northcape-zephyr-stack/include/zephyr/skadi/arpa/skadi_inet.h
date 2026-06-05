#ifndef SKADI_ARPA_INET_H
#define SKADI_ARPA_INET_H

#include <zephyr/posix/arpa/inet.h>
#include <zephyr/skadi/skadi_subsystem.h>

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(char *, __skadi_inet_ntop, sa_family_t family, const void *src, char *dst, size_t size);

static inline char * _skadi_inet_ntop(sa_family_t family, const void *src, char *dst, size_t size){
    const void *src_token = skadi_cap_ops_derive_arg_ro(src, size);
    char *dst_token = skadi_cap_ops_derive_arg(dst, size);
    char *ret;

    __ASSERT_NO_MSG(src_token);
    __ASSERT_NO_MSG(dst_token);

    if(!src_token || !dst_token){
        ret = NULL;
        goto out;
    }

    ret = __skadi_inet_ntop(family, src_token, dst_token, size);

out:
    if(src_token){
        skadi_cap_ops_drop(src_token);
    }

    if(dst_token){
        skadi_cap_ops_drop(dst_token);
    }
    
    return ret;
}


#define skadi_inet_ntop(FAMILY, SRC, DST, SIZE) _skadi_inet_ntop(FAMILY, SRC, DST, SIZE)

#endif /* SKADI_ARPA_INET_H*/
