#!/bin/bash -x -e

stage1="/tmp/stage1.sh"
stage2="/tmp/stage2.sh"

get_all_install_info() {
  clear
  echo "I found the following disks: "
  lsblk -d -l -o 'NAME,SIZE,TYPE' -p
  echo "Enter the NAME of the target disk:"
  read target_disk

  echo "What root password would you like to use:"
  read -s root_pass
  echo "Repeat that please:"
  read -s root_pass1
  if [[ x"$root_pass" != x"$root_pass1" ]]; then
    echo "Passwords do not match..."
    exit 1
  fi

  echo "What ZFS passphrase would you like to use:"
  read -s zfs_pass
  echo "Repeat that please:"
  read -s zfs_pass1
  if [[ x"$zfs_pass" != x"$zfs_pass1" ]]; then
    echo "Passwords do not match..."
    exit 1
  fi
  if [[ "${#zfs_pass}" -lt 8 ]]; then
    echo "ZFS passphrase should be more than 8 characters."
    exit 1
  fi

  echo "What hostname should I set:"
  read my_hostname

  DST_DEV=${target_disk}
  echo "Continue with installation on \"$DST_DEV\"?"
  echo "This will destroy everything on that disk!"
  echo -en "Answer with \"YES\" to continue "
  read yesno
  if [[ x"${yesno}" != x"YES" ]]; then
    echo "Bailing out..."
    exit 1
  fi
}

installer_packages() {
  pacman --noconfirm -Sy git base-devel python-setuptools wget sudo dialog
}

resize_cowspace() {
  COWSIZE=$(awk '/MemTotal/ {print int($2/1024/2)}' /proc/meminfo)

  if [[ $COWSIZE < 1800 ]]; then
    echo "Not enough memory installed 4GB is the bare minimum, sorry."
    exit 1
  elif [[ $COWSIZE > 4096 ]]; then
    COWSIZE=4096
  fi
  mount -o remount,size=${COWSIZE}M /run/archiso/cowspace
}

setup_nonroot_user() {
  cat <<_EOD
useradd -m -G wheel nonroot
echo -en "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/00-nonrootinstaller
_EOD
}

cleanup_nonroot_user() {
  cat <<_EOD
userdel -f -r nonroot
rm -f /etc/sudoers.d/00-nonrootinstaller
_EOD
}

nonroot_exec() {
  cat <<_EOD
su - nonroot -c "$1"
_EOD
}

build_yay() {
  nonroot_exec 'git clone https://aur.archlinux.org/yay.git; cd yay; makepkg -si --noconfirm; cd -'
  nonroot_exec 'rm -rf ~/yay'
}

add_gpg_keys() {
  nonroot_exec 'gpg --keyserver pool.sks-keyservers.net  --recv-keys C33DF142657ED1F7C328A2960AB9E991C6AF658B'
  nonroot_exec 'gpg --keyserver pool.sks-keyservers.net  --recv-keys 4F3BA9AB6D1F8D683DC2DFB56AD860EED4598027'
}

install_kernel_headers() {
  cat <<_EOD
wget https://archive.archlinux.org/packages/l/linux-headers/linux-headers-$(uname -r | sed 's/-/./')-x86_64.pkg.tar.zst
pacman --noconfirm -U linux-headers-$(uname -r | sed 's/-/./')-x86_64.pkg.tar.zst
_EOD
}

build_zfs() {
  nonroot_exec 'yay --noconfirm -S zfs-dkms zfs-utils'
}


load_zfs_module() {
  cat <<_EOD
modprobe zfs
_EOD
}

partition_disk() {
  cat <<_EOD
parted $DST_DEV mklabel gpt
parted $DST_DEV mkpart ESP fat32 1 513
parted $DST_DEV set 1 boot on
parted $DST_DEV name 1 boot
parted $DST_DEV mkpart primary 513 100%
parted $DST_DEV name 2 rootfs
_EOD
  BOOT_DEV=${DST_DEV}1
  ROOT_DEV=${DST_DEV}2
}

create_zpool() {
  cat <<_EOD
zpool create -f -o ashift=12 \
-O acltype=posixacl \
-O compression=lz4 \
-O relatime=on \
-O xattr=sa \
zroot $ROOT_DEV
_EOD
}

create_zfs_datasets() {
  cat <<_EOD
echo $zfs_pass | zfs create -o encryption=on -o keyformat=passphrase -o keylocation=prompt -o mountpoint=none zroot/encr
zfs create -o mountpoint=none zroot/encr/data
zfs create -o mountpoint=none zroot/encr/ROOT
zfs create -o mountpoint=/ zroot/encr/ROOT/default
zfs create -o mountpoint=legacy zroot/encr/data/home
zfs umount -a
zpool set bootfs=zroot/encr/ROOT/default zroot
_EOD
}

create_swap_device() {
  cat <<_EOD
zfs create -V 4G -b 4096 -o logbias=throughput -o sync=always -o primarycache=metadata -o com.sun:auto-snapshot=false zroot/encr/swap
mkswap -f /dev/zvol/zroot/encr/swap
_EOD
}

reimport_pool() {
  cat <<_EOD
zpool export zroot
zpool import -R /mnt -l zroot
_EOD
}

pool_cache() {
  cat <<_EOD
zpool set cachefile=/etc/zfs/zpool.cache zroot
mkdir -p /mnt/etc/zfs
cp /etc/zfs/zpool.cache /mnt/etc/zfs/
_EOD
}

boot_partition() {
  cat <<_EOD
mkdir /mnt/boot
mkfs.fat -F32 $BOOT_DEV
mount $BOOT_DEV /mnt/boot
_EOD
}

pacstrap_system() {
  cat <<_EOD
pacstrap -i /mnt base base-devel
_EOD
}

genfstab() {
  cat <<_EOD
genfstab -U -p /mnt | grep boot >> /mnt/etc/fstab
echo "/dev/zvol/zroot/encr/swap none swap discard 0 0" >> /mnt/etc/fstab
echo "zroot/encr/data/home /home zfs rw,xattr,posixacl 0 0" >> /mnt/etc/fstab
_EOD
}

stage2_packages() {
  cat <<_EOD
pacman --noconfirm -Sy linux linux-headers git sudo vim openssh networkmanager
_EOD
}

stage2_configure_system() {
  cat <<_EOD
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
ln -sf /usr/share/zoneinfo/Europe/Amsterdam /etc/localtime
hostnamectl set-hostname $my_hostname
systemctl enable NetworkManager.service
systemctl enable sshd.service
_EOD
}

stage2_update_hooks() {
  cat <<_EOD
cp /usr/lib/initcpio/hooks/zfs /usr/lib/initcpio/hooks/zfs.org
curl -s https://aur.archlinux.org/cgit/aur.git/plain/zfs-utils.initcpio.hook?h=zfs-utils-common > /usr/lib/initcpio/hooks/zfs
sed -i 's/^HOOKS.*$/HOOKS=(base udev autodetect modconf keyboard keymap consolefont block zfs filesystems)/' /mnt/etc/mkinitcpio.conf
mkinitcpio -p linux
_EOD
}

stage2_bootloader() {
  cat <<_EOD
bootctl --path=/boot install

cat <<EOF > /boot/loader/loader.conf
default arch
timeout 4
editor 0
EOF

cat <<EOF > /boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options zfs=bootfs rw
EOF

cat <<EOF > /boot/loader/entries/arch-fallback.conf
title Arch Linux Fallback
linux /vmlinuz-linux
initrd /initramfs-linux-fallback.img
options zfs=bootfs rw
EOF

_EOD
}

stage2_root_password() {
  cat <<_EOD
passwd
_EOD
}

stage2_umount() {
  cat <<_EOD
umount -l /home
_EOD
}

generate_stage1_install() {
  echo "$FUNCNAME"
  fn=${stage1}
  echo "#!/bin/bash -x -e" > ${fn}
  chmod 755 ${fn}
  setup_nonroot_user >> ${fn}
  add_gpg_keys >> ${fn}
  build_yay >> ${fn}
  install_kernel_headers >> ${fn}
  build_zfs >> ${fn}
  load_zfs_module >> ${fn}
  partition_disk >> ${fn}
  create_zpool >> ${fn}
  create_zfs_datasets >> ${fn}
  create_swap_device >> ${fn}
  reimport_pool >> ${fn}
  pool_cache >> ${fn}
  boot_partition >> ${fn}
  pacstrap_system >> ${fn}
  genfstab >> ${fn}
}

execute_stage1_install() {
  echo "$FUNCNAME"
  bash -x -e ${stage1}
}

generate_stage2_install() {
  echo "$FUNCNAME"
  fn=${stage2}
  echo "#!/bin/bash -x -e" > ${fn}
  chmod 755 ${fn}
  stage2_packages >> ${fn}
  setup_nonroot_user >> ${fn}
  add_gpg_keys >> ${fn}
  build_yay >> ${fn}
  build_zfs >> ${fn}
  stage2_update_hooks >> ${fn}
  stage2_configure_system >> ${fn}
  stage2_bootloader >> ${fn}
  stage2_root_password >> ${fn}
  stage2_umount >> ${fn}
}

execute_stage2_install() {
  echo "$FUNCNAME"
  cp /tmp/stage2.sh /mnt/stage2.sh
  arch-chroot /mnt /stage2.sh
  cp /etc/zfs/zpool.cache /mnt/etc/zfs
  umount /mnt/boot
  zpool export zroot
}

resize_cowspace
installer_packages
get_all_install_info

generate_stage1_install
execute_stage1_install
generate_stage2_install
execute_stage2_install

echo "Done! Reboot or do whatever you want to do if you know what to do but you probably know because you know you decided to use arch linux and this ugly script. :p"
