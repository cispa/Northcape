#!/bin/sh
set -e
echo "Installing python packages"
python3 -m venv .venv
. .venv/bin/activate
pip install west
pip install -r scripts/requirements.txt

echo "Preparing build config in West"
rm -rf ../.west ../bootloader ../modules ../tools || true
west init -l .
west config manifest.project-filter -- +lz4
west update
west zephyr-export

echo "Setting Zephyr SDK Variables";
cd zephyr-sdk-custom
./setup.sh -t all -h -c

cd ..
./scripts/skadi/setup_mosquitto_ca.sh


echo "Applying picolibc patches"

cp ./scripts/skadi/picolibc.patch ../modules/lib/picolibc/

cd ../modules/lib/picolibc

pwd

cat newlib/libc/machine/riscv/strcmp.S

# could be cached
git apply picolibc.patch || true

git status

cd ../../../northcape-zephyr-stack

cp ./scripts/skadi/lz4.patch ../modules/lib/lz4/

cd ../modules/lib/lz4/
git checkout 11b8a1e22fa651b524494e55d22b69d3d9cebcfd # tested version
git apply lz4.patch || true
git status

cd ../../../northcape-zephyr-stack
