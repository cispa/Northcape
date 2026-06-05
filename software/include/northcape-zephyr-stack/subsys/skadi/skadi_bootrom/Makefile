CROSS ?= ../../../zephyr-sdk-custom/riscv64-zephyr-elf/bin/riscv64-zephyr-elf-

all: bootrom_64.sv

zephyr.bin: ../../../build/zephyr/zephyr.bin
	cp -v $^ $@

bootrom_64.o: zephyr.bin skadi_bootrom.S
	$(CROSS)as -march=rv64gc -mabi=lp64 -fpic skadi_bootrom.S -o bootrom_64.o

bootrom_64.elf: bootrom_64.o
	$(CROSS)ld -T linker.ld -Ttext=0x0 bootrom_64.o -o bootrom_64.elf

bootrom_64.img: bootrom_64.elf
	$(CROSS)objcopy -O binary bootrom_64.elf bootrom_64.img

bootrom_64.sv: bootrom_64.img
	python3 gen_rom.py bootrom_64.img

.PHONY: clean
clean:
	$(RM) bootrom_64.o bootrom_64.elf bootrom_64.img bootrom_64.sv zephyr.bin
