# Makefile for Qarma golden reference
all: xsim.dir/work/xsc/dpi.so

xsim.dir/work/xsc/dpi.so: xsim.dir/work/xsc/QARMA64.lnx64.o xsim.dir/work/xsc/qarma_cbc.lnx64.o
	xsc $(EXTRA_DEFINES_XSC) -shared --gcc_link_options "-Wl,-lwolftpm -Wl,-lwolfssl"
	
xsim.dir/work/xsc/QARMA64.lnx64.o: ../../include/QARMA64/code/QARMA64.c
	sed -i "s/int sbox_use = 2;/int sbox_use = 0;/g" $^
	xsc -compile $(EXTRA_DEFINES_XSC) $^
	strip --strip-symbol main $@
	sed -i "s/int sbox_use = 0;/int sbox_use = 2;/g" $^
	

xsim.dir/work/xsc/qarma_cbc.lnx64.o: qarma_cbc.c dpi.h
	xsc -compile $(EXTRA_DEFINES_XSC) qarma_cbc.c

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
current_dir := $(patsubst %/,%,$(dir $(mkfile_path)))



clean:
	rm -r xsim.dir
