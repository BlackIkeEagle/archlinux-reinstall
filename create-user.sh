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

# groups
groups="--member-of=wheel"
if which docker > /dev/null 2>&1; then
    groups="$groups --member-of=docker"
fi
if which virtualbox > /dev/null 2>&1; then
    groups="$groups --member-of=vboxusers"
fi

homectl create "$name" \
    --real-name="$fullname" \
    --shell="/usr/bin/zsh" \
    --storage=luks \
    --fs-type=ext4 \
    $groups

# subuid / subgid
touch /etc/subuid
touch /etc/subgid
usermod --add-subuids 100000-165535 "$name"
usermod --add-subgids 100000-165535 "$name"

echo "$name ALL=(ALL) ALL" > /etc/sudoers.d/$name
chmod u=rw,g=r,o= /etc/sudoers.d/$name
