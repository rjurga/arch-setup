# Assumptions

* Booting in UEFI mode.
* The main storage disk is an SSD.

# Installation

1. Download the [installation image](https://archlinux.org/download/).

2. Prepare the installation USB drive. Make sure that it is not mounted.
```
sudo bash -c 'cat path/to/archlinux-version-x86_64.iso > /dev/sdx'
```

3. Boot the live USB drive.

4. Set azerty console keyboard layout.
```
loadkeys fr-latin1
```

5. Connect to the wireless network.
```
iwctl
[iwd]# device list
[iwd]# station <device> scan
[iwd]# station <device> get-networks
[iwd]# station <device> connect "<SSID>"
```

6. Download this repository.
```
curl -sfL https://github.com/rjurga/arch-setup/archive/master.tar.gz | tar zxf -
```

7. Modify the variables at the top of `setup.sh` and `setup-chroot.sh`.

8. Run `setup.sh`. When asked, type:
    * The disk encryption password (3 times).
    * The user password (2 times).
    * SSH key passphrase (2 times).

9. Reboot.
```
reboot
```

# Post-installation steps

1. Install yay AUR helper.
```
curl -sfL https://aur.archlinux.org/cgit/aur.git/snapshot/yay-bin.tar.gz | tar zxf -
cd yay-bin
makepkg -si
cd ..
rm -rf yay-bin
```

2. Install Google Chrome.
```
yay -S google-chrome
```

3. Install Visual Studio Code.
```
yay -S visual-studio-code-bin
code --install-extension ms-python.python
code --install-extension ms-vscode.cpptools
```

4. Install Anki.
```
yay -S anki-official-binary-bundle
```

5. Install Tailscale.
```
yay -S tailscale
sudo systemctl enable --now tailscaled.service
sudo tailscale up
```

# Notes

* During installation, you might see harmless errors about microcode reloading. Reloading is done properly on reboot.
* Btrfs-specific mount options for subvolumes are specified even if not taken into account. [Subvolume options support is planned in the future](https://btrfs.wiki.kernel.org/index.php/FAQ#Can_I_mount_subvolumes_with_different_mount_options.3F), so I just leave it there.
* Configuring `/etc/hosts` for local hostname resolution might not be necessary anymore.

# TODO

* Steam
* fwupd
* Chrome hardware acceleration
* Qemu
* bcachefs once it lands in kernel and is stable

