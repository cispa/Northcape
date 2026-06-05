# SPDX-License-Identifier: Apache-2.0

if(CONFIG_SKADI_LOADER)

  create_skadi_subsystem_custom_sources(
    EXT_NAME mqtt
    APP zephyr
    SRCS
      mqtt_decoder.c
      mqtt_encoder.c
      mqtt_rx.c
      mqtt_transport_socket_tcp.c
      mqtt_transport.c
      mqtt.c
    )
  skadi_extension_add_sources_ifdef(mqtt CONFIG_MQTT_LIB_TLS mqtt_transport_socket_tls.c)
  skadi_extension_add_sources_ifdef(mqtt CONFIG_MQTT_LIB_WEBSOCKET mqtt_transport_websocket.c)

else()
zephyr_library()

zephyr_library_sources(
  mqtt_decoder.c
  mqtt_encoder.c
  mqtt_rx.c
  mqtt_transport_socket_tcp.c
  mqtt_transport.c
  mqtt.c
  )

zephyr_library_sources_ifdef(CONFIG_MQTT_LIB_TLS
  mqtt_transport_socket_tls.c
  )

zephyr_library_sources_ifdef(CONFIG_MQTT_LIB_WEBSOCKET
  mqtt_transport_websocket.c
  )
endif()
