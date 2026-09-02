#!/usr/bin/env bash
#
# device-presets.sh — device-aware display and input defaults for Omarchy Android.
#
# This module is a shared, sourceable helper. It is loaded:
#   * by runtime/host/omarchy-android-start BEFORE the generated
#     runtime.conf is sourced, so an explicit value in config/runtime.conf or
#     the caller's environment always wins over a detected preset;
#   * by lib/platform.sh during ./install.sh, so the installer can record and
#     emit the detected per-device preset instead of hard-coding phone tuning.
#
# It inspects Android's device properties (getprop) to identify a VITURE
# headset host (Pro Neckband or Luma Ultra) and exports tuned defaults so a
# native-panel desktop is presented with the right resolution / refresh /
# scale and Bluetooth-friendly input timings. Non-VITURE phones fall back to
# the stock Omarchy behavior. The module is additive and safe to source more
# than once (a guard variable prevents re-evaluation).

# shellcheck disable=SC2034  # exported OAD_* + OMARCHY_* consumed by callers
if [[ -n "${OMARCHY_DEVICE_PRESETS_LOADED:-}" ]]; then
  return 0
fi
OMARCHY_DEVICE_PRESETS_LOADED=1

# ---------------------------------------------------------------------------
# Stock (non-VITURE) defaults — byte-identical to the historical phone tuning.
# ---------------------------------------------------------------------------
# Refresh / scale stay the classic 120 Hz / 2x values.
OAD_DEFAULT_REFRESH_MHZ="${OMARCHY_DEFAULT_REFRESH_MHZ:-120000}"
OAD_DEFAULT_SCALE="${OMARCHY_DEFAULT_SCALE:-2}"
# Resolution stays the 'auto' sentinel on a phone so omarchy-android-start keeps
# its dynamic Termux:X11 geometry path (long edge capped at OMARCHY_AUTO_LONG_EDGE).
# A detected VITURE profile substitutes a fixed native-panel WxH below.
OAD_DEFAULT_RESOLUTION="auto"

# BT-safe XKB autorepeat defaults. The outer X11 repeat layer is disabled by
# omarchy-android-start so Hyprland owns repeat timing; these document/preset the
# Wayland-side equivalents (see hypr/input.lua) and the X11 helper preset that is
# applied with: omarchy-x11-keyboard on "$OMARCHY_X11_REPEAT_DELAY" "$OMARCHY_X11_REPEAT_INTERVAL".
OMARCHY_X11_REPEAT_DELAY="${OMARCHY_X11_REPEAT_DELAY:-700}"
OMARCHY_X11_REPEAT_INTERVAL="${OMARCHY_X11_REPEAT_INTERVAL:-65}"
# BT mouse handedness default; honored by hypr/input.lua + hypr/input/pointer.lua.
OMARCHY_POINTER_LEFT_HANDED="${OMARCHY_POINTER_LEFT_HANDED:-0}"

# Resolved device profile (unknown when not a VITURE host).
OAD_DEVICE_PROFILE=unknown
OAD_DEVICE_NAME="Android phone"
# Base UI scale / refresh. Resolution may stay 'auto' (dynamic geometry) on phones.
OAD_DEVICE_RESOLUTION="$OAD_DEFAULT_RESOLUTION"
OAD_DEVICE_REFRESH_MHZ="$OAD_DEFAULT_REFRESH_MHZ"
OAD_DEVICE_SCALE="$OAD_DEFAULT_SCALE"
# Fractional Hyprland monitor scale (comfort on dense panels); empty -> keep OAD_DEVICE_SCALE.
OAD_DEVICE_MONITOR_SCALE=""

# Match the Android property blob to a device profile. Read via getprop under a
# command guard; honors an explicit OMARCHY_DEVICE_PROFILE override.
odp_match_device() {
  local haystack part
  haystack=""
  if [[ -n "${OAD_DEVICE_PROPERTIES:-}" ]]; then
    haystack="$OAD_DEVICE_PROPERTIES"
  else
    if command -v getprop >/dev/null 2>&1; then
      for part in \
        ro.product.manufacturer ro.product.model ro.product.name \
        ro.product.device ro.product.marketname ro.build.product; do
        haystack+=" $(getprop "$part" 2>/dev/null || true)"
      done
    fi
  fi
  haystack="$(printf '%s\n' "$haystack" | tr '[:upper:]' '[:lower:]')"

  # The Luma Ultra is a display-only headset (no Android SoC), so any Android
  # VITURE host is the Neckband. Only return luma-ultra for an explicit model
  # match, since it never runs this software by itself.
  case "$haystack" in
    *viture*luma*|*luma*ultra*) printf '%s\n' "luma-ultra" ;;
    *neckband*|*viture*) printf '%s\n' "neckband-pro" ;;
    *) printf '%s\n' "unknown" ;;
  esac
}

# Detect the headset host and populate OAD_DEVICE_* from the profile table.
odp_detect() {
  local profile="unknown"
  if [[ -n "${OMARCHY_DEVICE_PROFILE:-}" ]]; then
    profile="$OMARCHY_DEVICE_PROFILE"
  else
    profile="$(odp_match_device)"
  fi

  OAD_DEVICE_PROFILE=unknown
  OAD_DEVICE_NAME="Android phone"
  OAD_DEVICE_RESOLUTION="$OAD_DEFAULT_RESOLUTION"
  OAD_DEVICE_REFRESH_MHZ="$OAD_DEFAULT_REFRESH_MHZ"
  OAD_DEVICE_SCALE="$OAD_DEFAULT_SCALE"
  OAD_DEVICE_MONITOR_SCALE=""

  case "$profile" in
    neckband-pro)
      OAD_DEVICE_PROFILE=neckband-pro
      OAD_DEVICE_NAME="VITURE Pro Neckband"
      OAD_DEVICE_RESOLUTION="1920x1080"
      OAD_DEVICE_REFRESH_MHZ="90000"
      OAD_DEVICE_SCALE="1"
      OAD_DEVICE_MONITOR_SCALE="1.0"
      ;;
    luma-ultra)
      OAD_DEVICE_PROFILE=luma-ultra
      OAD_DEVICE_NAME="VITURE Luma Ultra"
      OAD_DEVICE_RESOLUTION="1920x1200"
      OAD_DEVICE_REFRESH_MHZ="120000"
      OAD_DEVICE_SCALE="1"
      OAD_DEVICE_MONITOR_SCALE="1.25"
      ;;
    *) OAD_DEVICE_PROFILE=unknown ;;
  esac
}

# Resolve the caller's display values to concrete integers. Reads the current
# OMARCHY_DISPLAY_RESOLUTION / OMARCHY_REFRESH_MHZ / OMARCHY_SCALE env values
# (already populated by config/runtime.conf), converts the 'auto' sentinel to
# the detected preset or stock default, and writes the three resolved words
# back through the named output variables (resolution, refresh, scale) via
# indirect assignment. Explicit, non-'auto' values are left untouched.
odp_resolve_display() {
  local _res _rf _sc
  _res="${OMARCHY_DISPLAY_RESOLUTION:-$OAD_DEFAULT_RESOLUTION}"
  _rf="${OMARCHY_REFRESH_MHZ:-auto}"
  _sc="${OMARCHY_SCALE:-auto}"
  [[ "$_res" == auto || -z "$_res" ]] && _res="$OAD_DEVICE_RESOLUTION"
  [[ "$_rf" == auto || -z "$_rf" ]] && _rf="$OAD_DEVICE_REFRESH_MHZ"
  [[ "$_sc" == auto || -z "$_sc" ]] && _sc="$OAD_DEVICE_SCALE"
  printf -v "$1" '%s' "$_res"
  printf -v "$2" '%s' "$_rf"
  printf -v "$3" '%s' "$_sc"
}

# Run detection once at source time so callers can rely on OAD_DEVICE_* being set.
odp_detect
