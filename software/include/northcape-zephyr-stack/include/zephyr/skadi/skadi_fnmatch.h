#ifndef SKADI_FNMATCH_H
#define SKADI_FNMATCH_H

#include <zephyr/posix/fnmatch.h>
#include <zephyr/skadi/skadi_subsystem.h>

#if defined(SKADI_SUBSYSTEM) && defined(CONFIG_POSIX_C_LIB_EXT)
/* in the loader, use the z_impl_* variants directly */

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_fnmatch, const char *pattern, const char *string, int flags);

static inline int _skadi_fnmatch(const char *pattern, const char *string, int flags){
    const char *pattern_token = skadi_cap_ops_derive_arg_ro(pattern, strlen(pattern) + 1);
    const char *string_token = skadi_cap_ops_derive_arg_ro(string, strlen(string) + 1);
    int ret;

    __ASSERT_NO_MSG(pattern_token);
    __ASSERT_NO_MSG(string_token);

    if(!pattern_token || !string_token){
        ret = -ENOMEM;
        goto out;
    }

    ret = __skadi_fnmatch(pattern_token, string_token, flags);

out:
    if(pattern_token){
        skadi_cap_ops_drop(pattern_token);
    }

    if(string_token){
        skadi_cap_ops_drop(string_token);
    }

    return ret;
}

#define skadi_fnmatch(PATTERN, STRING, FLAGS) _skadi_fnmatch(PATTERN, STRING, FLAGS)


#endif /* SKADI_SUBSYSTEM */

#endif /* SKADI_FNMATCH_H */
