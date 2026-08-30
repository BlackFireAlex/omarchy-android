#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
version="${1:-$(date -u +%Y%m%d)}"
output_dir="${2:-$ROOT/.work/releases}"
builder_name="${OMARCHY_RELEASE_BUILDER_NAME:-omarchy-android-release-builder}"
builder_root="${PREFIX:?Run this script from Termux}/var/lib/proot-distro/containers/$builder_name/rootfs"
builder_manifest="${builder_root%/rootfs}/manifest.json"
graphics_root="$ROOT/.work/guest-artifacts/graphics"
weston_root="$ROOT/.work/artifact-test/host-weston"
release_work="$ROOT/.work/release-$version"
patched_omarchy="$release_work/omarchy"
bundle_root="$release_work/bundle"
rootfs_archive="$bundle_root/rootfs.tar.xz"
rootfs_partial="$rootfs_archive.partial"
bundle="$output_dir/omarchy-android-aarch64-$version.bundle.tar"
packages_lock="$ROOT/manifest/packages-aarch64-$version.lock"

rootfs_archive_is_valid() {
  local members="$release_work/rootfs-members.txt"

  [[ -s "$rootfs_archive" ]] || return 1
  if ! tar -tf "$rootfs_archive" > "$members"; then
    rm -f "$members"
    return 1
  fi
  if ! grep -qxF './etc/omarchy-android-release' "$members" ||
     ! grep -qxF './opt/omarchy-android/hyprland/bin/Hyprland' "$members" ||
     ! grep -qxF './home/omarchy/.config/hypr/hyprland.lua' "$members" ||
     ! grep -qxF './usr/local/bin/uwsm-app' "$members" ||
     grep -Eq '^\./mnt/(project|forks|output|omarchy|graphics)(/|$)' "$members"; then
    rm -f "$members"
    return 1
  fi
  rm -f "$members"
}

[[ "$version" =~ ^[A-Za-z0-9._-]+$ ]] || {
  printf 'Invalid release version: %s\n' "$version" >&2
  exit 2
}
for required in \
  "$graphics_root/SHA256SUMS" \
  "$weston_root/lib/libweston-14/x11-backend.so" \
  "$packages_lock" \
  "$ROOT/licenses/weston-COPYING"; do
  [[ -f "$required" ]] || {
    printf 'Missing clean build artifact: %s\n' "$required" >&2
    exit 1
  }
done
[[ ! -e "$bundle" && ! -e "$bundle.sha256" ]] || {
  printf 'Refusing to overwrite completed release output for %s.\n' "$version" >&2
  exit 1
}

"$ROOT/scripts/validate.sh"
mkdir -p "$release_work" "$output_dir"
if [[ -d "$patched_omarchy/.git" ]]; then
  [[ -z "$(git -C "$patched_omarchy" status --porcelain=v1)" ]] || {
    printf 'Refusing dirty resumed Omarchy source: %s\n' "$patched_omarchy" >&2
    exit 1
  }
  printf 'Resuming patched Omarchy source at %s.\n' "$(git -C "$patched_omarchy" rev-parse --short=12 HEAD)"
else
  [[ ! -e "$patched_omarchy" ]] || {
    printf 'Invalid resumed Omarchy source: %s\n' "$patched_omarchy" >&2
    exit 1
  }
  "$ROOT/scripts/fetch-sources.sh" omarchy
  git clone --no-hardlinks "$ROOT/.work/upstream/omarchy" "$patched_omarchy"
  git -C "$patched_omarchy" checkout --detach "$(awk -F '|' '$1=="omarchy" {print $4}' "$ROOT/manifest/components.lock")"
  git -C "$patched_omarchy" config user.name 'Omarchy Android Builder'
  git -C "$patched_omarchy" config user.email 'builder@omarchy-android.invalid'
  git -C "$patched_omarchy" am "$ROOT"/patches/omarchy-shell/*.patch
fi

if [[ -d "$bundle_root" ]]; then
  printf 'Resuming the partial release bundle at %s.\n' "$bundle_root"
  rm -f \
    "$bundle_root/BUNDLE-MANIFEST" \
    "$bundle_root/SHA256SUMS"
elif [[ -e "$bundle_root" ]]; then
  printf 'Partial bundle path is not a directory: %s\n' "$bundle_root" >&2
  exit 1
fi

if [[ -f "$builder_root/etc/omarchy-android-release" ]] && \
   grep -q '^omarchy:' "$builder_root/etc/passwd"; then
  if ! grep -qF '"image_ref": "danhunsaker/archlinuxarm:20260517"' "$builder_manifest" ||
     ! grep -qF 'sha256:a2920b02b16de310b39f36ff28ffdfa1912bd6ea904fa7f95bd96087003eb0d7' "$builder_manifest"; then
    printf 'Assembled rootfs does not come from the locked Arch Linux ARM layer.\n' >&2
    exit 1
  fi
  printf 'Resuming the assembled release rootfs in %s.\n' "$builder_name"
else
  "$ROOT/builder/host/prepare-release-rootfs.sh"
  proot-distro login \
    --isolated \
    --bind "$ROOT:/mnt/project" \
    --bind "$patched_omarchy:/mnt/omarchy" \
    --bind "$graphics_root:/mnt/graphics" \
    "$builder_name" -- \
    /mnt/project/builder/guest/assemble-release-rootfs.sh \
      /mnt/project /mnt/omarchy /mnt/graphics
fi

# A resumed assembled builder may predate a small curated runtime fix. Refresh
# only the repository-owned Android overlay before packing, then restore the
# intended user ownership for its home-directory files.
proot-distro login --isolated \
  --bind "$ROOT:/mnt/project" \
  "$builder_name" -- \
  /bin/bash -euc '
    /mnt/project/runtime/guest/install-runtime.sh /
    chown -R 1000:1000 /home/omarchy
  '

# The explicit package list is a public release input. Refuse a rolling Arch
# repository result that differs from the closure accepted for this version.
installed_packages="$release_work/packages-aarch64-$version.actual"
expected_packages="$release_work/packages-aarch64-$version.expected"
grep -v '^[[:space:]]*#' "$packages_lock" | sed '/^[[:space:]]*$/d' > "$expected_packages"
proot-distro login --isolated "$builder_name" -- /usr/bin/pacman -Q | \
  LC_ALL=C sort > "$installed_packages"
if ! diff -u "$expected_packages" "$installed_packages"; then
  printf 'Release builder package closure differs from %s.\n' "$packages_lock" >&2
  exit 1
fi
rm -f "$expected_packages" "$installed_packages"

for forbidden_release_path in \
  "$builder_root/root/.ssh" \
  "$builder_root/root/.gnupg" \
  "$builder_root/root/.bash_history" \
  "$builder_root/home/omarchy"/.ssh \
  "$builder_root/home/omarchy"/.gnupg \
  "$builder_root/home/omarchy"/.bash_history \
  "$builder_root/home/omarchy/.config"/chromium/Default/History \
  "$builder_root/home/omarchy/.config"/chromium/Default/Cookies \
  "$builder_root/home/omarchy/.config"/chromium/Default/'Login Data' \
  "$builder_root/home/omarchy/.config"/chromium/Default/'Web Data'; do
  [[ ! -e "$forbidden_release_path" ]] || {
    printf 'Refusing sensitive release-rootfs path: %s\n' "$forbidden_release_path" >&2
    exit 1
  }
done
[[ ! -s "$builder_root/etc/machine-id" ]] || {
  printf 'Refusing nonempty release machine identity.\n' >&2
  exit 1
}
if find "$builder_root/var/cache/pacman/pkg" "$builder_root/var/log" \
    -type f -print -quit 2>/dev/null | grep -q .; then
  printf 'Refusing release rootfs with package cache or log files.\n' >&2
  exit 1
fi

mkdir -p \
  "$bundle_root/host/opt/weston/lib/libweston-14" \
  "$bundle_root/host/bin" \
  "$bundle_root/host/share/licenses/omarchy-android" \
  "$bundle_root/host/share/licenses/weston" \
  "$bundle_root/manifest"
cp "$weston_root/lib/libweston-14/x11-backend.so" \
  "$bundle_root/host/opt/weston/lib/libweston-14/x11-backend.so"
install -m 0644 "$ROOT/LICENSE" \
  "$bundle_root/host/share/licenses/omarchy-android/LICENSE"
install -m 0644 "$ROOT/licenses/weston-COPYING" \
  "$bundle_root/host/share/licenses/weston/COPYING"
install -m 0644 "$packages_lock" \
  "$bundle_root/manifest/$(basename -- "$packages_lock")"
"$ROOT/runtime/host/build-helpers.sh" "$bundle_root/host/bin"

if rootfs_archive_is_valid; then
  printf 'Reusing the validated rootfs archive.\n'
else
  rm -f "$rootfs_archive" "$rootfs_partial"
  printf 'Packing clean rootfs (this is the slow, compression-heavy step)...\n'
  # PRoot represents guest hard links as private absolute symlinks in the host
  # rootfs. Archiving that directory from Termux would leak the disposable
  # builder path into the release and make linked executables fail after the
  # builder is removed. Run tar through PRoot so it sees normal guest inodes
  # and hard links, while excluding PRoot's private bookkeeping directory.
  proot-distro login --isolated \
    --bind "$bundle_root:/mnt/output" \
    "$builder_name" -- \
    env XZ_OPT='-T1 -3' tar \
      --numeric-owner \
      --xattrs \
      --exclude='./.l2s' \
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
      -C / \
      -cJf /mnt/output/rootfs.tar.xz.partial .
  mv "$rootfs_partial" "$rootfs_archive"
  rootfs_archive_is_valid || {
    printf 'The newly packed rootfs failed validation.\n' >&2
    exit 1
  }
fi

cat > "$bundle_root/BUNDLE-MANIFEST" <<EOF
format=1
version=$version
architecture=aarch64
rootfs=rootfs.tar.xz
components_lock_sha256=$(sha256sum "$ROOT/manifest/components.lock" | awk '{print $1}')
patches_lock_sha256=$(sha256sum "$ROOT/manifest/patches.lock" | awk '{print $1}')
packages_lock_sha256=$(sha256sum "$packages_lock" | awk '{print $1}')
EOF
(
  cd "$bundle_root"
  checksum_file="$(mktemp)"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > "$checksum_file"
  mv "$checksum_file" SHA256SUMS
  sha256sum -c SHA256SUMS
)
tar -C "$bundle_root" -cf "$bundle" .
(
  cd "$output_dir"
  bundle_name="$(basename -- "$bundle")"
  sha256sum "$bundle_name" > "$bundle_name.sha256"
)
chmod 0644 "$bundle" "$bundle.sha256"

printf 'Release bundle: %s\n' "$bundle"
printf 'Release checksum: %s\n' "$bundle.sha256"
