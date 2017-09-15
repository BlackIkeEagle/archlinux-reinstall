#!/usr/bin/env bash

set -e

echo "*** WARNING ****************************************************"
echo "* HAVE YOU PASSED IN THE PACKAGE FILES YOU WANT FOR INSTALL    *"
echo "* MAKE SURE YOUR USB DEVICE IS MOUNTED UNDER /media/usb        *"
echo "* OR AT LEAST MAKE SURE YOU COPY THE INFORMATION WRITTEN there *"
echo "*** WARNING ****************************************************"

echo -n "did you mount your usb drive under /media/usb? "
read -a dummy

[[ ! -d /media/usb ]] && mkdir -p /media/usb

echo -n "enter the block device's name: "
read -a blockdev

echo -n "full partitioning or leave efi alone (full|noefi|none): "
read -a partitioning

echo -n "nvme disk or regular (nvme|regular): "
read -a nvmedisk

if [[ "$nvmedisk" == "nvme" ]]; then
    partitionextra="p"
else
    partitionextra=""
fi

# create random string to append to the keyfile and hostname
randstring="$(date +%s | sha256sum | base64 | head -c 8)"

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
        mkpart primary linux-swap 501MiB 4597MiB \
        mkpart primary 4597MiB 100%

    badblocks -c 10240 -s -w -t random -v /dev/${blockdev}${partitionextra}2
    badblocks -c 10240 -s -w -t random -v /dev/${blockdev}${partitionextra}3
else
    badblocks -c 10240 -s -w -t random -v /dev/${blockdev}${partitionextra}2
    badblocks -c 10240 -s -w -t random -v /dev/${blockdev}${partitionextra}3
fi

# always make an arch folder in EFI
mount /dev/${blockdev}${partitionextra}1 /mnt
mkdir -p /mnt/EFI/archlinux
rm -rf /mnt/EFI/archlinux/*
umount /mnt

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

# sample cryptsetup boot params
####
# cryptdevice=/dev/disk/by-uuid/6cd5d037-e4e1-4e70-a4c4-d2496265ab36:archlinux:allow-discards cryptkey=/dev/disk/by-uuid/48eb8491-f0e3-4425-b837-94e7cb5ea0c6:ext2:id_rsa rw root=/dev/mapper/archlinux
####

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

mount -o subvol=root,noatime,nodiratime,discard /dev/mapper/archlinux /mnt
mkdir -p /mnt/home
mount -o subvol=home,noatime,nodiratime,discard /dev/mapper/archlinux /mnt/home
mkdir -p /mnt/var/cache
mount -o subvol=var/cache,noatime,nodiratime,discard /dev/mapper/archlinux /mnt/var/cache
mkdir -p /mnt/var/lib/docker
mount -o subvol=var/lib/docker,noatime,nodiratime,discard /dev/mapper/archlinux /mnt/var/lib/docker
mkdir -p /mnt/mnt/efi
mount /dev/${blockdev}${partitionextra}1 /mnt/mnt/efi
mkdir -p /mnt/boot
mount -o bind /mnt/mnt/efi/EFI/archlinux /mnt/boot

# install packages
pacstrap -C ./pacman.conf /mnt $(cat base-packages.txt) $(cat "$@")
cp ./pacman.conf /mnt/etc/

# generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# set timezone
ln -sf /usr/share/zoneinfo/Europe/Brussels /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc

# generate locales for en_US
sed -e 's/#en_US/en_US/g' -i /mnt/etc/locale.gen
arch-chroot /mnt locale-gen

# keyboard
echo "KEYMAP=be-latin1" > /mnt/etc/vconsole.conf
cp ./00-keyboard.conf /mnt/etc/X11/xorg.conf.d/


# set hostname
echo "archlinux-$randstring" > /mnt/etc/hostname
echo "127.0.1.1 archlinux-$randstring" >> /mnt/etc/hosts

# update mkinitcpio
cp ./mkinitcpio.conf /mnt/etc/
arch-chroot /mnt mkinitcpio -p linux-bede || true

# set default refind_linux.conf
cp ./refind_linux.conf /mnt/boot

# set the root password
arch-chroot /mnt passwd
