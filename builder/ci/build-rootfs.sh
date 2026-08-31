#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
version="${1:-edge}"
work_root="$ROOT/.work/ci-image-$version"
base_image="danhunsaker/archlinuxarm:20260517"
base_layer="sha256:a2920b02b16de310b39f36ff28ffdfa1912bd6ea904fa7f95bd96087003eb0d7"
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
if ! docker image inspect --format '{{range .RootFS.Layers}}{{println .}}{{end}}' "$base_image" |
    grep -qxF "$base_layer"; then
  printf 'Arch Linux ARM base does not contain the locked OCI layer %s\n' "$base_layer" >&2
  exit 1
fi

docker run --detach \
  --name "$container_name" \
  --volume "$ROOT:/mnt/project" \
  --workdir /mnt/project \
  "$base_image" \
  /usr/bin/bash -c 'trap "exit 0" TERM INT; while :; do sleep 3600; done'
container_started=1

docker exec \
  -e OMARCHY_BUILD_JOBS="${OMARCHY_BUILD_JOBS:-4}" \
  "$container_name" \
  /mnt/project/builder/ci/build-rootfs-container.sh \
    /mnt/project "$version" "/mnt/project/.work/ci-image-$version"

printf 'Image output: %s\n' "$work_root/output"
