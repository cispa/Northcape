################################################################################
#
# NC_PULP_TIMER
#
################################################################################
PULP_TIMER_SITE = $(BR2_EXTERNAL_NORTHCAPE_PATH)/pulp_timer
PULP_TIMER_SITE_METHOD = local
PULP_TIMER_VERSION = 1.0

$(eval $(kernel-module))
$(eval $(generic-package))

