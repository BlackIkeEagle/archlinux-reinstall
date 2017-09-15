#!/usr/bin/env bash

cd "$(dirname "$(readlink -f "$0")")"
grepextra=""
if [[ ! -z $1 ]]; then
    for file in "$@"; do
        grepextra="$grepextra -f $file"
    done
fi
pacman -Qeq | grep -v -f base-packages.txt$grepextra
