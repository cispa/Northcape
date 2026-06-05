#include <math.h>
#include <string.h>

#include <zephyr/skadi/skadi_ops_driver.h>

static int __strcmp_slow(const volatile char *s1, const volatile char *s2){
    while(*s1 == *s2 && *s1 && *s2){
        s1++;
        s2++;
    }

    return *s1 - *s2;
}

#define CAPABILITY_MISALIGNED(CAPABILITY_BASE,CAPABILITY_TOKEN) \
    (((CAPABILITY_BASE) + skadi_get_capability_offset(CAPABILITY_TOKEN)) & (sizeof(long)-1))

int strcmp(const char *s1, const char *s2){
    size_t cap_length_1;
    size_t cap_length_2;
    uintptr_t cap_base_1;
    uintptr_t cap_base_2;
    skadi_inspect_metadata_t metadata_out = {0};
    bool ret;

#ifndef SKADI_SUBSYSTEM
    /* Loader - Northcape not yet loaded */
    if(!skadi_cap_ops_get_northcape_enabled()){
        return __strcmp_slow(s1, s2);
    }
#endif

    ret = skadi_cap_ops_inspect(s1, &metadata_out);
    __ASSERT_NO_MSG(ret);

    cap_length_1 = metadata_out.capability_length - skadi_get_capability_offset(s1);
    cap_base_1 = metadata_out.capability_base;

    ret = skadi_cap_ops_inspect(s2, &metadata_out);
    __ASSERT_NO_MSG(ret);

    cap_length_2 = metadata_out.capability_length - skadi_get_capability_offset(s2);
    cap_base_2 = metadata_out.capability_base;


    __ASSERT_NO_MSG(cap_length_1);
    __ASSERT_NO_MSG(cap_length_2);

    if(CAPABILITY_MISALIGNED(cap_base_1, s1) || CAPABILITY_MISALIGNED(cap_base_2, s2)){
        return __strcmp_slow(s1, s2);
    }


    /* strncmp takes care to not over-read the capability */
    return strncmp(s1, s2, MIN(cap_length_1, cap_length_2));
}

static char *__strcpy_slow(volatile char *dest, const volatile char *src){
    while(*src){
        *dest++ = *src++;
    }
    *dest = '\0';
    return (char*) dest;
}

#define POINTER_UNALIGNED(POINTER) ((((uintptr_t) POINTER) & (sizeof(long)-1)) != 0)

/* macro from picolibc */
/* Nonzero if X (a long int) contains a NULL byte. */
#define DETECTNULL(X) (((X) - 0x0101010101010101) & ~(X) & 0x8080808080808080)

/* CANNOT use strncpy - this would have to overwrite rest of the capability, possibly call strlen unnecessarily as well */
char *strcpy(char *dest, const char *src){
    size_t cap_length_1;
    size_t cap_length_2;
    uintptr_t cap_base_1;
    uintptr_t cap_base_2;
    bool ret;
    skadi_inspect_metadata_t metadata_out = {0};
    const long *src_long;
    long *dest_long;
    char *or_dest = dest;

#ifndef SKADI_SUBSYSTEM
    /* Loader - Northcape not yet loaded */
    if(!skadi_cap_ops_get_northcape_enabled()){
        return __strcpy_slow(dest, src);
    }
#endif
    
    ret = skadi_cap_ops_inspect(dest, &metadata_out);
    cap_length_1 = metadata_out.capability_length - skadi_get_capability_offset(dest);
    cap_base_1 = metadata_out.capability_base;
    __ASSERT_NO_MSG(ret);

    ret = skadi_cap_ops_inspect(src, &metadata_out);
    cap_length_2 = metadata_out.capability_length - skadi_get_capability_offset(src);
    cap_base_2 = metadata_out.capability_base;
    __ASSERT_NO_MSG(ret);

    __ASSERT_NO_MSG(cap_length_1);
    __ASSERT_NO_MSG(cap_length_2);

     if(CAPABILITY_MISALIGNED(cap_base_1, dest) || CAPABILITY_MISALIGNED(cap_base_2, src)){
        return __strcpy_slow(dest, src);
    }


    while(POINTER_UNALIGNED(dest) || POINTER_UNALIGNED(src)){
        *dest++=*src;
        if(!*src){
            return or_dest;
        }
        src++;
        cap_length_2--;
   }

   src_long = (const long *) src;
   dest_long = (long *) dest;

   while(cap_length_2 >= sizeof(long) && !DETECTNULL(*src_long)){
    *dest_long ++ = *src_long++;
    cap_length_2 -= sizeof(long);
   }

   dest = (char *) dest_long;
   src = (const char *) src_long;

   while((*dest++ = *src++));

   return or_dest;
}

static size_t __strlen_slow(const char *s){
    const volatile char *const start = s;
    while(*s != '\0'){
        s++;
    }
    return s - start;
}

size_t strlen(const char *s){
    size_t cap_length;
    uintptr_t cap_base;
    const long *it;
    bool ok;
    skadi_inspect_metadata_t metadata_out = {0};
    const char *const start = s;
#ifndef SKADI_SUBSYSTEM
    /* Loader - Northcape not yet loaded */
    if(!skadi_cap_ops_get_northcape_enabled()){
        return __strlen_slow(s);
    }
#endif

    if(!skadi_cap_ops_get_northcape_enabled()){
        return __strlen_slow(s);
    }
    

    ok = skadi_cap_ops_inspect(s, &metadata_out);
    cap_length = metadata_out.capability_length - skadi_get_capability_offset(s);
    cap_base = metadata_out.capability_base;
    __ASSERT_NO_MSG(ok);

    if(CAPABILITY_MISALIGNED(cap_base, s)){
        return __strlen_slow(s);
    }


    while(POINTER_UNALIGNED(s)){
        if(!*s){
            return s - start;
        }
        s++;
        cap_length --;
    }

    it  = (const long *) s;

    /* aligned - read register-width-wise while possible*/
    while(cap_length >= sizeof(long) && !DETECTNULL(*it)){
        it++;
        cap_length -= sizeof(long);
    }

    s = (const char*) it;

    while(*s){
        s++;
    }

    return s - start;

}



/* inlined for performance + bootstrapping; TODO optimize in case dest and source permit XLEN-byte access */
static void *__memcpy_slow(void *const dest, const void *src, size_t n){
    volatile uint8_t *dest_ptr = dest;
    const volatile uint8_t *src_ptr = src;

    for(size_t i = 0; i < n; i++){
        dest_ptr[i] = src_ptr[i];
    }

    return dest;

}


void *memcpy(void *const dest, const void *src, size_t n){
    size_t cap_length_1;
    size_t cap_length_2;
    uintptr_t cap_base_1;
    uintptr_t cap_base_2;
    bool ret;
    skadi_inspect_metadata_t metadata_out = {0};
    long *dest_long = dest;
    const long *src_long = src;
    char *dest_char;
    const char *src_char;

#ifndef SKADI_SUBSYSTEM
    /* Loader - Northcape not yet loaded */
    if(!skadi_cap_ops_get_northcape_enabled()){
        return __memcpy_slow(dest, src, n);
    }
#endif
    

    ret = skadi_cap_ops_inspect(dest, &metadata_out);
    cap_length_1 = metadata_out.capability_length - skadi_get_capability_offset(dest);
    cap_base_1 = metadata_out.capability_base;
    __ASSERT_NO_MSG(ret);

    ret = skadi_cap_ops_inspect(src, &metadata_out);
    cap_length_2 = metadata_out.capability_length - skadi_get_capability_offset(src);
    cap_base_2 = metadata_out.capability_base;
    __ASSERT_NO_MSG(ret);

     if(CAPABILITY_MISALIGNED(cap_base_1, dest) || CAPABILITY_MISALIGNED(cap_base_2, src)){
        return __memcpy_slow(dest, src, n);
    }

    __ASSERT(!(cap_length_1 < n || cap_length_2 < n), "One capability is too short - length 1 %zu lenght 2 %zu n %zu", cap_length_1, cap_length_2, n);

    while(n>=sizeof(long)){
        *dest_long++=*src_long++;
        n-=sizeof(long);
    }

    dest_char = (char *) dest_long;
    src_char = (const char *) src_long;

    while(n){
        *dest_char++=*src_char++;
        n--;
    }

    return dest;
}
