#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PROJECT_ROOT
# shellcheck source=lib/common.sh
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck source=lib/manifest.sh
source "$PROJECT_ROOT/lib/manifest.sh"

destination="$PROJECT_ROOT/.work/upstream"
declare -a requested=()

usage() {
  cat <<'EOF'
Usage: scripts/fetch-sources.sh [--destination PATH] [COMPONENT ...]

Fetches pristine git components at the exact commits in components.lock.
Archives are handled by the artifact builder and are not fetched here.
EOF
}

while (($#)); do
  case "$1" in
    --destination)
      shift
      [[ -n "${1:-}" ]] || die "--destination requires a path."
      destination="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*) die "Unknown option: $1" ;;
    *) requested+=("$1") ;;
  esac
  shift
done

validate_component_lock || die "Invalid component lock."
has_command git || die "git is required."
mkdir -p "$destination"

if ((${#requested[@]} == 0)); then
  mapfile -t requested < <(list_git_components)
fi

for component in "${requested[@]}"; do
  record="$(component_record "$component" || true)"
  [[ -n "$record" ]] || die "Unknown component: $component"
  IFS='|' read -r name type upstream revision license <<<"$record"
  [[ "$type" == git ]] || die "$component is not a git component."

  target="$destination/$name"
  if [[ ! -d "$target/.git" ]]; then
    [[ ! -e "$target" ]] || die "$target exists but is not a git checkout."
    info "Cloning $name from $upstream"
    git clone --filter=blob:none --no-checkout "$upstream" "$target"
  else
    info "Refreshing $name"
    current_url="$(git -C "$target" remote get-url origin)"
    [[ "$current_url" == "$upstream" ]] || die "$name origin mismatch: $current_url"
  fi

  git -C "$target" fetch --filter=blob:none origin "$revision"
  git -C "$target" checkout --detach --force "$revision"
  git -C "$target" clean -dffx

  resolved="$(git -C "$target" rev-parse HEAD)"
  [[ "$resolved" == "$revision" ]] || die "$name resolved to $resolved instead of $revision"
  [[ -z "$(git -C "$target" status --porcelain=v1)" ]] || die "$name checkout is not clean"
  success "$name pinned at ${revision:0:12} ($license)"
done

