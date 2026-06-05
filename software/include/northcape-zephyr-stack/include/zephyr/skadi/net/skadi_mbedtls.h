#ifndef SKADI_MBEDTLS_H
#define SKADI_MBEDTLS_H

#include <mbedtls/ssl.h>
#include <zephyr/skadi/skadi_subsystem.h>

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_ssl_conf_authmode, mbedtls_ssl_config *conf, int authmode);
#define skadi_mbedtls_ssl_conf_authmode(CONF, AUTHMODE) __skadi_mbedtls_ssl_conf_authmode(CONF, AUTHMODE)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_ssl_write, mbedtls_ssl_context *ssl, const unsigned char *buf, size_t len);
static inline int skadi_mbedtls_ssl_write(mbedtls_ssl_context *ssl, const unsigned char *buf, size_t len){
    const unsigned char *buf_token = skadi_cap_ops_derive_arg_ro(buf, len);
    int ret;

    __ASSERT_NO_MSG(buf_token);
    if(!buf_token){
        return -ENOMEM;
    }

    ret = __skadi_mbedtls_ssl_write(ssl, buf_token, len);

    (void) skadi_cap_ops_drop(buf_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_ssl_session_save, const mbedtls_ssl_session *session, unsigned char *buf, size_t buf_len, size_t *olen);

static inline int skadi_mbedtls_ssl_session_save(const mbedtls_ssl_session *session, unsigned char *buf, size_t buf_len, size_t *olen){
    int ret;
    unsigned char *buf_token = skadi_cap_ops_derive_arg_wo(buf, buf_len);
    size_t *olen_token = skadi_cap_ops_derive_arg_wo(olen, sizeof(*olen));

    __ASSERT_NO_MSG(buf_token);
    __ASSERT_NO_MSG(olen_token);

    if(!buf_token){
        ret = -ENOMEM;
        goto out;
    }
    if(!olen_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_mbedtls_ssl_session_save(session, buf_token, buf_len, olen_token);

    out:

    if(buf_token){
        (void)skadi_cap_ops_drop(buf_token);
    }
    if(olen_token){
        (void)skadi_cap_ops_drop(olen_token);
    }
    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_ssl_session_reset, mbedtls_ssl_context *ssl);
#define skadi_mbedtls_ssl_session_reset(SSL) __skadi_mbedtls_ssl_session_reset(SSL)


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_x509_crt_parse, mbedtls_x509_crt *chain, const unsigned char *buf, size_t buflen);
static inline int skadi_mbedtls_x509_crt_parse(mbedtls_x509_crt *chain, const unsigned char *buf, size_t buflen){
    const unsigned char *buf_token = skadi_cap_ops_derive_arg_ro(buf, buflen);
    int ret;

    __ASSERT_NO_MSG(buf_token);
    if(!buf_token){
        return -ENOMEM;
    }

    ret = __skadi_mbedtls_x509_crt_parse(chain, buf_token, buflen);

    (void) skadi_cap_ops_drop(buf_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_ssl_conf_rng, mbedtls_ssl_config *conf, int(*f_rng)(void*, unsigned char*, size_t), void *p_rng);
#define skadi_mbedtls_ssl_conf_rng(CONF, F_RNG, P_RNG) __skadi_mbedtls_ssl_conf_rng(CONF, F_RNG, P_RNG)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_pk_parse_key, mbedtls_pk_context *ctx, const unsigned char *key, size_t keylen, const unsigned char *pwd, size_t pwdlen, int (*f_rng)(void*, unsigned char*, size_t), void *p_rng);

static inline int skadi_mbedtls_pk_parse_key(mbedtls_pk_context *ctx, const unsigned char *key, size_t keylen, const unsigned char *pwd, size_t pwdlen, int (*f_rng)(void*, unsigned char*, size_t), void *p_rng){
    const unsigned char *key_token = skadi_cap_ops_derive_arg_ro(key, keylen);
    const unsigned char *pwd_token = skadi_cap_ops_derive_arg_ro(pwd, pwdlen);
    int ret;

    __ASSERT_NO_MSG(key_token);
    __ASSERT_NO_MSG(pwd_token);

    if(!key_token){
        ret = -ENOMEM;
        goto out;
    }
    if(!pwd_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_mbedtls_pk_parse_key(ctx, key_token, keylen, pwd_token, pwdlen, f_rng, p_rng);

    out:
    if(key_token){
        (void)skadi_cap_ops_drop(key_token);
    }
    if(pwd_token){
        (void)skadi_cap_ops_drop(pwd_token);
    }
    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_x509_crt_free, mbedtls_x509_crt *crt);
#define skadi_mbedtls_x509_crt_free(CRT) __skadi_mbedtls_x509_crt_free(CRT)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_ssl_get_ciphersuite_id, const char *ciphersuite_name);

static inline int skadi_mbedtls_ssl_get_ciphersuite_id(const char *ciphersuite_name){
    const char *ciphersuite_name_token = skadi_cap_ops_derive_arg_ro(ciphersuite_name, strlen(ciphersuite_name)+1);
    int ret;

    __ASSERT_NO_MSG(ciphersuite_name_token);
    if(!ciphersuite_name_token){
        return -ENOMEM;
    }

    ret = __skadi_mbedtls_ssl_get_ciphersuite_id(ciphersuite_name_token);

    (void)skadi_cap_ops_drop(ciphersuite_name_token);
    
    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_ssl_session_load, mbedtls_ssl_session *session, const unsigned char *buf, size_t len);

static inline int skadi_mbedtls_ssl_session_load(mbedtls_ssl_session *session, const unsigned char *buf, size_t len){
    const unsigned char *buf_token = skadi_cap_ops_derive_arg_ro(buf, len);
    int ret;
    __ASSERT_NO_MSG(buf_token);
    if(!buf_token){
        return -ENOMEM;
    }

    ret = __skadi_mbedtls_ssl_session_load(session, buf_token, len);

    (void)skadi_cap_ops_drop(buf_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_x509_crt_parse_der_nocopy, mbedtls_x509_crt *chain, const unsigned char *buf, size_t buflen);

static inline int skadi_mbedtls_x509_crt_parse_der_nocopy(mbedtls_x509_crt *chain, const unsigned char *buf, size_t buflen){
    const unsigned char *buf_token = skadi_cap_ops_derive_arg_ro(buf, buflen);
    int ret;
    __ASSERT_NO_MSG(buf_token);

    if(!buf_token){
        return -ENOMEM;
    }

    ret = __skadi_mbedtls_x509_crt_parse_der_nocopy(chain, buf, buflen);

    (void)skadi_cap_ops_drop(buf);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_ssl_session_free, mbedtls_ssl_session *session);
#define skadi_mbedtls_ssl_session_free(SESSION) __skadi_mbedtls_ssl_session_free(SESSION)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(size_t, __skadi_mbedtls_ssl_get_bytes_avail, mbedtls_ssl_context *ssl);
#define skadi_mbedtls_ssl_get_bytes_avail(SSL) __skadi_mbedtls_ssl_get_bytes_avail(SSL)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_ssl_conf_ciphersuites, mbedtls_ssl_config *conf, const int *ciphersuites);
static inline void skadi_mbedtls_ssl_conf_ciphersuites(mbedtls_ssl_config *conf, const int *ciphersuites){
    const int *ciphersuites_ptr = ciphersuites;
    size_t ciphersuites_size;

    for(ciphersuites_size = 1; *ciphersuites_ptr != 0; ciphersuites_size++){
        ciphersuites_ptr++;
    }

    ciphersuites_ptr = skadi_cap_ops_derive_arg_ro(ciphersuites, ciphersuites_size * sizeof(int));

    __ASSERT_NO_MSG(ciphersuites_ptr);
    if(!ciphersuites_ptr){
        return;
    }

    /* will be cleared in free func */
    __skadi_mbedtls_ssl_conf_ciphersuites(conf, ciphersuites_ptr);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_ssl_config_free, mbedtls_ssl_config *conf);
static inline void skadi_mbedtls_ssl_config_free(mbedtls_ssl_config *conf){
    if(conf->private_ciphersuite_list){
        (void)skadi_cap_ops_drop(conf->private_ciphersuite_list);
    }
    if(conf->private_cert_profile){
        (void)skadi_cap_ops_drop(conf->private_cert_profile);
    }
    __skadi_mbedtls_ssl_config_free(conf);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int*, __skadi_mbedtls_ssl_list_ciphersuites);
#define skadi_mbedtls_ssl_list_ciphersuites __skadi_mbedtls_ssl_list_ciphersuites

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_ssl_close_notify, mbedtls_ssl_context *ssl);
#define skadi_mbedtls_ssl_close_notify(SSL) __skadi_mbedtls_ssl_close_notify(SSL)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_ssl_session_init, mbedtls_ssl_session *session);
static inline void skadi_mbedtls_ssl_session_init(mbedtls_ssl_session *session){
    mbedtls_ssl_session *session_token = skadi_cap_ops_derive_arg_wo(session, sizeof(*session));
    __ASSERT_NO_MSG(session_token);
    if(!session_token){
        return;
    }
    __skadi_mbedtls_ssl_session_init(session_token);
    (void)skadi_cap_ops_drop(session_token);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_ssl_set_hostname, mbedtls_ssl_context *ssl, const char *hostname);
static inline int skadi_mbedtls_ssl_set_hostname(mbedtls_ssl_context *ssl, const char *hostname){
    const char *hostname_token = skadi_cap_ops_derive_arg_ro(hostname, strlen(hostname)+1);
    int ret;

    __ASSERT_NO_MSG(hostname_token);
    if(!hostname_token){
        return -ENOMEM;
    }

    ret = __skadi_mbedtls_ssl_set_hostname(ssl, hostname);

    (void) skadi_cap_ops_drop(hostname_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_ssl_set_bio, mbedtls_ssl_context *ssl, void *p_bio, mbedtls_ssl_send_t *f_send, mbedtls_ssl_recv_t *f_recv, mbedtls_ssl_recv_timeout_t *f_recv_timeout);
#define skadi_mbedtls_ssl_set_bio(SSL, P_BIO, F_SEND, F_RECV, F_RECV_TIMEOUT) __skadi_mbedtls_ssl_set_bio(SSL, P_BIO, F_SEND, F_RECV, F_RECV_TIMEOUT) 

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_ssl_conf_cert_profile, mbedtls_ssl_config *conf, const mbedtls_x509_crt_profile *profile);
static inline void skadi_mbedtls_ssl_conf_cert_profile(mbedtls_ssl_config *conf, const mbedtls_x509_crt_profile *profile){
    const mbedtls_x509_crt_profile *profile_token = skadi_cap_ops_derive_arg_ro(profile, sizeof(*profile));

    __ASSERT_NO_MSG(profile_token);
    if(!profile_token){
        return;
    }

    /* will be cleared in free function */
    __skadi_mbedtls_ssl_conf_cert_profile(conf, profile_token);    

}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_pk_free, mbedtls_pk_context *pk);
#define skadi_mbedtls_pk_free(PK) __skadi_mbedtls_pk_free(PK)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_ssl_conf_ca_chain, mbedtls_ssl_config *conf, mbedtls_x509_crt *ca_chain, mbedtls_x509_crl *ca_crl);
#define skadi_mbedtls_ssl_conf_ca_chain(CONF, CA_CHAIN, CA_CRL) __skadi_mbedtls_ssl_conf_ca_chain(CONF, CA_CHAIN, CA_CRL) 

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(const char *, __skadi_mbedtls_ssl_get_ciphersuite, const mbedtls_ssl_context *ssl);
#define skadi_mbedtls_ssl_get_ciphersuite(SSL) __skadi_mbedtls_ssl_get_ciphersuite(SSL)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_ssl_free, mbedtls_ssl_context *ssl);
#define skadi_mbedtls_ssl_free(SSL) __skadi_mbedtls_ssl_free(SSL)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_ssl_handshake, mbedtls_ssl_context *ssl);
#define skadi_mbedtls_ssl_handshake(SSL) __skadi_mbedtls_ssl_handshake(SSL)

static inline void *skadi_mbedtls_calloc(size_t nmemb, size_t size){
    return skadi_allocator_calloc_rw(nmemb, size);
}
static inline void skadi_mbedtls_free(void *ptr){
    skadi_allocator_free(ptr);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_ssl_set_session, mbedtls_ssl_context *ssl, const mbedtls_ssl_session *session);
static inline int skadi_mbedtls_ssl_set_session(mbedtls_ssl_context *ssl, const mbedtls_ssl_session *session){
    const mbedtls_ssl_session *session_token = skadi_cap_ops_derive_arg_ro(session, sizeof(*session));
    int ret;
    __ASSERT_NO_MSG(session_token);
    if(!session_token){
        return -ENOMEM;
    }
    ret = __skadi_mbedtls_ssl_set_session(ssl, session);

    (void)skadi_cap_ops_drop(session_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_ssl_conf_max_frag_len, mbedtls_ssl_config *conf, unsigned char mfl_code);
#define skadi_mbedtls_ssl_conf_max_frag_len(CONF, MFL_CODE) __skadi_mbedtls_ssl_conf_max_frag_len(CONF, MFL_CODE)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_ssl_config_defaults, mbedtls_ssl_config *conf, int endpoint, int transport, int preset);
#define skadi_mbedtls_ssl_config_defaults(CONF, ENDPOINT, TRANSPORT, PRESET) __skadi_mbedtls_ssl_config_defaults(CONF, ENDPOINT, TRANSPORT, PRESET)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_pk_init, mbedtls_pk_context *pk);
#define skadi_mbedtls_pk_init(PK) __skadi_mbedtls_pk_init(PK)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_ssl_config_init, mbedtls_ssl_config *conf);
#define skadi_mbedtls_ssl_config_init(CONF) __skadi_mbedtls_ssl_config_init(CONF)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_ssl_setup, mbedtls_ssl_context *ssl, const mbedtls_ssl_config *conf);
/* config token to be managed by caller! */
#define skadi_mbedtls_ssl_setup(SSL, CONF) __skadi_mbedtls_ssl_setup(SSL,CONF)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_ssl_init, mbedtls_ssl_context *ssl);
#define skadi_mbedtls_ssl_init(SSL) __skadi_mbedtls_ssl_init(SSL)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_ssl_get_session, const mbedtls_ssl_context *ssl, mbedtls_ssl_session *dst);
static inline int skadi_mbedtls_ssl_get_session(const mbedtls_ssl_context *ssl, mbedtls_ssl_session *dst){
    mbedtls_ssl_session *dst_token = skadi_cap_ops_derive_arg_wo(dst, sizeof(*dst));
    int ret;

    __ASSERT_NO_MSG(dst_token);
    if(!dst_token){
        return -ENOMEM;
    }

    ret = __skadi_mbedtls_ssl_get_session(ssl, dst_token);

    (void)skadi_cap_ops_drop(dst_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_mbedtls_x509_crt_init, mbedtls_x509_crt *crt);
#define skadi_mbedtls_x509_crt_init(CRT) __skadi_mbedtls_x509_crt_init(CRT)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_ssl_read, mbedtls_ssl_context *ssl, unsigned char *buf, size_t len);
static inline int skadi_mbedtls_ssl_read(mbedtls_ssl_context *ssl, unsigned char *buf, size_t len){
    unsigned char *buf_token = len ? skadi_cap_ops_derive_arg_wo(buf, len) : buf;
    int ret;

    if(len){
        __ASSERT_NO_MSG(buf_token);
        if(!buf_token){
            return -ENOMEM;
        }
    }

    ret = __skadi_mbedtls_ssl_read(ssl, buf_token, len);

    if(len){
        (void)skadi_cap_ops_drop(buf_token);
    }

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_mbedtls_ssl_conf_own_cert, mbedtls_ssl_config *conf, mbedtls_x509_crt *own_cert, mbedtls_pk_context *pk_key);
#define skadi_mbedtls_ssl_conf_own_cert(CONF, OWN_CERT, PK_KEY) __skadi_mbedtls_ssl_conf_own_cert(CONF, OWN_CERT, PK_KEY)

#endif /* SKADI_MBEDTLS_H */
