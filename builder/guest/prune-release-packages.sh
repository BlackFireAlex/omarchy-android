#!/usr/bin/env bash

set -Eeuo pipefail

packages_file="${1:-/mnt/project/builder/guest/runtime-packages.txt}"
[[ $EUID == 0 ]] || {
  printf 'Package pruning must run as root inside the disposable builder.\n' >&2
  exit 1
}
[[ -f "$packages_file" ]] || {
  printf 'Runtime package manifest is missing: %s\n' "$packages_file" >&2
  exit 1
}

temporary_root="/var/tmp/omarchy-release-prune.$$"
mkdir -p "$temporary_root"
cleanup() {
  if [[ "$temporary_root" == /var/tmp/omarchy-release-prune.* && -d "$temporary_root" ]]; then
    find "$temporary_root" -depth -delete
  fi
}
trap cleanup EXIT

sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$packages_file" > "$temporary_root/runtime"
pacman -Qq > "$temporary_root/installed"
mapfile -t runtime_packages < "$temporary_root/runtime"
mapfile -t installed_packages < "$temporary_root/installed"
(( ${#runtime_packages[@]} > 0 && ${#installed_packages[@]} > 0 )) || {
  printf 'Cannot resolve the runtime package closure.\n' >&2
  exit 1
}

# Convert the builder into a release image by retaining exactly the dependency
# closure of the declared runtime roots. This removes compilers and headers
# even when the release is resumed from a public-source graphics builder.
pacman -D --asdeps "${installed_packages[@]}" >/dev/null
pacman -D --asexplicit "${runtime_packages[@]}" >/dev/null

while true; do
  # Use -tt so build tools retained only as optional dependencies of a runtime
  # package are still considered removable. Every optional component intended
  # for the desktop is already an explicit root in runtime-packages.txt.
  pacman -Qdttq > "$temporary_root/orphaned" || true
  mapfile -t orphaned < "$temporary_root/orphaned"
  (( ${#orphaned[@]} > 0 )) || break
  pacman -Rns --noconfirm "${orphaned[@]}"
done

# These exact paths belong exclusively to the disposable graphics builder.
for build_path in /var/tmp/omarchy-android-sources /var/tmp/omarchy-android-build; do
  if [[ -e "$build_path" ]]; then
    find "$build_path" -depth -delete
  fi
done
rm -f /var/log/pacman.log
rm -rf /var/cache/pacman/pkg/*

printf 'Release package closure contains %s packages.\n' "$(pacman -Qq | wc -l)"
