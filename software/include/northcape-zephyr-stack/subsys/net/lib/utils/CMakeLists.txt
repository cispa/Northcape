# SPDX-License-Identifier: Apache-2.0

if(CONFIG_SKADI_OS)
  skadi_extension_add_sources(net addr_utils.c)
else()

  zephyr_sources(
    addr_utils.c
  )

endif()
