#!/bin/bash -x

mount -o remount,size=4G /run/archiso/cowspace

useradd -m -G wheel nonroot

echo -en "root ALL=(ALL) ALL\n%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers

pacman --noconfirm -Sy git base-devel python-setuptools

su - nonroot -c 'git clone https://aur.archlinux.org/yay.git; cd yay; makepkg -si --noconfirm; cd -'

su - nonroot -c 'wget https://archive.archlinux.org/packages/l/linux-headers/linux-headers-$(uname -r | sed 's/-/./')-x86_64.pkg.tar.zst'
su - nonroot -c 'sudo pacman --noconfirm -U linux-headers-$(uname -r | sed 's/-/./')-x86_64.pkg.tar.zst'

su - nonroot -c 'yay --noconfirm -S zfs-dkms zfs-utils'

modprobe zfs

zpool import -R /mnt -l zroot

cat <<_EOD

# Now do the following

# Mount /boot, change device accordingly
mount /dev/sdX1 /mnt/boot

# Enter chroot
arch-chroot /mnt /bin/bash

# Do your fixes
