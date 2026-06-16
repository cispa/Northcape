#!/bin/sh
set -e
echo "Installing system packages"
ln -fs /usr/share/zoneinfo/Europe/Berlin /etc/localtime

export DEBIAN_FRONTEND=noninteractive

sudo apt-get update && sudo apt-get install -y software-properties-common

sudo add-apt-repository ppa:deadsnakes/ppa

# "python3" binary should point to the upstream version, for which distutils etc. exists
# so we install the older version first
sudo apt-get update && sudo apt-get install -y python3.8 python3.8-dev python3.8-distutils

sudo apt-get update && sudo apt-get install -y \
    python3 \
    python3-venv \
    python3-dev \
    git cmake ninja-build gperf \
    ccache dfu-util device-tree-compiler wget \
    python3-dev python3-venv python3-pip python3-setuptools python3-tk python3-wheel xz-utils file \
    make gcc gcc-multilib g++-multilib libsdl2-dev libmagic1 libtool-bin meson chrpath \
    diffstat flex texinfo unzip help2man autoconf automake bison gettext help2man libboost-dev \
    libboost-regex-dev libncurses5-dev libtool-bin libtool-doc pkg-config p7zip jq dos2unix gawk \
    mosquitto mosquitto-clients libssl-dev linuxptp libjim-dev xxd libmpfr-dev libmpc-dev libgmp-dev lz4 \
    parallel libwolfssl-dev curl

./scripts/skadi/download_install_iperf_2_0_5.sh
