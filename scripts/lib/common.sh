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
