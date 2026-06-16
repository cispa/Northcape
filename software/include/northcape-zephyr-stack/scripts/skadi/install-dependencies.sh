#!/bin/sh

set -e

./scripts/skadi/install-packages.sh

SDK_VERSION=0.16.8
if [ -d zephyr-sdk-${SDK_VERSION} ]; then
    echo "Zephyr SDK exists!";
else
    echo "Installing Zephyr SDK";
    wget https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${SDK_VERSION}/zephyr-sdk-${SDK_VERSION}_linux-x86_64.tar.xz;
    wget -O - https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${SDK_VERSION}/sha256.sum | shasum --check --ignore-missing;
    tar xvf zephyr-sdk-${SDK_VERSION}_linux-x86_64.tar.xz;
fi

SDK_DIR="zephyr-sdk-custom"
if [ -d ${SDK_DIR} ]; then
    echo "Zephyr SDK exists!";
else
    ./scripts/skadi/install-zephyr-sdk-custom.sh
fi

echo "\"Repurposing\" libgcc for soft-float support"
mkdir /tmp/soft-fp
cp zephyr-sdk-custom/riscv64-zephyr-elf/picolibc/lib/gcc/riscv64-zephyr-elf/14.2.0/rv64imac_zicsr_zifencei/lp64/large/libgcc.a /tmp/soft-fp
cp zephyr-sdk-${SDK_VERSION}/riscv64-zephyr-elf/picolibc/lib/gcc/riscv64-zephyr-elf/12.2.0/rv64imac_zicsr_zifencei/lp64/medany/libgcc.a /tmp/soft-fp/libgcc_medany.a

ORIGINAL_LOCATION=$(pwd)

cd /tmp/soft-fp
# fp-library-relevant files and their dependencies
for OBJ_FILE in `ar t libgcc.a`; do C_FILE=`echo $OBJ_FILE | sed  's/\.o/.c/'`; echo $C_FILE; if [ -f $ORIGINAL_LOCATION/sdk-ng/gcc/libgcc/soft-fp/$C_FILE ] || [ "$OBJ_FILE" = "_clzdi2.o" ] || [ "$OBJ_FILE" = "_lshrdi3.o" ] || [ "$OBJ_FILE" = "_ashldi3.o" ] || [ "$OBJ_FILE" = "_clzsi2.o" ] || [ "$OBJ_FILE" = "_clz.o" ] || [ "$OBJ_FILE" = "floatundidf.o" ] || [ "$OBJ_FILE" = "divdf3.o" ]; then echo Keeping file $OBJ_FILE; else echo Deleting file $OBJ_FILE; ar d libgcc.a $OBJ_FILE; fi;  done
for OBJ_FILE in `ar t libgcc_medany.a`; do C_FILE=`echo $OBJ_FILE | sed  's/\.o/.c/'`; echo $C_FILE; if [ -f $ORIGINAL_LOCATION/sdk-ng/gcc/libgcc/soft-fp/$C_FILE ] || [ "$OBJ_FILE" = "_clzdi2.o" ] || [ "$OBJ_FILE" = "_lshrdi3.o" ] || [ "$OBJ_FILE" = "_ashldi3.o" ] || [ "$OBJ_FILE" = "_clzsi2.o" ] || [ "$OBJ_FILE" = "_clz.o" ] || [ "$OBJ_FILE" = "floatundidf.o" ] || [ "$OBJ_FILE" = "divdf3.o" ]; then echo Keeping file $OBJ_FILE; else echo Deleting file $OBJ_FILE; ar d libgcc_medany.a $OBJ_FILE; fi;  done
cp -v libgcc.a $ORIGINAL_LOCATION/zephyr-sdk-custom/riscv64-zephyr-elf/riscv64-zephyr-elf/lib/libskadi-float.a
cp -v libgcc_medany.a $ORIGINAL_LOCATION/zephyr-sdk-custom/riscv64-zephyr-elf/riscv64-zephyr-elf/lib/libskadi-float-medany.a

rm -r /tmp/soft-fp

cd $ORIGINAL_LOCATION


# we currently cannot generate host tools due to version incompatibility in m4
cp -r zephyr-sdk-${SDK_VERSION}/setup.sh zephyr-sdk-${SDK_VERSION}/zephyr-sdk-x86_64-hosttools-standalone-0.9.sh zephyr-sdk-custom/


OPENOCD_VERSION=eb01c632a4bb1c07d2bddb008d6987c809f1c496

echo "Installing more recent OpenOCD ${OPENOCD_VERSION} to work around missing I-fence"
cd /tmp
git clone https://github.com/riscv-collab/riscv-openocd 
cd riscv-openocd
git checkout ${OPENOCD_VERSION}
./bootstrap && ./configure && make
cd $ORIGINAL_LOCATION
cp -v /tmp/riscv-openocd/src/openocd zephyr-sdk-custom/sysroots/x86_64-pokysdk-linux/usr/bin/openocd

rm -r /tmp/riscv-openocd

echo "Checking OpenOCD"
zephyr-sdk-custom/sysroots/x86_64-pokysdk-linux/usr/bin/openocd --version

./scripts/skadi/setup-docker.sh
