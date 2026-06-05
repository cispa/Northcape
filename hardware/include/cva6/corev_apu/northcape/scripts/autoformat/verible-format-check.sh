#!/bin/bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd $SCRIPT_DIR
./verible-format.sh

if [[ `git status --porcelain --untracked-files=no` ]]; then
  echo "Git repository was modified - assuming formatter found something!"
  exit 1
else
  echo "Formatter satisfied!"
  exit 0
fi