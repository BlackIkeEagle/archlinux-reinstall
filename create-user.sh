#!/usr/bin/env bash

if [[ -n "$1" ]]; then
    name="$1"
    shift
fi

if [[ -n "$1" ]]; then
    fullname="$1"
    shift
fi

if [[ -z "$name" ]]; then
    name=ike
fi
if [[ -z "$fullname" ]]; then
    fullname="Ike Devolder"
fi

homectl create "$name" \
    --real-name="$fullname" \
    --shell="/usr/bin/zsh" \
    --storage=luks \
    --luks-discard=true \
    --fs-type=ext4 \
    --member-of=flatpak
