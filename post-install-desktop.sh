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

if [[ "$name" != "root" ]]; then
    # groups
    groups="wheel"
    if which docker > /dev/null 2>&1; then
        groups="$groups,docker"
    fi
    if which virtualbox > /dev/null 2>&1; then
        groups="$groups,vboxusers"
    fi

    useradd -U -m -c "$fullname" -s /usr/bin/zsh -G "$groups" "$name"

    # subuid / subgid
    touch /etc/subuid
    touch /etc/subgid
    usermod --add-subuids 100000-165535 "$name"
    usermod --add-subgids 100000-165535 "$name"

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
    fi

fi

if [[ -n "$password" ]]; then
    echo "$name:$password" | chpasswd
else
    passwd $name
fi

# enable timesyncd
timedatectl set-ntp 1
systemctl enable systemd-timesyncd.service

# enable systemd-homed
systemctl enable systemd-homed.service

# btrfs related
if which snapper > /dev/null 2>&1; then
    systemctl enable snapper-timeline.timer
    systemctl enable snapper-cleanup.timer
fi

systemctl enable sshd.service
systemctl enable systemd-oomd.service
if which auditctl > /dev/null 2>&1; then
    systemctl enable auditd.service
fi
if which aa-status > /dev/null 2>&1; then
    systemctl enable apparmor.service
fi
if which firewalld > /dev/null 2>&1; then
    systemctl enable firewalld.service
fi
if which powerprofilesctl > /dev/null 2>&1; then
    systemctl enable power-profiles-daemon.service
fi
if which thermald > /dev/null 2>&1; then
    systemctl enable thermald.service
fi
if which NetworkManager > /dev/null 2>&1; then
    systemctl enable NetworkManager.service
    if which iwctl > /dev/null 2>&1; then
        systemctl mask wpa_supplicant.service
        systemctl enable iwd.service
    fi
fi
if which docker > /dev/null 2>&1; then
    systemctl enable docker.service
fi
if [ -x /usr/lib/bluetooth/bluetoothd ]; then
    systemctl enable bluetooth.service
fi
if which smartd > /dev/null 2>&1; then
    systemctl enable smartd.service
fi
if which run-system-update > /dev/null 2>&1; then
    systemctl enable download-updates.timer
    systemctl enable cleanup-pacman-cache.timer
fi
if which sddm > /dev/null 2>&1; then
    systemctl enable sddm.service
fi
if which lightdm > /dev/null 2>&1; then
    systemctl enable lightdm.service
fi
