################################################################################
#
# MQTT_BENCH
#
################################################################################
MQTT_BENCH_SITE = $(BR2_EXTERNAL_NORTHCAPE_PATH)/mqtt_bench
MQTT_BENCH_SITE_METHOD = local

define MQTT_BENCH_BUILD_CMDS
	"$(TARGET_CC)" $(@D)/mqtt_bench.c -o $(@D)/mqtt_bench -I $(BR2_EXTERNAL_NORTHCAPE_PATH)/include \
		"$(TARGET_CFLAGS)" -lm -lmosquitto
endef
define MQTT_BENCH_INSTALL_TARGET_CMDS
	$(INSTALL) -D $(@D)/mqtt_bench $(TARGET_DIR)/usr/bin/mqtt_bench
endef

$(eval $(generic-package))

