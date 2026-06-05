# SPDX-License-Identifier: Apache-2.0

if(CONFIG_SKADI_OS)
  list(APPEND zperf_sources zperf_common.c zperf_session.c zperf_udp_receiver.c zperf_udp_uploader.c zperf_tcp_receiver.c zperf_tcp_uploader.c)

  # shell stubs go into SHELL subsystem
  # they use subsytem calls to communicate with the rest of this subsystem
  # TODO resolve loop
  skadi_extension_add_sources_ifdef(
    shell
    CONFIG_NET_SHELL
    zperf_shell.c
  )

  if(CONFIG_NET_SHELL)
    skadi_extension_add_compile_options(shell -I${ZEPHYR_BASE}/subsys/net/ip/ -I${CMAKE_CURRENT_SOURCE_DIR})
  endif()

  create_skadi_subsystem_custom_sources(EXT_NAME zperf APP zephyr SRCS ${zperf_sources} EXTRA_CPPFLAGS -I${ZEPHYR_BASE}/subsys/net/ip/ -I${CMAKE_CURRENT_SOURCE_DIR})
else()

  zephyr_library_named(zperf)

  zephyr_library_sources(
    zperf_common.c
    zperf_session.c
    zperf_udp_receiver.c
    zperf_udp_uploader.c
    zperf_tcp_receiver.c
    zperf_tcp_uploader.c
  )

  zephyr_library_sources_ifdef(CONFIG_NET_SHELL
    zperf_shell.c
  )

  zephyr_library_include_directories(
    ${ZEPHYR_BASE}/subsys/net/ip
  )

endif()
