#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

must_be_root_or_sudo

ARCH_IN="${ARCH:-x86_64}"
ARCH="$(arch_normalize "$ARCH_IN")"

ROOT="$(repo_root)"
DIST_DIR="$ROOT/dist/$ARCH"
WORK_DIR="$ROOT/.cache/rootfs/$ARCH"

SUITE="${UBUNTU_SUITE:-noble}"
IMAGE_SIZE="${ROOTFS_SIZE:-2G}"

ROOTFS_DIR="$WORK_DIR/rootfs"
IMG="$DIST_DIR/rootfs.ext4"
MNT="$WORK_DIR/mnt"

HOSTNAME_FILE="$ROOT/configs/hostname"
PKG_LIST="$ROOT/configs/rootfs-packages.txt"
SOURCES_LIST="$ROOT/configs/rootfs-apt-sources.list"

MIRROR_AMD64="${UBUNTU_MIRROR_AMD64:-http://archive.ubuntu.com/ubuntu}"
MIRROR_ARM64="${UBUNTU_MIRROR_ARM64:-http://ports.ubuntu.com/ubuntu-ports}"
SECURITY_AMD64="${UBUNTU_SECURITY_AMD64:-http://security.ubuntu.com/ubuntu}"

require_cmd debootstrap
require_cmd mkfs.ext4
require_cmd truncate
require_cmd mount
require_cmd umount
require_cmd chroot
require_cmd rsync

mkdir -p "$DIST_DIR" "$WORK_DIR"
rm -rf "$ROOTFS_DIR" "$MNT"
mkdir -p "$ROOTFS_DIR" "$MNT"

is_cross_arm64=0
if [[ "$ARCH" == "arm64" && "$(uname -m)" != "aarch64" ]]; then
  is_cross_arm64=1
  require_cmd qemu-aarch64-static
fi

chroot_sh() {
  local cmd="$1"
  if [[ "$is_cross_arm64" -eq 1 ]]; then
    chroot "$ROOTFS_DIR" /usr/bin/qemu-aarch64-static /bin/sh -c "$cmd"
  else
    chroot "$ROOTFS_DIR" /bin/sh -c "$cmd"
  fi
}

cleanup() {
  set +e
  if grep -qs " $MNT " /proc/mounts; then
    umount "$MNT" 2>/dev/null || true
  fi
  umount -R "$ROOTFS_DIR/proc" 2>/dev/null || true
  umount -R "$ROOTFS_DIR/sys" 2>/dev/null || true
  umount -R "$ROOTFS_DIR/dev" 2>/dev/null || true
}
trap cleanup EXIT

DEBOOTSTRAP_ARCH="$ARCH"

MIRROR="$MIRROR_AMD64"
if [[ "$ARCH" == "arm64" ]]; then
  MIRROR="$MIRROR_ARM64"
fi

echo "==> debootstrap ($SUITE, $DEBOOTSTRAP_ARCH)"
if [[ "$is_cross_arm64" -eq 1 ]]; then
  debootstrap --arch="$DEBOOTSTRAP_ARCH" --foreign "$SUITE" "$ROOTFS_DIR" "$MIRROR"
  install -m 0755 "$(command -v qemu-aarch64-static)" "$ROOTFS_DIR/usr/bin/qemu-aarch64-static"
  chroot "$ROOTFS_DIR" /usr/bin/qemu-aarch64-static /bin/sh /debootstrap/debootstrap --second-stage
else
  debootstrap --arch="$DEBOOTSTRAP_ARCH" "$SUITE" "$ROOTFS_DIR" "$MIRROR"
fi

echo "==> configure apt sources"
install -d "$ROOTFS_DIR/etc/apt"
if [[ "$ARCH" == "arm64" ]]; then
  cat >"$ROOTFS_DIR/etc/apt/sources.list" <<EOF
deb $MIRROR_ARM64 $SUITE main universe

deb $MIRROR_ARM64 ${SUITE}-updates main universe

deb $MIRROR_ARM64 ${SUITE}-security main universe
EOF
else
  install -m 0644 "$SOURCES_LIST" "$ROOTFS_DIR/etc/apt/sources.list"
fi

echo "==> set hostname"
install -m 0644 "$HOSTNAME_FILE" "$ROOTFS_DIR/etc/hostname"

# Minimal /etc/hosts
cat >"$ROOTFS_DIR/etc/hosts" <<'EOF'
127.0.0.1 localhost
127.0.1.1 vm-os
EOF

echo "==> mount pseudo-filesystems"
mount -t proc proc "$ROOTFS_DIR/proc"
mount --rbind /sys "$ROOTFS_DIR/sys"
mount --make-rslave "$ROOTFS_DIR/sys"
mount --rbind /dev "$ROOTFS_DIR/dev"
mount --make-rslave "$ROOTFS_DIR/dev"

# Ensure DNS works for apt in chroot.
cp -L /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

echo "==> install packages"
install -m 0644 "$PKG_LIST" "$ROOTFS_DIR/tmp/pkglist"
chroot_sh "export DEBIAN_FRONTEND=noninteractive; apt-get update; pkgs=\$(grep -Ev '^\s*#|^\s*$' /tmp/pkglist | tr '\n' ' '); apt-get install -y \$pkgs; apt-get clean"
rm -f "$ROOTFS_DIR/tmp/pkglist"

echo "==> create user peer-ci (sudo, passwordless)"
chroot_sh "id -u peer-ci >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo peer-ci"
chroot_sh "passwd -l peer-ci >/dev/null"
install -d "$ROOTFS_DIR/etc/sudoers.d"
cat >"$ROOTFS_DIR/etc/sudoers.d/peer-ci" <<'EOF'
peer-ci ALL=(ALL) NOPASSWD:ALL
EOF
chmod 0440 "$ROOTFS_DIR/etc/sudoers.d/peer-ci"

echo "==> disable ssh"
chroot_sh "apt-get purge -y openssh-server >/dev/null 2>&1 || true"

echo "==> systemd hygiene"
# Let systemd generate a fresh machine-id on first boot.
: >"$ROOTFS_DIR/etc/machine-id" || true

echo "==> unmount pseudo-filesystems"
umount -R "$ROOTFS_DIR/proc" 2>/dev/null || true
umount -R "$ROOTFS_DIR/sys" 2>/dev/null || true
umount -R "$ROOTFS_DIR/dev" 2>/dev/null || true

echo "==> build ext4 image ($IMAGE_SIZE)"
rm -f "$IMG"
truncate -s "$IMAGE_SIZE" "$IMG"
mkfs.ext4 -F -L rootfs "$IMG" >/dev/null

mount -o loop "$IMG" "$MNT"
rsync -aHAX --numeric-ids "$ROOTFS_DIR/" "$MNT/"
sync
umount "$MNT"

echo "Built $IMG"
