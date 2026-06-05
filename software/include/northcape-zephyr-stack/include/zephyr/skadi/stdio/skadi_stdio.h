#ifndef SKADI_STDIO_H
#define SKADI_STDIO_H

#if defined(SKADI_SUBSYSTEM)

/* no exception, even for otherwise unprotected subsystem - the trampoline in the libc subsystem does not support this */
#if !defined(__ASSEMBLER__)
/* va_list */
#include <stdarg.h>
/* size_t */
#include <sys/types.h>
/* FILE */
#include <stdio.h>

#include <zephyr/skadi/skadi_subsystem.h>

typedef enum {
    SKADI_PRINTF_OK,
    SKADI_PRINTF_DIRECT,
    SKADI_PRINTF_REJECT
} skadi_printf_verdict_t;

extern int __always_direct_vprintf(const char *format, va_list ap);
extern int __always_direct_vfprintf(FILE *stream, const char *format, va_list ap);
extern int __always_direct_vsnprintf(char *buffer, size_t size, const char *format, va_list ap);

/* TODO in case we have %s format specifiers in the printf() call, we cannot do a subsystem call without incurring an exception - figure out what to do in this case bsaed on per-subsytem config */
static inline skadi_printf_verdict_t skadi_printf_check_format_string(const char *fmt, const char *file, int line){
    ARG_UNUSED(fmt);
    ARG_UNUSED(file);
    ARG_UNUSED(line);
    return SKADI_PRINTF_OK;
}

__attribute__ ((format (printf, 1, 5))) static inline int _skadi_printf(const char *fmt, const char *file, int line, size_t arg_count, ...){
    va_list args, args_copy;
    int ret;
    skadi_printf_verdict_t check_verdict = skadi_printf_check_format_string(fmt, file, line);
    
    va_start(args, arg_count);

    switch(check_verdict){
        case SKADI_PRINTF_DIRECT:
            return __always_direct_vprintf(fmt, args);
        case SKADI_PRINTF_OK:
            /* can proceed */
            break;
        default:
            _skadi_printf("<Unsupported print>\n", file, line, 0);
            return -EOPNOTSUPP;
    }


    args_copy = skadi_valist_clone(args, arg_count, true);

    ret = vprintf(fmt, args_copy);

    skadi_cloned_valist_free(args_copy);

    va_end(args);

    return ret;
}

static inline  __attribute__ ((__always_inline__)) int __skadi_printf(const char *format, const char *file, int line, ...) __attribute__ ((format (printf, 1, 4)));

static inline  __attribute__ ((__always_inline__)) int __skadi_printf(const char *format, const char *file, int line, ...){
    size_t arg_count = __builtin_va_arg_pack_len();
    return _skadi_printf(format, file, line, arg_count, __builtin_va_arg_pack());
}

/* crude way to wrap printf without changing wrappers */
#define printf(FMT,...) __skadi_printf(FMT, __FILE__, __LINE__ __VA_OPT__(,) __VA_ARGS__)


__attribute__ ((format (printf, 2, 6))) static inline int _skadi_fprintf(FILE* stream, const char *fmt, const char *file, int line, size_t arg_count, ...){
    va_list args, args_copy;
    int ret;

    skadi_printf_verdict_t check_verdict = skadi_printf_check_format_string(fmt, file, line);


    va_start(args, arg_count);

    switch(check_verdict){
        case SKADI_PRINTF_DIRECT:
            return __always_direct_vfprintf(stream, fmt, args);
        case SKADI_PRINTF_OK:
            /* can proceed */
            break;
        default:
            _skadi_printf("<Unsupported print>\n", file, line, 0);
            return -EOPNOTSUPP;
    }


    args_copy = skadi_valist_clone(args, arg_count, true);

    ret = vfprintf(stream, fmt, args_copy);

    skadi_cloned_valist_free(args_copy);

    va_end(args);

    return ret;
}

static inline  __attribute__ ((__always_inline__)) int __skadi_fprintf(FILE* stream, const char *format, const char *file, int line, ...) __attribute__ ((format (printf, 2, 5)));

static inline  __attribute__ ((__always_inline__)) int __skadi_fprintf(FILE* stream, const char *format, const char *file, int line, ...){
    size_t arg_count = __builtin_va_arg_pack_len();
    return _skadi_fprintf(stream, format, file, line, arg_count, __builtin_va_arg_pack());
}

/* crude way to wrap printf without changing wrappers */
#define fprintf(STREAM, FMT, ...) __skadi_fprintf(STREAM, FMT, __FILE__, __LINE__ __VA_OPT__(,) __VA_ARGS__)


__attribute__ ((format (printf, 3, 7))) static inline int _skadi_snprintf(char *str, size_t size, const char *fmt, const char *file, const int line, size_t arg_count, ...){
    va_list args, args_copy;
    int ret;

    skadi_printf_verdict_t check_verdict = skadi_printf_check_format_string(fmt, file, line);

    va_start(args, arg_count);

    switch(check_verdict){
        case SKADI_PRINTF_DIRECT:
            return __always_direct_vsnprintf(str, size, fmt, args);
        case SKADI_PRINTF_OK:
            /* can proceed */
            break;
        default:
            _skadi_printf("<Unsupported print>\n", file, line, 0);
            return -EOPNOTSUPP;
    }

    args_copy = skadi_valist_clone(args, arg_count, true);

    ret = vsnprintf(str, size, fmt, args_copy);

    skadi_cloned_valist_free(args_copy);

    va_end(args);

    return ret;
}

static inline  __attribute__ ((__always_inline__)) int __skadi_snprintf(char *str, size_t size, const char *format, const char *file, const int line, ...) __attribute__ ((format (printf, 3, 6)));

static inline  __attribute__ ((__always_inline__)) int __skadi_snprintf(char *str, size_t size, const char *format, const char *file, const int line, ...){
    size_t arg_count = __builtin_va_arg_pack_len();
    return _skadi_snprintf(str, size, format, file, line, arg_count, __builtin_va_arg_pack());
}

/* crude way to wrap printf without changing wrappers */
#define snprintf(STR, SIZE, FMT, ...) __skadi_snprintf(STR, SIZE, FMT, __FILE__, __LINE__ __VA_OPT__(,) __VA_ARGS__)

#elif defined(SKADI_SUBSYSTEM_ALLOCATOR)

#define printf(...)
#define vprintf(...)
#define fprintf(...)
#define snprintf(...)

#endif /* !__ASSEMBLER__ */

#endif /* SKADI_SUBSYSTEM */

#endif /* SKADI_STDIO_H */
