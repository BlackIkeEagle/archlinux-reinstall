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
if which virtualbox > /dev/null 2>&1; then
    groups="$groups,vboxusers"
fi

useradd -U -m -c "$fullname" -s /usr/bin/zsh -G "$groups" $name
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
fi

timedatectl set-ntp 1

# btrfs related
if which snapper > /dev/null 2>&1; then
    snapper --no-dbus -c root create-config /
    systemctl enable snapper-cleanup.timer
fi

systemctl enable haveged.service
systemctl enable sshd.service
if which auditctl > /dev/null 2>&1; then
    systemctl enable auditd.service
fi
if which aa-status > /dev/null 2>&1; then
    systemctl enable apparmor.service
fi
if which firewalld > /dev/null 2>&1; then
    systemctl enable firewalld.service
fi
if which NetworkManager > /dev/null 2>&1; then
    systemctl enable NetworkManager.service
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
if which sddm > /dev/null 2>&1; then
    systemctl enable sddm.service
fi
if which lightdm > /dev/null 2>&1; then
    systemctl enable lightdm.service
fi

# nvidia configuration with multiple gpu
if which nvidia-xconfig > /dev/null 2>&1; then
    if [[ $(lspci| grep -i '\(3D\|VGA\)' | wc -l) -gt 1 ]]; then
        busid=$(nvidia-xconfig --query-gpu-info | grep -i 'BusID' | sed -e 's/.*\(PCI\:.*\)/\1/g')
        cat > /etc/X11/xorg.conf.d/15-nvidia.conf <<-EOF
Section "Module"
    Load "modesetting"
EndSection

Section "Device"
    Identifier     "NVIDIA Graphics"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
    BusID          "$busid"

    Option         "ProbeAllGpus" "false"
    Option         "NoLogo" "True"
    Option         "UseEDID" "false"
    #Option         "RenderAccel" "True"
    #Option         "AddARGBGLXVisuals" "true"
    #Option         "AllowGLXWithComposite" "true"
    #Option         "TripleBuffer" "True"
    #Option         "DamageEvents" "True"
    #Option         "UseDisplayDevice" "none"
EndSection
EOF
        if which sddm > /dev/null 2>&1; then
            cat > /usr/share/sddm/scripts/Xsetup <<-EOF
xrandr --setprovideroutputsource modesetting NVIDIA-0
xrandr --auto
EOF
        fi
        if which lightdm > /dev/null 2>&1; then
            cat > /etc/lightdm/display_setup.sh <<-EOF
#!/bin/sh
xrandr --setprovideroutputsource modesetting NVIDIA-0
xrandr --auto
EOF
            chmod +x /etc/lightdm/display_setup.sh
            sed -e 's/.*display-setup-script.*/display-setup-script=\/etc\/lightdm\/display_setup.sh/g' \
                -i /etc/lightdm/lightdm.conf
        fi
    fi
fi

