#!/usr/bin/env bash

set -e

echo "*** WARNING ****************************************************"
echo "* HAVE YOU PASSED IN THE PACKAGE FILES YOU WANT FOR INSTALL ?  *"
echo "*** WARNING ****************************************************"

echo "AVAILABLE BLOCK DEVICES"
lsblk

echo -n "enter the block device's name (sda,nvme1): "
read blockdev

echo -n "efi booting or legacy (efi|legacy): "
read boottype

echo -n "main filesystem (xfs|ext4|btrfs): "
read filesystem

echo -n "nvme disk or regular (nvme|regular): "
read nvmedisk

echo -n "check blocks (yes|no (default)): "
read checkblocks

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

if [[ "$checkblocks" == "yes" ]]; then
    badblocks -c 10240 -s -w -t random -v /dev/$blockdev
fi

if [[ "$boottype" == "efi" ]]; then
    if [[ "$filesystem" == "btrfs" ]]; then
        parted --script /dev/$blockdev \
            mklabel gpt \
            mkpart ESP fat32 0% 200MiB \
            set 1 esp on \
            set 1 legacy_boot on \
            mkpart primary 200MiB 4496MiB \
            mkpart primary 4496MiB 100%

        efipart=1
        swappart=2
        rootpart=3
    else
        parted --script /dev/$blockdev \
            mklabel gpt \
            mkpart ESP fat32 0% 200MiB \
            set 1 esp on \
            set 1 legacy_boot on \
            mkpart primary 200MiB 400MiB \
            mkpart primary 400MiB 4496MiB \
            mkpart primary 4496MiB 100%

        efipart=1
        bootpart=2
        swappart=3
        rootpart=4
    fi

    # EFI Partition
    mkfs.fat -F32 -n EFI /dev/${blockdev}${partitionextra}${efipart}
else
    if [[ "$filesystem" == "btrfs" ]]; then
        parted --script /dev/$blockdev \
            mklabel msdos \
            mkpart primary 0% 4096MiB \
            mkpart primary 4096MiB 100% \
            set 2 boot on \

        swappart=1
        rootpart=2
    else
        parted --script /dev/$blockdev \
            mklabel msdos \
            mkpart primary 0% 200MiB \
            set 1 boot on \
            mkpart primary 200MiB 4296MiB \
            mkpart primary 4296MiB 100%

        bootpart=1
        swappart=2
        rootpart=3
    fi

fi

if [[ ! -z $bootpart ]]; then
    mkfs.ext2 -L boot /dev/${blockdev}${partitionextra}${bootpart}
fi

basepackagelist=("server-base-packages.txt")
if [[ "$filesystem" == "btrfs" ]]; then
    basepackagelist+=("btrfs-packages.txt")

    # "ROOT"
    mkfs.btrfs -L ROOT /dev/${blockdev}${partitionextra}${rootpart}
    mount /dev/${blockdev}${partitionextra}${rootpart} /mnt
    mkdir -p /mnt/var
    mkdir -p /mnt/var/lib
    btrfs subvolume create /mnt/root
    btrfs subvolume create /mnt/home
    btrfs subvolume create /mnt/var/cache
    btrfs subvolume create /mnt/var/lib/docker
    btrfs subvolume list -p /mnt

    umount /mnt

    rootmountoptions="rw,noatime,nodiratime,ssd,space_cache,compress=lzo,subvol=root"

    mount -o $rootmountoptions /dev/${blockdev}${partitionextra}${rootpart} /mnt
    mkdir -p /mnt/home
    mount -o rw,noatime,nodiratime,ssd,space_cache,compress=lzo,subvol=home /dev/${blockdev}${partitionextra}${rootpart} /mnt/home
    mkdir -p /mnt/var/cache
    mount -o rw,noatime,nodiratime,ssd,space_cache,compress=lzo,subvol=var/cache /dev/${blockdev}${partitionextra}${rootpart} /mnt/var/cache
    mkdir -p /mnt/var/lib/docker
    mount -o rw,noatime,nodiratime,ssd,space_cache,compress=lzo,subvol=var/lib/docker /dev/${blockdev}${partitionextra}${rootpart} /mnt/var/lib/docker
elif [[ "$filesystem" == "xfs" ]]; then
    basepackagelist+=("xfs-packages.txt")

    mkfs.xfs -L ROOT /dev/${blockdev}${partitionextra}${rootpart}
    rootmountoptions="rw,noatime,attr2,inode64,noquota,discard"
    mount -o $rootmountoptions /dev/${blockdev}${partitionextra}${rootpart} /mnt
elif [[ "$filesystem" == "ext4" ]]; then
    basepackagelist+=("ext4-packages.txt")

    mkfs.ext4 -L ROOT /dev/${blockdev}${partitionextra}${rootpart}
    rootmountoptions="rw,noatime,data=ordered,discard"
    mount -o $rootmountoptions /dev/${blockdev}${partitionextra}${rootpart} /mnt
else
    echo "unsupported filesystem defined"
    exit 1
fi

bootloaderpackage=grub
if [[ "$boottype" == "efi" ]]; then
    bootloaderpackage="$bootloaderpackage efibootmgr"
    mkdir -p /mnt/boot
    if [[ ! -z $bootpart ]]; then
        mount /dev/${blockdev}${partitionextra}${bootpart} /mnt/boot
    fi
    mkdir -p /mnt/boot/efi
    mount /dev/${blockdev}${partitionextra}${efipart} /mnt/boot/efi
    mkdir -p /mnt/boot/efi/EFI/archlinux
else
    mkdir -p /mnt/boot
    if [[ ! -z $bootpart ]]; then
        mount /dev/${blockdev}${partitionextra}${bootpart} /mnt/boot
    fi
fi

# use our mirrorlist, not the one from the iso
cp ./etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist

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
ln -sf /usr/share/zoneinfo/UTC /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc

# generate locales for en_US
sed -e 's/#en_US/en_US/g' -e 's/#nl_BE/nl_BE/g' -i /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

# keyboard
echo "KEYMAP=be-latin1" > /mnt/etc/vconsole.conf

# set hostname
echo "archserver-$randstring" > /mnt/etc/hostname
echo "127.0.1.1 archserver-$randstring" >> /mnt/etc/hosts

# make sure firewalld uses iptables
if [[ -e /mnt/etc/firewalld/firewalld.conf ]]; then
    sed -e 's/^\(FirewallBackend=\).*/\1iptables/' \
        -i /mnt/etc/firewalld/firewalld.conf
fi

# just swap
mkswap -L swap /dev/${blockdev}${partitionextra}${swappart}

# bootloader installation
if [[ "$boottype" == "efi" ]]; then
    arch-chroot /mnt grub-install \
        --target=x86_64-efi \
        --bootloader-id=GRUB \
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
eval $(blkid -o export /dev/${blockdev}${partitionextra}${rootpart})
ROOTUUID=$UUID
grubcmd="root=/dev/disk/by-uuid/$ROOTUUID rootflags=$rootmountoptions"
grubcmd="${grubcmd//\//\\\/}"

## add grub GRUB_CMDLINE_LINUX
sed -e "s/^\(GRUB_CMDLINE_LINUX=\).*/\1\"$grubcmd\"/" \
    -i /mnt/etc/default/grub

if [[ "$boottype" == "efi" ]]; then
    arch-chroot /mnt grub-mkconfig -o /boot/efi/EFI/BOOT/grub/grub.cfg
else
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
fi

arch-chroot /mnt mkinitcpio -p linux-besrv || true

rm -f /mnt/etc/resolv.conf && \
    ln -sf /run/systemd/resolve/resolv.conf /mnt/etc/resolv.conf

# finish the installation
cp -a server-post-install.sh /mnt
arch-chroot /mnt /server-post-install.sh

rm /mnt/server-post-install.sh

