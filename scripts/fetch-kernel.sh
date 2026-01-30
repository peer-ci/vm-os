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
chmod 1777 "$WORK_DIR" || true
rm -rf "$WORK_DIR/extracted" && mkdir -p "$WORK_DIR/extracted"

# Use linux-image-virtual on Ubuntu noble.
PKG="linux-image-${FLAVOR}"

echo "==> downloading kernel package ($PKG:$ARCH)"
if [[ "$ARCH" == "arm64" ]]; then
  if [[ "$(dpkg --print-architecture)" == "arm64" ]]; then
    # Native arm64 runner: let apt/dpkg auto-detect architecture.
    ( cd "$WORK_DIR" && apt-get update >/dev/null && apt-get download "$PKG:$ARCH" )
  else
    # Cross-download arm64 .debs on an amd64 host: avoid relying on host apt sources
    # (which may not serve arm64 from security.ubuntu.com). Use ports.ubuntu.com.
    if ! dpkg --print-foreign-architectures | grep -qx arm64; then
      echo "error: dpkg arm64 architecture not enabled (run: sudo dpkg --add-architecture arm64)" >&2
      exit 1
    fi

    cat >"$WORK_DIR/arm64.list" <<EOF
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $SUITE main universe
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports ${SUITE}-updates main universe
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports ${SUITE}-security main universe
EOF

    ( cd "$WORK_DIR" && \
      apt-get update -o Dir::Etc::sourcelist="$WORK_DIR/arm64.list" -o Dir::Etc::sourceparts="-" -o APT::Architecture=arm64 -o APT::Architectures=arm64 >/dev/null && \
      apt-get download -o Dir::Etc::sourcelist="$WORK_DIR/arm64.list" -o Dir::Etc::sourceparts="-" -o APT::Architecture=arm64 -o APT::Architectures=arm64 "$PKG:$ARCH" )
  fi
else
  ( cd "$WORK_DIR" && apt-get update >/dev/null && apt-get download "$PKG:$ARCH" )
fi

deb="$(ls -1t "$WORK_DIR"/*.deb | head -1)"

extract_and_find_vmlinuz() {
  local deb="$1"
  rm -rf "$WORK_DIR/extracted" && mkdir -p "$WORK_DIR/extracted"
  dpkg-deb -x "$deb" "$WORK_DIR/extracted"
  ls -1 "$WORK_DIR"/extracted/boot/vmlinuz* 2>/dev/null | head -1 || true
}

echo "==> extracting $deb"
VMLINUX_PATH="$(extract_and_find_vmlinuz "$deb")"
if [[ -z "$VMLINUX_PATH" ]]; then
  deps="$(dpkg-deb -f "$deb" Depends 2>/dev/null || true)"
  img_pkg="$(echo "$deps" | tr ',' '\n' | tr '|' '\n' | sed -E 's/\([^)]*\)//g' | awk '{print $1}' | grep -E "^linux-image(-unsigned)?-[0-9].*-${FLAVOR}$" | head -1 || true)"
  if [[ -z "$img_pkg" ]]; then
    echo "error: could not find extracted /boot/vmlinuz* inside $deb" >&2
    echo "error: package appears to be meta; Depends: $deps" >&2
    exit 1
  fi

  echo "==> $PKG is a meta package; downloading dependency ($img_pkg:$ARCH)"
  rm -f "$WORK_DIR"/*.deb
  if [[ "$ARCH" == "arm64" && "$(dpkg --print-architecture)" != "arm64" ]]; then
    ( cd "$WORK_DIR" && \
      apt-get update -o Dir::Etc::sourcelist="$WORK_DIR/arm64.list" -o Dir::Etc::sourceparts="-" -o APT::Architecture=arm64 -o APT::Architectures=arm64 >/dev/null && \
      apt-get download -o Dir::Etc::sourcelist="$WORK_DIR/arm64.list" -o Dir::Etc::sourceparts="-" -o APT::Architecture=arm64 -o APT::Architectures=arm64 "$img_pkg:$ARCH" )
  else
    ( cd "$WORK_DIR" && apt-get update >/dev/null && apt-get download "$img_pkg:$ARCH" )
  fi

  deb="$(ls -1t "$WORK_DIR"/*.deb | head -1)"
  echo "==> extracting $deb"
  VMLINUX_PATH="$(extract_and_find_vmlinuz "$deb")"
  if [[ -z "$VMLINUX_PATH" ]]; then
    echo "error: could not find extracted /boot/vmlinuz* inside dependency package $deb" >&2
    exit 1
  fi
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
