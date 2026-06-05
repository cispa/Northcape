#!/bin/sh
. ./testsetup.sh || exit $?

if command -v qrun >/dev/null; then
    echo "Questa simulator found!";
else
    echo "Please add questa bin directory to PATH and try again!"
    exit 1;
fi