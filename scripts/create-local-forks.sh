#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PROJECT_ROOT
# shellcheck source=lib/common.sh
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck source=lib/manifest.sh
source "$PROJECT_ROOT/lib/manifest.sh"

upstream_root="$PROJECT_ROOT/.work/upstream"
destination="${PROJECT_ROOT%/*}/omarchy-android-forks"
declare -a requested=(omarchy hyprland aquamarine weston mesa)

usage() {
  cat <<'EOF'
Usage: scripts/create-local-forks.sh [--destination PATH] [--component NAME ...]

Creates independent local fork repositories from pristine pinned checkouts.
Each fork has an `upstream` remote and an `omarchy-android` branch. Nothing is
pushed to a network service.
EOF
}

explicit_components=false
while (($#)); do
  case "$1" in
    --destination)
      shift
      [[ -n "${1:-}" ]] || die "--destination requires a path."
      destination="$1"
      ;;
    --component)
      shift
      [[ -n "${1:-}" ]] || die "--component requires a name."
      if [[ "$explicit_components" == false ]]; then
        requested=()
        explicit_components=true
      fi
      requested+=("$1")
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift
done

"$PROJECT_ROOT/scripts/fetch-sources.sh" "${requested[@]}"
mkdir -p "$destination"

for component in "${requested[@]}"; do
  record="$(component_record "$component" || true)"
  [[ -n "$record" ]] || die "Unknown component: $component"
  IFS='|' read -r name type upstream revision license <<<"$record"
  [[ "$type" == git ]] || die "$component is not a git component."

  source_repo="$upstream_root/$name"
  fork_repo="$destination/$name"
  [[ ! -e "$fork_repo" ]] || die "Refusing to replace existing fork: $fork_repo"

  info "Creating local $name fork"
  git clone --no-hardlinks "$source_repo" "$fork_repo"
  git -C "$fork_repo" remote remove origin
  git -C "$fork_repo" remote add upstream "$upstream"
  git -C "$fork_repo" checkout -b omarchy-android "$revision"

  patch_dir="$PROJECT_ROOT/patches/$name"
  if [[ "$name" == omarchy ]]; then
    patch_dir="$PROJECT_ROOT/patches/omarchy-shell"
  fi
  if compgen -G "$patch_dir/*.patch" >/dev/null; then
    git -C "$fork_repo" am "$patch_dir"/*.patch
  fi

  success "Local fork ready: $fork_repo"
done

cat <<EOF

Local forks were created without public remotes:
  $destination

Add a public origin only after review, then preserve upstream for updates.
EOF
