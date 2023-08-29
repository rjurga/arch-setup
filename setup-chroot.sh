#!/bin/bash

set -eux

SETUP_TIMEZONE=Europe/Paris
SETUP_LOCALE=en_US
SETUP_KEYMAP=us
SETUP_HOSTNAME=arch
SETUP_CPU_MANUFACTURER=amd
SETUP_GPU_MANUFACTURER=amd
SETUP_USER=rjurga
SETUP_EMAIL="radoslaw.jurga@gmail.com"
SETUP_DOTFILES_BRANCH=master


# Timezone

ln -sf /usr/share/zoneinfo/"${SETUP_TIMEZONE}" /etc/localtime
hwclock --systohc


# Localization

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
if [[ ! "${SETUP_LOCALE}" = en_US ]]; then
    echo "${SETUP_LOCALE}.UTF-8 UTF-8" >> /etc/locale.gen
fi
locale-gen

echo "LANG=${SETUP_LOCALE}.UTF-8" > /etc/locale.conf

if [[ ! "${SETUP_KEYMAP}" = us ]]; then
    echo "KEYMAP=${SETUP_KEYMAP}" > /etc/vconsole.conf
fi


# Pacman configuration

sed -i \
    -e "s/^#\(Color\)$/\1/" \
    -e "s/^#\(VerbosePkgLists\)$/\1/" \
    /etc/pacman.conf

pacman -S --noconfirm pacman-contrib

mkdir -p /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/pacman-cache-cleanup.hook << EOF
[Trigger]
Type = Package
Operation = Remove
Operation = Install
Operation = Upgrade
Target = *

[Action]
Description = Removing old cached packages
When = PostTransaction
Exec = /usr/bin/paccache -r
EOF


# Network configuration

echo "${SETUP_HOSTNAME}" > /etc/hostname

cat > /etc/hosts << EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${SETUP_HOSTNAME}
EOF

## NetworkManager
pacman -S --noconfirm networkmanager

mkdir -p /etc/systemd/system/{multi-user,network-online}.target.wants

ln -s /usr/lib/systemd/system/NetworkManager.service             /etc/systemd/system/multi-user.target.wants/NetworkManager.service
ln -s /usr/lib/systemd/system/NetworkManager-dispatcher.service  /etc/systemd/system/dbus-org.freedesktop.nm-dispatcher.service
ln -s /usr/lib/systemd/system/NetworkManager-wait-online.service /etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service

mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/dns.conf << EOF
[main]
dns=systemd-resolved
EOF

## systemd-resolved
ln -s /usr/lib/systemd/system/systemd-resolved.service /etc/systemd/system/multi-user.target.wants/systemd-resolved.service
ln -s /usr/lib/systemd/system/systemd-resolved.service /etc/systemd/system/dbus-org.freedesktop.resolve1.service
# Symlink to resolv.conf is created from outside the chroot

sed -i "s/^#\(MulticastDNS=\).*$/\1no/" /etc/systemd/resolved.conf

## Avahi
pacman -S --noconfirm avahi nss-mdns

mkdir -p /etc/systemd/system/sockets.target.wants

ln -s /usr/lib/systemd/system/avahi-daemon.service /etc/systemd/system/multi-user.target.wants/avahi-daemon.service
ln -s /usr/lib/systemd/system/avahi-daemon.socket  /etc/systemd/system/sockets.target.wants/avahi-daemon.socket
ln -s /usr/lib/systemd/system/avahi-daemon.service /etc/systemd/system/dbus-org.freedesktop.Avahi.service

sed -i "s/^\(hosts:.*\) resolve/\1 mdns_minimal [NOTFOUND=return] resolve/" /etc/nsswitch.conf


# Initramfs

sed -i \
    -e "s/^\(BINARIES=\).*$/\1(btrfs)/" \
    -e "s/^\(HOOKS=\).*$/\1(base udev autodetect modconf block keyboard keymap encrypt filesystems fsck)/" \
    /etc/mkinitcpio.conf

rm /boot/initramfs-linux-fallback.img
sed -i "s/^\(PRESETS=\).*$/\1('default')/" /etc/mkinitcpio.d/linux.preset

mkinitcpio -p linux


# Microcode

pacman -S --noconfirm "${SETUP_CPU_MANUFACTURER}"-ucode


# Boot loader

bootctl install

cat > /etc/pacman.d/hooks/100-systemd-boot.hook << EOF
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Gracefully upgrading systemd-boot...
When = PostTransaction
Exec = /usr/bin/systemctl restart systemd-boot-update.service
EOF

cat > /boot/loader/loader.conf << EOF
default arch.conf
timeout 0
EOF

cat > /boot/loader/entries/arch.conf << EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /${SETUP_CPU_MANUFACTURER}-ucode.img
initrd  /initramfs-linux.img
options rw quiet loglevel=3 nowatchdog cryptdevice=PARTLABEL=cryptroot:root:allow-discards root=LABEL=root rootflags=subvol=@
EOF


# Swappinness

echo "vm.swappiness=10" > /etc/sysctl.d/99-swappiness.conf



# Periodic TRIM

mkdir -p /etc/systemd/system/timers.target.wants
ln -s /usr/lib/systemd/system/fstrim.timer /etc/systemd/system/timers.target.wants/fstrim.timer


# Clock synchronization

mkdir -p /etc/systemd/system/sysinit.target.wants
ln -s /usr/lib/systemd/system/systemd-timesyncd.service /etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service
ln -s /usr/lib/systemd/system/systemd-timesyncd.service /etc/systemd/system/dbus-org.freedesktop.timesync1.service


# Create user

useradd -m -G wheel -s /bin/bash "${SETUP_USER}"
passwd "${SETUP_USER}"


# Create user directories

pacman -S --noconfirm xdg-user-dirs
sudo -u ${SETUP_USER} mkdir -p /home/${SETUP_USER}/Projects


# Sudo

echo "%wheel    ALL = (ALL) ALL" > /etc/sudoers.d/wheel
echo "Defaults env_keep += \"DIFFPROG\"" > /etc/sudoers.d/env_keep


# Disable root login

passwd --lock root


# Automatic login to virtual console

mkdir -p "/etc/systemd/system/getty@tty1.service.d"
cat > "/etc/systemd/system/getty@tty1.service.d/autologin.conf" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin ${SETUP_USER} - \$TERM
Type=simple
EOF


# Python

pacman -S --noconfirm \
    python


# Fonts

pacman -S --noconfirm \
    fontconfig \
    noto-fonts \
    noto-fonts-cjk \
    noto-fonts-emoji \
    ttf-hack

ln -s /usr/share/fontconfig/conf.avail/10-sub-pixel-rgb.conf     /etc/fonts/conf.d/10-sub-pixel-rgb.conf


# Command-line utilities

pacman -S --noconfirm \
    alacritty \
    bash-completion \
    bat \
    fd \
    gdb \
    gdu \
    git \
    htop \
    neovim \
    openssh \
    p7zip \
    ripgrep \
    rsync \
    tree \
    usbutils \
    unrar \
    unzip \
    wl-clipboard


# Documentation

pacman -S --noconfirm \
    man-db \
    man-pages \
    tealdeer

sudo -u ${SETUP_USER} tldr --update


# Video drivers

if [ "${SETUP_GPU_MANUFACTURER}" = intel ]; then
    pacman -S --noconfirm \
        mesa \
        mesa-utils \
        intel-media-driver \
        libva-utils \
        vulkan-intel \
        vulkan-icd-loader \
        vulkan-tools
elif [ "${SETUP_GPU_MANUFACTURER}" = amd ]; then
    pacman -S --noconfirm \
        mesa \
        mesa-utils \
        libva-mesa-driver \
        libva-utils \
        vulkan-radeon \
        vulkan-icd-loader \
        vulkan-tools
elif [ "${SETUP_GPU_MANUFACTURER}" = nvidia ]; then
    pacman -S --noconfirm \
        mesa \
        mesa-utils \
        nvidia \
        nvidia-utils \
        vdpauinfo \
        vulkan-icd-loader \
        vulkan-tools \
        egl-wayland
    sed -i "s/^\(options .*\)$/\1 nvidia-drm.modeset=1/" /boot/loader/entries/arch.conf
fi


# PipeWire

pacman -S --noconfirm \
    pipewire \
    pipewire-alsa \
    pipewire-jack \
    pipewire-pulse \
    wireplumber \
    xdg-desktop-portal \
    xdg-desktop-portal-kde


# Plasma

pacman -S --noconfirm --asdeps phonon-qt5-gstreamer
pacman -S --noconfirm \
    plasma-meta \
    plasma-wayland-session


# KDE software

pacman -S --noconfirm \
    ark \
    dolphin \
    ebook-tools \
    ffmpegthumbs \
    gwenview \
    kcalc \
    kdegraphics-thumbnailers \
    kdialog \
    kolourpaint \
    okular \
    partitionmanager


# Multimedia

pacman -S --noconfirm \
    avidemux-qt \
    mpv \
    yt-dlp


# Printing

pacman -S --noconfirm \
    cups \
    print-manager \
    system-config-printer

ln -sf /usr/lib/systemd/system/cups.socket /etc/systemd/system/sockets.target.wants/cups.socket


# Office software and spell checking

pacman -S --noconfirm \
    hunspell \
    hunspell-en_us \
    hunspell-fr \
    libreoffice-fresh


# Other software

pacman -S --noconfirm \
    firefox \
    flameshot \
    hugo \
    neovide \
    qbittorrent


# Generate SSH key

sudo -u ${SETUP_USER} ssh-keygen -t ed25519 -C ${SETUP_EMAIL} -f /home/${SETUP_USER}/.ssh/id_ed25519


# Dotfiles

cd /home/${SETUP_USER}
sudo -u ${SETUP_USER} git init
sudo -u ${SETUP_USER} git remote add origin https://github.com/rjurga/dotfiles.git
sudo -u ${SETUP_USER} git fetch
sudo -u ${SETUP_USER} git checkout -f ${SETUP_DOTFILES_BRANCH}
sudo -u ${SETUP_USER} git remote set-url origin git@github.com:rjurga/dotfiles.git

