#!/bin/sh

set -e

export ORIGINAL_LOCATION=$(pwd)

export ZEPHYR_SDK_VERSION=0.16.8

if [ -d sdk-ng ]; then
    echo "sdk-ng exists!";
else
    git clone --depth 1 -b "v${ZEPHYR_SDK_VERSION}" --recursive https://github.com/zephyrproject-rtos/sdk-ng.git
fi

cd sdk-ng

export WORKSPACE=$(pwd)
export GITHUB_WORKSPACE=${WORKSPACE}
export CONFIG_FILE_NAME=riscv64-zephyr-elf
export SDK_CONFIG_FILE=${WORKSPACE}/configs/${CONFIG_FILE_NAME}.config
export TOOLCHAIN_OUTPUT_DIR=${WORKSPACE}/output/${CONFIG_FILE_NAME}
export BUILD_DIR="${WORKSPACE}"/build-${CONFIG_FILE_NAME}


export CT_PREFIX="${WORKSPACE}"/output
export CT_NG="${WORKSPACE}"/crosstool-ng/bin/ct-ng

mkdir -p ${TOOLCHAIN_OUTPUT_DIR}

if [ -f "$CT_NG" ]; then
    echo "crosstool-ng exists!"
else
    (cd crosstool-ng/ && ./bootstrap)
    (cd crosstool-ng/ && ./configure --prefix="${WORKSPACE}/crosstool-ng" && make && sudo make install)
fi

mkdir -p ${BUILD_DIR}

cat "${WORKSPACE}"/configs/common.config "${SDK_CONFIG_FILE}" > ${BUILD_DIR}/.config
cat << 'EOF' >> ${BUILD_DIR}/.config
CT_SHOW_CT_VERSION=n
CT_LOCAL_TARBALLS_DIR="${WORKSPACE}/sources"
CT_OVERLAY_LOCATION="${GITHUB_WORKSPACE}/overlays"
CT_LOG_PROGRESS_BAR=n
CT_LOG_EXTRA=y
CT_LOG_LEVEL_MAX="EXTRA"
CT_GDB_CROSS_PYTHON=y
CT_GDB_CROSS_PYTHON_VARIANT=y
CT_GDB_CROSS_PYTHON_BINARY="python3.8"
CT_EXPERIMENTAL=y
CT_ALLOW_BUILD_AS_ROOT=y
CT_ALLOW_BUILD_AS_ROOT_SURE=y
# custom gcc
CT_GCC_SRC_DEVEL=y
CT_GCC_DEVEL_VCS_git=y
CT_GCC_DEVEL_VCS="git"
CT_GCC_DEVEL_URL="git://gcc.gnu.org/git/gcc.git"
CT_GCC_DEVEL_BRANCH="releases/gcc-14.2.0"
CT_GCC_VERY_NEW=y
CT_GCC_VERSION="new"
# custom CFLAGS for newlib nano needed for GCC 14
CT_LIBC_NEWLIB_NANO_TARGET_CFLAGS="-Wno-error=implicit-function-declaration -Wno-error=int-conversion -mno-relax -mcmodel=large -fno-jump-tables"
# force correct arch etc.
CT_LIBC_PICOLIBC_TARGET_CFLAGS="-Wno-error=implicit-function-declaration -Wno-error=int-conversion -march=${TARGET_ARCH} -mabi=${TARGET_ABI} -mno-relax -fno-jump-tables -mcmodel=large ${TARGET_EXTRA_CFLAGS}"
EOF

sed -i s/CT_GCC_SRC_CUSTOM=y//g ${BUILD_DIR}/.config
sed -i 's|CT_GCC_CUSTOM_LOCATION="${GITHUB_WORKSPACE}/gcc"||g' ${BUILD_DIR}/.config

# implicit-function-declaration, int-conversion (and a few other warnings) are errors in new GCC versions by default
sed -i 's/CT_LIBC_NEWLIB_TARGET_CFLAGS="-O2"/CT_LIBC_NEWLIB_TARGET_CFLAGS="-O2 -Wno-error=implicit-function-declaration -Wno-error=int-conversion -mno-relax -fno-jump-tables -mcmodel=large"/g' ${BUILD_DIR}/.config
sed -i 's/CT_LIBC_NEWLIB_NANO_TARGET_CFLAGS=""/CT_LIBC_NEWLIB_NANO_TARGET_CFLAGS="-Wno-error=implicit-function-declaration -Wno-error=int-conversion -mno-relax -fno-jump-tables -mcmodel=large"/g' ${BUILD_DIR}/.config

export TARGET_ARCH=rv64imafdc_zicsr_zifencei
export TARGET_ABI=lp64d
export TARGET_EXTRA_CFLAGS="-mcmodel=large -mno-relax -fno-jump-tables"
# gcc build specific
export CFLAGS_FOR_TARGET="-mcmodel=large -mno-relax -fno-jump-tables"
# arch settings

sed -i 's/CT_ARCH_ARCH="rv32ima_zicsr_zifencei"/CT_ARCH_ARCH="${TARGET_ARCH}"/g' ${BUILD_DIR}/.config
sed -i 's/CT_ARCH_ABI="ilp32"/CT_ARCH_ABI="${TARGET_ABI}"/g' ${BUILD_DIR}/.config
sed -i 's/CT_TARGET_CFLAGS="-ftls-model=local-exec"/CT_TARGET_CFLAGS="-ftls-model=local-exec ${TARGET_EXTRA_CFLAGS}"/g' ${BUILD_DIR}/.config

# need to force picolibc to use the exact same compiler options as we will use in the final binary
# otherwise, we'll get linker errors

(cd ${BUILD_DIR} && \
    "${CT_NG}" savedefconfig DEFCONFIG=build.config && \
    "${CT_NG}" distclean && \
    "${CT_NG}" defconfig DEFCONFIG=build.config && \
    sed -i 's|CT_CC_GCC_EXTRA_CONFIG_ARRAY="--with-gnu-ld --with-gnu-as --enable-initfini-array"|CT_CC_GCC_EXTRA_CONFIG_ARRAY="CFLAGS=\\"-fno-jump-tables -mcmodel=large\\" --with-gnu-ld --with-gnu-as --enable-initfini-array --with-multilib-generator=rv64imafdc_zicsr_zifencei-lp64d--\\;rv64imac_zicsr_zifencei-lp64--\\;--cmodel=large"|g' .config && \
    "${CT_NG}" build)

chmod -R u+w "${TOOLCHAIN_OUTPUT_DIR}"

mkdir $ORIGINAL_LOCATION/zephyr-sdk-custom
cp -v -r ${TOOLCHAIN_OUTPUT_DIR} $ORIGINAL_LOCATION/zephyr-sdk-custom/riscv64-zephyr-elf
cp -v -r cmake $ORIGINAL_LOCATION/zephyr-sdk-custom/cmake

echo ${ZEPHYR_SDK_VERSION} > $ORIGINAL_LOCATION/zephyr-sdk-custom/sdk_version
echo "riscv64-zephyr-elf" > $ORIGINAL_LOCATION/zephyr-sdk-custom/sdk_toolchains

NON_RISCV_TOOLCHAINS=$(cd $ORIGINAL_LOCATION/ && find zephyr-sdk-${ZEPHYR_SDK_VERSION} -maxdepth 1 -type d | grep elf | grep -v riscv64-zephyr-elf)

for toolchain in $NON_RISCV_TOOLCHAINS; do 
    TOOLCHAIN_NAME=$(echo $toolchain | awk -F '/' '{print $2};')
    echo "Installing $TOOLCHAIN_NAME in custom SDK!"; 
    ln -s $ORIGINAL_LOCATION/$toolchain $ORIGINAL_LOCATION/zephyr-sdk-custom/$TOOLCHAIN_NAME
    echo $TOOLCHAIN_NAME >> $ORIGINAL_LOCATION/zephyr-sdk-custom/sdk_toolchains
done
