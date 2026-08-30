#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

PROJECT_ROOT="$ROOT"
export PROJECT_ROOT
# shellcheck source=lib/manifest.sh
source "$ROOT/lib/manifest.sh"

# Only validate files that are part of this repository. `.work` contains exact
# upstream checkouts; linting those would report upstream issues that are not
# part of the Android distribution.
mapfile -t scripts < <(
  find "$ROOT" \
    \( -type d \( -name .git -o -name .work \) -prune \) -o \
    \( -type f -name '*.sh' -print \) | sort
)
for script in "${scripts[@]}"; do
  bash -n "$script"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "${scripts[@]}"
fi

forbidden=(
  'omarchy-real'
  '/var/lib/proot-distro/containers/omarchy-arm'
  '/var/lib/proot-distro/containers/omarchy-utm'
  '/home/omarchy/.config/chromium'
  '/home/omarchy/.ssh'
  'BEGIN OPENSSH PRIVATE KEY'
  'BEGIN PGP PRIVATE KEY BLOCK'
  'gh auth login'
  'signed Arch Linux ARM rootfs'
)

for pattern in "${forbidden[@]}"; do
  if grep -R -n -F --exclude-dir=.git --exclude-dir=.work --exclude=validate.sh -- "$pattern" "$ROOT" >/dev/null; then
    printf 'forbidden development-install reference found: %s\n' "$pattern" >&2
    exit 1
  fi
done

validate_component_lock
validate_build_dependency_lock
validate_patch_lock

packages_lock="$ROOT/manifest/packages-aarch64-0.1.0.lock"
[[ -f "$packages_lock" ]] || {
  printf 'missing release package inventory: %s\n' "$packages_lock" >&2
  exit 1
}
package_count="$(grep -Evc '^[[:space:]]*(#|$)' "$packages_lock")"
(( package_count == 555 )) || {
  printf 'expected 555 release packages, found %s\n' "$package_count" >&2
  exit 1
}
if grep -Ev '^[[:space:]]*(#|$)' "$packages_lock" | LC_ALL=C sort -cu; then
  :
else
  printf 'release package inventory is not unique and bytewise sorted\n' >&2
  exit 1
fi
if grep -Ev '^[[:space:]]*(#|$)' "$packages_lock" | \
    grep -Ev '^[a-z0-9@._+:-]+ [^[:space:]]+$' >/dev/null; then
  printf 'release package inventory contains an invalid line\n' >&2
  exit 1
fi

"$ROOT/tests/options.sh"
"$ROOT/tests/runtime.sh"
printf 'validation passed\n'
