# Arch Linux - Root on ZFS on LUKS without archzfs

Sevaral documents can be found on the Internet about how to install Arch linux with root on ZFS. Most of the documents use the archzfs repo to do the actual installation. This works, but after installation you will get into trouble at some point in time. The archzfs repo is not always up to date with the kernels released in Arch linux. I always moved to the regular `zfs-dkms` and `zfs-utils` packages which are provided through the AUR.

This document describes how to install Arch Linux with root on ZFS on LUKS without the need of using archzfs.

## Prepare for installation

Just use the regular media to boot the installation media. Consult the Arch wiki for more info on that.

## Prepare install environment

Some of the steps require the use of a non-root user. So we'll need to create a temporary non-root user.
The default disk space is not sufficient to store all of the needed packages and tools, so we also need to increase the available disk space during the install.

### Increase disk space

    mount -o remount,size=4G /run/archiso/cowspace

### Create a temporary non-root user

During the install we will be using tools that refuse to run under the root user. So we'll need to create a non-root user that can execute commands as root ( a user with sudo powerz ).

    useradd -m -G wheel nonroot
    passwd nonroot

Configure sudo.

    visudo


Uncomment the following line and write the changes to disk:

    %wheel ALL=(ALL) NOPASSWD: ALL

You should never do this in a normal environment, but in our case it is convenient not to enter our password each and every time.

### Install yay

Install some requirements for building `yay` and ZFS.

    pacman -Sy git base-devel python-setuptools

Build and install `yay`:

    su - nonroot
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si
    cd -

Yay is an AUR package manager like `yaourt`.

### Get and install kernel headers

Still as user `nonroot`:

    wget https://archive.archlinux.org/packages/l/linux-headers/linux-headers-5.3.8.1-1-x86_64.pkg.tar.xz
    sudo pacman -S linux-headers-5.3.8.1-1-x86_64.pkg.tar.xz

### Install ZFS from AUR in install environment

As user `nonroot`:

    yay -S zfs-dkms zfs-utils

After successful installation we can exit the `nonroot` user:

    exit


