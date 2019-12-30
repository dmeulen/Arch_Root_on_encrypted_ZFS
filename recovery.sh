#!/bin/bash

mount -o remount,size=4G /run/archiso/cowspace

useradd -m -G wheel nonroot

echo -en "root ALL=(ALL) ALL\n%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers

pacman --noconfirm -Sy git base-devel python-setuptools

su - nonroot
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
cd -

wget https://archive.archlinux.org/packages/l/linux-headers/linux-headers-5.3.8.1-1-x86_64.pkg.tar.xz
sudo pacman -U linux-headers-5.3.8.1-1-x86_64.pkg.tar.xz

yay -S zfs-dkms zfs-utils

exit

modprobe zfs
