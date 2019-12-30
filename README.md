# WIP: Arch Linux - Root on ZFS with native encryption enabled

Several documents can be found on the Internet about how to install Arch linux with root on ZFS.
Most of the documents use the archzfs repo to do the actual installation. This works, but after installation you will get into trouble at some point in time.
The archzfs repo is not always up to date with the kernels released in Arch linux.
So I always end up moving to the regular `zfs-dkms` and `zfs-utils` packages which are provided through the AUR.

This document describes how to install Arch Linux with root on ZFS on LUKS without the need of using archzfs.
In the future I plan to automate most of the steps...

( Note: This document only applies to UEFI systems )

# Prepare for installation

Just use the regular media to boot the installation media. Consult the Arch wiki for more info on how to create install media.


Some of the steps require the use of a non-root user. So we'll need to create a temporary non-root user.
The default disk space is not sufficient to store all of the needed packages and tools, so we also need to increase the available disk space during the install.
The `nonroot` user and sudo settings will not be present after the installation, except from the user and sudo config we configure when we are in the chroot environment.

## Increase disk space

    mount -o remount,size=4G /run/archiso/cowspace

## Create a temporary non-root user

During the install we will be using tools that refuse to run under the root user. So we'll need to create a non-root user that can execute commands as root ( a user with sudo powerz ).

    useradd -m -G wheel nonroot

Configure sudo.

    visudo

Uncomment the following line and write the changes to disk:

    %wheel ALL=(ALL) NOPASSWD: ALL

You should never do this in a normal environment, but in our case it is convenient not to enter our password each and every time.

## Install yay

### Install some requirements for building `yay` and ZFS.

    pacman -Sy git base-devel python-setuptools

### Build and install `yay`:

    su - nonroot
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si
    cd -

Yay is an AUR package manager like `yaourt`.

## Get and install kernel headers

You might need to change the URL used below. It should be the same kernel version as the installer runs ( check with `uname -a` ). If your installer runs another kernel version, find the correct package [here](https://archive.archlinux.org/packages/l/linux-headers/).


Still as user `nonroot`:

    wget https://archive.archlinux.org/packages/l/linux-headers/linux-headers-5.3.8.1-1-x86_64.pkg.tar.xz
    sudo pacman -U linux-headers-5.3.8.1-1-x86_64.pkg.tar.xz

## Install ZFS from AUR in install environment

As user `nonroot`:

    yay -S zfs-dkms zfs-utils

### After successful installation we can exit the `nonroot` user and load the zfs kernel module:

    exit
    modprobe zfs

### Create the ZFS pool cache file:

    touch /etc/zfs/zpool.cache

## Partitioning

    parted /dev/sdx
    (parted) mklabel gpt
    (parted) mkpart ESP fat32 1MiB 513MiB
    (parted) set 1 boot on
    (parted) mkpart primary 2 100%
    (parted) quit

## Create zpool and zfs filesystems

### Create our zpool:

    zpool create -o ashift=12 \
      -o cachefile=/etc/zfs/zpool.cache \
      -O acltype=posixacl \
      -O compression=lz4 \
      -O relatime=on \
      -O xattr=sa \
      zroot /dev/sdx2

### The ZFS filesystems:

Ignore any errors regarding not being able to mount the filesystem.

    zfs create -o encryption=on -o keyformat=passphrase -o mountpoint=none zroot/encr
    zfs create -o mountpoint=none zroot/encr/data
    zfs create -o mountpoint=none zroot/encr/ROOT
    zfs create -o compression=lz4 -o mountpoint=/ zroot/encr/ROOT/default
    zfs create -o compression=lz4 -o mountpoint=legacy zroot/encr/data/home

### Unmount the filesystems:

    zfs umount -a

Just making sure the mountpoints are correct ( better safe than sorry ):

    zfs set mountpoint=/ zroot/encr/ROOT/default
    zfs set mountpoint=legacy zroot/encr/data/home

### Set bootfs and some defaults:

    zpool set bootfs=zroot zroot
    zfs set compression=lz4 zroot
    zfs set relatime=on zroot

### Create a swap device:

    zfs create -V 4G -b 4096 -o logbias=throughput -o sync=always -o primarycache=metadata -o com.sun:auto-snapshot=false zroot/encr/swap
    mkswap -f /dev/zvol/zroot/encr/swap

### Export and re-import the created zpool:

Our filesystems will be mounted under `/mnt`.

    zpool export zroot
    zpool import -R /mnt -l zroot

## Install the base system

### Mount the `/boot` filesystem in our installation:

    mkdir /mnt/boot
    mkfs.fat -F32 /dev/sdx1
    mount /dev/sdx1 /mnt/boot

### Install the base system:

    pacstrap -i /mnt base base-devel


## Configure system

### Generate an fstab:

    genfstab -U -p /mnt | grep boot >> /mnt/etc/fstab
    echo "/dev/zvol/zroot/swap none swap discard 0 0" >> /mnt/etc/fstab
    echo "zroot/data/home /home zfs rw,xattr,posixacl 0 0" >> /mnt/etc/fstab

### Chroot into our Arch installation

    arch-chroot /mnt /bin/bash

### Mount home directory

    mount /home

### Install our favorite editor:

    pacman -S vim

### Set locale:

    # vim /etc/locale.gen
    --------------------
    Uncomment en_US.UTF-8 UTF-8

    # locale-gen

    # vim /etc/locale.conf
    ---------------------
    LANG=en_US.UTF-8

### Set timezone:

    ln -sf /usr/share/zoneinfo/Europe/Amsterdam /etc/localtime

### Configure hostname:

    # echo "<hostname>" >> /etc/hostname

### Set root password:

    passwd

### Add a user:

    useradd -m -G wheel jdoe
    passwd jdoe

### Edit sudoers file:

    visudo

Uncomment out following line:

    %wheel ALL=(ALL) ALL

### Build and install ZFS dkms modules and ZFS utils as our newly created user:

    su - jdoe
    sudo pacman -S linux linux-headers git
    mkdir git
    cd git
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si
    yay -S zfs-dkms zfs-utils
    exit

### Install and enable networkmanager and ssh:

    pacman -S networkmanager opennssh
    systemctl enable NetworkManager.service
    systemctl enable sshd.service

## Configure for boot (UEFI only)

Find the HOOKS setting in `/etc/mkinitcpio.conf` and update mkinitcpio hooks:

    # vim /etc/mkinitcpio.conf
    --------------------------
    HOOKS=(base udev autodetect modconf keyboard keymap consolefont block zfs filesystems)

### Generate kernel image with updated hooks:

    mkinitcpio -p linux

### Install bootloader:

    bootctl --path=/boot install

### Configure bootloader:

    # vim /boot/loader/loader.conf
    ------------------------------
    default arch
    timeout 4
    editor 0

### Create main boot entry:

`REPLACEME` will be replaced in a later step with `sed`,

    # vim /boot/loader/entries/arch.conf
    ------------------------------------
    title Arch Linux
    linux /vmlinuz-linux
    initrd /initramfs-linux.img
    options zfs=zroot/ROOT/default rw

### Create fallback boot entry:

    # vim /boot/loader/entries/arch-fallback.conf
    title Arch Linux Fallback
    linux /vmlinuz-linux
    initrd /initramfs-linux-fallback.img
    options zfs=zroot/ROOT/default rw

### Unmount home directory

    umount /home

### Exit chroot environment:

		exit

### Copy ZFS cache file into installed system:

		cp /etc/zfs/zpool.cache /mnt/etc/zfs

### Unmount filesystems and reboot:

		umount /mnt/boot
		zpool export zroot
		reboot

# DONE!

Enjoy your new encrypted ZFS system!
