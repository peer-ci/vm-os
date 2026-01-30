#!/usr/bin/env bash
set -euo pipefail

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing required command: $1" >&2
    exit 1
  }
}

arch_normalize() {
  case "${1:-}" in
    x86_64|amd64) echo "amd64";;
    aarch64|arm64) echo "arm64";;
    *) echo "error: unsupported ARCH '$1' (use x86_64 or aarch64)" >&2; exit 2;;
  esac
}

qemu_static_binary() {
  case "${1:-}" in
    amd64) echo "";;
    arm64) echo "qemu-aarch64-static";;
    *) echo "error: unsupported arch '$1'" >&2; exit 2;;
  esac
}

must_be_root_or_sudo() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "error: this script needs root privileges (run via sudo)" >&2
    exit 1
  fi
}
