#!/usr/bin/env bash

set -Eeuo pipefail

project_root="${1:-/mnt/project}"
forks_root="${2:-/mnt/forks}"
artifact_root="${3:-/mnt/output/graphics}"
source_root="${4:-/var/tmp/omarchy-android-sources}"
build_root="${5:-/var/tmp/omarchy-android-build}"

for path in "$project_root" "$forks_root" "$artifact_root" "$source_root" "$build_root"; do
  [[ "$path" == /* ]] || {
    printf 'All paths must be absolute: %s\n' "$path" >&2
    exit 2
  }
done
[[ -f "$project_root/manifest/components.lock" ]] || {
  printf 'Invalid project checkout: %s\n' "$project_root" >&2
  exit 1
}
for component in mesa aquamarine hyprland; do
  [[ -d "$forks_root/$component/.git" ]] || {
    printf 'Missing local fork: %s\n' "$forks_root/$component" >&2
    exit 1
  }
done
for path in "$artifact_root" "$source_root" "$build_root"; do
  [[ ! -e "$path" ]] || {
    printf 'Refusing to reuse clean-build path: %s\n' "$path" >&2
    exit 1
  }
done

revision_for() {
  local component="$1"
  awk -F '|' -v component="$component" '$1 == component { print $4; found=1; exit } END { if (!found) exit 1 }' \
    "$project_root/manifest/components.lock"
}

dependency_revision_for() {
  local parent="$1"
  local dependency="$2"
  awk -F '|' -v parent="$parent" -v dependency="$dependency" \
    '$1 == parent && $2 == dependency { print $5; found=1; exit } END { if (!found) exit 1 }' \
    "$project_root/manifest/build-dependencies.lock"
}

clone_at_revision() {
  local component="$1"
  local revision
  revision="$(revision_for "$component")"
  git clone --no-hardlinks --no-checkout "$forks_root/$component" "$source_root/$component"
  git -C "$source_root/$component" checkout --detach "$revision"
}

mkdir -p "$source_root"
clone_at_revision mesa
clone_at_revision aquamarine
clone_at_revision hyprland

for component in aquamarine hyprland; do
  series=("$project_root/patches/$component"/*.patch)
  [[ -f "${series[0]}" ]] || {
    printf 'No patch series found for %s.\n' "$component" >&2
    exit 1
  }
  git -C "$source_root/$component" config user.name 'Omarchy Android Builder'
  git -C "$source_root/$component" config user.email 'builder@omarchy-android.invalid'
  git -C "$source_root/$component" am --committer-date-is-author-date "${series[@]}"
done

# Hyprland falls back to its pinned udis86 submodule when no distro package is
# available. The protocol and Tracy submodules are also initialized at the
# exact commits recorded by the pinned Hyprland tree.
git -C "$source_root/hyprland" submodule update --init --recursive
for dependency_path in \
  hyprland-protocols:subprojects/hyprland-protocols \
  tracy:subprojects/tracy \
  udis86:subprojects/udis86; do
  dependency="${dependency_path%%:*}"
  path="${dependency_path#*:}"
  expected="$(dependency_revision_for hyprland "$dependency")"
  actual="$(git -C "$source_root/hyprland/$path" rev-parse HEAD)"
  [[ "$actual" == "$expected" ]] || {
    printf 'Locked dependency mismatch for %s: expected %s, got %s\n' \
      "$dependency" "$expected" "$actual" >&2
    exit 1
  }
done
export OMARCHY_GLAZE_REVISION
OMARCHY_GLAZE_REVISION="$(dependency_revision_for hyprland glaze)"

"$project_root/builder/guest/build-graphics.sh" \
  "$source_root/mesa" \
  "$source_root/aquamarine" \
  "$source_root/hyprland" \
  "$artifact_root" \
  "$build_root"
