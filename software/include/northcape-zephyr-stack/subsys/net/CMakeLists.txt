# SPDX-License-Identifier: Apache-2.0

if(CONFIG_SKADI_OS)
  create_skadi_subsystem_custom_sources(EXT_NAME net APP zephyr SRCS EXTRA_CPPFLAGS -I${CMAKE_CURRENT_SOURCE_DIR}/lib)

  skadi_extension_add_sources_ifdef(net CONFIG_NET_HOSTNAME_ENABLE hostname.c)

  
  skadi_extension_add_sources_ifdef(net CONFIG_NET_BUF ${ZEPHYR_BASE}/lib/net_buf/buf.c ${ZEPHYR_BASE}/lib/net_buf/buf_simple.c)
  
else()
  zephyr_library()
  zephyr_library_sources_ifdef(CONFIG_NET_HOSTNAME_ENABLE hostname.c)
endif()

if(CONFIG_NETWORKING)
  add_subdirectory(l2)
  add_subdirectory(pkt_filter)

  if(CONFIG_NET_RAW_MODE)
    if(CONFIG_SKADI_OS)
    skadi_extension_add_sources(net ip/net_pkt.c)
    else()
      zephyr_library_sources(ip/net_pkt.c)
    endif()
  else()
    add_subdirectory(ip)
  endif()
endif()

add_subdirectory(lib)

if(CONFIG_NET_CONNECTION_MANAGER)
  add_subdirectory(conn_mgr)
endif()
