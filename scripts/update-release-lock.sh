#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
version="${1:?usage: update-release-lock.sh VERSION REPOSITORY SHA256}"
repository="${2:?usage: update-release-lock.sh VERSION REPOSITORY SHA256}"
bundle_sha256="${3:?usage: update-release-lock.sh VERSION REPOSITORY SHA256}"

[[ "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ &&
   "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ &&
   "$bundle_sha256" =~ ^[0-9a-f]{64}$ ]] || {
  printf 'Invalid release-lock version, repository, or checksum.\n' >&2
  exit 2
}

tag="v$version"
asset="omarchy-android-aarch64-$version.bundle.tar"
temporary_lock="$(mktemp "$ROOT/manifest/release.lock.XXXXXX")"
cleanup() {
  if [[ "$temporary_lock" == "$ROOT/manifest/release.lock."* && -f "$temporary_lock" ]]; then
    rm "$temporary_lock"
  fi
}
trap cleanup EXIT

cat > "$temporary_lock" <<EOF
format=1
version=$version
tag=$tag
asset=$asset
url=https://github.com/$repository/releases/download/$tag/$asset
sha256=$bundle_sha256
EOF
chmod 0644 "$temporary_lock"
mv "$temporary_lock" "$ROOT/manifest/release.lock"
trap - EXIT

printf 'Installer release lock now targets %s (%s).\n' "$tag" "$bundle_sha256"
