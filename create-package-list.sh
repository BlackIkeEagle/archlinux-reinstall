#!/usr/bin/env bash

cd "$(dirname "$(readlink -f "$0")")"
pacman -Qeq | grep -v -f base-packages.txt
