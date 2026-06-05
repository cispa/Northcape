#ifndef SKADI_TIME_H
#define SKADI_TIME_H

#include <zephyr/posix/time.h>
#include <zephyr/skadi/skadi_subsystem.h>

#ifdef SKADI_SUBSYSTEM
/* in the loader, use the z_impl_* variants directly */

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_clock_getres, clockid_t clockid, struct timespec *ts);

static inline int _skadi_clock_getres(clockid_t clockid, struct timespec *ts){
    struct timespec *ts_token = skadi_cap_ops_derive_arg(ts, sizeof(*ts));
    int ret;

    __ASSERT_NO_MSG(ts_token);

    if(!ts_token){
        return -ENOMEM;
    }

    ret = __skadi_clock_getres(clockid, ts_token);

    if(ts_token){
        skadi_cap_ops_drop(ts_token);
    }

    return ret;
}

#define skadi_clock_getres(CLOCKID, TS) _skadi_clock_getres(CLOCKID, TS)

#ifdef CONFIG_SKADI_LIBRARY_LOCAL_CLOCK
/* implementation in library */
extern int skadi_clock_gettime(clockid_t clockid, struct timespec *ts);
#else
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_clock_gettime, clockid_t clockid, struct timespec *ts);

static inline int _skadi_clock_gettime(clockid_t clockid, struct timespec *ts){
    struct timespec *ts_token = skadi_cap_ops_derive_arg(ts, sizeof(*ts));
    int ret;

    __ASSERT_NO_MSG(ts_token);

    if(!ts_token){
        return -ENOMEM;
    }

    ret = __skadi_clock_gettime(clockid, ts_token);

    if(ts_token){
        skadi_cap_ops_drop(ts_token);
    }

    return ret;
}

#define skadi_clock_gettime(CLOCKID, TS) _skadi_clock_gettime(CLOCKID, TS)
#endif

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_clock_settime, clockid_t clockid, const struct timespec *ts);

static inline int _skadi_clock_settime(clockid_t clockid, const struct timespec *ts){
    const struct timespec *ts_token = skadi_cap_ops_derive_arg_ro(ts, sizeof(*ts));
    int ret;

    __ASSERT_NO_MSG(ts_token);

    if(!ts_token){
        return -ENOMEM;
    }

    ret = __skadi_clock_settime(clockid, ts_token);

    if(ts_token){
        skadi_cap_ops_drop(ts_token);
    }

    return ret;
}

#define skadi_clock_settime(CLOCKID, TS) _skadi_clock_settime(CLOCKID, TS)

#ifdef CONFIG_SKADI_LIBRARY_LOCAL_CLOCK
/* declared elsewhere */
struct timeval;
/* implementation in local library */
extern int skadi_gettimeofday(struct timeval *tv, void *tz);
#else
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_gettimeofday, struct timeval *tv, void *tz);

static inline int _skadi_gettimeofday(struct timeval *tv, void *tz){
    struct timeval *tv_wrapper = skadi_cap_ops_derive_arg_wo(tv, sizeof(*tv));
    int ret;

    __ASSERT_NO_MSG(tv_wrapper);

    if(!tv_wrapper){
        return -ENOMEM;
    }

    __ASSERT(!tz, "tz only exists for historical reasons and should be NULL!");

    ret = __skadi_gettimeofday(tv_wrapper, tz);

    skadi_cap_ops_drop(tv_wrapper);

    return ret;
}

#define skadi_gettimeofday(TV, TZ) _skadi_gettimeofday(TV, NULL)
#endif

#endif /* SKADI_SUBSYSTEM */

#endif /* SKADI_TIME_H */
