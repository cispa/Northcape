#!/bin/sh

CURRENT_DIR=$(dirname "$0")
export NORTHCAPE_ROOT=$(realpath $CURRENT_DIR/../../)
echo "Set Northcape root to $NORTHCAPE_ROOT"

CURRENT_DIR=$(realpath $CURRENT_DIR)

if command -v envsubst >/dev/null; then
    echo "envsubst found!";
else
    echo "Please install envsubst and try again!"
    exit 1;
fi

echo "Going back to dir $CURRENT_DIR"
cd $CURRENT_DIR