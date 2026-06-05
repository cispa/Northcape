#!/bin/sh
. ./testsetup.sh || exit $?

if command -v xsim >/dev/null; then
    echo "Vivado simulator found!";
else
    echo "Please add Vivado bin directory to PATH and try again!"
    exit 1;
fi