#ifndef SKADI_UNISTD_H
#define SKADI_UNISTD_H

#include <unistd.h>
#include <zephyr/skadi/skadi_subsystem.h>

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_close, int fd);

static inline int _skadi_close(int fd){
    return __skadi_close(fd);
}

#define skadi_close(FD) _skadi_close(FD)

#ifdef CONFIG_POSIX_C_LIB_EXT
/* multiple invocations of getopt require me to use THE SAME capabilities due to global state! */
static char **__skadi_getopt_nargv = NULL;
static const char *__skadi_getopt_ostr = NULL;

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_getopt, int nargc, char *const nargv[], const char *ostr);

static inline int _skadi_getopt(int nargc, char *const nargv[], const char *ostr){
    int ret;
    if(__skadi_getopt_nargv == NULL){
        // first call - need to initialize state
        __skadi_getopt_nargv = skadi_allocator_alloc_rw(sizeof(__skadi_getopt_nargv[0]) * nargc);
        
        __skadi_getopt_ostr = skadi_cap_ops_derive_arg_ro(ostr, strlen(ostr) + 1);

        __ASSERT_NO_MSG(__skadi_getopt_nargv);
        __ASSERT_NO_MSG(__skadi_getopt_ostr);

        if(!__skadi_getopt_nargv || !__skadi_getopt_ostr){
            ret = -1;
            goto out;
        }
    }

    return __skadi_getopt(nargc, __skadi_getopt_nargv, __skadi_getopt_ostr);

    out:
        if(ret < 0){
            // maintain state if success for next call
            // on error or finished
            if(__skadi_getopt_nargv){
                skadi_allocator_free(__skadi_getopt_nargv);
            }
            __skadi_getopt_nargv = NULL;
            if(__skadi_getopt_ostr){
                skadi_cap_ops_drop(__skadi_getopt_ostr);
            }
            __skadi_getopt_ostr = NULL;
        }
    return ret;
}

#define skadi_getopt(NARGC, NARGV, OSTR) _skadi_getopt(NARGC, NARGV, OSTR)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_getopt_init, void);

static inline void _skadi_getopt_init(void){
    __skadi_getopt_init();
}

#define skadi_getopt_init _skadi_getopt_init

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_optind, void);

static inline int _skadi_optind(void){
    return __skadi_optind();
}

#define skadi_optind _skadi_optind()

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_optind_set, int);

static inline void _skadi_optind_set(int new_optind){
    __skadi_optind_set(new_optind);
}

#define skadi_optind_set(NEW_OPTIND) _skadi_optind_set(NEW_OPTIND)

// char is from caller-provided capability...
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(char*, __skadi_optarg, void);

static inline char* _skadi_optarg(void){
    return __skadi_optarg();
}

#define skadi_optarg _skadi_optarg()

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_optopt, void);

static inline int _skadi_optopt(void){
    return __skadi_optopt();
}

#define skadi_optopt _skadi_optopt()

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_opterr, void);

static inline int _skadi_opterr(void){
    return __skadi_opterr();
}

#define skadi_opterr _skadi_opterr()

#endif

#endif /* SKADI_UNISTD_H */
