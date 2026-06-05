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

#include <zephyr/sys/cbprintf.h>

#ifndef CONFIG_SKADI_OS
EXPORT_SYMBOL(strcpy);
EXPORT_SYMBOL(strncpy);
EXPORT_SYMBOL(strlen);
EXPORT_SYMBOL(strcmp);
EXPORT_SYMBOL(strncmp);
EXPORT_SYMBOL(snprintf);
EXPORT_SYMBOL(strchr);
EXPORT_SYMBOL(strrchr);
EXPORT_SYMBOL(strtoul);
EXPORT_SYMBOL(strtol);
EXPORT_SYMBOL(strerror);
EXPORT_SYMBOL(memcmp);
EXPORT_SYMBOL(memcpy);
EXPORT_SYMBOL(memset);
EXPORT_SYMBOL(memchr);
EXPORT_SYMBOL(memmove);
EXPORT_SYMBOL(printf);
EXPORT_SYMBOL(fprintf);
EXPORT_SYMBOL(stdout);
EXPORT_SYMBOL(stderr);
EXPORT_SYMBOL(stdin);
EXPORT_SYMBOL(cbvprintf);
EXPORT_SYMBOL(strncasecmp);
EXPORT_SYMBOL(strtoull);
EXPORT_SYMBOL(strstr);
EXPORT_SYMBOL(puts);
EXPORT_SYMBOL(putchar);
EXPORT_SYMBOL(gmtime_r);


#include <zephyr/syscall_export_llext.c>
#endif
