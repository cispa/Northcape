#ifndef SKADI_BITARRAY_H
#define SKADI_BITARRAY_H

#include <zephyr/sys/bitarray.h>
#include <zephyr/skadi/skadi_subsystem.h>

#ifdef SKADI_SUBSYSTEM
/* in the loader, use the z_impl_* variants directly */

/* we need a shareable token for the bundles */
static inline void skadi_bitarray_ensure_init(sys_bitarray_t *bitarray){
    size_t bundle_uint32s = DIV_ROUND_UP(DIV_ROUND_UP(bitarray->num_bits, 8), sizeof(uint32_t));
    size_t bundle_bytes = bundle_uint32s * sizeof(uint32_t);

    if(!bitarray->bundles_initialized){
        uint32_t *bundles_token = skadi_cap_ops_derive_arg(bitarray->bundles, bundle_bytes);

        __ASSERT_NO_MSG(bundles_token);

        if(!bundles_token){
            return;
        }

        bitarray->bundles = bundles_token;
        bitarray->bundles_initialized = true;
    }
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_sys_bitarray_set_bit, sys_bitarray_t *bitarray, size_t bit);

static inline int skadi_sys_bitarray_set_bit(sys_bitarray_t *bitarray, size_t bit){
    sys_bitarray_t *bitarray_token = skadi_cap_ops_derive_arg(bitarray, sizeof(*bitarray));
    int ret;

    __ASSERT_NO_MSG(bitarray_token);

    if(!bitarray_token){
        return -ENOMEM;
    }

    skadi_bitarray_ensure_init(bitarray);

    ret = __skadi_sys_bitarray_set_bit(bitarray_token, bit);

    skadi_cap_ops_drop(bitarray_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_sys_bitarray_clear_bit, sys_bitarray_t *bitarray, size_t bit);

static inline int skadi_sys_bitarray_clear_bit(sys_bitarray_t *bitarray, size_t bit){
    sys_bitarray_t *bitarray_token = skadi_cap_ops_derive_arg(bitarray, sizeof(*bitarray));
    int ret;

    __ASSERT_NO_MSG(bitarray_token);

    if(!bitarray_token){
        return -ENOMEM;
    }

    skadi_bitarray_ensure_init(bitarray);

    ret = __skadi_sys_bitarray_clear_bit(bitarray_token, bit);

    skadi_cap_ops_drop(bitarray_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_sys_bitarray_test_bit, sys_bitarray_t *bitarray, size_t bit, int *val);

static inline int skadi_sys_bitarray_test_bit(sys_bitarray_t *bitarray, size_t bit, int *val){
    sys_bitarray_t *bitarray_token = skadi_cap_ops_derive_arg(bitarray, sizeof(*bitarray));
    int *val_token = val ? skadi_cap_ops_derive_arg_wo(val, sizeof(*val)) : val;
    int ret;

    __ASSERT_NO_MSG(bitarray_token);
    __ASSERT_NO_MSG(!val || val_token);

    if(!bitarray_token || (val && !val_token)){
        ret = -ENOMEM;
        goto out;
    }

    skadi_bitarray_ensure_init(bitarray);

    ret = __skadi_sys_bitarray_test_bit(bitarray_token, bit, val_token);

out:
    if(bitarray_token){
        skadi_cap_ops_drop(bitarray_token);
    }
    if(val_token){
        skadi_cap_ops_drop(val_token);
    }
    

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_sys_bitarray_test_and_set_bit, sys_bitarray_t *bitarray, size_t bit, int *val);

static inline int skadi_sys_bitarray_test_and_set_bit(sys_bitarray_t *bitarray, size_t bit, int *val){
    sys_bitarray_t *bitarray_token = skadi_cap_ops_derive_arg(bitarray, sizeof(*bitarray));
    int *val_token = val ? skadi_cap_ops_derive_arg_wo(val, sizeof(*val)) : val;
    int ret;

    __ASSERT_NO_MSG(bitarray_token);
    __ASSERT_NO_MSG(!val || val_token);

    if(!bitarray_token || (val && !val_token)){
        ret = -ENOMEM;
        goto out;
    }

    skadi_bitarray_ensure_init(bitarray);

    ret = __skadi_sys_bitarray_test_and_set_bit(bitarray_token, bit, val_token);

out:
    if(bitarray_token){
        skadi_cap_ops_drop(bitarray_token);
    }
    if(val_token){
        skadi_cap_ops_drop(val_token);
    }
    

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_sys_bitarray_test_and_clear_bit, sys_bitarray_t *bitarray, size_t bit, int *val);

static inline int skadi_sys_bitarray_test_and_clear_bit(sys_bitarray_t *bitarray, size_t bit, int *val){
    sys_bitarray_t *bitarray_token = skadi_cap_ops_derive_arg(bitarray, sizeof(*bitarray));
    int *val_token = val ? skadi_cap_ops_derive_arg_wo(val, sizeof(*val)) : val;
    int ret;

    __ASSERT_NO_MSG(bitarray_token);
    __ASSERT_NO_MSG(!val || val_token);

    if(!bitarray_token || (val && !val_token)){
        ret = -ENOMEM;
        goto out;
    }

    skadi_bitarray_ensure_init(bitarray);

    ret = __skadi_sys_bitarray_test_and_clear_bit(bitarray_token, bit, val_token);

out:
    if(bitarray_token){
        skadi_cap_ops_drop(bitarray_token);
    }
    if(val_token){
        skadi_cap_ops_drop(val_token);
    }
    

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_sys_bitarray_alloc, sys_bitarray_t *bitarray, size_t num_bits, size_t *offset);

static inline int skadi_sys_bitarray_alloc(sys_bitarray_t *bitarray, size_t num_bits, size_t *offset){
    sys_bitarray_t *bitarray_token = skadi_cap_ops_derive_arg(bitarray, sizeof(*bitarray));
    size_t *offset_token = offset ? skadi_cap_ops_derive_arg_wo(offset, sizeof(*offset)) : offset;
    int ret;

    __ASSERT_NO_MSG(bitarray_token);
    __ASSERT_NO_MSG(!offset || offset_token);

    if(!bitarray_token || (offset && !offset_token)){
        ret = -ENOMEM;
        goto out;
    }

    skadi_bitarray_ensure_init(bitarray);

    ret = __skadi_sys_bitarray_alloc(bitarray_token, num_bits, offset_token);

out:
    if(bitarray_token){
        skadi_cap_ops_drop(bitarray_token);
    }
    if(offset_token){
        skadi_cap_ops_drop(offset_token);
    }
    

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_sys_bitarray_free, sys_bitarray_t *bitarray, size_t num_bits, size_t offset);

static inline int skadi_sys_bitarray_free(sys_bitarray_t *bitarray, size_t num_bits, size_t offset){
    sys_bitarray_t *bitarray_token = skadi_cap_ops_derive_arg(bitarray, sizeof(*bitarray));
    int ret;

    __ASSERT_NO_MSG(bitarray_token);

    if(!bitarray_token){
        return -ENOMEM;
    }

    skadi_bitarray_ensure_init(bitarray);

    ret = __skadi_sys_bitarray_free(bitarray_token, num_bits, offset);

    skadi_cap_ops_drop(bitarray_token);

    return ret;
}


#endif /* SKADI_SUBSYSTEM */

#endif /* SKADI_BITARRAY_H */
