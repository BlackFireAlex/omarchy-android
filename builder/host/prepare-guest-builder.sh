#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
builder_name="${OMARCHY_BUILDER_NAME:-omarchy-android-builder}"
builder_image=danhunsaker/archlinuxarm:20260517
container_root="${PREFIX:?Run this script from Termux}/var/lib/proot-distro/containers/$builder_name/rootfs"
container_manifest="${container_root%/rootfs}/manifest.json"
packages_file="$ROOT/builder/guest/packages.txt"
base_layer_digest=a2920b02b16de310b39f36ff28ffdfa1912bd6ea904fa7f95bd96087003eb0d7

command -v proot-distro >/dev/null || {
  printf 'Missing proot-distro. Install it with: pkg install proot-distro\n' >&2
  exit 1
}
[[ "$(uname -m)" == aarch64 ]] || {
  printf 'The clean builder currently supports native ARM64 Android only.\n' >&2
  exit 1
}

if [[ ! -d "$container_root" ]]; then
  printf 'Creating disposable Arch Linux ARM builder %s...\n' "$builder_name"
  proot-distro install --name "$builder_name" --architecture aarch64 "$builder_image"
else
  printf 'Reusing existing builder %s.\n' "$builder_name"
fi

if ! grep -qF '"image_ref": "danhunsaker/archlinuxarm:20260517"' "$container_manifest" ||
   ! grep -qF "sha256:$base_layer_digest" "$container_manifest"; then
    printf 'Builder base image does not match the locked Arch Linux ARM layer.\n' >&2
    exit 1
fi

pacman_conf="$container_root/etc/pacman.conf"
[[ -f "$pacman_conf" ]] || {
  printf 'Builder has no pacman.conf: %s\n' "$pacman_conf" >&2
  exit 1
}

# Pacman 7 download isolation depends on kernel features unavailable through
# PRoot. Limit concurrency and disable only those nested pacman sandboxes; the
# entire builder remains isolated by PRoot and is disposable.
if grep -q '^ParallelDownloads' "$pacman_conf"; then
  sed -i 's/^ParallelDownloads.*/ParallelDownloads = 1/' "$pacman_conf"
else
  printf '\nParallelDownloads = 1\n' >>"$pacman_conf"
fi
if grep -q '^DownloadUser' "$pacman_conf"; then
  sed -i 's/^DownloadUser.*/DownloadUser = root/' "$pacman_conf"
else
  printf 'DownloadUser = root\n' >>"$pacman_conf"
fi
grep -qxF 'DisableSandboxFilesystem' "$pacman_conf" || printf 'DisableSandboxFilesystem\n' >>"$pacman_conf"
grep -qxF 'DisableSandboxSyscalls' "$pacman_conf" || printf 'DisableSandboxSyscalls\n' >>"$pacman_conf"

printf 'Updating the disposable builder...\n'
proot-distro login "$builder_name" -- pacman -Syu --noconfirm

mapfile -t packages < <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$packages_file")
(( ${#packages[@]} > 0 )) || {
  printf 'Empty package manifest: %s\n' "$packages_file" >&2
  exit 1
}

printf 'Installing %d pinned build dependency names...\n' "${#packages[@]}"
proot-distro login "$builder_name" -- pacman -S --needed --noconfirm "${packages[@]}"
printf 'Builder %s is ready.\n' "$builder_name"
