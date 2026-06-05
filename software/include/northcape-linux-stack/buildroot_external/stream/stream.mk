################################################################################
#
# Stream
#
################################################################################
STREAM_VERSION = 6703f7504a38a8da96b353cadafa64d3c2d7a2d3
STREAM_SITE = $(call github,jeffhammond,Stream,$(STREAM_VERSION))
STREAM_LICENSE_FILES = LICENSE.txt
define STREAM_BUILD_CMDS
	"$(TARGET_CC)" $(@D)/stream.c -o $(@D)/stream -DSTREAM_ARRAY_SIZE=$(BR2_PACKAGE_STREAM_ARRAY_SIZE) \
		"$(TARGET_CFLAGS)"
endef
define STREAM_INSTALL_TARGET_CMDS
	$(INSTALL) -D $(@D)/stream $(TARGET_DIR)/usr/bin/stream
endef
$(eval $(generic-package))
