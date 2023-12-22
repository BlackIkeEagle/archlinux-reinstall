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

if [[ "$name" == "vagrant" ]]; then
    echo "$name ALL=(root) NOPASSWD: ALL" > /etc/sudoers.d/$name
else
    echo "$name ALL=(ALL) ALL" > /etc/sudoers.d/$name
fi
chmod u=rw,g=r,o= /etc/sudoers.d/$name

if [[ "$name" == "vagrant" ]]; then
    mkdir -p /home/vagrant/.ssh
    chown vagrant:vagrant /home/vagrant/.ssh
    curl --output /home/vagrant/.ssh/authorized_keys \
        --location https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub
    chown vagrant:vagrant /home/vagrant/.ssh/authorized_keys
    chmod 0600 /home/vagrant/.ssh/authorized_keys
    # remove default network config
    rm -f /etc/systemd/network/*
    cat <<EOF >/etc/systemd/network/en.network
[Match]
Name=en*

[Network]
DHCP=ipv4
EOF
fi

timedatectl set-ntp 1

# btrfs related
if which snapper > /dev/null 2>&1; then
    systemctl enable snapper-timeline.timer
    systemctl enable snapper-cleanup.timer
fi

systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
systemctl enable sshd.service
systemctl enable systemd-oomd.service
systemctl enable auditd.service
systemctl enable apparmor.service
if which docker > /dev/null 2>&1; then
    systemctl enable docker.service
fi
if which firewalld > /dev/null 2>&1; then
    systemctl enable firewalld.service
fi
if which run-system-update > /dev/null 2>&1; then
    systemctl enable download-updates.timer
    systemctl enable cleanup-pacman-cache.timer
fi
