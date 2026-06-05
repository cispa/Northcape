#!/bin/sh

set -e

cd /tmp

echo "Downloading iperf 2.0.5 source"

wget https://sourceforge.net/projects/iperf2/files/Original%20Iperf/iperf-2.0.5.tar.gz/download

tar -xvzf download

cd iperf-2.0.5/

echo "Patching unneeded / broken configure check"

sed -i s/DAST_CHECK_BOOL//g configure.ac 

autoconf

./configure

make

sudo make install

/usr/local/bin/iperf --version || true

echo "iperf 2.0.5 was installed to /usr/local/bin/iperf - please use this version with zephyr/skadi!"

rm -r /tmp/iperf*
