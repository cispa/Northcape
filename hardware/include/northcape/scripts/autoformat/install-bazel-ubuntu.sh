#!/bin/sh

set -e

apt update
apt install -y apt-transport-https curl gnupg build-essential git linux-headers-generic python3 wget
