#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
version="${1:?usage: assemble-bundle.sh VERSION IMAGE_OUTPUT RELEASE_OUTPUT}"
image_output="${2:?usage: assemble-bundle.sh VERSION IMAGE_OUTPUT RELEASE_OUTPUT}"
release_output="${3:?usage: assemble-bundle.sh VERSION IMAGE_OUTPUT RELEASE_OUTPUT}"

[[ "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] || {
  printf 'Release bundle version must be semantic X.Y.Z: %s\n' "$version" >&2
  exit 2
}
for path in "$image_output" "$release_output"; do
  [[ "$path" == /* ]] || {
    printf 'Bundle paths must be absolute: %s\n' "$path" >&2
    exit 2
  }
done
[[ -d "$image_output" ]] || {
  printf 'ARM64 image output is missing: %s\n' "$image_output" >&2
  exit 1
}
for command_name in curl tar sha256sum awk od readelf; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'Missing release-assembly command: %s\n' "$command_name" >&2
    exit 1
  }
done

"$ROOT/scripts/validate.sh"
(
  cd "$image_output"
  sha256sum -c SHA256SUMS
)

image_manifest="$image_output/IMAGE-MANIFEST"
[[ "$(awk -F= '$1=="version" {print $2}' "$image_manifest")" == "$version" ]] || {
  printf 'Image manifest version does not match %s.\n' "$version" >&2
  exit 1
}
[[ "$(awk -F= '$1=="architecture" {print $2}' "$image_manifest")" == aarch64 ]] || {
  printf 'Image manifest is not AArch64.\n' >&2
  exit 1
}
rootfs_name="$(awk -F= '$1=="rootfs" {print $2}' "$image_manifest")"
[[ "$rootfs_name" == "omarchy-android-rootfs-aarch64-$version.tar.xz" ]] || {
  printf 'Unexpected rootfs name in image manifest: %s\n' "$rootfs_name" >&2
  exit 1
}
rootfs="$image_output/$rootfs_name"
packages="$image_output/packages-aarch64-$version.lock"
[[ -f "$rootfs" && -f "$packages" ]] || {
  printf 'Image output is incomplete.\n' >&2
  exit 1
}

host_record="$(awk -F '|' '$1=="android-host" {print; found=1; exit} END {if (!found) exit 1}' \
  "$ROOT/manifest/host-artifacts.lock")"
IFS='|' read -r host_name host_version host_url host_sha256 source_bundle_sha256 <<<"$host_record"
[[ "$host_name" == android-host && "$host_version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ &&
   "$host_url" == https://* && "$host_sha256" =~ ^[0-9a-f]{64}$ &&
   "$source_bundle_sha256" =~ ^[0-9a-f]{64}$ ]] || {
  printf 'Invalid pinned Android host artifact.\n' >&2
  exit 1
}

work_root="$ROOT/.work/ci-bundle-$version"
bundle_root="$work_root/bundle"
host_root="$work_root/host-bootstrap"
[[ ! -e "$work_root" ]] || {
  printf 'Refusing to replace release work: %s\n' "$work_root" >&2
  exit 1
}
mkdir -p "$host_root" "$bundle_root" "$release_output"
host_archive="$work_root/${host_url##*/}"
curl --fail --location --retry 3 --output "$host_archive" "$host_url"
actual_host_sha256="$(sha256sum "$host_archive")"
actual_host_sha256="${actual_host_sha256%% *}"
[[ "$actual_host_sha256" == "$host_sha256" ]] || {
  printf 'Android host artifact checksum mismatch.\n' >&2
  exit 1
}
while IFS= read -r member; do
  case "$member" in
    /*|../*|*/../*|*/..) printf 'Unsafe Android host member: %s\n' "$member" >&2; exit 1 ;;
  esac
done < <(tar -tf "$host_archive")
tar -xf "$host_archive" -C "$host_root"
(
  cd "$host_root"
  sha256sum -c SHA256SUMS
)

[[ "$(awk -F= '$1=="format" {print $2}' "$host_root/HOST-MANIFEST")" == 1 &&
   "$(awk -F= '$1=="version" {print $2}' "$host_root/HOST-MANIFEST")" == "$host_version" &&
   "$(awk -F= '$1=="architecture" {print $2}' "$host_root/HOST-MANIFEST")" == aarch64 &&
   "$(awk -F= '$1=="source_bundle_sha256" {print $2}' "$host_root/HOST-MANIFEST")" == "$source_bundle_sha256" ]] || {
  printf 'Android host manifest does not match its lock.\n' >&2
  exit 1
}

expected_host_files="$work_root/expected-host-files"
actual_host_files="$work_root/actual-host-files"
cat > "$expected_host_files" <<'EOF'
HOST-MANIFEST
SHA256SUMS
host/bin/omarchy-process-guard
host/bin/omarchy-x11-keyboard
host/opt/weston/lib/libweston-14/x11-backend.so
host/share/licenses/omarchy-android/LICENSE
host/share/licenses/weston/COPYING
EOF
find "$host_root" -type f -printf '%P\n' | LC_ALL=C sort > "$actual_host_files"
LC_ALL=C sort -o "$expected_host_files" "$expected_host_files"
cmp "$expected_host_files" "$actual_host_files"

for elf in \
  "$host_root/host/bin/omarchy-process-guard" \
  "$host_root/host/bin/omarchy-x11-keyboard" \
  "$host_root/host/opt/weston/lib/libweston-14/x11-backend.so"; do
  machine="$(od -An -tx1 -j18 -N2 "$elf" | tr -d '[:space:]')"
  [[ "$machine" == b700 ]] || {
    printf 'Release host artifact is not AArch64: %s\n' "$elf" >&2
    exit 1
  }
done
for executable in \
  "$host_root/host/bin/omarchy-process-guard" \
  "$host_root/host/bin/omarchy-x11-keyboard"; do
  program_headers="$(readelf -l "$executable")"
  grep -q '/system/bin/linker64' <<<"$program_headers" || {
    printf 'Release helper is not Android/Bionic: %s\n' "$executable" >&2
    exit 1
  }
done

cp -a "$host_root/host" "$bundle_root/host"
cp --reflink=auto "$rootfs" "$bundle_root/rootfs.tar.xz"
install -D -m 0644 "$packages" "$bundle_root/manifest/$(basename -- "$packages")"

components_lock_sha256="$(sha256sum "$ROOT/manifest/components.lock")"
components_lock_sha256="${components_lock_sha256%% *}"
patches_lock_sha256="$(sha256sum "$ROOT/manifest/patches.lock")"
patches_lock_sha256="${patches_lock_sha256%% *}"
artifacts_lock_sha256="$(sha256sum "$ROOT/manifest/artifacts.lock")"
artifacts_lock_sha256="${artifacts_lock_sha256%% *}"
packages_lock_sha256="$(sha256sum "$packages")"
packages_lock_sha256="${packages_lock_sha256%% *}"
cat > "$bundle_root/BUNDLE-MANIFEST" <<EOF
format=1
version=$version
architecture=aarch64
rootfs=rootfs.tar.xz
components_lock_sha256=$components_lock_sha256
patches_lock_sha256=$patches_lock_sha256
artifacts_lock_sha256=$artifacts_lock_sha256
packages_lock_sha256=$packages_lock_sha256
host_artifact_sha256=$host_sha256
host_source_bundle_sha256=$source_bundle_sha256
EOF
chmod 0644 "$bundle_root/BUNDLE-MANIFEST"

(
  cd "$bundle_root"
  find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$work_root/bundle-checksums"
  mv "$work_root/bundle-checksums" SHA256SUMS
  chmod 0644 SHA256SUMS
  sha256sum -c SHA256SUMS
)

asset="omarchy-android-aarch64-$version.bundle.tar"
bundle="$release_output/$asset"
[[ ! -e "$bundle" && ! -e "$bundle.sha256" ]] || {
  printf 'Refusing to replace release output: %s\n' "$bundle" >&2
  exit 1
}
partial="$bundle.partial"
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$bundle_root" -cf "$partial" .
mv "$partial" "$bundle"
(
  cd "$release_output"
  sha256sum "$asset" > "$asset.sha256"
  sha256sum -c "$asset.sha256"
)
chmod 0644 "$bundle" "$bundle.sha256"

printf 'Complete release bundle: %s\n' "$bundle"
printf 'Release checksum:        %s\n' "$bundle.sha256"
