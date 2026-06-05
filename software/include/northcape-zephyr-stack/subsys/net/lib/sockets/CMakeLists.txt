# SPDX-License-Identifier: Apache-2.0

if(CONFIG_SKADI_OS)
  skadi_extension_add_compile_options(net  -I${ZEPHYR_BASE}/subsys/net/ip -I${ZEPHYR_BASE}/subsys/net/l2)

  skadi_extension_add_sources(net getaddrinfo.c  skadi_sockets.c  sockets_select.c)

  if(NOT CONFIG_NET_SOCKETS_OFFLOAD)
    skadi_extension_add_sources(net getnameinfo.c sockets_misc.c)
  endif()

  skadi_extension_add_sources_ifdef(net    CONFIG_NET_SOCKETS_CAN                sockets_can.c)
  skadi_extension_add_sources_ifdef(net    CONFIG_NET_SOCKETS_PACKET             sockets_packet.c)
  skadi_extension_add_sources_ifdef(net    CONFIG_NET_SOCKETS_SOCKOPT_TLS        skadi_sockets_tls.c)
  skadi_extension_add_sources_ifdef(net    CONFIG_NET_SOCKETS_OFFLOAD            socket_offload.c)
  skadi_extension_add_sources_ifdef(net    CONFIG_NET_SOCKETS_OFFLOAD_DISPATCHER socket_dispatcher.c)
  skadi_extension_add_sources_ifdef(net    CONFIG_NET_SOCKETS_OBJ_CORE           socket_obj_core.c)
  skadi_extension_add_sources_ifdef(net    CONFIG_NET_SOCKETS_SERVICE            sockets_service.c)
  skadi_extension_add_sources_ifdef(net    CONFIG_NET_SOCKETPAIR                 skadi_socketpair.c)
  if(CONFIG_NET_SOCKETS_SOCKOPT_TLS)
    skadi_extension_add_compile_options(net -I${ZEPHYR_BASE}/modules/mbedtls/configs)
    skadi_extension_add_compile_options(net -I${ZEPHYR_BASE}/modules/mbedtls/include)
    skadi_extension_add_compile_options(net -I${ZEPHYR_MBEDTLS_MODULE_DIR}/include)
    skadi_extension_add_compile_options(net -DMBEDTLS_CONFIG_FILE="${CONFIG_MBEDTLS_CFG_FILE}")
  endif()

else()


  zephyr_syscall_header(
    ${ZEPHYR_BASE}/include/zephyr/net/socket.h
    ${ZEPHYR_BASE}/include/zephyr/net/socket_select.h
  )

  zephyr_library_include_directories(.)

  zephyr_library_sources(
    getaddrinfo.c
    sockets.c
    sockets_select.c
  )

  if(NOT CONFIG_NET_SOCKETS_OFFLOAD)
  zephyr_library_sources(
    getnameinfo.c
    sockets_misc.c
    )
  endif()

  zephyr_library_sources_ifdef(CONFIG_NET_SOCKETS_CAN                sockets_can.c)
  zephyr_library_sources_ifdef(CONFIG_NET_SOCKETS_PACKET             sockets_packet.c)
  zephyr_library_sources_ifdef(CONFIG_NET_SOCKETS_SOCKOPT_TLS        sockets_tls.c)
  zephyr_library_sources_ifdef(CONFIG_NET_SOCKETS_OFFLOAD            socket_offload.c)
  zephyr_library_sources_ifdef(CONFIG_NET_SOCKETS_OFFLOAD_DISPATCHER socket_dispatcher.c)
  zephyr_library_sources_ifdef(CONFIG_NET_SOCKETS_OBJ_CORE           socket_obj_core.c)
  zephyr_library_sources_ifdef(CONFIG_NET_SOCKETS_SERVICE            sockets_service.c)

  if(CONFIG_NET_SOCKETS_NET_MGMT)
    zephyr_library_sources(sockets_net_mgmt.c)
    zephyr_library_include_directories(${ZEPHYR_BASE}/subsys/net/ip)
  endif()

  if(CONFIG_SOCKS)
    zephyr_library_include_directories(${ZEPHYR_BASE}/subsys/net/lib/socks)
  endif()

  zephyr_library_sources_ifdef(CONFIG_NET_SOCKETPAIR socketpair.c)

  zephyr_library_link_libraries_ifdef(CONFIG_MBEDTLS mbedTLS)
endif()
