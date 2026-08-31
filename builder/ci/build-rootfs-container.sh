#!/usr/bin/env bash

set -Eeuo pipefail

project_root="${1:-/mnt/project}"
version="${2:-edge}"
work_root="${3:-/mnt/project/.work/ci-image-$version}"
omarchy_source="$work_root/omarchy"
graphics_root="$work_root/graphics"
output_root="$work_root/output"
build_packages="$project_root/builder/guest/packages.txt"
runtime_packages="$project_root/builder/guest/runtime-packages.txt"
home=/home/omarchy

[[ $EUID == 0 ]] || {
  printf 'The CI image builder must run as root in its disposable container.\n' >&2
  exit 1
}
[[ "$(uname -m)" == aarch64 ]] || {
  printf 'The CI image builder requires native ARM64.\n' >&2
  exit 1
}
# The third-party Arch Linux ARM OCI config is mislabeled amd64. Do not trust
# that metadata: e_machine at ELF offset 18 must be 0x00b7 (AArch64) before we
# execute a compiler or publish an image.
bash_machine="$(od -An -tx1 -j18 -N2 /usr/bin/bash | tr -d '[:space:]')"
[[ "$bash_machine" == b700 ]] || {
  printf 'The locked builder rootfs is not AArch64 (ELF machine bytes: %s).\n' \
    "$bash_machine" >&2
  exit 1
}
[[ "$version" =~ ^[A-Za-z0-9._-]+$ ]] || {
  printf 'Invalid image version: %s\n' "$version" >&2
  exit 2
}
for path in "$project_root" "$work_root" "$omarchy_source"; do
  [[ "$path" == /* ]] || {
    printf 'All paths must be absolute: %s\n' "$path" >&2
    exit 2
  }
done
[[ -f "$omarchy_source/shell/shell.qml" ]] || {
  printf 'Patched Omarchy source is missing: %s\n' "$omarchy_source" >&2
  exit 1
}
[[ ! -e "$graphics_root" && ! -e "$output_root" ]] || {
  printf 'Refusing to reuse CI image output under %s\n' "$work_root" >&2
  exit 1
}

pacman_conf=/etc/pacman.conf
if grep -q '^ParallelDownloads' "$pacman_conf"; then
  sed -i 's/^ParallelDownloads.*/ParallelDownloads = 4/' "$pacman_conf"
else
  sed -i '/^\[options\]$/a ParallelDownloads = 4' "$pacman_conf"
fi
if grep -q '^DownloadUser' "$pacman_conf"; then
  sed -i 's/^DownloadUser.*/DownloadUser = root/' "$pacman_conf"
else
  sed -i '/^\[options\]$/a DownloadUser = root' "$pacman_conf"
fi
# Pacman 7's own Landlock/seccomp download sandbox cannot nest inside Docker.
# Disable only those inner restrictions; the entire builder remains confined
# to a disposable GitHub-hosted container.
sed -i \
  -e '/^DisableSandboxFilesystem$/d' \
  -e '/^DisableSandboxSyscalls$/d' \
  "$pacman_conf"
sed -i \
  -e '/^\[options\]$/a DisableSandboxSyscalls' \
  -e '/^\[options\]$/a DisableSandboxFilesystem' \
  "$pacman_conf"

mapfile -t build_roots < <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$build_packages")
mapfile -t runtime_roots < <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$runtime_packages")
(( ${#build_roots[@]} > 0 && ${#runtime_roots[@]} > 0 )) || {
  printf 'A package root manifest is empty.\n' >&2
  exit 1
}

printf 'Updating the disposable Arch Linux ARM container...\n'
pacman -Syu --noconfirm
pacman -S --needed --noconfirm "${build_roots[@]}" "${runtime_roots[@]}"

# The checked-out sources are owned by GitHub's runner UID and mounted
# read-only in practice, while this disposable build container runs as root.
# Trust only the three pinned repositories consumed by the graphics builder.
for component in mesa aquamarine hyprland; do
  git config --global --add safe.directory "$project_root/.work/upstream/$component"
  git config --global --add safe.directory "$project_root/.work/upstream/$component/.git"
done

OMARCHY_BUILD_JOBS="${OMARCHY_BUILD_JOBS:-4}" \
  "$project_root/builder/guest/build-from-local-forks.sh" \
    "$project_root" \
    "$project_root/.work/upstream" \
    "$graphics_root" \
    /var/tmp/omarchy-android-sources \
    /var/tmp/omarchy-android-build

"$project_root/builder/guest/prune-release-packages.sh" "$runtime_packages"
"$project_root/builder/guest/assemble-release-rootfs.sh" \
  "$project_root" "$omarchy_source" "$graphics_root"

mkdir -p "$output_root"
package_inventory="$output_root/packages-aarch64-$version.lock"
pacman -Q | LC_ALL=C sort > "$package_inventory"

if [[ -n "${OMARCHY_PACKAGES_LOCK:-}" ]]; then
  [[ "$OMARCHY_PACKAGES_LOCK" == /* && -f "$OMARCHY_PACKAGES_LOCK" ]] || {
    printf 'OMARCHY_PACKAGES_LOCK is not an absolute file: %s\n' "$OMARCHY_PACKAGES_LOCK" >&2
    exit 2
  }
  diff -u "$OMARCHY_PACKAGES_LOCK" "$package_inventory"
fi

# Enforce the same privacy boundary as the phone release builder before any
# rootfs bytes leave the ephemeral runner.
for forbidden_path in \
  /root/.ssh \
  /root/.gnupg \
  /root/.bash_history \
  "$home"/.ssh \
  "$home"/.gnupg \
  "$home"/.bash_history \
  "$home/.config"/chromium/Default/History \
  "$home/.config"/chromium/Default/Cookies \
  "$home/.config"/chromium/Default/'Login Data' \
  "$home/.config"/chromium/Default/'Web Data'; do
  [[ ! -e "$forbidden_path" ]] || {
    printf 'Refusing sensitive image path: %s\n' "$forbidden_path" >&2
    exit 1
  }
done
[[ ! -s /etc/machine-id ]] || {
  printf 'Refusing a nonempty image machine identity.\n' >&2
  exit 1
}
if find /var/cache/pacman/pkg /var/log -type f -print -quit 2>/dev/null | grep -q .; then
  printf 'Refusing image with package cache or log files.\n' >&2
  exit 1
fi

rootfs="$output_root/omarchy-android-rootfs-aarch64-$version.tar.xz"
printf 'Packing sanitized ARM64 rootfs...\n'
XZ_OPT='-T1 -3' tar \
  --numeric-owner \
  --xattrs \
  --exclude='./mnt' \
  --exclude='./mnt/*' \
  --exclude='./proc' \
  --exclude='./proc/*' \
  --exclude='./sys' \
  --exclude='./sys/*' \
  --exclude='./dev' \
  --exclude='./dev/*' \
  --exclude='./run' \
  --exclude='./run/*' \
  --exclude='./var/tmp' \
  --exclude='./var/tmp/*' \
  --exclude='./etc/hostname' \
  --exclude='./etc/hosts' \
  --exclude='./etc/resolv.conf' \
  -C / -cJf "$rootfs" .

members="$output_root/rootfs-members.txt"
tar -tf "$rootfs" > "$members"
for required_member in \
  ./etc/omarchy-android-release \
  ./opt/omarchy-android/hyprland/bin/Hyprland \
  ./home/omarchy/.config/hypr/hyprland.lua \
  ./home/omarchy/.config/omarchy/proot-session-bus.conf \
  ./usr/local/bin/omarchy-dbus-service \
  ./usr/local/bin/omarchy-voxtype-daemon \
  ./usr/local/bin/voxtype; do
  grep -qxF "$required_member" "$members" || {
    printf 'Packed rootfs is missing %s\n' "$required_member" >&2
    exit 1
  }
done
if grep -Eq '^\./mnt(/|$)' "$members"; then
  printf 'Packed rootfs contains a disposable build mount.\n' >&2
  exit 1
fi

cat > "$output_root/IMAGE-MANIFEST" <<EOF
format=1
version=$version
architecture=aarch64
rootfs=$(basename -- "$rootfs")
components_lock_sha256=$(sha256sum "$project_root/manifest/components.lock" | awk '{print $1}')
patches_lock_sha256=$(sha256sum "$project_root/manifest/patches.lock" | awk '{print $1}')
artifacts_lock_sha256=$(sha256sum "$project_root/manifest/artifacts.lock" | awk '{print $1}')
packages_lock_sha256=$(sha256sum "$package_inventory" | awk '{print $1}')
EOF

(
  cd "$output_root"
  sha256sum \
    "$(basename -- "$rootfs")" \
    "$(basename -- "$package_inventory")" \
    IMAGE-MANIFEST > SHA256SUMS
  sha256sum -c SHA256SUMS
)

printf 'ARM64 image artifacts are ready under %s\n' "$output_root"
