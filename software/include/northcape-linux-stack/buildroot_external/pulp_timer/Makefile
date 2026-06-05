obj-m += $(addsuffix .o, $(notdir $(basename $(wildcard $(BR2_EXTERNAL_NORTHCAPE_PATH)/pulp_timer/*.c))))
ccflags-y := -DDEBUG -g -std=gnu99 -Wno-declaration-after-statement -I $(BR2_EXTERNAL_NORTHCAPE_PATH)/include

.PHONY: all clean

all:
	$(MAKE) -C '$(LINUX_DIR)' M='$(PWD)' modules

clean:
	$(MAKE) -C '$(LINUX_DIR)' M='$(PWD)' clean
