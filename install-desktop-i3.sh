#!/usr/bin/env bash

set -e

./install-desktop.sh desktop.packages default-wm.packages other-desktop.packages i3-wm.packages "$@"
