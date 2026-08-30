#!/usr/bin/env bash

set -Eeuo pipefail

artifact_root="${1:-}"
install_root="${2:-/opt/omarchy-android}"
[[ "$artifact_root" == /* && "$install_root" == /* ]] || {
  printf 'usage: %s ABSOLUTE_ARTIFACT_ROOT [ABSOLUTE_INSTALL_ROOT]\n' "$0" >&2
  exit 2
}

mesa="$artifact_root/mesa"
aquamarine="$artifact_root/aquamarine"
hyprland="$artifact_root/hyprland"
turnip="$mesa/root/usr/lib/libvulkan_freedreno.so"
kgsl="$mesa/root/usr/lib/dri/kgsl_dri.so"
aquamarine_library="$aquamarine/lib/libaquamarine.so.0.14.0"
hyprland_binary="$hyprland/bin/Hyprland"

for file in "$turnip" "$kgsl" "$aquamarine_library" "$hyprland_binary"; do
  [[ -e "$file" ]] || { printf 'Missing graphics artifact: %s\n' "$file" >&2; exit 1; }
done
for elf in "$turnip" "$kgsl" "$aquamarine_library" "$hyprland_binary"; do
  elf_header="$(readelf -h "$elf")"
  grep -q 'Machine:.*AArch64' <<<"$elf_header" || {
    printf 'Graphics artifact is not ARM64: %s\n' "$elf" >&2
    exit 1
  }
done

python - "$mesa/freedreno_icd.json" \
  "$install_root/mesa/root/usr/lib/libvulkan_freedreno.so" <<'PY'
import json
import sys

manifest, expected = sys.argv[1:]
with open(manifest, encoding="utf-8") as stream:
    actual = json.load(stream)["ICD"]["library_path"]
if actual != expected:
    raise SystemExit(f"Turnip ICD path mismatch: expected {expected}, got {actual}")
PY

grep -qxF "prefix=$install_root/aquamarine" \
  "$aquamarine/lib/pkgconfig/aquamarine.pc" || {
  printf 'Aquamarine metadata contains the wrong install prefix.\n' >&2
  exit 1
}
grep -a -qF "$install_root/hyprland/share" "$hyprland_binary" || {
  printf 'Hyprland does not contain its final data-directory prefix.\n' >&2
  exit 1
}
aquamarine_dynamic="$(readelf -d "$aquamarine_library")"
grep -qF '[libgbm.so.1]' <<<"$aquamarine_dynamic" || {
  printf 'Aquamarine is not linked to GBM.\n' >&2
  exit 1
}
hyprland_dynamic="$(readelf -d "$hyprland_binary")"
grep -qF '[libaquamarine.so.13]' <<<"$hyprland_dynamic" || {
  printf 'Hyprland is not linked to the expected Aquamarine ABI.\n' >&2
  exit 1
}

printf 'ARM64 graphics artifact audit passed.\n'
