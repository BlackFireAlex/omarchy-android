#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
forks_root="${1:-${OMARCHY_FORKS_ROOT:-$ROOT/../omarchy-android-forks}}"
artifact_root="${2:-$ROOT/.work/guest-artifacts/graphics}"
builder_name="${OMARCHY_BUILDER_NAME:-omarchy-android-builder}"

for path in "$forks_root" "$artifact_root"; do
  [[ "$path" == /* ]] || {
    printf 'All paths must be absolute: %s\n' "$path" >&2
    exit 2
  }
done
[[ ! -e "$artifact_root" ]] || {
  printf 'Refusing to overwrite artifact root: %s\n' "$artifact_root" >&2
  exit 1
}
for component in mesa aquamarine hyprland; do
  [[ -d "$forks_root/$component/.git" ]] || {
    printf 'Missing local fork: %s\n' "$forks_root/$component" >&2
    exit 1
  }
done

artifact_parent="$(dirname -- "$artifact_root")"
artifact_name="$(basename -- "$artifact_root")"
mkdir -p "$artifact_parent"

proot-distro login \
  --isolated \
  --bind "$ROOT:/mnt/project" \
  --bind "$forks_root:/mnt/forks" \
  --bind "$artifact_parent:/mnt/output" \
  "$builder_name" -- \
  /mnt/project/builder/guest/build-from-local-forks.sh \
    /mnt/project /mnt/forks "/mnt/output/$artifact_name"

printf 'Guest graphics artifacts are available at %s\n' "$artifact_root"
