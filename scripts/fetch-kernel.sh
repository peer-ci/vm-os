#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ARCH_IN="${ARCH:-x86_64}"
ARCH="$(arch_normalize "$ARCH_IN")"

ROOT="$(repo_root)"
DIST_DIR="$ROOT/dist/$ARCH"

mkdir -p "$DIST_DIR"

cat >"$DIST_DIR/KERNEL-TODO.txt" <<EOF
Kernel fetch scaffold.

Strategy: consume Ubuntu packaged kernel.

Next: download linux-image / vmlinuz for $ARCH, extract a Firecracker-compatible kernel image.
EOF

echo "Wrote $DIST_DIR/KERNEL-TODO.txt"
