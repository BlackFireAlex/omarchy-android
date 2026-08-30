#!/usr/bin/env bash

set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
template_root="$script_dir/home"
system_template_root="$script_dir/root"
target_root="${1:-}"

if [[ -z "$target_root" || "$target_root" != /* ]]; then
  printf 'usage: %s ABSOLUTE_ROOTFS_PATH\n' "$0" >&2
  exit 2
fi
if [[ ! -d "$target_root" || ! -d "$target_root/home" ]]; then
  printf 'Not a prepared guest rootfs: %s\n' "$target_root" >&2
  exit 1
fi

file_list="$(mktemp)"
cleanup() {
  rm -f -- "$file_list"
}
trap cleanup EXIT
find "$template_root" -type f -print0 > "$file_list"

while IFS= read -r -d '' source_file; do
  relative_path="${source_file#"$template_root"/}"
  destination="$target_root/home/$relative_path"
  install -D -m 0644 -- "$source_file" "$destination"
done < "$file_list"

if [[ -d "$system_template_root" ]]; then
  find "$system_template_root" -type f -print0 > "$file_list"
  while IFS= read -r -d '' source_file; do
    relative_path="${source_file#"$system_template_root"/}"
    destination="$target_root/$relative_path"
    case "$relative_path" in
      usr/local/bin/*) mode=0755 ;;
      *) mode=0644 ;;
    esac
    install -D -m "$mode" -- "$source_file" "$destination"
  done < "$file_list"
fi

printf 'Installed curated Android guest runtime into %s\n' "$target_root"
