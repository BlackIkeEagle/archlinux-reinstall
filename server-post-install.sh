#!/usr/bin/env bash

if [[ -n "$1" ]]; then
    name="$1"
    shift
fi

if [[ -n "$1" ]]; then
    fullname="$1"
    shift
fi

if [[ -n "$1" ]]; then
    password="$1"
    shift
fi

if [[ -z "$name" ]]; then
    name=ike
fi
if [[ -z "$fullname" ]]; then
    fullname="Ike Devolder"
fi

# groups
groups="wheel"
if which docker > /dev/null 2>&1; then
    groups="$groups,docker"
fi

useradd -U -m -c "$fullname" -s /bin/bash -G "$groups" $name
if [[ -n "$password" ]]; then
    echo "$name:$password" | chpasswd
else
    passwd $name
fi

echo "$name ALL=(ALL) ALL" > /etc/sudoers.d/$name
echo "$name ALL=(root) NOPASSWD: /usr/bin/systemctl poweroff" \
    >> /etc/sudoers.d/$name
chmod u=rw,g=r,o= /etc/sudoers.d/$name

timedatectl set-ntp 1

# btrfs related
if which snapper > /dev/null 2>&1; then
    snapper -c root create-config /
    systemctl enable snapper-cleanup.timer
fi

systemctl enable haveged.service
systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
systemctl enable sshd.service
systemctl enable auditd.service
systemctl enable apparmor.service
if which docker > /dev/null 2>&1; then
    systemctl enable docker.service
fi
if which firewalld > /dev/null 2>&1; then
    systemctl enable firewalld.service
fi
