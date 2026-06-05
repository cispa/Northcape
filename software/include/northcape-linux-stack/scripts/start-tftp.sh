#!/bin/sh
INTERFACE_IP="10.10.10.1/24"
INTERFACE="ens19"
set -e

[ -d install64 ] || (cd .. && echo "Creating install64 symlink for TFTP" && ln -s $(pwd)/install64 scripts/install64)

echo "Adding interface IP $INTERFACE_IP to interface $INTERFACE"
ip addr add $INTERFACE_IP dev $INTERFACE || true

echo "Creating dnsmasq config"
[ -f .tftp.conf ] || envsubst < tftp.conf > .tftp.conf

echo "Allowing uImage to be transferred via TFTP"
chown -R dnsmasq install64

echo "Starting dnsmasq"
dnsmasq  -p0 -C .tftp.conf