# Arch Linux - Root on ZFS on LUKS without archzfs

Sevaral documents can be found on the Internet about how to install Arch linux with root on ZFS. Most of the documents use the archzfs repo to do the actual installation. This works, but after installation you will get into trouble at some point in time. The archzfs repo is not always up to date with the kernels released in Arch linux. I always moved to the regular `zfs-dkms` and `zfs-utils` packages which are provided through the AUR.

This document describes how to install Arch Linux with root on ZFS on LUKS without the need of using archzfs.


