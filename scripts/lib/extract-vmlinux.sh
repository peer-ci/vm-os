#!/usr/bin/env bash
# Extract the uncompressed kernel (vmlinux) from a Linux boot image (vmlinuz).
# Works for x86_64 Ubuntu vmlinuz images that contain a compressed ELF payload.
set -euo pipefail

VMLINUX_IN="${1:-}"
if [[ -z "$VMLINUX_IN" || ! -f "$VMLINUX_IN" ]]; then
  echo "usage: $0 /path/to/vmlinuz" >&2
  exit 2
fi

# Search for common compression signatures inside the boot image and decompress.
# Prefer xz, then gzip, then bzip2, then lz4.
# (This is intentionally small and dependency-light; it may need tuning for some kernels.)

# shellcheck disable=SC2002
if grep -a -m1 -obUaP "\xFD7zXZ\x00" "$VMLINUX_IN" >/dev/null; then
  off=$(grep -a -m1 -obUaP "\xFD7zXZ\x00" "$VMLINUX_IN" | cut -d: -f1)
  tail -c +$((off+1)) "$VMLINUX_IN" | xz -dc
elif grep -a -m1 -obUaP "\x1F\x8B\x08" "$VMLINUX_IN" >/dev/null; then
  off=$(grep -a -m1 -obUaP "\x1F\x8B\x08" "$VMLINUX_IN" | cut -d: -f1)
  tail -c +$((off+1)) "$VMLINUX_IN" | gzip -dc
elif grep -a -m1 -obUaP "BZh" "$VMLINUX_IN" >/dev/null; then
  off=$(grep -a -m1 -obUaP "BZh" "$VMLINUX_IN" | cut -d: -f1)
  tail -c +$((off+1)) "$VMLINUX_IN" | bzip2 -dc
elif grep -a -m1 -obUaP "\x04\x22\x4D\x18" "$VMLINUX_IN" >/dev/null; then
  off=$(grep -a -m1 -obUaP "\x04\x22\x4D\x18" "$VMLINUX_IN" | cut -d: -f1)
  tail -c +$((off+1)) "$VMLINUX_IN" | lz4 -dc
else
  echo "error: could not find a known compressed payload in $VMLINUX_IN" >&2
  exit 1
fi
