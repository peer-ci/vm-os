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

## Rootfs build (ext4)

The rootfs builder uses `debootstrap` and requires root privileges.

```bash
sudo ARCH=x86_64 make rootfs
sudo ARCH=aarch64 make rootfs
```

Outputs:
- `dist/amd64/rootfs.ext4`
- `dist/arm64/rootfs.ext4`

## Next steps
We will add:
- a kernel fetch/prepare step (from Ubuntu packages)
- optional local Firecracker boot smoke test
