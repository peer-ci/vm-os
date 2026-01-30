#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ARCH_IN="${ARCH:-x86_64}"
ARCH="$(arch_normalize "$ARCH_IN")"

ROOT="$(repo_root)"
DIST_DIR="$ROOT/dist/$ARCH"

mkdir -p "$DIST_DIR"

cat >"$DIST_DIR/ROOTFS-TODO.txt" <<EOF
Rootfs build scaffold.

Decisions locked in:
- Ubuntu: 24.04 (noble)
- Init: systemd
- Rootfs: ext4
- Arch: $ARCH

Next: implement debootstrap + apt + systemd config and emit $DIST_DIR/rootfs.ext4
EOF

echo "Wrote $DIST_DIR/ROOTFS-TODO.txt"
