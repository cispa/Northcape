# Copyright (c) 2024 Nordic Semiconductor ASA
#
# SPDX-License-Identifier: Apache-2.0

if(CONFIG_SKADI_OS)
    # TODO not ported
    # skadi_extension_add_sources_ifdef(net      CONFIG_NET_DHCPV4 dhcpv4.c)
    # skadi_extension_add_sources_ifdef(net      CONFIG_NET_DHCPV4_SERVER dhcpv4_server.c)
else()
    zephyr_library()

    zephyr_library_include_directories(${ZEPHYR_BASE}/subsys/net/ip)

    zephyr_library_sources_ifdef(CONFIG_NET_DHCPV4 dhcpv4.c)
    zephyr_library_sources_ifdef(CONFIG_NET_DHCPV4_SERVER dhcpv4_server.c)

endif()
