# SPDX-License-Identifier: Apache-2.0

if(CONFIG_SKADI_OS)
    skadi_extension_add_sources_ifdef(fd CONFIG_ZVFS_EVENTFD skadi_zvfs_eventfd.c)
else()
    zephyr_library()
    zephyr_library_sources_ifdef(CONFIG_ZVFS_EVENTFD zvfs_eventfd.c)
endif()
