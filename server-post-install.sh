#!/usr/bin/env bash

echo -n "give your default administrator username: "
read user

echo -n "give your full name: "
read fullname

if [[ -z name ]]; then
    name=ike
fi
if [[ -z $fullname ]]; then
    fullname="Ike Devolder"
fi

# groups
groups="wheel"
if which docker > /dev/null 2>&1; then
    groups="$groups,docker"
fi

useradd -U -m -c "$fullname" -s /bin/bash -G "$groups" $user
passwd $user

echo "$user ALL=(ALL) ALL" > /etc/sudoers.d/$user
chmod u=rw,g=r,o= /etc/sudoers.d/$user

timedatectl set-ntp 1

# btrfs related
if which snapper > /dev/null 2>&1; then
    #snapper --no-dbus -c root create-config /
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
