#include <string.h>

#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_sched.h>
#include <zephyr/skadi/skadi_allocator.h>
#include <time.h>

/* this creates an issue down below for some reason */
#ifdef printf
#undef printf
#endif

int printf(const char *fmt, ...){
    return -EINVAL;
}

enum skadi_printf_parsing_state {
    IDLE,
    FOUND_DIRECTIVE_START
};

enum skadi_printf_parsing_modifier {
    MODIFIER_NONE,
    MODIFIER_H_H,
    MODIFIER_H,
    MODIFIER_L,
    MODIFIER_L_L,
    MODIFIER_L_L_DOUBLE,
    MODIFIER_J,
    MODIFIER_Z,
    MODIFIER_T
};

#define RISCV_VALIST_PADDING (sizeof(uintptr_t))

/**
 * @brief Iterates through format, looking for %s modifiers. Locates arguments in va_list accordingly, deriving a capability accordingly.
 * This code is only correct for RISC-V 64!
 * 
 * @param format printf format
 * @param va_list argument list
 * @param caps_out will write a void* here that points to an array of the allocated tokens for later cap ops free()
 * @return number of found %s specifiers
 */
static size_t skadi_printf_like_handle_string_templates(const char *format, va_list ap, void*** caps_out, size_t *ap_size);
/* loader proxy and allocator have a circular dependency here - fix it by not supporting this feature in the loader proxy */
#if defined(CONFIG_SKADI_LIBRARY_PRINTF_STRING_BYTES_OUT_SUPPORT) && !defined(LOADER_SUBSYSTEM)

static void skadi_add_cap_to_caps_out(size_t *caps_found, size_t *caps_out_size, void ***caps_out, void *cap){
    void **caps_array;
    if(*caps_out_size == *caps_found){
        if(!*caps_out_size){
            *caps_out_size = 1;
        }
        *caps_out_size = *caps_out_size * 2;
        *caps_out = skadi_allocator_realloc(*caps_out, *caps_out_size * sizeof(void*));
    }
    __ASSERT_NO_MSG(*caps_out);
    if(*caps_out == NULL){
        *caps_out_size = 0;
        *caps_found = 0;
        return;
    }
    caps_array = *caps_out;
    caps_array[*caps_found] = cap;
    *caps_found = *caps_found + 1;
}

static size_t skadi_printf_like_handle_string_templates(const char *format, va_list ap, void*** caps_out, size_t *ap_size){
    size_t found = 0;
    size_t caps_out_size = 0;
    uint8_t *parsed_list = (void *) ap;
    enum skadi_printf_parsing_state state = IDLE;
    enum skadi_printf_parsing_modifier active_modifier;

    *caps_out = NULL;

    while(format && *format != '\0'){
        switch(state){
            case FOUND_DIRECTIVE_START:
            {
                switch(*format){
                    /* modifiers - indicate a size */
                    case 'h':
                        if(format[1] == 'h'){
                            /* hh */
                            format += 2;
                            active_modifier = MODIFIER_H_H;
                            continue;
                        }
                        active_modifier = MODIFIER_H;
                        format++;
                        continue;
                    case 'l': 
                        if(format[1] == 'l'){
                            /* ll */
                            active_modifier = MODIFIER_L_L;
                            format += 2;
                            continue;
                        }
                        active_modifier = MODIFIER_L;
                        format++;
                        continue;
                    case 'q':
                        /* same as l */
                        active_modifier = MODIFIER_L_L;
                        format += 2;
                        continue;
                    case 'L':
                        active_modifier = MODIFIER_L_L_DOUBLE;
                        format ++;
                        continue;
                    case 'j':
                        active_modifier = MODIFIER_J;
                        format++;
                        continue;
                    case 'z':
                    case 'Z':
                        active_modifier = MODIFIER_Z;
                        format++;
                        continue;
                    case 't':
                        active_modifier = MODIFIER_T;
                        format++;
                        continue;

                    /* conversion specififiers */
                    
                    /* all int types */
                    case 'd':
                    case 'i':
                    case 'o':
                    case 'u':
                    case 'x':
                    case 'X':

                    /* all float types */
                    case 'e':
                    case 'E':
                    case 'f':
                    case 'F':
                    case 'g':
                    case 'G':
                    case 'a':
                    case 'A':
                    case 'c':

                    /* pointer */
                    case 'p':
                    
                    parsed_list += RISCV_VALIST_PADDING;
                    format++;
                    *ap_size = *ap_size + 1;
                    state = IDLE;
                    continue;

                    /* output STRING */
                    case 's':
                    {
                        size_t size_total = sizeof(char);
                        void **ap_parsed = (void **)parsed_list;
                        const char *candidate_str = ap_parsed[0];
                        const char *str_out;

                        __ASSERT(active_modifier != MODIFIER_L, "%%ls conversions not supported!");
                            
                        size_total *= strlen(candidate_str) + 1;

                        str_out = skadi_cap_ops_derive_arg_ro(candidate_str, size_total);

                        ap_parsed[0] = (void*) str_out;

                        skadi_add_cap_to_caps_out(&found, &caps_out_size, caps_out, (void*)str_out);

                        parsed_list += RISCV_VALIST_PADDING;
                        *ap_size = *ap_size + 1;

                        format++;
                        state = IDLE;
                        continue;

                    }

                    case '*': {
                        /* indicates field width in a scalar */
                        parsed_list += RISCV_VALIST_PADDING;
                        *ap_size = *ap_size + 1;
                        format++;
                        continue;
                    }

                    /* give us bytes written so far */
                    case 'n':{
                        const size_t size_total = sizeof(int);
                        void **ap_parsed = (void **)parsed_list;
                        int *bytes_out = ap_parsed[0];
                        int *bytes_out_writable;

                        __ASSERT(active_modifier != MODIFIER_NONE, "conversions not supported with %%n!");

                        bytes_out_writable = skadi_cap_ops_derive_arg_wo(bytes_out, size_total);

                        ap_parsed[0] = bytes_out_writable;

                        skadi_add_cap_to_caps_out(&found, &caps_out_size, caps_out, bytes_out_writable);

                        parsed_list += RISCV_VALIST_PADDING;
                        *ap_size = *ap_size + 1;

                        format++;
                        state = IDLE;
                        continue;
                    }

                        
                    case '%':
                        /* quoted % */
                        state = IDLE;
                        format++;
                        continue;

                    default:
                    /* irrelevant specificer such as flag like +-# */
                    format++;
                    continue;
                }
            };
            case IDLE:
            default:
                active_modifier = MODIFIER_NONE;
                if(*format == '%'){
                    state = FOUND_DIRECTIVE_START;
                }
                format++;
                continue;
        }
    }

    return found;
}
#else

static size_t skadi_printf_like_handle_string_templates(const char *format, va_list ap, void*** caps_out, size_t *ap_size){
    ARG_UNUSED(format);
    ARG_UNUSED(ap);
    ARG_UNUSED(caps_out);
    ARG_UNUSED(ap_size);
    return 0;
}
#endif

const static skadi_restriction_t skadi_no_restriction = SKADI_NO_RESTRICTION;

#ifndef SKADI_SUBSYSTEM_NO_PROTECTED_LIBC


#ifndef CONFIG_SKADI_LIBC_INLINE
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(char*, __skadi_strncpy, char *dest, const char *src, size_t n);

#define ASSERT_ALIGNED_STRING(STR) __ASSERT(!(((uintptr_t) STR) & (sizeof(long)-1)), "Alignment mismacth for string %p!", STR)

char *strncpy(char *dest, const char *src, size_t n){
    size_t actual_n = MIN(n, strlen(src)+1);
    /* careful: will fill destination with zeros if smaller than source */
    char *dest_token = skadi_cap_ops_derive_arg_wo(dest, n);
    const char *src_token = skadi_cap_ops_derive_arg_ro(src, actual_n);
    char *ret;

    __ASSERT_NO_MSG(dest_token);
    __ASSERT_NO_MSG(src_token);
    ASSERT_ALIGNED_STRING(dest);
    ASSERT_ALIGNED_STRING(src);

    if(!dest_token || !src_token){
        ret = NULL;
        goto out;
    }

    ret = __skadi_strncpy(dest_token, src_token, actual_n);

    for(size_t it = actual_n; it < n; it++){
        dest[it] = '\0';
    }

    out:
    if(dest_token){
        skadi_cap_ops_drop(dest_token);
    }
    if(src_token){
        skadi_cap_ops_drop(src_token);
    }

    return ret ? dest : ret;

}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_strncmp, const char *s1, const char *s2, size_t n);

int strncmp(const char *s1, const char *s2, size_t n){
    const char *s1_token = skadi_cap_ops_derive_arg_ro(s1, MIN(strlen(s1)+1, n));
    const char *s2_token = skadi_cap_ops_derive_arg_ro(s2, MIN(strlen(s2)+1, n));
    int ret;

    __ASSERT_NO_MSG(s1_token);
    __ASSERT_NO_MSG(s2_token);
    ASSERT_ALIGNED_STRING(s1);
    ASSERT_ALIGNED_STRING(s2);

    if(!s1_token || !s2_token){
        /* TODO no great return value here... */
        ret = 0;
        goto out;
    }

    ret = __skadi_strncmp(s1_token, s2_token, n);

    out:
    if(s1_token){
        skadi_cap_ops_drop(s1_token);
    }
    if(s2_token){
        skadi_cap_ops_drop(s2_token);
    }

    return ret;

}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_strncasecmp, const char *s1, const char *s2, size_t n);

int strncasecmp(const char *s1, const char *s2, size_t n){
    const char *s1_token = skadi_cap_ops_derive_arg_ro(s1, MIN(strlen(s1)+1,n));
    const char *s2_token = skadi_cap_ops_derive_arg_ro(s2, MIN(strlen(s2)+1,n));
    int ret;

    __ASSERT_NO_MSG(s1_token);
    __ASSERT_NO_MSG(s2_token);
    ASSERT_ALIGNED_STRING(s1);
    ASSERT_ALIGNED_STRING(s2);

    if(!s1_token || !s2_token){
        /* TODO no great return value here... */
        ret = 0;
        goto out;
    }

    ret = __skadi_strncasecmp(s1_token, s2_token, n);

    out:
    if(s1_token){
        skadi_cap_ops_drop(s1_token);
    }
    if(s2_token){
        skadi_cap_ops_drop(s2_token);
    }

    return ret;

}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(long, __skadi_strtol, const char *nptr, char **endptr, int base);

long strtol(const char *nptr, char **endptr, int base){
    const char *nptr_token = skadi_cap_ops_derive_arg_ro(nptr, strlen(nptr)+1);
    char **endptr_token = endptr ? skadi_cap_ops_derive_arg_wo(endptr, sizeof(*endptr)) : endptr;
    long ret;

    __ASSERT_NO_MSG(nptr_token);
    __ASSERT_NO_MSG(!endptr || endptr_token);

    if(!nptr_token || (endptr && !endptr_token)){
        errno = ENOMEM;
        ret = 0;
        goto out;
    }

    ret = __skadi_strtol(nptr_token, endptr_token, base);

    if(endptr){
        __ASSERT_NO_MSG(*endptr);
        /* capabilities lose validity, and endptr is not readable via the token - but value must have been written through */
        *endptr = (char *)((uintptr_t )nptr + ((uintptr_t)*endptr - (uintptr_t) nptr_token));
    }

    out:
    if(nptr_token){
        skadi_cap_ops_drop(nptr_token);
    }
    if(endptr_token){
        skadi_cap_ops_drop(endptr_token);
    }

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(long long, __skadi_strtoll, const char *nptr, char **endptr, int base);

long long strtoll(const char *nptr, char **endptr, int base){
    const char *nptr_token = skadi_cap_ops_derive_arg_ro(nptr, strlen(nptr)+1);
    char **endptr_token = endptr ? skadi_cap_ops_derive_arg_wo(endptr, sizeof(*endptr)) : endptr;
    long long ret;

    __ASSERT_NO_MSG(nptr_token);
    __ASSERT_NO_MSG(!endptr || endptr_token);

    if(!nptr_token || (endptr && !endptr_token)){
        errno = ENOMEM;
        ret = 0;
        goto out;
    }

    ret = __skadi_strtoll(nptr_token, endptr_token, base);

    if(endptr){
        __ASSERT_NO_MSG(*endptr);
        /* capabilities lose validity, and endptr is not readable via the token - but value must have been written through */
        *endptr = (char *)((uintptr_t )nptr + ((uintptr_t)*endptr - (uintptr_t) nptr_token));
    }

    out:
    if(nptr_token){
        skadi_cap_ops_drop(nptr_token);
    }
    if(endptr_token){
        skadi_cap_ops_drop(endptr_token);
    }

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(unsigned long, __skadi_strtoul, const char *nptr, char **endptr, int base);

unsigned long strtoul(const char *nptr, char **endptr, int base){
    const char *nptr_token = skadi_cap_ops_derive_arg_ro(nptr, strlen(nptr)+1);
    char **endptr_token = endptr ? skadi_cap_ops_derive_arg_wo(endptr, sizeof(*endptr)) : endptr;
    unsigned long ret;

    __ASSERT_NO_MSG(nptr_token);
    __ASSERT_NO_MSG(!endptr || endptr_token);

    if(!nptr_token || (endptr && !endptr_token)){
        errno = ENOMEM;
        ret = 0;
        goto out;
    }

    ret = __skadi_strtoul(nptr_token, endptr_token, base);


    if(endptr){
        __ASSERT_NO_MSG(*endptr);
        /* capabilities lose validity, and endptr is not readable via the token - but value must have been written through */
        *endptr = (char *)((uintptr_t )nptr + ((uintptr_t)*endptr - (uintptr_t) nptr_token));
    }

    out:
    if(nptr_token){
        skadi_cap_ops_drop(nptr_token);
    }
    if(endptr_token){
        skadi_cap_ops_drop(endptr_token);
    }

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(unsigned long long, __skadi_strtoull, const char *nptr, char **endptr, int base);

unsigned long long strtoull(const char *nptr, char **endptr, int base){
    const char *nptr_token = skadi_cap_ops_derive_arg_ro(nptr, strlen(nptr)+1);
    char **endptr_token = endptr ? skadi_cap_ops_derive_arg_wo(endptr, sizeof(*endptr)) : endptr;
    unsigned long long ret;

    __ASSERT_NO_MSG(nptr_token);
    __ASSERT_NO_MSG(!endptr || endptr_token);

    if(!nptr_token || (endptr && !endptr_token)){
        errno = ENOMEM;
        ret = 0;
        goto out;
    }

    ret = __skadi_strtoull(nptr_token, endptr_token, base);

    if(endptr){
        __ASSERT_NO_MSG(*endptr);
        /* capabilities lose validity, and endptr is not readable via the token - but value must have been written through */
        *endptr = (char *)((uintptr_t )nptr + ((uintptr_t)*endptr - (uintptr_t) nptr_token));
    }

    out:
    if(nptr_token){
        skadi_cap_ops_drop(nptr_token);
    }
    if(endptr_token){
        skadi_cap_ops_drop(endptr_token);
    }

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(char *, __skadi_strstr, const char *haystack, const char *needle);

char *strstr(const char *haystack, const char *needle){
    const char *haystack_token = skadi_cap_ops_derive_arg_ro(haystack, strlen(haystack)+1);
    const char *needle_token = skadi_cap_ops_derive_arg_ro(needle, strlen(needle)+1);
    char *ret;

    __ASSERT_NO_MSG(haystack_token);
    __ASSERT_NO_MSG(needle_token);

    if(!haystack_token || !needle_token){
        ret = NULL;
        goto out;
    }

    ret = __skadi_strstr(haystack_token, needle_token);

    if(ret){
        /* capability will soon cease to exist */
        ret = (char*)((uintptr_t) ret - (uintptr_t)haystack_token);
        ret = (char*)((uintptr_t) haystack + (uintptr_t)ret);
    }

    out:

    if(haystack_token){
        skadi_cap_ops_drop(haystack_token);
    }

    if(needle_token){
        skadi_cap_ops_drop(needle_token);
    }

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(char *, __skadi_strchr, const char *s, int c);

char *strchr(const char *s, int c){
    const char *s_token = skadi_cap_ops_derive_arg_ro(s, strlen(s)+1);
    char *ret;

    __ASSERT_NO_MSG(s_token);

    if(!s_token){
        return NULL;
    }

    ret = __skadi_strchr(s_token, c);

    if(ret){
        /* capability will soon cease to exist */
        ret = (char*)((uintptr_t) ret - (uintptr_t)s_token);
        ret = (char*)((uintptr_t) s + (uintptr_t)ret);
    }

    if(s_token){
        skadi_cap_ops_drop(s_token);
    }

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(char *, __skadi_strrchr, const char *s, int c);

char *strrchr(const char *s, int c){
    const char *s_token = skadi_cap_ops_derive_arg_ro(s, strlen(s)+1);
    char *ret;

    __ASSERT_NO_MSG(s_token);

    if(!s_token){
        return NULL;
    }

    ret = __skadi_strrchr(s_token, c);

    if(ret){
        /* capability will soon cease to exist */
        ret = (char*)((uintptr_t) ret - (uintptr_t)s_token);
        ret = (char*)((uintptr_t) s + (uintptr_t)ret);
    }
    
    if(s_token){
        skadi_cap_ops_drop(s_token);
    }

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(char *, __skadi_strerror, int errnum);

char *strerror(int errnum){
    // long-lived token from libc's .rodata
    return __skadi_strerror(errnum);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_memcmp, const void *s1, const void *s2, size_t n);

int memcmp(const void *s1, const void *s2, size_t n){
    const void *s1_token = skadi_cap_ops_derive_arg_ro(s1, n);
    const void *s2_token = skadi_cap_ops_derive_arg_ro(s2, n);
    int ret;

    __ASSERT_NO_MSG(s1_token);
    __ASSERT_NO_MSG(s2_token);

    if(!s1_token || !s2_token){
        /* TODO no great return value here... */
        ret = 0;
        goto out;
    }

    ret = __skadi_memcmp(s1_token, s2_token, n);

    out:
    if(s1_token){
        skadi_cap_ops_drop(s1_token);
    }
    if(s2_token){
        skadi_cap_ops_drop(s2_token);
    }

    return ret;

}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void*, __skadi_memset, void *s, int c, size_t n);

void *memset(void *s, int c, size_t n){
    void *s_token = n ? skadi_cap_ops_derive_arg_wo(s, n) : 0;
    void *ret;

    if(!n){
        /* nothing to do */
        return s;
    }

    __ASSERT_NO_MSG(s_token);

    if(!s_token){
        return NULL;
    }

    (void)__skadi_memset(s_token, c, n);

    ret = s;

    if(s_token){
        skadi_cap_ops_drop(s_token);
    }

    return ret;

}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void*, __skadi_memchr, const void *s, int c, size_t n);

void *memchr(const void *s, int c, size_t n){
    const void *s_token = skadi_cap_ops_derive_arg_ro(s, n);
    void *ret;

    __ASSERT_NO_MSG(s_token);

    if(!s_token){
        return NULL;
    }

    ret = __skadi_memchr(s_token, c, n);

    if(ret){
        ret = (void *)((uintptr_t) ret - (uintptr_t)s_token);
        ret = (void *)((uintptr_t) ret + (uintptr_t) s);
    }

    if(s_token){
        skadi_cap_ops_drop(s_token);
    }

    return ret;

}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void*, __skadi_memmove, void *dest, const void *src, size_t n);

void *memmove(void *dest, const void *src, size_t n){
    void *dest_token = skadi_cap_ops_derive_arg_wo(dest, n);
    const void *src_token = skadi_cap_ops_derive_arg_ro(src, n);
    void *ret;

    __ASSERT_NO_MSG(dest_token);
    __ASSERT_NO_MSG(src_token);

    if(!dest_token || !src_token){
        ret = NULL;
        goto out;
    }

    (void)__skadi_memmove(dest_token, src_token, n);

    ret = dest;

    out:
    if(dest_token){
        skadi_cap_ops_drop(dest_token);
    }
    if(src_token){
        skadi_cap_ops_drop(src_token);
    }

    return ret;

}
#endif /* !CONFIG_SKADI_LIBC_INLINE */

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_vsnprintf, char *buffer, size_t size, const char *format, va_list ap);

int vsnprintf(char *buffer, size_t size, const char *format, va_list ap){
    const char *format_token = skadi_cap_ops_derive_arg_ro(format, strlen(format)+1);
    char *buffer_token = skadi_cap_ops_derive_arg_wo(buffer, size);
    int ret;
    void **caps_out;
    size_t caps_found;
    size_t ap_size = 0;

    __ASSERT_NO_MSG(format_token);
    __ASSERT_NO_MSG(buffer_token);

    caps_found = skadi_printf_like_handle_string_templates(format, ap, &caps_out, &ap_size);

    if(!format_token || !buffer_token){
        ret = EOF;
        goto out;
    }

    /* write permission no longer required */
    if(ap){
        (void)skadi_cap_ops_restrict(ap, skadi_no_restriction, 0, 0, SKADI_PERMISSION_READ | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS);
    }

    /* ap provided by wrapper function and initialized */
    ret = __skadi_vsnprintf(buffer_token, size, format_token, ap);

out:
    if(format_token){
        skadi_cap_ops_drop(format_token);
    }
    if(buffer_token){
        skadi_cap_ops_drop(buffer_token);
    }

    for(size_t cap = 0; cap < caps_found; cap++){
        skadi_cap_ops_drop(caps_out[cap]);
    }
    if(caps_found){
        skadi_allocator_free(caps_out);
    }

    return ret;
}

#endif /* SKADI_SUBSYSTEM_PROTECTED_LIBC */
/* otherwise, will resolve the exported symbols from the libc */


/* printf and frieds cannot be invoked directly, as they themselves use a caller trampoline */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_puts, const char *s);

int puts(const char *s){
    const char *s_token = skadi_cap_ops_derive_arg_ro(s, strlen(s)+1);
    int ret;

    __ASSERT_NO_MSG(s_token);

    if(!s_token){
        /* error return */
        return -ENOMEM;
    }

    ret = __skadi_puts(s_token);

    skadi_cap_ops_drop(s_token);

    return ret;
}


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_fputc, int c, FILE *stream);

int fputc(int c, FILE *stream){
    /* the only streams that we currently support here, as they are exported 1:1 from the libc */
    __ASSERT(stream == stdout || stream == stderr, "Unsupported stream %p!", stream);
    return __skadi_fputc(c, stream);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_vprintf, const char *format, va_list ap);

#if defined(CONFIG_SKADI_EARLYCON) && !defined(SKADI_SUBSYSTEM_ALLOCATOR)
static bool skadi_libc_uart_available = false;
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_vprintf_early, const char *format, va_list ap);

static int init_uart_complete(void){
    skadi_libc_uart_available = true;
    return 0;
}
SYS_INIT(init_uart_complete, POST_KERNEL, CONFIG_SKADI_EARLYCON_INIT_PRIO);
#endif

int vprintf(const char *format, va_list ap){
    const char *format_token = skadi_cap_ops_derive_arg_ro(format, strlen(format)+1);
    int ret;
    void **caps_out;
    size_t caps_found;
    size_t ap_size = 0;

    __ASSERT_NO_MSG(format_token);

    caps_found = skadi_printf_like_handle_string_templates(format, ap, &caps_out, &ap_size);

    /* write permission no longer required */
    if(ap){
        (void)skadi_cap_ops_restrict(ap, skadi_no_restriction, 0, 0, SKADI_PERMISSION_READ | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS);
    }

    if(!format_token){
        return -ENOMEM;
    }
#if defined(CONFIG_SKADI_EARLYCON) && !defined(SKADI_SUBSYSTEM_ALLOCATOR)
    if(!skadi_libc_uart_available){
        ret = __skadi_vprintf_early(format_token, ap);
    }
    else{
#endif        
        /* ap provided by wrapper function and initialized */
        ret = __skadi_vprintf(format_token, ap);
#if defined(CONFIG_SKADI_EARLYCON) && !defined(SKADI_SUBSYSTEM_ALLOCATOR)
    }
#endif

    skadi_cap_ops_drop(format_token);

    for(size_t cap = 0; cap < caps_found; cap++){
        skadi_cap_ops_drop(caps_out[cap]);
    }
    if(caps_found){
        skadi_allocator_free(caps_out);
    }

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_vfprintf, FILE *stream, const char *format, va_list ap);


int vfprintf(FILE *stream, const char *format, va_list ap){
    const char *format_token = skadi_cap_ops_derive_arg_ro(format, strlen(format)+1);
    int ret;
    void **caps_out;
    size_t caps_found;
    size_t ap_size = 0;

    __ASSERT_NO_MSG(format_token);

    __ASSERT(stream == stdout || stream == stderr, "Only stdout and stderr supported but got stream %p!", stream);

    caps_found = skadi_printf_like_handle_string_templates(format, ap, &caps_out, &ap_size);

    /* write permission no longer required */
    if(ap){
        (void)skadi_cap_ops_restrict(ap, skadi_no_restriction, 0, 0, SKADI_PERMISSION_READ | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS);
    }

    if(!format_token){
        return -ENOMEM;
    }
    /* ap provided by wrapper function and initialized */
    ret = __skadi_vfprintf(stream, format_token, ap);

    skadi_cap_ops_drop(format_token);

    for(size_t cap = 0; cap < caps_found; cap++){
        skadi_cap_ops_drop(caps_out[cap]);
    }
    if(caps_found){
        skadi_allocator_free(caps_out);
    }

    return ret;
}


#if !defined(CONFIG_FPU)
    /* double passed in integer register */
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(double, __skadi_sqrt, double x);
    /* float library functions */
    double sqrt(double x){
        return __skadi_sqrt(x);
    }
#endif

void *malloc(size_t size){
    return skadi_allocator_alloc_rw(size);
}

void *calloc(size_t nmemb, size_t size){
    return skadi_allocator_calloc_rw(nmemb, size);
}

void free(void *ptr){
    skadi_allocator_free(ptr);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(struct tm *, __skadi_gmtime_r, const time_t *ZRESTRICT timep, struct tm *ZRESTRICT result);
struct tm *gmtime_r(const time_t *ZRESTRICT timep,
		    struct tm *ZRESTRICT result){
    const time_t *timep_token = skadi_cap_ops_derive_arg_ro(timep, sizeof(*timep));
    struct tm *result_token = skadi_cap_ops_derive_arg(result, sizeof(*result));
    __ASSERT_NO_MSG(timep_token);
    __ASSERT_NO_MSG(result_token);

    if(!timep_token || !result_token){
        result = NULL;
        goto err_out;
    }

    result = __skadi_gmtime_r(timep_token, result_token);

    err_out:
    if(timep_token){
        (void)skadi_cap_ops_drop(timep_token);
    }
    if(result_token){
        (void)skadi_cap_ops_drop(result_token);
    }
    return result;

}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_cbvprintf, cbprintf_cb out, void *ctx, const char *fp, va_list ap);

struct cbvprintf_context_wr{
    void *ctx;
    cbprintf_cb callback;
};

static struct cbvprintf_context_wr wr_context = {};
struct k_spinlock cbvprintf_lock = {};

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_cbvprintf_callback_wrapper, int c, void *ctx)
{
    __ASSERT_NO_MSG(wr_context.callback);
    if(!wr_context.callback){
        return -EINVAL;
    }
    /* untrusted */
    ARG_UNUSED(ctx);
    return wr_context.callback(c, wr_context.ctx);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_cbvprintf_callback_wrapper)

int cbvprintf(cbprintf_cb out, void *ctx, const char *format, va_list ap){
    k_spinlock_key_t key = k_spin_lock(&cbvprintf_lock);

    const char *format_token = skadi_cap_ops_derive_arg_ro(format, strlen(format)+1);
    int ret;
    va_list ap_clone = NULL;
    void **caps_out;
    size_t caps_found;
    size_t ap_size = 0;

    wr_context.callback = out;
    wr_context.ctx = ctx;

    caps_found = skadi_printf_like_handle_string_templates(format, ap, &caps_out, &ap_size);

    /* could have no arguments -> will fail erroneously*/
    if(ap_size){
        ap_clone = skadi_valist_clone(ap, ap_size, false);

        if(!ap_clone){
            return -ENOMEM;
        }
    }

    if(!format_token){
        return -ENOMEM;
    }

    __skadi_cbvprintf(SKADI_SUBSYSTEM_FUNCTION_POINTER(__skadi_cbvprintf_callback_wrapper), NULL, format_token, ap_clone);
    if(ap_clone){
        skadi_cloned_valist_free(ap_clone);
    }
    (void)skadi_cap_ops_drop(format_token);
    for(size_t cap = 0; cap < caps_found; cap++){
        skadi_cap_ops_drop(caps_out[cap]);
    }
    if(caps_found){
        skadi_allocator_free(caps_out);
    }

    wr_context.callback = NULL;

    k_spin_unlock(&cbvprintf_lock, key);
    return ret;
}
