#!/usr/bin/env bash
# Install build dependencies. Needs sudo (the user types the password).
set -euo pipefail
sudo dnf -y builddep mesa m1n1
sudo dnf -y install \
	gcc make flex bison bc perl rsync kmod cpio dwarves \
	elfutils-libelf-devel openssl-devel \
	rust cargo rust-src bindgen-cli clang clang-devel llvm llvm-devel lld \
	rust-std-static-aarch64-unknown-none-softfloat \
	meson ninja-build python3-mako python3-pyyaml python3-ply python3-packaging \
	libclc-devel spirv-llvm-translator-devel spirv-tools-devel glslang \
	libdrm-devel wayland-devel wayland-protocols-devel \
	vulkan-tools mesa-demos
echo DEPS_DONE
