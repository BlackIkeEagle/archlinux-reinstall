#!/usr/bin/env bash

set -e

echo "*** WARNING ****************************************************"
echo "* HAVE YOU PASSED IN THE PACKAGE FILES YOU WANT FOR INSTALL ?  *"
echo "*** WARNING ****************************************************"

echo "AVAILABLE BLOCK DEVICES"
lsblk

echo -n "enter the block device's name (sda,nvme1): "
read -r blockdev

echo -n "efi booting or legacy (efi|legacy): "
read -r boottype

echo -n "main filesystem (xfs|ext4|btrfs): "
read -r filesystem

echo -n "nvme disk or regular (nvme|regular): "
read -r nvmedisk

echo -n "additional kernel commandline flags (default empty): "
read -r kernelcmdline

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

# force local update of archlinux-keyring
/usr/bin/archlinux-keyring-wkd-sync

basepackagelist=("server-base-packages.txt")

if [[ "$boottype" == "efi" ]]; then
    basepackagelist+=("efi-packages.txt")

    parted --script "/dev/$blockdev" \
        mklabel gpt \
        mkpart ESP fat32 0% 200MiB \
        set 1 esp on \
        set 1 legacy_boot on \
        mkpart primary 200MiB 4296MiB \
        mkpart primary 4296MiB 100%

    efipart=1

    # EFI Partition
    mkfs.fat -F32 -n EFI "/dev/${blockdev}${partitionextra}${efipart}"
else
    parted --script "/dev/$blockdev" \
        mklabel gpt \
        mkpart non-fs 0% 2MiB \
        set 1 bios_grub on \
        mkpart primary 2MiB 4098MiB \
        mkpart primary 4098MiB 100% \
        set 3 boot on
fi

swappart=2
rootpart=3

rootdev="/dev/${blockdev}${partitionextra}${rootpart}"

if [[ "$filesystem" == "btrfs" ]]; then
    basepackagelist+=("fs-btrfs-packages.txt")

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
    basepackagelist+=("fs-xfs-packages.txt")

    mkfs.xfs -L ROOT "$rootdev"
    rootmountoptions="rw,noatime,attr2,inode64,noquota,discard"
    mount -o $rootmountoptions "$rootdev" /mnt
elif [[ "$filesystem" == "ext4" ]]; then
    basepackagelist+=("fs-ext4-packages.txt")

    mkfs.ext4 -L ROOT "$rootdev"
    rootmountoptions="rw,noatime,data=ordered,discard"
    mount -o $rootmountoptions "$rootdev" /mnt
else
    echo "unsupported filesystem defined"
    exit 1
fi

bootloaderpackage=grub
if [[ "$boottype" == "efi" ]]; then
    mkdir -p /mnt/boot
    mkdir -p /mnt/boot/efi
    mount "/dev/${blockdev}${partitionextra}${efipart}" /mnt/boot/efi
    mkdir -p /mnt/boot/efi/EFI/BOOT
else
    mkdir -p /mnt/boot
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
cp -a ./etc-server/* /mnt/etc/
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
ln -sf /usr/share/zoneinfo/UTC /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc

# generate locales for en_US
sed -e 's/#en_US/en_US/g' -e 's/#nl_BE/nl_BE/g' -i /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
{
    echo "LANG=en_US.UTF-8"
    echo "LC_NUMERIC=nl_BE.UTF-8"
    echo "LC_TIME=nl_BE.UTF-8"
    echo "LC_COLLATE=en_US.UTF-8"
    echo "LC_MONETARY=nl_BE.UTF-8"
    echo "LC_NAME=nl_BE.UTF-8"
    echo "LC_ADDRESS=nl_BE.UTF-8"
    echo "LC_TELEPHONE=nl_BE.UTF-8"
    echo "LC_MEASUREMENT=nl_BE.UTF-8"
} > /mnt/etc/locale.conf

# keyboard
{
    echo "KEYMAP=be-latin1"
    echo "XKBLAYOUT=be"
    echo "XKBOPTIONS=terminate:ctrl_alt_bksp"
} > /mnt/etc/vconsole.conf

# set hostname
echo "archserver-$randstring" > /mnt/etc/hostname
{
    echo "127.0.0.1 localhost archserver-$randstring"
    echo "::1 localhost archserver-$randstring"
} >> /mnt/etc/hosts

# just swap
mkswap -L swap "/dev/${blockdev}${partitionextra}${swappart}"

{
    echo ""
    echo "/dev/${blockdev}${partitionextra}${swappart}  none  swap  defaults  0  0"
} >> /mnt/etc/fstab

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

grubcmd="root=/dev/disk/by-uuid/$ROOTUUID"

## root filesystem flags
grubcmd="$grubcmd rootflags=$rootmountoptions"
if [[ "$btrfsroroot" == "yes" ]]; then
    grubcmd="$grubcmd ro"
fi
grubcmd="${grubcmd//\//\\\/}"
grubcmd="$grubcmd lockdown=integrity"
if [[ -n "$kernelcmdline" ]]; then
    grubcmd="$grubcmd $kernelcmdline"
fi

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

arch-chroot /mnt dracut-rebuild || true

rm -f /mnt/etc/resolv.conf && \
    ln -sf /run/systemd/resolve/resolv.conf /mnt/etc/resolv.conf

# finish the installation
cp -a server-post-install.sh /mnt
arch-chroot /mnt /server-post-install.sh "$user" "$fullname" "$password"

rm /mnt/server-post-install.sh

