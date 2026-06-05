# SPDX-License-Identifier: Apache-2.0

if(CONFIG_SKADI_OS)
  # added separately
else()
  zephyr_library()
  zephyr_library_sources_ifdef(
    CONFIG_NET_BUF
    buf.c
    buf_simple.c
    )
endif()
