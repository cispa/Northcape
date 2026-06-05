# SPDX-License-Identifier: Apache-2.0

if(CONFIG_SKADI_OS)
  skadi_extension_add_compile_options(net  -I${CMAKE_CURRENT_SOURCE_DIRECTORY})

  if(CONFIG_NEWLIB_LIBC)
    skadi_extension_add_compile_options(net  "-D CONFIG_NEWLIB_LIBC" "-D __LINUX_ERRNO_EXTENSIONS__")
  endif()
  
  skadi_extension_add_sources_ifdef(net CONFIG_NET_CONFIG_SETTINGS skadi_init.c)
  if(CONFIG_NET_CONFIG_SETTINGS)
    skadi_extension_add_sources_ifdef(net CONFIG_NET_L2_IEEE802154 ieee802154_settings.c)
  endif()
  skadi_extension_add_sources_ifdef(net CONFIG_NET_CONFIG_CLOCK_SNTP_INIT init_clock_sntp.c)
else()
  zephyr_library()
  zephyr_library_compile_definitions_ifdef(
    CONFIG_NEWLIB_LIBC __LINUX_ERRNO_EXTENSIONS__
    )

  zephyr_library_sources_ifdef(CONFIG_NET_CONFIG_SETTINGS init.c)

  if(CONFIG_NET_CONFIG_SETTINGS)
    zephyr_library_sources_ifdef(
      CONFIG_NET_L2_IEEE802154
      ieee802154_settings.c
      )
  endif()

  zephyr_library_sources_ifdef(CONFIG_NET_CONFIG_CLOCK_SNTP_INIT init_clock_sntp.c)
endif()
