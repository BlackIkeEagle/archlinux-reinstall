#!/usr/bin/env bash

set -e

echo "*** WARNING ****************************************************"
echo "* HAVE YOU PASSED IN THE PACKAGE FILES YOU WANT FOR INSTALL ?  *"
echo "* MAKE SURE YOUR USB DEVICE IS MOUNTED UNDER /media/usb        *"
echo "* OR AT LEAST MAKE SURE YOU COPY THE INFORMATION WRITTEN there *"
echo "*** WARNING ****************************************************"

echo -n "did you mount your usb drive under /media/usb? "
read -a dummy

[[ ! -d /media/usb ]] && mkdir -p /media/usb

echo -n "enter the block device's name: "
read -a blockdev

echo -n "efi booting or legacy (efi|legacy): "
read -a boottype

echo -n "full partitioning or leave efi alone (full|noefi|none): "
read -a partitioning

echo -n "main filesystem (btrfs|xfs): "
read -a filesystem

echo -n "nvme disk or regular (nvme|regular): "
read -a nvmedisk

if [[ "$nvmedisk" == "nvme" ]]; then
    partitionextra="p"
else
    partitionextra=""
fi

# create random string to append to the keyfile and hostname
randstring="$(date +%s | sha256sum | base64 | head -c 8)"

# bootloader package
bootloaderpackage="refind-efi"

# randomize data on the device

if [[ "$partitioning" == "full" ]]; then
    badblocks -c 10240 -s -w -t random -v /dev/$blockdev

    parted --script /dev/$blockdev \
        mklabel gpt \
        mkpart primary fat32 0% 200MiB \
        set 1 esp on \
        set 1 legacy_boot on \
        mkpart primary linux-swap 200MiB 4296MiB \
        mkpart primary 4296MiB 100%

    # EFI Partition
    mkfs.fat -F32 -n EFI /dev/${blockdev}${partitionextra}1
elif [[ "$partitioning" == "noefi" ]]; then
    parted --script /dev/$blockdev \
        mkpart primary linux-swap 200MiB 4296MiB \
        mkpart primary 4296MiB 100%

    badblocks -c 10240 -s -w -t random -v /dev/${blockdev}${partitionextra}2
    badblocks -c 10240 -s -w -t random -v /dev/${blockdev}${partitionextra}3
else
    badblocks -c 10240 -s -w -t random -v /dev/${blockdev}${partitionextra}2
    badblocks -c 10240 -s -w -t random -v /dev/${blockdev}${partitionextra}3
fi

if [[ "$boottype" == "efi" ]]; then
    # always make an kernel name folder in EFI
    mount /dev/${blockdev}${partitionextra}1 /mnt
    mkdir -p /mnt/EFI/linux-bede
    rm -rf /mnt/EFI/linux-bede/*
    umount /mnt
fi

# swap
mkswap /dev/${blockdev}${partitionextra}2
swapon /dev/${blockdev}${partitionextra}2

# encryption on "ROOT"
dd bs=512 count=8 if=/dev/urandom of=/media/usb/keyfile-$randstring
lukspassword="$(date +%s | sha256sum | base64 | head -c 32)"
echo "$lukspassword" > /media/usb/luks-password-$randstring.txt
echo "$lukspassword" | cryptsetup -y luksFormat /dev/${blockdev}${partitionextra}3
echo "$lukspassword" | cryptsetup -y luksAddKey /dev/${blockdev}${partitionextra}3 /media/usb/keyfile-$randstring
cryptsetup open /dev/${blockdev}${partitionextra}3 archlinux --key-file /media/usb/keyfile-$randstring

if [[ "$filesystem" == "btrfs" ]]; then
    # "ROOT"
    mkfs.btrfs -L ROOT /dev/mapper/archlinux
    mount /dev/mapper/archlinux /mnt
    mkdir -p /mnt/var
    mkdir -p /mnt/var/lib
    btrfs subvolume create /mnt/root
    btrfs subvolume create /mnt/home
    btrfs subvolume create /mnt/var/cache
    btrfs subvolume create /mnt/var/lib/docker
    btrfs subvolume list -p /mnt

    umount /mnt

    mount -o rw,noatime,nodiratime,ssd,discard,space_cache,compress=lzo,subvol=root /dev/mapper/archlinux /mnt
    mkdir -p /mnt/home
    mount -o rw,noatime,nodiratime,ssd,discard,space_cache,compress=lzo,subvol=home /dev/mapper/archlinux /mnt/home
    mkdir -p /mnt/var/cache
    mount -o rw,noatime,nodiratime,ssd,discard,space_cache,compress=lzo,subvol=var/cache /dev/mapper/archlinux /mnt/var/cache
    mkdir -p /mnt/var/lib/docker
    mount -o rw,noatime,nodiratime,ssd,discard,space_cache,compress=lzo,subvol=var/lib/docker /dev/mapper/archlinux /mnt/var/lib/docker
elif [[ "$filesystem" == "xfs" ]]; then
    mkfs.xfs -L ROOT /dev/mapper/archlinux
    mount -o rw,relatime,attr2,inode64,noquota /dev/mapper/archlinux /mnt
else
    echo "unsupported filesystem defined"
    exit 1
fi

if [[ "$boottype" == "efi" ]]; then
    bootloaderpackage="refind-efi"
    mkdir -p /mnt/mnt/efi
    mount /dev/${blockdev}${partitionextra}1 /mnt/mnt/efi
    mkdir -p /mnt/boot
    mount -o bind /mnt/mnt/efi/EFI/linux-bede /mnt/boot
else
    bootloaderpackage="syslinux"
    mkdir -p /mnt/boot
    mount /dev/${blockdev}${partitionextra}1 /mnt/boot
fi

basepackagelist=("base-packages.txt")
if [[ "$filesystem" == "btrfs" ]]; then
    basepackagelist+=("btrfs-packages.txt")
elif [[ "$filesystem" == "xfs" ]]; then
    basepackagelist+=("xfs-packages.txt")
fi

# install packages
if [[ ! -z $1 ]]; then
    pacstrap -C ./pacman.conf /mnt \
        $(cat ${basepackagelist[@]}) \
        $(cat "$@") \
        "$bootloaderpackage"
else
    pacstrap -C ./pacman.conf /mnt \
        $(cat ${basepackagelist[@]}) \
        "$bootloaderpackage"
fi
cp ./pacman.conf /mnt/etc/

# generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# set timezone
ln -sf /usr/share/zoneinfo/Europe/Brussels /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc

# generate locales for en_US
sed -e 's/#en_US/en_US/g' -e 's/#nl_BE/nl_BE/g' -i /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

# keyboard
mkdir -p /mnt/etc/X11/xorg.conf.d/
echo "KEYMAP=be-latin1" > /mnt/etc/vconsole.conf
cp ./00-keyboard.conf /mnt/etc/X11/xorg.conf.d/


# set hostname
echo "archlinux-$randstring" > /mnt/etc/hostname
echo "127.0.1.1 archlinux-$randstring" >> /mnt/etc/hosts

# update mkinitcpio
cp ./mkinitcpio.conf /mnt/etc/

# bootloader installation
if [[ "$boottype" == "efi" ]]; then
    arch-chroot /mnt refind-install
    cp refind_linux.conf /mnt/mnt/efi/EFI/linux-bede/
    bootloaderfile=/mnt/mnt/efi/EFI/linux-bede/refind_linux.conf
else
    arch-chroot /mnt syslinux-install_update -im
    cp syslinux.cfg /mnt/boot/syslinux/
    bootloaderfile=/mnt/boot/syslinux/syslinux.cfg
fi

# bootloader config
## encrypted device
eval $(blkid -o export /dev/${blockdev}${partitionextra}3)
sed -e "s#%%encuuid%%#$UUID#g" -i "$bootloaderfile"
## find usb with keyfile
usbdev=$(cat /etc/mtab| grep '/media/usb' | awk '{ print $1 }')
if [[ $? -eq 0 ]] && [[ "" != "$usbdev" ]]; then
    eval $(blkid -o export "$usbdev")
    sed -e "s#%%keydriveuuid%%#$UUID#g" \
        -e "s#%%keydrivetype%%#$TYPE#g" \
        -i "$bootloaderfile"
    sed -e "s#^\(MODULES=\".*\)\(\"\)#\1 vfat\2#" \
        -i /mnt/etc/mkinitcpio.conf
fi
## keyfile
sed -e "s#%%keyfile%%#keyfile-$randstring#g" -i "$bootloaderfile"

arch-chroot /mnt mkinitcpio -p linux-bede || true

# set the root password
arch-chroot /mnt passwd

# add post install first run script
cp -a post-install-first-run.sh /mnt/root/
