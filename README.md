# vm-os

Ubuntu-based kernel/rootfs build scaffolding for Firecracker microVMs.

## Target
- Ubuntu **24.04 LTS (noble)** userspace
- Rootfs image: **ext4**
- Init: **systemd**
- Architectures: **x86_64** and **aarch64**
- Kernel: **Ubuntu packaged kernel** (initially)

## Repo layout
- `scripts/` build scripts
- `configs/` configuration inputs (package lists, systemd units, etc.)
- `dist/` build outputs (gitignored)

## Next steps
We will add:
- a rootfs builder (debootstrap + apt)
- a kernel fetch/prepare step (from Ubuntu packages)
- optional local Firecracker boot smoke test
