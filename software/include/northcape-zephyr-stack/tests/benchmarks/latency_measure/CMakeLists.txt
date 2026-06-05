# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(latency_measure)

FILE(GLOB app_sources src/*.c)

if(CONFIG_SKADI_LOADER)
    create_skadi_subsystem_main(APP app SRCS ${app_sources} ${ZEPHYR_BASE}/subsys/timing/timing.c ${ZEPHYR_BASE}/arch/common/timing.c FPU)
else()
    target_sources(app PRIVATE ${app_sources})
endif()
