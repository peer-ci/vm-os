SHELL := /bin/bash

.PHONY: help
help:
	@echo "Targets:"
	@echo "  make rootfs ARCH=<x86_64|aarch64>"
	@echo "  make kernel ARCH=<x86_64|aarch64>"
	@echo "  make all ARCH=<x86_64|aarch64>"

.PHONY: rootfs
rootfs:
	@./scripts/build-rootfs.sh

.PHONY: kernel
kernel:
	@./scripts/fetch-kernel.sh

.PHONY: all
all: rootfs kernel
