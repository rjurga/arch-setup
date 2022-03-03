#!/bin/bash

set -eux

SETUP_DISK=sda
SETUP_MIRROR='http://mirrors.kernel.org/archlinux/$repo/os/$arch'
SETUP_SWAP_GIB=16

SETUP_DIR=$(dirname -- "${0}")


# Update the system clock

timedatectl set-local-rtc 0
timedatectl set-ntp 1


# Partition the disk

parted \
    --script \
    --align optimal \
    /dev/"${SETUP_DISK}" \
    mklabel gpt \
    mkpart "ESP" fat32 0% 1GiB \
    mkpart "cryptroot" btrfs 1GiB 100% \
    set 1 esp on \
    align-check optimal 1 \
    align-check optimal 2


# Format EFI system partition

mkfs.fat -n ESP -F 32 /dev/"${SETUP_DISK}1"


# Create and format encrypted root partition

cryptsetup \
    --batch-mode \
    --type luks \
    --cipher aes-xts-plain64 \
    --key-size 256 \
    --hash sha256 \
    --use-urandom \
    --verify-passphrase \
    luksFormat /dev/"${SETUP_DISK}2"
cryptsetup --allow-discards open --type luks /dev/"${SETUP_DISK}2" root
mkfs.btrfs -f -L root /dev/mapper/root

mkdir -p /tmp/root
mount -o defaults,noatime,compress=zstd /dev/mapper/root /tmp/root
btrfs subvolume create /tmp/root/@
btrfs subvolume create /tmp/root/@home
btrfs subvolume create /tmp/root/@pkg
btrfs subvolume create /tmp/root/@log
btrfs subvolume create /tmp/root/@swap


# Mount filesystems

mount -o defaults,noatime,compress=zstd,subvol=@     /dev/mapper/root /mnt
mkdir -p /mnt/{home,boot,var/log,var/cache/pacman/pkg,swap}
mount -o defaults,noatime,compress=zstd,subvol=@home /dev/mapper/root /mnt/home
mount -o defaults,noatime,compress=zstd,subvol=@pkg  /dev/mapper/root /mnt/var/cache/pacman/pkg
mount -o defaults,noatime,compress=zstd,subvol=@log  /dev/mapper/root /mnt/var/log
mount -o defaults,noatime,compress=no,subvol=@swap   /dev/mapper/root /mnt/swap
mount -o defaults,noatime /dev/"${SETUP_DISK}1" /mnt/boot


# Swap file

truncate -s 0 /mnt/swap/swapfile
chattr +C /mnt/swap/swapfile
btrfs property set /mnt/swap/swapfile compression no

dd if=/dev/zero of=/mnt/swap/swapfile bs=1MiB count=${SETUP_SWAP_GIB}KiB status=progress
chmod 0600 /mnt/swap/swapfile
mkswap /mnt/swap/swapfile


# Select the mirrors

echo "Server = ${SETUP_MIRROR}" > /etc/pacman.d/mirrorlist


# Install essential packages

pacstrap /mnt base base-devel linux linux-firmware btrfs-progs


# Create /etc/fstab

cat > /mnt/etc/fstab << EOF
# <device>       <dir>                 <type> <options>                                   <dump> <pass>
PARTLABEL=ESP    /boot                 vfat   defaults                                    0      2
/dev/mapper/root /root/btrfs-top-lvl   btrfs  defaults,noatime,compress=zstd,noauto       0      0
/dev/mapper/root /                     btrfs  defaults,noatime,compress=zstd,subvol=@     0      0
/dev/mapper/root /home                 btrfs  defaults,noatime,compress=zstd,subvol=@home 0      0
/dev/mapper/root /var/log              btrfs  defaults,noatime,compress=zstd,subvol=@log  0      0
/dev/mapper/root /var/cache/pacman/pkg btrfs  defaults,noatime,compress=zstd,subvol=@pkg  0      0
/dev/mapper/root /swap                 btrfs  defaults,noatime,compress=no,subvol=@swap   0      0
/swap/swapfile   none                  swap   defaults                                    0      0
EOF


# Create mountpoint for btrfs top-level and snapshots

mkdir -p /mnt/root/btrfs-top-lvl


# Continue in chroot

cp "${SETUP_DIR}"/setup-chroot.sh /mnt/root/setup-chroot.sh
arch-chroot /mnt /root/setup-chroot.sh
rm /mnt/root/setup-chroot.sh


# Setup systemd-resolved DNS resolver (cannot be done in chroot since the file is bind-mounted from the outside system)

ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf


# Unmount chroot

umount -R /mnt


# Snapshot subvolume @

btrfs subvolume snapshot -r /tmp/root/@ /tmp/root/@_snapshot_"$(date +%Y-%m-%d)"


# Close the LUKS container

umount -R /tmp/root
cryptsetup close root

