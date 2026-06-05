# Copyright (c) 2023 KNS Group LLC (YADRO)
#
# SPDX-License-Identifier: Apache-2.0

if(CONFIG_SKADI_LOADER)
  if(CONFIG_PROFILING_PERF)
    create_skadi_subsystem_custom_sources(EXT_NAME perf APP zephyr SRCS perf_skadi.c)
  endif()

  add_subdirectory(backends)
else()

  add_subdirectory(backends)

  zephyr_library()

  zephyr_library_sources(
    perf.c
  )
endif()
