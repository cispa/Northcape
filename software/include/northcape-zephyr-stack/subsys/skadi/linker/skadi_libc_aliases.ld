/* libc is linked against libc compiled without these renamings */
strncpy = __picolibc_strncpy;
strncmp = __picolibc_strncmp;
strncasecmp = __picolibc_strncasecmp;
strtol = __picolibc_strtol;
strtoll = __picolibc_strtoll;
strtoul = __picolibc_strtoul;
strtoull = __picolibc_strtoull;
strstr = __picolibc_strstr;
strchr = __picolibc_strchr;
strrchr = __picolibc_strrchr;
strerror = __picolibc_strerror;
memcmp = __picolibc_memcmp;
memset = __picolibc_memset;
memchr = __picolibc_memchr;
memmove = __picolibc_memmove;
