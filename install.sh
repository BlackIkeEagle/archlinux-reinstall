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

echo -n "enter the block device's name (sda,nvme1): "
read -a blockdev

echo -n "efi booting or legacy (efi|legacy): "
read -a boottype

echo -n "main filesystem (xfs|ext4|btrfs): "
read -a filesystem

echo -n "nvme disk or regular (nvme|regular): "
read -a nvmedisk

echo -n "check blocks (yes|no (default)): "
read -a checkblocks

if [[ "$blockdev" == "" ]]; then
    echo "no blockdev given"
    exit 1
fi
if [[ "$boottype" == "" ]]; then
    echo "no boottype given"
    exit 2
fi
if [[ "$filesystem" == "" ]]; then
    echo "no filesystem given"
    exit 4
fi
if [[ "$nvmedisk" == "" ]]; then
    echo "no nvmedisk given"
    exit 5
fi
if [[ "$checkblocks" == "" ]]; then
    checkblocks="no"
fi

if [[ "$nvmedisk" == "nvme" ]]; then
    partitionextra="p"
else
    partitionextra=""
fi

# create random string to append to the keyfile and hostname
randstring="$(date +%s | sha256sum | base64 | head -c 8)"

# bootloader package
bootloaderpackage="refind-efi"

if [[ "$boottype" == "efi" ]]; then
    if [[ "$checkblocks" == "yes" ]]; then
        badblocks -c 10240 -s -w -t random -v /dev/$blockdev
    fi

    parted --script /dev/$blockdev \
        mklabel gpt \
        mkpart primary fat32 0% 200MiB \
        set 1 esp on \
        set 1 legacy_boot on \
        mkpart primary 200MiB 400MiB \
        mkpart primary 400MiB 4496MiB \
        mkpart primary 4496MiB 100%

    efipart=1
    bootpart=2
    swappart=3
    rootpart=4

    # EFI Partition
    mkfs.fat -F32 -n EFI /dev/${blockdev}${partitionextra}${efipart}
    mkfs.ext2 -L boot /dev/${blockdev}${partitionextra}${bootpart}
else
    if [[ "$checkblocks" == "yes" ]]; then
        badblocks -c 10240 -s -w -t random -v /dev/$blockdev
    fi

    parted --script /dev/$blockdev \
        mklabel msdos \
        mkpart primary 0% 200MiB \
        set 1 boot on \
        mkpart primary 200MiB 4296MiB \
        mkpart primary 4296MiB 100%

    bootpart=1
    swappart=2
    rootpart=3

    mkfs.ext2 -L boot /dev/${blockdev}${partitionextra}${bootpart}
fi

# encryption on "ROOT"
dd bs=512 count=8 if=/dev/urandom of=/media/usb/keyfile-$randstring
lukspassword="$(date +%s | sha256sum | base64 | head -c 32)"
echo "$lukspassword" > /media/usb/luks-password-$randstring.txt
echo "$lukspassword" | cryptsetup -y luksFormat /dev/${blockdev}${partitionextra}${rootpart}
echo "$lukspassword" | cryptsetup -y luksAddKey /dev/${blockdev}${partitionextra}${rootpart} /media/usb/keyfile-$randstring
cryptsetup open /dev/${blockdev}${partitionextra}${rootpart} archlinux --key-file /media/usb/keyfile-$randstring

basepackagelist=("base-packages.txt")
if [[ "$filesystem" == "btrfs" ]]; then
    basepackagelist+=("btrfs-packages.txt")

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

    rootmountoptions="rw,noatime,nodiratime,ssd,space_cache,compress=lzo,subvol=root"

    mount -o $rootmountoptions /dev/mapper/archlinux /mnt
    mkdir -p /mnt/home
    mount -o rw,noatime,nodiratime,ssd,space_cache,compress=lzo,subvol=home /dev/mapper/archlinux /mnt/home
    mkdir -p /mnt/var/cache
    mount -o rw,noatime,nodiratime,ssd,space_cache,compress=lzo,subvol=var/cache /dev/mapper/archlinux /mnt/var/cache
    mkdir -p /mnt/var/lib/docker
    mount -o rw,noatime,nodiratime,ssd,space_cache,compress=lzo,subvol=var/lib/docker /dev/mapper/archlinux /mnt/var/lib/docker
elif [[ "$filesystem" == "xfs" ]]; then
    basepackagelist+=("xfs-packages.txt")

    mkfs.xfs -L ROOT /dev/mapper/archlinux
    rootmountoptions="rw,noatime,attr2,inode64,noquota,discard"
    mount -o $rootmountoptions /dev/mapper/archlinux /mnt
elif [[ "$filesystem" == "ext4" ]]; then
    basepackagelist+=("ext4-packages.txt")

    mkfs.ext4 -L ROOT /dev/mapper/archlinux
    rootmountoptions="rw,noatime,data=ordered,discard"
    mount -o $rootmountoptions /dev/mapper/archlinux /mnt
else
    echo "unsupported filesystem defined"
    exit 1
fi

bootloaderpackage=grub
if [[ "$boottype" == "efi" ]]; then
    bootloaderpackage="$bootloaderpackage efibootmgr"
    mkdir -p /mnt/boot
    mount /dev/${blockdev}${partitionextra}${bootpart} /mnt/boot
    mkdir -p /mnt/boot/efi
    mount /dev/${blockdev}${partitionextra}${efipart} /mnt/boot/efi
    mkdir -p /mnt/boot/efi/EFI/archlinux
else
    mkdir -p /mnt/boot
    mount /dev/${blockdev}${partitionextra}${bootpart} /mnt/boot
fi

# install packages
if [[ ! -z $1 ]]; then
    pacstrap -C ./etc/pacman.conf /mnt \
        $(cat ${basepackagelist[@]}) \
        $(cat "$@") \
        $bootloaderpackage
else
    pacstrap -C ./etc/pacman.conf /mnt \
        $(cat ${basepackagelist[@]}) \
        $bootloaderpackage
fi

# copy all etc extras
cp -a ./etc/ /mnt/

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
echo "KEYMAP=be-latin1" > /mnt/etc/vconsole.conf

# set hostname
echo "archlinux-$randstring" > /mnt/etc/hostname
echo "127.0.1.1 archlinux-$randstring" >> /mnt/etc/hosts

# make sure firewalld uses iptables
if [[ -e /mnt/etc/firewalld/firewalld.conf ]]; then
    sed -e 's/^\(FirewallBackend=\).*/\1iptables/' \
        -i /mnt/etc/firewalld/firewalld.conf
fi

# encrypted swap
mkfs.ext2 -L cryptswap /dev/${blockdev}${partitionextra}${swappart} 1M

printf "\nswap  LABEL=cryptswap  /dev/urandom  swap,offset=2048,cipher=aes-xts-plain64,size=512" \
    >> /mnt/etc/crypttab

printf "\n/dev/mapper/swap  none  swap  defaults  0  0" \
    >> /mnt/etc/fstab

# bootloader installation
if [[ "$boottype" == "efi" ]]; then
    arch-chroot /mnt grub-install \
        --target=x86_64-efi \
        --boot-directory=/boot \
        --efi-directory=/boot/efi \
        --bootloader=archlinux \
        --boot-directory=/boot/efi/EFI/BOOT \
        --removable \
        --recheck
    mkdir -p /mnt/boot/efi/EFI/BOOT/grub
else
    arch-chroot /mnt grub-install \
        --target=i386-pc \
        --boot-directory=/boot \
        --recheck \
        /dev/${blockdev}${partitionextra}
fi

# bootloader extra cmd
## encrypted device
eval $(blkid -o export /dev/${blockdev}${partitionextra}${rootpart})
ROOTUUID=$UUID
grubcmd="rd.luks.name=$ROOTUUID=archlinux rd.luks.options=allow-discards"
## find usb with keyfile
usbdev=$(cat /etc/mtab| grep '/media/usb' | awk '{ print $1 }')
if [[ $? -eq 0 ]] && [[ "" != "$usbdev" ]]; then
    eval $(blkid -o export "$usbdev")
    grubcmd="$grubcmd rd.luks.key=$ROOTUUID=/keyfile-$randstring:UUID=$UUID"
    if [[ "ext2" == $TYPE ]] || [[ "ext3" == $TYPE ]]; then
        TYPE="ext4"
    fi
    sed -e "s/^\(MODULES=(.*\)\()\)/\1 $TYPE\2/" \
        -i /mnt/etc/mkinitcpio.conf
fi
## root filesystem flags
grubcmd="$grubcmd rootflags=$rootmountoptions"
grubcmd="${grubcmd//\//\\\/}"

## add grub GRUB_CMDLINE_LINUX
sed -e "s/^\(GRUB_CMDLINE_LINUX=\).*/\1\"$grubcmd\"/" \
    -i /mnt/etc/default/grub

if [[ "$boottype" == "efi" ]]; then
    arch-chroot /mnt grub-mkconfig -o /boot/efi/EFI/BOOT/grub/grub.cfg
else
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
fi

arch-chroot /mnt mkinitcpio -p linux-bede || true

# set the root password
arch-chroot /mnt passwd

# add post install first run script
cp -a post-install-first-run.sh /mnt/root/
