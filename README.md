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
