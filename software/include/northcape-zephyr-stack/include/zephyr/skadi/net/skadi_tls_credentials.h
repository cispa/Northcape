#ifndef SKADI_TLS_CREDENTIALS_H
#define SKADI_TLS_CREDENTIALS_H

#include <zephyr/net/tls_credentials.h>
#include <zephyr/skadi/skadi_subsystem.h>

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_tls_credential_add, sec_tag_t tag, enum tls_credential_type type, const void *cred, size_t credlen);

static inline int skadi_tls_credential_add(sec_tag_t tag, enum tls_credential_type type, const void *cred, size_t credlen){
    int ret;
    const void *cred_token = skadi_cap_ops_derive_arg_ro(cred, credlen);
    __ASSERT_NO_MSG(cred_token);
    if(!cred_token){
        return -ENOMEM;
    }

    ret = __skadi_tls_credential_add(tag, type, cred_token, credlen);

    /* to be dropped in skadi_tls_credential_delete */

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_tls_credential_get, sec_tag_t tag, enum tls_credential_type type, void *cred, size_t *credlen);

static inline int skadi_tls_credential_get(sec_tag_t tag, enum tls_credential_type type, void *cred, size_t *credlen){
    int ret;
    void *cred_token = skadi_cap_ops_derive_arg_wo(cred, *credlen);
    size_t *credlen_token = (size_t*) skadi_cap_ops_derive_arg(credlen, sizeof(*credlen));

    __ASSERT_NO_MSG(cred_token);
    __ASSERT_NO_MSG(credlen_token);
    if(!cred_token){
        ret = -ENOMEM;
        goto out;
    }

    if(!credlen_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_tls_credential_get(tag, type, cred_token, credlen_token);

    out:
    if(cred_token){
        (void)skadi_cap_ops_drop(cred_token);
    }
    if(credlen_token){
        (void)skadi_cap_ops_drop(credlen_token);
    }
    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_tls_credential_delete, sec_tag_t tag, enum tls_credential_type type);

#define skadi_tls_credential_delete(TAG, TYPE) __skadi_tls_credential_delete(TAG, TYPE)


#endif /* SKADI_TLS_CREDENTIALS_H */
