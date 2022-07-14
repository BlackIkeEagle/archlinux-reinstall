#!/usr/bin/env bash

set -e

echo "*** WARNING ****************************************************"
echo "* HAVE YOU PASSED IN THE PACKAGE FILES YOU WANT FOR INSTALL ?  *"
echo "*** WARNING ****************************************************"

[[ ! -d /media/usb ]] && mkdir -p /media/usb

echo "AVAILABLE BLOCK DEVICES"
lsblk

echo -n "Do you want to encrypt your harddisk (yes/no): "
read -r encrypt

if [[ "$encrypt" != "no" ]]; then
    encrypt="yes"
fi

if [[ "$encrypt" == "yes" ]]; then
    echo -n "enter the usb key device name (sda1,sdb1): "
    read -r usbkey

    mount "/dev/$usbkey" /media/usb
fi

echo -n "enter the block device's name (sda,nvme1): "
read -r blockdev

echo -n "efi booting or legacy (efi|legacy): "
read -r boottype

echo -n "main filesystem (xfs|ext4|btrfs): "
read -r filesystem

echo -n "nvme disk or regular (nvme|regular): "
read -r nvmedisk

echo -n "check blocks (yes|no (default)): "
read -r checkblocks

echo -n "give your default administrator username: "
read -r user

echo -n "give your full name: "
read -r fullname

echo -n "set your password: "
read -r password


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

if [[ "$filesystem" == "btrfs" ]]; then
    echo -n "btrfs read-only root? (yes|no (default)): "
    read -r btrfsroroot
fi
if [[ "$btrfsroroot" == "yes" ]]; then
    btrfsroroot=yes
else
    btrfsroroot=no
fi

if [[ "$nvmedisk" == "nvme" ]]; then
    partitionextra="p"
else
    partitionextra=""
fi

# create random string to append to the keyfile and hostname
randstring="$(date +%s | sha256sum | base64 | head -c 8)"

if [[ "$checkblocks" == "yes" ]]; then
    badblocks -c 10240 -s -w -t random -v "/dev/$blockdev"
fi

if [[ "$boottype" == "efi" ]]; then
    parted --script "/dev/$blockdev" \
        mklabel gpt \
        mkpart ESP fat32 0% 200MiB \
        set 1 esp on \
        set 1 legacy_boot on \
        mkpart primary 200MiB 600MiB \
        mkpart primary 600MiB 4696MiB \
        mkpart primary 4696MiB 100%

    efipart=1

    # EFI Partition
    mkfs.fat -F32 -n EFI "/dev/${blockdev}${partitionextra}${efipart}"
else
    parted --script "/dev/$blockdev" \
        mklabel gpt \
        mkpart non-fs 0% 2MiB \
        set 1 bios_grub on \
        mkpart primary 2MiB 400MiB \
        set 2 boot on \
        mkpart primary 400MiB 4496MiB \
        mkpart primary 4496MiB 100%
fi

bootpart=2
swappart=3
rootpart=4

mkfs.ext2 -L boot "/dev/${blockdev}${partitionextra}${bootpart}"

if [[ "$encrypt" == "yes" ]]; then
    # encryption on "ROOT"
    dd bs=512 count=8 if=/dev/urandom of="/media/usb/keyfile-$randstring"
    lukspassword="$(date +%s | sha256sum | base64 | head -c 32)"
    echo "$lukspassword" > "/media/usb/luks-password-$randstring.txt"
    echo "$lukspassword" | cryptsetup -y luksFormat "/dev/${blockdev}${partitionextra}${rootpart}"
    echo "$lukspassword" | cryptsetup -y luksAddKey "/dev/${blockdev}${partitionextra}${rootpart}" "/media/usb/keyfile-$randstring"
    cryptsetup open "/dev/${blockdev}${partitionextra}${rootpart}" archlinux --key-file "/media/usb/keyfile-$randstring"

    rootdev="/dev/mapper/archlinux"
else
    rootdev="/dev/${blockdev}${partitionextra}${rootpart}"
fi

basepackagelist=("base-packages.txt")
if [[ "$filesystem" == "btrfs" ]]; then
    basepackagelist+=("btrfs-packages.txt")

    pacman -Sy --noconfirm snapper

    # "ROOT"
    mkfs.btrfs -L ROOT "$rootdev"
    mount "$rootdev" /mnt
    btrfs subvolume create /mnt/root
    btrfs subvolume create /mnt/home
    btrfs subvolume create /mnt/srv
    mkdir -p /mnt/usr
    btrfs subvolume create /mnt/usr/local
    btrfs subvolume create /mnt/var
    # disable CoW on /var
    chattr +C /mnt/var
    umount /mnt

    # write first snapshot info manually
    mount -o subvol=root "$rootdev" /mnt
    snapper --no-dbus -c root create-config /mnt
    snapper create \
        --read-write \
        --cleanup-algorithm number \
        --description "initial install"
    umount /mnt


    mount "$rootdev" /mnt
    btrfs subvolume list -p /mnt

    # root subvol id
    rootsubvol=$(btrfs subvolume list -p /mnt | grep 'root/.snapshots/1/snapshot' | sed 's/ID \([0-9]\+\).*/\1/g')
    btrfs subvolume set-default "$rootsubvol" /mnt

    umount /mnt

    rootmountoptions="rw,noatime,nodiratime,discard=async,compress=zstd"

    mount -o $rootmountoptions "$rootdev" /mnt
    mkdir -p /mnt/.snapshots
    mount -o $rootmountoptions,subvol=root/.snapshots "$rootdev" /mnt/.snapshots
    mkdir -p /mnt/home
    mount -o $rootmountoptions,subvol=home "$rootdev" /mnt/home
    mkdir -p /mnt/srv
    mount -o $rootmountoptions,subvol=srv "$rootdev" /mnt/srv
    mkdir -p /mnt/usr/local
    mount -o $rootmountoptions,subvol=usr/local "$rootdev" /mnt/usr/local
    mkdir -p /mnt/var
    mount -o $rootmountoptions,subvol=var "$rootdev" /mnt/var
elif [[ "$filesystem" == "xfs" ]]; then
    basepackagelist+=("xfs-packages.txt")

    mkfs.xfs -L ROOT "$rootdev"
    rootmountoptions="rw,noatime,attr2,inode64,noquota,discard"
    mount -o $rootmountoptions "$rootdev" /mnt
elif [[ "$filesystem" == "ext4" ]]; then
    basepackagelist+=("ext4-packages.txt")

    mkfs.ext4 -L ROOT "$rootdev"
    rootmountoptions="rw,noatime,data=ordered,discard"
    mount -o $rootmountoptions "$rootdev" /mnt
else
    echo "unsupported filesystem defined"
    exit 1
fi

bootloaderpackage=grub
if [[ "$boottype" == "efi" ]]; then
    bootloaderpackage="$bootloaderpackage efibootmgr"
    mkdir -p /mnt/boot
    mount "/dev/${blockdev}${partitionextra}${bootpart}" /mnt/boot
    mkdir -p /mnt/boot/efi
    mount "/dev/${blockdev}${partitionextra}${efipart}" /mnt/boot/efi
    mkdir -p /mnt/boot/efi/EFI/archlinux
else
    mkdir -p /mnt/boot
    mount "/dev/${blockdev}${partitionextra}${bootpart}" /mnt/boot
fi

# use our mirrorlist, not the one from the iso
cp ./etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist

# install packages
# shellcheck disable=SC2046
pacstrap -C ./etc/pacman.conf /mnt \
    $(cat "${basepackagelist[@]}") \
    $bootloaderpackage

# copy all etc extras
cp -a ./etc/ /mnt/
cp -a ./etc-desktop/* /mnt/etc/
chown root: -R /mnt/etc

if [[ "$filesystem" == "btrfs" ]]; then
    cp -a /etc/conf.d/snapper \
        /mnt/etc/conf.d/snapper
    cp -a /etc/snapper/configs/root \
        /mnt/etc/snapper/configs/root
    sed -e 's/\(SUBVOLUME=\).*/\1"\/"/' \
        -e 's/\(^NUMBER_LIMIT=\).*/\1"20"/' \
        -e 's/\(^NUMBER_LIMIT_IMPORTANT=\).*/\1"5"/' \
        -e 's/\(^TIMELINE_CREATE=\).*/\1"no"/' \
        -i /mnt/etc/snapper/configs/root
    # make sure the pacman db is on the root subvolume if btrfs is in use
    sed -e 's/#\(DBPath.*=\).*/\1 \/opt\/pacman/' -i /mnt/etc/pacman.conf
    mv /mnt/var/lib/pacman /mnt/opt/pacman
fi

# install the remaining packages (avoid gpg key issues with extra packages)
# shellcheck disable=SC2046
if [[ -n $1 ]]; then
    arch-chroot /mnt \
        pacman -Syu --noconfirm \
        $(cat "$@")
fi

# generate fstab
genfstab -U /mnt >> /mnt/etc/fstab
sed -e '/\s\+\/\s\+/d' -i /mnt/etc/fstab

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
echo "127.0.0.1 localhost archlinux-$randstring" >> /mnt/etc/hosts
echo "::1 localhost archlinux-$randstring" >> /mnt/etc/hosts

if [[ "$encrypt" == "yes" ]]; then
    # encrypted swap
    mkfs.ext2 -L cryptswap "/dev/${blockdev}${partitionextra}${swappart}" 1M

    printf "\nswap  LABEL=cryptswap  /dev/urandom  swap,offset=2048,cipher=aes-xts-plain64,size=512" \
        >> /mnt/etc/crypttab

    printf "\n/dev/mapper/swap  none  swap  defaults  0  0" \
        >> /mnt/etc/fstab

else
    mkswap -L swap "/dev/${blockdev}${partitionextra}${swappart}"

    (
        echo ""
        echo "/dev/${blockdev}${partitionextra}${swappart}  none  swap  defaults  0  0"
    ) >> /mnt/etc/fstab
fi

# bootloader installation
if [[ "$boottype" == "efi" ]]; then
    arch-chroot /mnt grub-install \
        --target=x86_64-efi \
        --bootloader-id=GRUB \
        --efi-directory=/boot/efi \
        --boot-directory=/boot/efi/EFI/BOOT \
        --removable \
        --recheck
    mkdir -p /mnt/boot/efi/EFI/BOOT/grub
else
    arch-chroot /mnt grub-install \
        --target=i386-pc \
        --boot-directory=/boot \
        --recheck \
        "/dev/${blockdev}${partitionextra}"
fi

# bootloader extra cmd
eval "$(blkid -o export "/dev/${blockdev}${partitionextra}${rootpart}")"
ROOTUUID=$UUID

if [[ "$encrypt" == "yes" ]]; then
    grubcmd="rd.luks.name=$ROOTUUID=archlinux rd.luks.options=allow-discards"
    ## find usb with keyfile
    usbdev=$(grep '/media/usb' /etc/mtab | awk '{ print $1 }')
    # shellcheck disable=SC2181
    if [[ $? -eq 0 ]] && [[ "" != "$usbdev" ]]; then
        eval "$(blkid -o export "$usbdev")"
        grubcmd="$grubcmd rd.luks.key=$ROOTUUID=/keyfile-$randstring:UUID=$UUID"
        if [[ "ext2" == "$TYPE" ]] || [[ "ext3" == "$TYPE" ]]; then
            TYPE="ext4"
        fi
        sed -e "s/^\(MODULES=(.*\)\()\)/\1 $TYPE\2/" \
            -i /mnt/etc/mkinitcpio.conf
    fi
else
    grubcmd="root=/dev/disk/by-uuid/$ROOTUUID"
fi

## root filesystem flags
grubcmd="$grubcmd rootflags=$rootmountoptions"
if [[ "$btrfsroroot" == "yes" ]]; then
    grubcmd="$grubcmd ro"
fi
grubcmd="${grubcmd//\//\\\/}"
grubcmd="$grubcmd mem_sleep_default=deep"

## add grub GRUB_CMDLINE_LINUX
sed -e "s/^\(GRUB_CMDLINE_LINUX=\).*/\1\"$grubcmd\"/" \
    -e 's/^\(GRUB_CMDLINE_LINUX_DEFAULT=\).*/\1"loglevel=3"/' \
    -e 's/^\(GRUB_TERMINAL_INPUT\)/#\1/' \
    -i /mnt/etc/default/grub

if [[ "$boottype" == "efi" ]]; then
    (
        cd /mnt/boot
        ln -s efi/EFI/BOOT/grub .
    )
    arch-chroot /mnt grub-mkconfig -o /boot/efi/EFI/BOOT/grub/grub.cfg
else
    sed -e 's/^\(GRUB_GFXPAYLOAD_LINUX=\)/\1text/' \
        -i /mnt/etc/default/grub
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
fi

arch-chroot /mnt mkinitcpio -p linux-bede || true

# finish the installation
cp -a post-install-desktop.sh /mnt
arch-chroot /mnt /post-install-desktop.sh "$user" "$fullname" "$password"

rm /mnt/post-install-desktop.sh

