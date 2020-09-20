# WIP: Arch Linux - Root on ZFS with native encryption enabled

This document describes how to install Arch Linux with root on ZFS with native ZFS encryption.
In the future I plan to automate most of the steps...

( Note: This document only applies to UEFI systems )

# Prepare for installation

Just use the regular media to boot the installation media. Consult the Arch wiki for more info on how to create install media.


Some of the steps require the use of a non-root user. So we'll need to create a temporary non-root user.
The default disk space is not sufficient to store all of the needed packages and tools, so we also need to increase the available disk space during the install.
The `nonroot` user and sudo settings will not be present after the installation, except from the user and sudo config we configure when we are in the chroot environment.

## Install and configure ssh for installation with a proper terminal

  This is only needed when you want to continue the installation via SSH. This will give you the possibility to copy and paste commands, making the install process a lot more convenient.

### Install SSH

    pacman --noconfirm -Sy openssh

### Set a root password

This password will only be used during the installation, no need to use your super secret password here.

    passwd

### Start the sshd daemon

    systemctl start sshd.service

### Get your IP address

Obviously, this will only work when connected to a network. Usually you'll get an IP address via DHCP. If not, use your google skillz to find out how to configure networking on Arch Linux.

    ip a

### Log in to your installation via another computer

You should use the IP address you got from `ip a`.

    ssh root@192.168.122.194

# Continue the installation



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

Yay is an AUR package manager like `yaourt`, but actively developed.

### Install some requirements for building `yay` and ZFS.

    pacman --noconfirm -Sy git base-devel python-setuptools wget

### Build and install `yay`:

    su - nonroot
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd -

## Get and install kernel headers

You might need to change the URL used below. It should be the same kernel version as the installer runs ( check with `uname -a` ). If your installer runs another kernel version, find the correct package [here](https://archive.archlinux.org/packages/l/linux-headers/).


Still as user `nonroot`:

    wget https://archive.archlinux.org/packages/l/linux-headers/linux-headers-5.3.8.1-1-x86_64.pkg.tar.xz
    sudo pacman --noconfirm -U linux-headers-5.3.8.1-1-x86_64.pkg.tar.xz

## Install ZFS from AUR in install environment

As user `nonroot`:

    yay --noconfirm -S zfs-dkms zfs-utils

If importing keys fails try this and re-run the above command:

    gpg --keyserver pool.sks-keyservers.net  --recv-keys C33DF142657ED1F7C328A2960AB9E991C6AF658B
    gpg --keyserver pool.sks-keyservers.net  --recv-keys 4F3BA9AB6D1F8D683DC2DFB56AD860EED4598027


### After successful installation we can exit the `nonroot` user and load the zfs kernel module:

    exit
    modprobe zfs

## Partitioning ( UEFI only )

    parted /dev/sdX
    (parted) mklabel gpt
    (parted) mkpart ESP fat32 1 513
    (parted) set 1 boot on
    (parted) name 1 boot
    (parted) mkpart primary 513 100%
    (parted) name 2 rootfs
    (parted) quit

## Partitioning ( BIOS only )

    parted /dev/sdX
    (parted) mklabel gpt
    (parted) mkpart primary 1 3
    (parted) set 1 bios_grub on
    (parted) mkpart primary 3 500
    (parted) set 2 boot on
    (parted) name 2 boot
    (parted) mkpart primary 500 100%
    (parted) name 3 rootfs
    (parted) quit

## Create zpool and zfs filesystems

### Create our zpool:

Remember to create the pool on the partition we named `rootfs`, 2nd partition for UEFI based systems, 3rd for BIOS. The following is an example for UEFI.

    zpool create -o ashift=12 \
      -O acltype=posixacl \
      -O compression=lz4 \
      -O relatime=on \
      -O xattr=sa \
      zroot /dev/sdX2

### The ZFS filesystems:

Ignore any errors regarding not being able to mount the filesystem. Compression and other settings will be inherited from the pool.

    zfs create -o encryption=on -o keyformat=passphrase -o mountpoint=none zroot/encr
    zfs create -o mountpoint=none zroot/encr/data
    zfs create -o mountpoint=none zroot/encr/ROOT
    zfs create -o mountpoint=/ zroot/encr/ROOT/default
    zfs create -o mountpoint=legacy zroot/encr/data/home

### Unmount the filesystems:

    zfs umount -a

### Set bootfs

    zpool set bootfs=zroot/encr/ROOT/default zroot

### Create a swap device:

    zfs create -V 4G -b 4096 -o logbias=throughput -o sync=always -o primarycache=metadata -o com.sun:auto-snapshot=false zroot/encr/swap
    mkswap -f /dev/zvol/zroot/encr/swap

### Export and re-import the created zpool:

Our filesystems will be mounted under `/mnt`.

    zpool export zroot
    zpool import -R /mnt -l zroot

### Create zfs pool cache file

    zpool set cachefile=/etc/zfs/zpool.cache zroot
    mkdir -p /mnt/etc/zfs
    cp /etc/zfs/zpool.cache /mnt/etc/zfs/

## Install the base system

### Mount the `/boot` filesystem in our installation ( UEFI only )

    mkdir /mnt/boot
    mkfs.fat -F32 /dev/sdX1
    mount /dev/sdX1 /mnt/boot

### Mount the /boot partition in our installation ( BIOS only )

    mkdir /mnt/boot
    mkfs.ext4 /dev/sdX2
    mount /dev/sdX2 /mnt/boot

### Install the base system:

    pacstrap -i /mnt base base-devel


## Configure system

### Create fstab entry for the boot partition ( UEFI only )

    genfstab -U -p /mnt | grep boot >> /mnt/etc/fstab

### Add swap and home entries to fstab

    echo "/dev/zvol/zroot/encr/swap none swap discard 0 0" >> /mnt/etc/fstab
    echo "zroot/encr/data/home /home zfs rw,xattr,posixacl 0 0" >> /mnt/etc/fstab

### Chroot into our Arch installation

    arch-chroot /mnt /bin/bash

### Mount home directory

    mount /home

### Install our favorite editor:

    pacman --noconfirm -S vim

### Set locale:

    # vim /etc/locale.gen
    --------------------
    en_US.UTF-8 UTF-8

    locale-gen

    # vim /etc/locale.conf
    ---------------------
    LANG=en_US.UTF-8

### Set timezone:

    ln -sf /usr/share/zoneinfo/Europe/Amsterdam /etc/localtime

### Configure hostname:

    hostnamectl set-hostname <hostname>

### Set root password

Now you do use your super secret password!:

    passwd

### Add a user:

    useradd -m -G wheel jdoe
    passwd jdoe

### Edit sudoers file:

    visudo

Uncomment out following line:

    %wheel ALL=(ALL) ALL

### Build and install ZFS dkms modules and ZFS utils as our newly created user:

If you had roblems importing keys in earlier steps, do this first:

    gpg --keyserver pool.sks-keyservers.net  --recv-keys C33DF142657ED1F7C328A2960AB9E991C6AF658B
    gpg --keyserver pool.sks-keyservers.net  --recv-keys 4F3BA9AB6D1F8D683DC2DFB56AD860EED4598027

Build yay and zfs:

    pacman --noconfirm -S linux linux-headers git
    su - jdoe
    mkdir git
    cd git
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    yay --noconfirm -S zfs-dkms zfs-utils
    exit

### Install and enable networkmanager and ssh:

    pacman --noconfirm -S networkmanager openssh
    systemctl enable NetworkManager.service
    systemctl enable sshd.service

If you don't like networkmanager, feel free to use whatever makes you happy.

### Generate kernel image with updated hooks:

Replace contents of `/usr/lib/initcpio/hooks/zfs` with one that supports importing encrypted zpools: https://aur.archlinux.org/cgit/aur.git/plain/zfs-utils.initcpio.hook?h=zfs-utils-common

Find the HOOKS setting in `/etc/mkinitcpio.conf` and update mkinitcpio hooks:

    # vim /etc/mkinitcpio.conf
    --------------------------
    HOOKS=(base udev autodetect modconf keyboard keymap consolefont block zfs filesystems)

Generate image:

    mkinitcpio -p linux

## Configure systemd-boot bootloader (UEFI only)

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
    options zfs=bootfs rw

### Create fallback boot entry:

    # vim /boot/loader/entries/arch-fallback.conf
    title Arch Linux Fallback
    linux /vmlinuz-linux
    initrd /initramfs-linux-fallback.img
    options zfs=bootfs rw

## Configure and install the GRUB boot loader ( BIOS only )

### Install grub

    pacman --noconfirm -Sy grub

### Install grub in MBR

    grub-install --target=i386-pc /dev/sdX

### Configure GRUB

    # vim /boot/grub/grub.cfg
    -------------------------
    set timeout=5
    set default=0

    menuentry "Arch Linux" {
        search --no-floppy -l rootfs
        linux /vmlinuz-linux zfs=zroot/ROOT/default rw
        initrd /initramfs-linux.img
    }
    menuentry "Arch Linux Fallback" {
        search --no-floppy -l rootfs
        linux /vmlinuz-linux zfs=zroot/ROOT/default rw
        initrd /initramfs-linux-fallback.img
    }



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
