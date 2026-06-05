################################################################################
#
# NC_NETPERF
#
################################################################################
NC_NETPERF_SITE = $(BR2_EXTERNAL_NORTHCAPE_PATH)/nc_netperf
NC_NETPERF_SITE_METHOD = local
define NC_NETPERF_BUILD_CMDS
	"$(TARGET_CC)" $(@D)/net_overhead.c -o $(@D)/net_overhead -I $(BR2_EXTERNAL_NORTHCAPE_PATH)/include \
		"$(TARGET_CFLAGS)" -lm
endef
define NC_NETPERF_INSTALL_TARGET_CMDS
	$(INSTALL) -D $(@D)/net_overhead $(TARGET_DIR)/usr/bin/net_overhead
endef
$(eval $(generic-package))
