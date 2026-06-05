# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(mqtt_publisher)

FILE(GLOB app_sources src/*.c)

if(CONFIG_SKADI_LOADER)
    create_skadi_subsystem_main(APP app SRCS ${app_sources} ${ZEPHYR_BASE}/subsys/timing/timing.c ${ZEPHYR_BASE}/arch/common/timing.c EXTRA_CPPFLAGS -I${ZEPHYR_MBEDTLS_MODULE_DIR}/include -I${ZEPHYR_BASE}/modules/mbedtls/configs -DMBEDTLS_CONFIG_FILE="${CONFIG_MBEDTLS_CFG_FILE}" FPU)
else()
    target_sources(app PRIVATE ${app_sources})
endif()
