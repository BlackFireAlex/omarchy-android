#!/usr/bin/env bash
# overlay-viture.sh
# Applies the VITURE optimizations (Neckband Pro / Luma Ultra) on top of an
# ALREADY-INSTALLED Omarchy Android (v0.1.1) guest WITHOUT rebuilding the rootfs.
#
# Run this from a clone of the optimized repo, inside Termux on the device:
#   git clone -b optimize-viture https://github.com/<owner>/omarchy-android.git
#   cd omarchy-android && ./overlay-viture.sh
#
# It backs up every file it replaces to a .orig copy so you can roll back:
#   ./overlay-viture.sh --revert
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
OA_PREFIX="${HOME}/.local/share/omarchy-android"
RUNTIME_CONF="$OA_PREFIX/config/runtime.conf"
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
REVERT=0
for a in "$@"; do [[ "$a" == "--revert" ]] && REVERT=1; done

die() { echo "overlay: $*" >&2; exit 1; }
info() { echo ">> $*"; }

[[ -n "$PREFIX" ]] || { echo "Please run this inside Termux." >&2; exit 1; }
[[ -f "$RUNTIME_CONF" ]] || die "No runtime.conf at $RUNTIME_CONF — is Omarchy Android installed?";
# shellcheck source=/dev/null
source "$RUNTIME_CONF" 2>/dev/null || true
CONTAINER="${OMARCHY_CONTAINER:-omarchy-android}"
ROOTFS="$TERMUX_PREFIX/var/lib/proot-distro/containers/$CONTAINER/rootfs"
[[ -d "$ROOTFS/home/omarchy" ]] || die "Guest rootfs not found at $ROOTFS (container=$CONTAINER)."

HYPR_SRC="$PROJECT_ROOT/runtime/guest/home/omarchy/.config/hypr"
HYPR_DST="$ROOTFS/home/omarchy/.config/hypr"
EXTRAS_SRC="$PROJECT_ROOT/runtime/guest/home/omarchy/omarchy-android-extras"
EXTRAS_DST="$ROOTFS/home/omarchy/omarchy-android-extras"

revert() {
  info "Reverting host runtime"
  [[ -f "$OA_PREFIX/omarchy-android-start.orig" ]] && mv -f "$OA_PREFIX/omarchy-android-start.orig" "$OA_PREFIX/bin/omarchy-android-start"
  rm -f "$OA_PREFIX/device-presets.sh"
  info "Reverting guest config"
  for f in input.lua input/pointer.lua monitors.lua hyprland.lua; do
    [[ -f "$HYPR_DST/$f.orig" ]] && mv -f "$HYPR_DST/$f.orig" "$HYPR_DST/$f"
  done
  info "Removing extras tree"
  rm -rf "$EXTRAS_DST"
  info "Revert complete."
  exit 0
}
if (( REVERT )); then revert; fi

info "== Applying VITURE optimizations to $CONTAINER =="
info "Host prefix : $OA_PREFIX"
info "Guest rootfs: $ROOTFS"

# 1) Host runtime: device-presets module + patched start script
info "Installing device-presets.sh and patched omarchy-android-start (host)"
install -m 0644 "$PROJECT_ROOT/runtime/host/device-presets.sh" "$OA_PREFIX/device-presets.sh"
if [[ -f "$OA_PREFIX/bin/omarchy-android-start" ]]; then
  cp -f "$OA_PREFIX/bin/omarchy-android-start" "$OA_PREFIX/bin/omarchy-android-start.orig"
fi
install -m 0755 "$PROJECT_ROOT/runtime/host/omarchy-android-start" "$OA_PREFIX/bin/omarchy-android-start"

# 2) Guest Hyprland config (backup .orig)
info "Layering Hyprland input/pointer/monitors/start config"
mkdir -p "$HYPR_DST/input"
for f in input.lua monitors.lua hyprland.lua; do
  [[ -f "$HYPR_DST/$f" ]] && cp -f "$HYPR_DST/$f" "$HYPR_DST/$f.orig"
  install -m 0644 "$HYPR_SRC/$f" "$HYPR_DST/$f"
done
cp -f "$HYPR_DST/input.lua" "$HYPR_DST/input.lua.orig" 2>/dev/null || true
install -m 0644 "$HYPR_SRC/input/pointer.lua" "$HYPR_DST/input/pointer.lua"

# 3) Guest extras (reminders/battery/brightness daemons + install helper)
info "Installing omarchy-android-extras (systemd-free feature ports)"
rm -rf "$EXTRAS_DST"
mkdir -p "$EXTRAS_DST"
cp -R "$EXTRAS_SRC/." "$EXTRAS_DST/"
chmod -R u=rwX,go=rX "$EXTRAS_DST"

# 4) Re-target runtime.conf to auto-detection (unless user pinned explicit values)
if [[ "${1:-}" != "keep" ]]; then
  sed -i \
    -e 's/^OMARCHY_DISPLAY_RESOLUTION=.*/OMARCHY_DISPLAY_RESOLUTION=auto/' \
    -e 's/^OMARCHY_REFRESH_MHZ=.*/OMARCHY_REFRESH_MHZ=auto/' \
    -e 's/^OMARCHY_SCALE=.*/OMARCHY_SCALE=auto/' \
    "$RUNTIME_CONF" 2>/dev/null || true
  info "runtime.conf display/refresh/scale set to auto (device presets active). Pass 'keep' to preserve pinned values."
fi

info ""
info "== Done. To finish on the device: =="
info "  1. Start the desktop:   ~/.local/share/omarchy-android/bin/omarchy-android start"
info "  2. Inside the guest:    ~/omarchy-android-extras/install.sh   # enables reminders/battery/brightness extras"
info "  3. On first real use, confirm the resolved profile:"
info "        grep -E '^OMARCHY_(DISPLAY|REFRESH|SCALE)' $RUNTIME_CONF"
info "  4. Roll back any time:  ./overlay-viture.sh --revert"
