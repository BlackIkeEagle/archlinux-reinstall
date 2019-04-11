#!/usr/bin/env bash

user="ike"
fulluser="Ike Devolder"

systemctl daemon-reload

# groups
groups="wheel"
if which docker > /dev/null 2>&1; then
    groups="$groups,docker"
fi
if which virtualbox > /dev/null 2>&1; then
    groups="$groups,vboxusers"
fi

useradd -U -m -c "$fulluser" -s /usr/bin/zsh -G "$groups" $user
echo "$user:123456" | chpasswd
chage -d 0 $user

echo "$user ALL=(ALL) ALL" > /etc/sudoers.d/$user
chmod u=rw,g=r,o= /etc/sudoers.d/$user

timedatectl set-ntp 1

usbguard generate-policy > /etc/usbguard/rules.conf
sed -e "s#^\(IPCAllowedUsers=\).*#\1root $user#" \
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
if which firewalld > /dev/null 2>&1; then
    systemctl enable firewalld.service
fi
if [ -x /usr/lib/bluetooth/bluetoothd ]; then
    systemctl enable bluetooth.service
fi
if which smartd > /dev/null 2>&1; then
    systemctl enable smartd.service
fi
if which tlp > /dev/null 2>&1; then
    systemctl mask systemd-rfkill.service
    systemctl mask systemd-rfkill.socket
    systemctl enable tlp.service
    systemctl enable tlp-sleep.service
fi
if which sddm > /dev/null 2>&1; then
    systemctl enable sddm.service
fi
if which lightdm > /dev/null 2>&1; then
    systemctl enable lightdm.service
fi

