#!/usr/bin/env bash

# groups
groups="wheel"
if which docker > /dev/null 2>&1; then
    groups="$groups,docker"
fi
if which virtualbox > /dev/null 2>&1; then
    groups="$groups,vboxusers"
fi

useradd -U -m -c 'Ike Devolder' -s /usr/bin/zsh -G "$groups" ike
echo "ike:123456" | chpasswd
chage -d 0 ike

timedatectl set-ntp 1

usbguard generate-policy > /etc/usbguard/rules.conf
sed -e 's#^\(IPCAllowedUsers=\).*#\1root ike#' \
    -i /etc/usbguard/usbguard-daemon.conf

# btrfs related
if which snapper > /dev/null 2>&1; then
    snapper -c root create-config /
    systemctl enable snapper-cleanup.timer
fi

systemctl enable haveged.service
systemctl enable usbguard.service
if which NetworkManager > /dev/null 2>&1; then
    systemctl enable NetworkManager.service
fi
if which docker > /dev/null 2>&1; then
    systemctl enable docker.service
fi
if which sddm > /dev/null 2>&1; then
    systemctl enable sddm.service
fi
if which lightdm > /dev/null 2>&1; then
    systemctl enable lightdm.service
fi

