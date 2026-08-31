#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temporary_parent="$ROOT/.work/runtime-test"
mkdir -p "$temporary_parent"
temporary_root="$(mktemp -d "$temporary_parent/rootfs.XXXXXX")"

cleanup() {
  if [[ "$temporary_root" == "$temporary_parent"/* && -d "$temporary_root" ]]; then
    find "$temporary_root" -depth -delete
  fi
}
trap cleanup EXIT

mkdir -p "$temporary_root/home"
"$ROOT/runtime/guest/install-runtime.sh" "$temporary_root" >/dev/null

expected_files=(
  home/omarchy/.config/hypr/autostart.lua
  home/omarchy/.config/hypr/bindings.lua
  home/omarchy/.config/hypr/hyprland.lua
  home/omarchy/.config/hypr/input.lua
  home/omarchy/.config/hypr/looknfeel.lua
  home/omarchy/.config/hypr/monitors.lua
  home/omarchy/.config/chromium-flags.conf
  home/omarchy/.config/mimeapps.list
  home/omarchy/.config/omarchy/dbus-services/ca.desrt.dconf.service
  home/omarchy/.config/omarchy/proot-session-bus.conf
  home/omarchy/.local/share/applications/org.gnome.Nautilus.desktop
  usr/local/bin/Xwayland
  usr/local/bin/omarchy-dbus-service
  usr/local/bin/omarchy-voxtype-daemon
  usr/local/bin/omarchy-voxtype-install
  usr/local/bin/uwsm-app
)

for expected_file in "${expected_files[@]}"; do
  [[ -f "$temporary_root/$expected_file" ]] || {
    printf 'guest runtime file was not installed: %s\n' "$expected_file" >&2
    exit 1
  }
done

installed_count="$(find "$temporary_root" -type f | wc -l)"
(( installed_count == ${#expected_files[@]} )) || {
  printf 'guest runtime installed unexpected files: %s\n' "$installed_count" >&2
  exit 1
}

grep -F 'OMARCHY_SCALE' "$temporary_root/home/omarchy/.config/hypr/monitors.lua" >/dev/null
grep -F 'local omarchy_monitor_scale =' "$temporary_root/home/omarchy/.config/hypr/monitors.lua" >/dev/null
grep -F 'local omarchy_gdk_scale =' "$temporary_root/home/omarchy/.config/hypr/monitors.lua" >/dev/null
grep -F 'hl.env("LANG", "C.UTF-8")' "$temporary_root/home/omarchy/.config/hypr/looknfeel.lua" >/dev/null
grep -F 'OMARCHY_KEYBOARD_LAYOUT' "$temporary_root/home/omarchy/.config/hypr/input.lua" >/dev/null
grep -F 'DBusActivatable=false' "$temporary_root/home/omarchy/.local/share/applications/org.gnome.Nautilus.desktop" >/dev/null
grep -F '<servicedir>/home/omarchy/.config/omarchy/dbus-services</servicedir>' \
  "$temporary_root/home/omarchy/.config/omarchy/proot-session-bus.conf" >/dev/null
HOME="$temporary_root/home/omarchy" \
  bash "$temporary_root/usr/local/bin/omarchy-dbus-service" --help >/dev/null
OMARCHY_PROOT=1 "$temporary_root/usr/local/bin/uwsm-app" -- true

grep -Fx 'gawk' "$ROOT/builder/guest/runtime-packages.txt" >/dev/null
grep -Fx 'wtype' "$ROOT/builder/guest/runtime-packages.txt" >/dev/null
grep -F 'stop_orphans "pulseaudio -n --daemonize=yes"' \
  "$ROOT/runtime/host/omarchy-android-stop" >/dev/null

printf 'runtime template tests passed\n'
