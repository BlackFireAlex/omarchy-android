#!/usr/bin/env bash

set -Eeuo pipefail

project_root="${1:-/mnt/project}"
target_root="${2:-/}"
artifacts_lock="$project_root/manifest/artifacts.lock"

[[ $EUID == 0 ]] || {
  printf 'Binary artifact installation must run as root.\n' >&2
  exit 1
}
for path in "$project_root" "$target_root"; do
  [[ "$path" == /* ]] || {
    printf 'All paths must be absolute: %s\n' "$path" >&2
    exit 2
  }
done
[[ -f "$artifacts_lock" ]] || {
  printf 'Artifact lock is missing: %s\n' "$artifacts_lock" >&2
  exit 1
}

record="$(awk -F '|' '$1 == "voxtype" { print; found=1; exit } END { if (!found) exit 1 }' "$artifacts_lock")"
IFS='|' read -r name version url expected_sha256 license <<<"$record"
[[ "$name" == voxtype && "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ &&
   "$expected_sha256" =~ ^[0-9a-f]{64}$ && "$license" == MIT ]] || {
  printf 'Invalid locked Voxtype artifact record.\n' >&2
  exit 1
}

download="$(mktemp)"
cleanup() {
  rm -f -- "$download"
}
trap cleanup EXIT

curl --fail --location --retry 3 --output "$download" "$url"
actual_sha256="$(sha256sum "$download" | awk '{print $1}')"
[[ "$actual_sha256" == "$expected_sha256" ]] || {
  printf 'Voxtype checksum mismatch: expected %s, got %s\n' \
    "$expected_sha256" "$actual_sha256" >&2
  exit 1
}

install -D -m 0755 "$download" "$target_root/usr/local/bin/voxtype"
install -D -m 0644 "$project_root/licenses/voxtype-LICENSE" \
  "$target_root/usr/share/licenses/voxtype/LICENSE"
"$target_root/usr/local/bin/voxtype" --version | grep -qxF "voxtype $version"

printf 'Installed checksum-verified Voxtype %s for ARM64.\n' "$version"
