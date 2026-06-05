/*
 * Copyright (c) 2023 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */


#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#include <time.h>
#include <zephyr/llext/symbol.h>
#include <math.h>
#include <ctype.h>

#include <zephyr/sys/cbprintf.h>

#include <zephyr/skadi/skadi_subsystem.h>

#define UNALIGNED_BASE(CAP) ((skadi_cap_ops_inspect_get_base(CAP) + skadi_get_capability_offset(CAP)) & (sizeof(long)-1))

#if defined(LIBC_SUBSYSTEM) && defined(CONFIG_SKADI_LIBC_INLINE)
#define NO_SUBSYS_CALLS
#endif

#if !defined(LIBC_SUBSYSTEM)
#define NO_SUBSYS_CALLS
#endif

#ifdef LIBC_SUBSYSTEM
#define EXPORT_SYMBOL_LIBC(SYMBOL) EXPORT_SYMBOL(SYMBOL)
#else
#define EXPORT_SYMBOL_LIBC(SYMBOL)
#endif

extern char *__picolibc_strncpy(char *dest, const char *src, size_t n);
extern int __picolibc_strncmp(const char *s1, const char *s2, size_t n);
extern int __picolibc_strncasecmp(const char *s1, const char *s2, size_t n);
extern long __picolibc_strtol(const char *nptr, char **endptr, int base);
extern long long __picolibc_strtoll(const char *nptr, char **endptr, int base);
extern unsigned long __picolibc_strtoul(const char *nptr, char **endptr, int base);
extern unsigned long long __picolibc_strtoull(const char *nptr, char **endptr, int base);
extern char *__picolibc_strstr(const char *haystack, const char *needle);
extern char *__picolibc_strchr(const char *s, int c);
extern char *__picolibc_strrchr(const char *s, int c);
extern char *__picolibc_strerror(int errnum);
extern int __picolibc_memcmp(const void *s1, const void *s2, size_t n);
extern void *__picolibc_memset(void *s, int c, size_t n);
extern void *__picolibc_memchr(const void *s, int c, size_t n);
extern void *__picolibc_memmove(void *dest, const void *src, size_t n);


char *strncpy(char *dest, const char *src, size_t n){
  size_t source_length = skadi_cap_ops_inspect_get_length(src), orig_n = n;
  char *ret;
  /* no need to check dest capability length - by convention, must be long enough */
  n = MIN(n, source_length);
  ret = __picolibc_strncpy(dest, src, n);

  /* dest needs to be 0-padded */
  while(n <= orig_n){
    dest[n++] = '\0';
  }

  return ret;
}
EXPORT_SYMBOL_LIBC(strncpy);
#ifndef NO_SUBSYS_CALLS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(char*, __skadi_strncpy, char *dest, const char *src, size_t n)
  return strncpy(dest, src, n);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_strncpy)
#endif

static inline int __strncmp_slow(const volatile char *s1, const volatile char *s2, size_t n){
  int index = 0;
  while(s1[index] && s1[index] == s2[index]){
    index++;
  }

  return s1[index] - s2[index];
}

int strncmp(const char *s1, const char *s2, size_t n){
  if(UNALIGNED_BASE(s1) || UNALIGNED_BASE(s2)){
    return __strncmp_slow(s1, s2, n);
  }
  return __picolibc_strncmp(s1, s2, n);
}
EXPORT_SYMBOL_LIBC(strncmp);
#ifndef NO_SUBSYS_CALLS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_strncmp, const char *s1, const char *s2, size_t n);
  return strncmp(s1, s2, n);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_strncmp);
#endif

static inline int __strncasecmp_slow(const volatile char *s1, const volatile char *s2, size_t n){
  int index = 0;
  while(s1[index] && tolower(s1[index]) == tolower(s2[index])){
    index++;
  }

  return s1[index] - s2[index];
}

int strncasecmp(const char *s1, const char *s2, size_t n){
  if(UNALIGNED_BASE(s1) || UNALIGNED_BASE(s2)){
    return __strncasecmp_slow(s1, s2, n);
  }
  return __picolibc_strncasecmp(s1, s2, n);
}
EXPORT_SYMBOL_LIBC(strncasecmp);

#ifndef NO_SUBSYS_CALLS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_strncasecmp, const char *s1, const char *s2, size_t n);
  return strncasecmp(s1, s2, n);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_strncasecmp);
#endif

long strtol(const char *nptr, char **endptr, int base){
  return __picolibc_strtol(nptr, endptr, base);
}
EXPORT_SYMBOL_LIBC(strtol);
#ifndef NO_SUBSYS_CALLS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(long, __skadi_strtol, const char *nptr, char **endptr, int base);
  return strtol(nptr, endptr, base);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_strtol);
#endif

unsigned long strtoul(const char *nptr, char **endptr, int base){
  return __picolibc_strtoul(nptr, endptr, base);
}
EXPORT_SYMBOL_LIBC(strtoul);
#ifndef NO_SUBSYS_CALLS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(unsigned long, __skadi_strtoul, const char *nptr, char **endptr, int base);
  return strtoul(nptr, endptr, base);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_strtoul);
#endif
long long strtoll(const char *nptr, char **endptr, int base){
  return __picolibc_strtoll(nptr, endptr, base);
}
EXPORT_SYMBOL_LIBC(strtoll);
#ifndef NO_SUBSYS_CALLS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(long long, __skadi_strtoll, const char *nptr, char **endptr, int base);
  return strtoll(nptr, endptr, base);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_strtoll);
#endif
unsigned long long strtoull(const char *nptr, char **endptr, int base){
  return __picolibc_strtoull(nptr, endptr, base);
}
EXPORT_SYMBOL_LIBC(strtoull);
#ifndef NO_SUBSYS_CALLS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(unsigned long long, __skadi_strtoull, const char *nptr, char **endptr, int base);
  return strtoull(nptr, endptr, base);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_strtoull);
#endif

/* lower-performance string symbols - no "slow" wrapper needed as we force picolibc to use a "slow" implementation */
char *strstr(const char *haystack, const char *needle){
  return __picolibc_strstr(haystack, needle);
}
EXPORT_SYMBOL_LIBC(strstr);
#ifndef NO_SUBSYS_CALLS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(char *, __skadi_strstr, const char *haystack, const char *needle);
  return strstr(haystack, needle);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_strstr);
#endif

char *strchr(const char *s, int c){
  return __picolibc_strchr(s, c);
}
EXPORT_SYMBOL_LIBC(strchr);
#ifndef NO_SUBSYS_CALLS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(char *, __skadi_strchr, const char *s, int c);
  return strchr(s, c);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_strchr)
#endif

char *strrchr(const char *s, int c){
  return __picolibc_strrchr(s, c);
}
EXPORT_SYMBOL_LIBC(strrchr);
#ifndef NO_SUBSYS_CALLS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(char *, __skadi_strrchr, const char *s, int c);
  return strrchr(s, c);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_strrchr)
#endif

char *strerror(int errnum){
  return  __picolibc_strerror(errnum);
}
EXPORT_SYMBOL_LIBC(strerror);
#ifndef NO_SUBSYS_CALLS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(char *, __skadi_strerror, int errnum);
  return strerror(errnum);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_strerror);
#endif

static inline int __memcmp_slow(const void *s1, const void *s2, size_t n){
  const volatile char *s1_ch = s1;
  const volatile char *s2_ch = s2;

  while(n && *s1_ch == *s2_ch){
    s1_ch++;
    s2_ch++;
    n--;
  }
  return n ? *s1_ch - *s2_ch : 0; 
}

int memcmp(const void *s1, const void *s2, size_t n){
  if(UNALIGNED_BASE(s1) || UNALIGNED_BASE(s2)){
    return __memcmp_slow(s1, s2, n);
  }
  return __picolibc_memcmp(s1, s2, n);
}

EXPORT_SYMBOL_LIBC(memcmp);
#ifndef NO_SUBSYS_CALLS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_memcmp, const void *s1, const void *s2, size_t n);
   return memcmp(s1, s2, n);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_memcmp);
#endif

static inline void *__memset_slow(void *s, int c, size_t n){
  /* needs to be volatile to force GCC not to inline memcpy here */
  volatile char *it = s;

  for(size_t i = 0; i < n; i++){
    *it++ = (char) c;
  }

  return s;
}

void *memset(void *s, int c, size_t n){
  if(UNALIGNED_BASE(s)){
    return __memset_slow(s, c, n);
  }
  return __picolibc_memset(s, c, n);
}
EXPORT_SYMBOL_LIBC(memset);


#ifndef NO_SUBSYS_CALLS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void*, __skadi_memset, void *s, int c, size_t n);
  return memset(s, c, n);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_memset);
#endif

static inline void *__memchr_slow(const void *s, int c, size_t n){
  const volatile char *it = s;

  for(size_t i = 0; i < n; i++){
    if(*it == (char) c){
      return(void*) it;
    }
    it++;
  }

  return NULL;
}

void *memchr(const void *s, int c, size_t n){
  if(UNALIGNED_BASE(s)){
    return __memchr_slow(s, c, n);
  }
  return __picolibc_memchr(s, c, n);
}
EXPORT_SYMBOL_LIBC(memchr);

#ifndef NO_SUBSYS_CALLS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void*, __skadi_memchr, const void *s, int c, size_t n);
  return memchr(s, c, n);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_memchr);
#endif

static inline void *__memmove_slow(void *dest, const void *src, size_t n){
  volatile char *dest_ch = dest;
  const volatile char *src_ch = src;

  if(src_ch < dest_ch && dest_ch < src_ch + n){
    /* src and dest overlap - copy backwards */
    src_ch += n;
    dest_ch += n;
    while(n--){
      *--dest_ch = *--src_ch;
    }
  }
  else{
    while(n--){
      *dest_ch++ = *src_ch++;
    }
  }
  return dest;
}

void *memmove(void *dest, const void *src, size_t n){
  if(UNALIGNED_BASE(dest) || UNALIGNED_BASE(src)){
    return __memmove_slow(dest, src, n);
  }
  return __picolibc_memmove(dest, src, n);
}

EXPORT_SYMBOL_LIBC(memmove);
#ifndef NO_SUBSYS_CALLS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void*, __skadi_memmove, void *dest, const void *src, size_t n);
 return memmove(dest, src, n);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_memmove);
#endif

/* picolibc hook */
char *
_user_strerror (int errnum,
       int internal,
       int *errptr)
{
  
  ARG_UNUSED(errnum);
  ARG_UNUSED(internal);
  ARG_UNUSED(errptr);

  return 0;
}


#ifdef LIBC_SUBSYSTEM

EXPORT_SYMBOL(stdout);
EXPORT_SYMBOL(stderr);
EXPORT_SYMBOL(stdin);

/* printf() and friends not exported, as the caller trampoline into console subsystem does not support it */
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_puts, const char *s);
  return puts(s);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_puts);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_fputc, int c, FILE *stream);
  return fputc(c, stream);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_fputc);

int __always_direct_vprintf(const char *format, va_list ap){
  return vprintf(format, ap);
}
EXPORT_SYMBOL(__always_direct_vprintf);

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_vprintf, const char *format, va_list ap)
  return vprintf(format, ap);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_vprintf)
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_vfprintf, FILE *stream, const char *format, va_list ap)
  return vfprintf(stream, format, ap);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_vfprintf)

int __always_direct_vfprintf(FILE *stream, const char *format, va_list ap){
  return vfprintf(stream, format, ap);
}
EXPORT_SYMBOL(__always_direct_vfprintf);


EXPORT_SYMBOL(snprintf);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_vsnprintf, char *buffer, size_t size, const char *format, va_list ap)
  return vsnprintf(buffer, size, format, ap);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_vsnprintf)

int __always_direct_vsnprintf(char *buffer, size_t size, const char *format, va_list ap){
  return vsnprintf(buffer, size, format, ap);
}
EXPORT_SYMBOL(__always_direct_vsnprintf);

EXPORT_SYMBOL(ceil);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(double, __skadi_ceil, double val)
  return ceil(val);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_ceil)

EXPORT_SYMBOL(floor);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(double, __skadi_floor, double val)
  return floor(val);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_floor)

#ifndef SKADI_SUBSYSTEM_HAS_FPU
    /* double passed in integer register */
    SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(double, __skadi_sqrt, double x);
      return sqrt(x);
    SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_sqrt)
#endif

/* This is defined in newlib; some subsystems need it */
extern const char _ctype_[1 + 256];
EXPORT_SYMBOL(_ctype_);

/* TODO there should be a better way of doing this... */
int z_errno_var, *z_errno_token = NULL;
int *z_errno(void)
{
  if(!z_errno_token){
    z_errno_token = skadi_cap_ops_derive_arg(&z_errno_var, sizeof(z_errno_var));
    __ASSERT_NO_MSG(z_errno_token);
  }
	return z_errno_token;
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int*, __skadi_errno)
  return z_errno();
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_errno);

/* called from picolibc; used, e.g., in printf %s args*/
const char *skadi_library_subsystem_replace_string_if_inaccessible(const char *string){
  skadi_inspect_metadata_t metadata = {0};
  bool inspect_ok;

  if(!string){
    return string;
  }

  inspect_ok = skadi_cap_ops_inspect(string, &metadata);

  if(inspect_ok == false || metadata.capability_length == 0 || !metadata.read_permission || !metadata.irq_accessible_permission){
	  return "(inaccessible)";
  }

  return string;
}

#ifdef CONFIG_PROFILING_PERF
uintptr_t skadi_profiling_current_isr_state_reloc;
EXPORT_SYMBOL(skadi_profiling_current_isr_state_reloc);
#endif

#endif /* LIBC_SUBSYSTEM */
