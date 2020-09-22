#!/bin/bash -x

stage1="/tmp/stage1.sh"
stage2="/tmp/stage2.sh"
DST_DEV="/dev/vda"

resize_cowspace() {
  COWSIZE=$(awk '/MemTotal/ {print int($2/1024/2)}')

  if [[ $COWSIZE < 2048 ]]; then
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
  cat <<_EOD
pacman --noconfirm -Sy git base-devel python-setuptools wget sudo
_EOD
  nonroot_exec 'git clone https://aur.archlinux.org/yay.git; cd yay; makepkg -si --noconfirm; cd -'
  nonroot_exec 'rm -rf ~/yay'
}

add_gpg_keys() {
  cat <<_EOD
gpg --keyserver pool.sks-keyservers.net  --recv-keys C33DF142657ED1F7C328A2960AB9E991C6AF658B
gpg --keyserver pool.sks-keyservers.net  --recv-keys 4F3BA9AB6D1F8D683DC2DFB56AD860EED4598027
_EOD
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
zpool create -o ashift=12 \
-O acltype=posixacl \
-O compression=lz4 \
-O relatime=on \
-O xattr=sa \
zroot $ROOT_DEV
_EOD
}

create_zfs_datasets() {
  cat <<_EOD
zfs create -o encryption=on -o keyformat=passphrase -o mountpoint=none zroot/encr
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

generate_stage1_install() {
  echo "$FUNCNAME"
  fn=${stage1}
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
  sh ${stage1}
}

generate_stage2_install() {
  echo "$FUNCNAME"
  fn=${stage2}
  setup_nonroot_user >> ${fn}
  add_gpg_keys >> ${fn}
  build_yay >> ${fn}
  build_zfs >> ${fn}
}

execute_stage2_install() {
  echo "$FUNCNAME"
}

resize_cowspace
generate_stage1_install
execute_stage1_install
generate_stage2_install
