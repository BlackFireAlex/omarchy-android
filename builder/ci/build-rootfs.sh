#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
version="${1:-edge}"
work_root="$ROOT/.work/ci-image-$version"
oci_record="$(awk -F '|' '$1 == "archlinuxarm" { print; found=1; exit } END { if (!found) exit 1 }' \
  "$ROOT/manifest/oci-images.lock")"
IFS='|' read -r _ base_repository base_tag base_manifest base_layer <<<"$oci_record"
base_image="$base_repository:$base_tag"
pinned_base_image="$base_repository@$base_manifest"
container_name="omarchy-android-ci-${GITHUB_RUN_ID:-$$}-${GITHUB_RUN_ATTEMPT:-1}"
container_started=0

[[ "$version" =~ ^[A-Za-z0-9._-]+$ ]] || {
  printf 'Invalid image version: %s\n' "$version" >&2
  exit 2
}
[[ "$(uname -m)" == aarch64 ]] || {
  printf 'Image builds run natively on ARM64 only.\n' >&2
  exit 1
}
for command_name in docker git sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  }
done
[[ ! -e "$work_root" ]] || {
  printf 'Refusing to replace existing CI work directory: %s\n' "$work_root" >&2
  exit 1
}

cleanup() {
  if (( container_started == 1 )); then
    docker rm --force "$container_name" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

"$ROOT/scripts/validate.sh"
printf 'Locked Arch Linux ARM base: %s (primary layer %s)\n' \
  "$pinned_base_image" "$base_layer"
"$ROOT/scripts/fetch-sources.sh" mesa aquamarine hyprland omarchy

mkdir -p "$work_root"
git clone --no-hardlinks "$ROOT/.work/upstream/omarchy" "$work_root/omarchy"
omarchy_revision="$(awk -F '|' '$1 == "omarchy" { print $4; exit }' "$ROOT/manifest/components.lock")"
git -C "$work_root/omarchy" checkout --detach "$omarchy_revision"
git -C "$work_root/omarchy" config user.name 'Omarchy Android Builder'
git -C "$work_root/omarchy" config user.email 'builder@omarchy-android.invalid'
git -C "$work_root/omarchy" am --committer-date-is-author-date \
  "$ROOT"/patches/omarchy-shell/*.patch

docker pull "$base_image"
if ! docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$base_image" |
    grep -qxF "$pinned_base_image"; then
  printf 'Arch Linux ARM base does not match locked manifest %s\n' "$base_manifest" >&2
  exit 1
fi

docker run --detach \
  --name "$container_name" \
  --volume "$ROOT:/mnt/project" \
  --workdir /mnt/project \
  "$pinned_base_image" \
  /usr/bin/bash -c 'trap "exit 0" TERM INT; while :; do sleep 3600; done'
container_started=1

docker exec \
  -e OMARCHY_BUILD_JOBS="${OMARCHY_BUILD_JOBS:-4}" \
  "$container_name" \
  /mnt/project/builder/ci/build-rootfs-container.sh \
    /mnt/project "$version" "/mnt/project/.work/ci-image-$version"

printf 'Image output: %s\n' "$work_root/output"
