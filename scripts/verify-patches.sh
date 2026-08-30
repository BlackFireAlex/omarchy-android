#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PROJECT_ROOT
# shellcheck source=lib/common.sh
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck source=lib/manifest.sh
source "$PROJECT_ROOT/lib/manifest.sh"

upstream_root="$PROJECT_ROOT/.work/upstream"
verify_root="$PROJECT_ROOT/.work/patch-check"
declare -a requested=("$@")
declare -a temporary_dirs=()

cleanup() {
  local temporary_dir
  for temporary_dir in "${temporary_dirs[@]}"; do
    [[ "$temporary_dir" == "$verify_root"/* && -d "$temporary_dir" ]] || continue
    find "$temporary_dir" -depth -delete
  done
}
trap cleanup EXIT

if ((${#requested[@]} == 0)); then
  mapfile -t requested < <(
    awk -F'|' '!/^#/ && !seen[$1]++ { print $1 }' "$OA_PATCHES_LOCK"
  )
fi

validate_component_lock
validate_patch_lock
mkdir -p "$verify_root"

for component in "${requested[@]}"; do
  record="$(component_record "$component" || true)"
  [[ -n "$record" ]] || die "Unknown component: $component"
  IFS='|' read -r name type _ revision _ <<<"$record"
  [[ "$type" == git ]] || die "$component is not a Git component."

  source_repo="$upstream_root/$name"
  [[ -d "$source_repo/.git" ]] || die "Missing pinned source for $name; run scripts/fetch-sources.sh first."
  [[ "$(git -C "$source_repo" rev-parse HEAD)" == "$revision" ]] ||
    die "$name source is not at its locked revision."

  temporary_dir="$(mktemp -d "$verify_root/$name.XXXXXX")"
  temporary_dirs+=("$temporary_dir")
  git clone --quiet --no-hardlinks "$source_repo" "$temporary_dir"
  git -C "$temporary_dir" checkout --quiet --detach "$revision"
  git -C "$temporary_dir" config user.name 'Omarchy Android Patch Check'
  git -C "$temporary_dir" config user.email 'noreply@localhost'

  mapfile -t component_patches < <(
    awk -F'|' -v wanted="$name" '!/^#/ && $1 == wanted { print $3 }' "$OA_PATCHES_LOCK"
  )
  ((${#component_patches[@]} > 0)) || die "No patch series found for $name."

  absolute_patches=()
  for patch_path in "${component_patches[@]}"; do
    absolute_patches+=("$PROJECT_ROOT/$patch_path")
  done
  git -C "$temporary_dir" am --quiet "${absolute_patches[@]}"
  git -C "$temporary_dir" diff --check "$revision"..HEAD
  success "$name patch series applies cleanly (${#absolute_patches[@]} patch(es))"
done
