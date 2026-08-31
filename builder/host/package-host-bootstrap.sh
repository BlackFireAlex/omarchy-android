#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source_bundle="${1:?usage: package-host-bootstrap.sh SOURCE_BUNDLE OUTPUT_DIR VERSION SOURCE_SHA256}"
output_dir="${2:?usage: package-host-bootstrap.sh SOURCE_BUNDLE OUTPUT_DIR VERSION SOURCE_SHA256}"
version="${3:?usage: package-host-bootstrap.sh SOURCE_BUNDLE OUTPUT_DIR VERSION SOURCE_SHA256}"
source_sha256="${4:?usage: package-host-bootstrap.sh SOURCE_BUNDLE OUTPUT_DIR VERSION SOURCE_SHA256}"

[[ "$source_bundle" == /* && -f "$source_bundle" ]] || {
  printf 'Source bundle must be an absolute regular file.\n' >&2
  exit 2
}
[[ "$output_dir" == /* && "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ &&
   "$source_sha256" =~ ^[0-9a-f]{64}$ ]] || {
  printf 'Invalid output path, version, or source checksum.\n' >&2
  exit 2
}
for command_name in tar sha256sum awk od readelf; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'Missing host-bootstrap command: %s\n' "$command_name" >&2
    exit 1
  }
done

actual_source_sha256="$(sha256sum "$source_bundle")"
actual_source_sha256="${actual_source_sha256%% *}"
[[ "$actual_source_sha256" == "$source_sha256" ]] || {
  printf 'Source release checksum mismatch.\n' >&2
  exit 1
}

asset="omarchy-android-host-aarch64-$version.tar.xz"
output="$output_dir/$asset"
[[ ! -e "$output" && ! -e "$output.sha256" ]] || {
  printf 'Refusing to replace an existing host-bootstrap artifact.\n' >&2
  exit 1
}
mkdir -p "$output_dir"

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-host-bootstrap.XXXXXX")"
cleanup() {
  if [[ "$temporary_root" == "${TMPDIR:-/tmp}"/omarchy-host-bootstrap.* && -d "$temporary_root" ]]; then
    find "$temporary_root" -depth -delete
  fi
}
trap cleanup EXIT
payload_root="$temporary_root/payload"
mkdir -p "$payload_root"

while IFS= read -r member; do
  case "$member" in
    /*|../*|*/../*|*/..) printf 'Unsafe source-bundle member: %s\n' "$member" >&2; exit 1 ;;
  esac
done < <(tar -tf "$source_bundle")

host_files=(
  ./host/bin/omarchy-process-guard
  ./host/bin/omarchy-x11-keyboard
  ./host/opt/weston/lib/libweston-14/x11-backend.so
  ./host/share/licenses/omarchy-android/LICENSE
  ./host/share/licenses/weston/COPYING
)
tar -xf "$source_bundle" -C "$payload_root" \
  ./BUNDLE-MANIFEST ./SHA256SUMS "${host_files[@]}"

# The first Termux-built release used the application's private umask in its
# outer tar metadata. Normalize only permissions here; file bytes must still
# verify against that release before they become the reusable CI input.
find "$payload_root" -type d -exec chmod 0755 {} +
chmod 0755 \
  "$payload_root/host/bin/omarchy-process-guard" \
  "$payload_root/host/bin/omarchy-x11-keyboard" \
  "$payload_root/host/opt/weston/lib/libweston-14/x11-backend.so"
chmod 0644 \
  "$payload_root/host/share/licenses/omarchy-android/LICENSE" \
  "$payload_root/host/share/licenses/weston/COPYING" \
  "$payload_root/BUNDLE-MANIFEST" \
  "$payload_root/SHA256SUMS"

source_checksums="$temporary_root/source-checksums"
: > "$source_checksums"
for host_file in "${host_files[@]}"; do
  awk -v path="$host_file" '$2 == path { print; found=1; exit } END { if (!found) exit 1 }' \
    "$payload_root/SHA256SUMS" >> "$source_checksums"
done
(
  cd "$payload_root"
  sha256sum -c "$source_checksums"
)

expected_files="$temporary_root/expected-files"
actual_files="$temporary_root/actual-files"
printf '%s\n' "${host_files[@]}" | sed 's#^\./##' | LC_ALL=C sort > "$expected_files"
find "$payload_root/host" -type f -printf '%P\n' | sed 's#^#host/#' | LC_ALL=C sort > "$actual_files"
cmp "$expected_files" "$actual_files"

for elf in \
  "$payload_root/host/bin/omarchy-process-guard" \
  "$payload_root/host/bin/omarchy-x11-keyboard" \
  "$payload_root/host/opt/weston/lib/libweston-14/x11-backend.so"; do
  machine="$(od -An -tx1 -j18 -N2 "$elf" | tr -d '[:space:]')"
  [[ "$machine" == b700 ]] || {
    printf 'Host artifact is not AArch64: %s\n' "$elf" >&2
    exit 1
  }
done
for executable in \
  "$payload_root/host/bin/omarchy-process-guard" \
  "$payload_root/host/bin/omarchy-x11-keyboard"; do
  program_headers="$(readelf -l "$executable")"
  grep -q '/system/bin/linker64' <<<"$program_headers" || {
    printf 'Host helper does not target Android/Bionic: %s\n' "$executable" >&2
    exit 1
  }
done

source_manifest_sha256="$(sha256sum "$payload_root/BUNDLE-MANIFEST")"
source_manifest_sha256="${source_manifest_sha256%% *}"
patches_lock_sha256="$(sha256sum "$ROOT/manifest/patches.lock")"
patches_lock_sha256="${patches_lock_sha256%% *}"
cat > "$payload_root/HOST-MANIFEST" <<EOF
format=1
version=$version
architecture=aarch64
source_bundle_sha256=$source_sha256
source_bundle_manifest_sha256=$source_manifest_sha256
patches_lock_sha256=$patches_lock_sha256
EOF
rm "$payload_root/BUNDLE-MANIFEST" "$payload_root/SHA256SUMS"
chmod 0644 "$payload_root/HOST-MANIFEST"

(
  cd "$payload_root"
  find ./host -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS
  sha256sum HOST-MANIFEST >> SHA256SUMS
  chmod 0644 SHA256SUMS
  sha256sum -c SHA256SUMS
)

partial="$output.partial"
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$payload_root" -cJf "$partial" .
mv "$partial" "$output"
(
  cd "$output_dir"
  sha256sum "$asset" > "$asset.sha256"
)
chmod 0644 "$output" "$output.sha256"

printf 'Host bootstrap: %s\n' "$output"
printf 'Host checksum:  %s\n' "$output.sha256"
