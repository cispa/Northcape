################################################################################
#
# IRQ_CLIENT
#
################################################################################
IRQ_CLIENT_SITE = $(BR2_EXTERNAL_NORTHCAPE_PATH)/irq_client
IRQ_CLIENT_SITE_METHOD = local

define IRQ_CLIENT_BUILD_CMDS
	"$(TARGET_CC)" $(@D)/irq_client.c -o $(@D)/irq_client_independent -I $(BR2_EXTERNAL_NORTHCAPE_PATH)/include \
		"$(TARGET_CFLAGS)" -lm
	"$(TARGET_CC)" $(@D)/irq_client.c -DCONFIG_TIMER_IRQ_SAMPLE_BENCHMARK_RATE -o $(@D)/irq_client_monotonic -I $(BR2_EXTERNAL_NORTHCAPE_PATH)/include \
		"$(TARGET_CFLAGS)" -lm
endef
define IRQ_CLIENT_INSTALL_TARGET_CMDS
	$(INSTALL) -D $(@D)/irq_client_independent $(TARGET_DIR)/usr/bin/irq_client_independent
	$(INSTALL) -D $(@D)/irq_client_monotonic $(TARGET_DIR)/usr/bin/irq_client_monotonic
endef

$(eval $(generic-package))

