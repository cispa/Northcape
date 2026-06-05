#!/bin/sh

set -e

VERIBLE_VERSION="v0.0-4023-gc1271a00"
export BAZEL_VERSION="7.6.1"
cd /tmp
git clone --depth 1 -b $VERIBLE_VERSION https://github.com/chipsalliance/verible.git
cd verible
echo Installing bazel build
.github/bin/install-bazel.sh
bazel build -c opt //...
.github/bin/simple-install.sh /usr/local/bin/

echo "Installed verible to /usr/local/bin"
