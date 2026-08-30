#!/usr/bin/env bash

set -Eeuo pipefail

source_dir="${1:-}"
install_prefix="${2:-}"
build_dir="${3:-}"

if [[ -z "$source_dir" || -z "$install_prefix" || -z "$build_dir" ]]; then
  printf 'usage: %s WESTON_SOURCE INSTALL_PREFIX BUILD_DIR\n' "$0" >&2
  exit 2
fi
for path in "$source_dir" "$install_prefix" "$build_dir"; do
  [[ "$path" == /* ]] || {
    printf 'All paths must be absolute: %s\n' "$path" >&2
    exit 2
  }
done
[[ -f "$source_dir/meson.build" ]] || {
  printf 'Not a Weston source tree: %s\n' "$source_dir" >&2
  exit 1
}
[[ ! -e "$build_dir" ]] || {
  printf 'Refusing to reuse build directory: %s\n' "$build_dir" >&2
  exit 1
}
[[ ! -e "$install_prefix" ]] || {
  printf 'Refusing to overwrite install prefix: %s\n' "$install_prefix" >&2
  exit 1
}

meson setup "$build_dir" "$source_dir" \
  -Dprefix="$install_prefix" \
  -Dbackend-drm=false \
  -Dbackend-drm-screencast-vaapi=false \
  -Dbackend-headless=false \
  -Dbackend-pipewire=false \
  -Dbackend-rdp=false \
  -Dbackend-vnc=false \
  -Dbackend-wayland=false \
  -Dbackend-x11=true \
  -Dbackend-default=x11 \
  -Dscreenshare=false \
  -Drenderer-gl=true \
  -Dxwayland=false \
  -Dsystemd=false \
  -Dremoting=false \
  -Dpipewire=false \
  -Dshell-desktop=false \
  -Dshell-fullscreen=false \
  -Dshell-ivi=false \
  -Dshell-kiosk=true \
  -Dcolor-management-lcms=false \
  -Dimage-jpeg=false \
  -Dimage-webp=false \
  -Dtools=[] \
  -Ddemo-clients=false \
  -Dsimple-clients=[] \
  -Dwcap-decode=false \
  -Dtests=false \
  -Dtest-junit-xml=false \
  -Ddoc=false \
  -Dc_link_args=-landroid-shmem

meson compile -C "$build_dir" x11-backend
module="$install_prefix/lib/libweston-14/x11-backend.so"
install -D -m 0755 -- \
  "$build_dir/libweston/backend-x11/x11-backend.so" \
  "$module"
[[ -f "$module" ]] || {
  printf 'Weston X11 backend was not installed: %s\n' "$module" >&2
  exit 1
}
sha256sum "$module"
