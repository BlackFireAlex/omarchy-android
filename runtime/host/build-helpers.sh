#!/usr/bin/env bash

set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
output_dir="${1:-$script_dir/bin}"
compiler="${CC:-}"

if [[ -z "$compiler" ]]; then
  if command -v clang >/dev/null 2>&1; then
    compiler=clang
  elif command -v cc >/dev/null 2>&1; then
    compiler=cc
  else
    printf 'A C compiler is required (install clang in Termux).\n' >&2
    exit 1
  fi
fi

command -v pkg-config >/dev/null 2>&1 || {
  printf 'pkg-config is required to locate Termux X11 headers.\n' >&2
  exit 1
}
pkg-config --exists x11 || {
  printf 'X11 development files are required (install xorgproto and libx11).\n' >&2
  exit 1
}

mkdir -p "$output_dir"

"$compiler" -std=c11 -O2 -Wall -Wextra -Wpedantic \
  "$script_dir/src/process-guard.c" \
  -o "$output_dir/omarchy-process-guard"

read -r -a x11_flags <<<"$(pkg-config --cflags --libs x11)"
"$compiler" -std=c11 -O2 -Wall -Wextra -Wpedantic \
  "$script_dir/src/x11-keyboard.c" \
  "${x11_flags[@]}" \
  -o "$output_dir/omarchy-x11-keyboard"

printf 'Built host helpers in %s\n' "$output_dir"
