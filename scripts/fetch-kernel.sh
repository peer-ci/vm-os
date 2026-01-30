#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

must_be_root_or_sudo

ARCH_IN="${ARCH:-x86_64}"
ARCH="$(arch_normalize "$ARCH_IN")"

ROOT="$(repo_root)"
DIST_DIR="$ROOT/dist/$ARCH"
WORK_DIR="$ROOT/.cache/kernel/$ARCH"

SUITE="${UBUNTU_SUITE:-noble}"
FLAVOR="${KERNEL_FLAVOR:-virtual}"

require_cmd apt-get
require_cmd dpkg-deb
require_cmd file
require_cmd sha256sum

mkdir -p "$DIST_DIR" "$WORK_DIR"
rm -rf "$WORK_DIR/extracted" && mkdir -p "$WORK_DIR/extracted"

# Use linux-image-virtual on Ubuntu noble.
PKG="linux-image-${FLAVOR}"

echo "==> downloading kernel package ($PKG:$ARCH)"
( cd "$WORK_DIR" && apt-get update >/dev/null && apt-get download "$PKG:$ARCH" )

deb="$(ls -1t "$WORK_DIR"/*.deb | head -1)"

echo "==> extracting $deb"
dpkg-deb -x "$deb" "$WORK_DIR/extracted"

VMLINUX_U="$WORK_DIR/extracted/boot/vmlinuz"*
VMLINUX_PATH="$(ls -1 $VMLINUX_U 2>/dev/null | head -1 || true)"
if [[ -z "$VMLINUX_PATH" ]]; then
  echo "error: could not find extracted /boot/vmlinuz* inside $deb" >&2
  exit 1
fi

echo "==> producing Firecracker kernel artifact"
if [[ "$ARCH" == "amd64" ]]; then
  require_cmd gzip
  require_cmd xz
  OUT="$DIST_DIR/vmlinux"
  "$ROOT/scripts/lib/extract-vmlinux.sh" "$VMLINUX_PATH" >"$OUT"
  chmod 0644 "$OUT"
  file "$OUT" | grep -q "ELF" || { echo "error: extracted kernel is not ELF" >&2; exit 1; }
  sha256sum "$OUT" >"$OUT.sha256"
  echo "Built $OUT"
elif [[ "$ARCH" == "arm64" ]]; then
  OUT="$DIST_DIR/Image"
  cp -f "$VMLINUX_PATH" "$OUT"
  chmod 0644 "$OUT"
  # Firecracker expects PE formatted images on aarch64.
  file "$OUT" | grep -qi "PE" || { echo "error: arm64 kernel is not PE formatted" >&2; file "$OUT"; exit 1; }
  sha256sum "$OUT" >"$OUT.sha256"
  echo "Built $OUT"
else
  echo "error: unsupported arch: $ARCH" >&2
  exit 2
fi
