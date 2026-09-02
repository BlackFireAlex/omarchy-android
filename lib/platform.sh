#!/usr/bin/env bash

OA_ANDROID_API=''
OA_ARCH=''
OA_PHANTOM_PROCESS_STATE='unknown'

detect_phantom_process_restriction() {
  local property_value
  property_value="$(getprop persist.sys.fflag.override.settings_enable_monitor_phantom_procs 2>/dev/null || true)"
  case "$property_value" in
    false) OA_PHANTOM_PROCESS_STATE=disabled ;;
    true|'') OA_PHANTOM_PROCESS_STATE=enabled ;;
    *) OA_PHANTOM_PROCESS_STATE=unknown ;;
  esac
}

platform_preflight() {
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || die "Do not run this installer as root."
  [[ -n "${PREFIX:-}" && -d "${PREFIX:-}/bin" ]] || die "This installer must run inside Termux."

  OA_ARCH="$(uname -m)"
  [[ "$OA_ARCH" == aarch64 || "$OA_ARCH" == arm64 ]] || die "Only native ARM64 Android is supported; found $OA_ARCH."

  if has_command getprop; then
    OA_ANDROID_API="$(getprop ro.build.version.sdk 2>/dev/null || true)"
  fi

  if [[ "$OA_ANDROID_API" =~ ^[0-9]+$ ]] && ((OA_ANDROID_API < 31)) && [[ "$OA_ALLOW_UNTESTED" != true ]]; then
    die "Android 12 or newer is currently required. Use --allow-untested only for development."
  fi

  detect_phantom_process_restriction
  if [[ "$OA_PHANTOM_PROCESS_STATE" != disabled ]]; then
    if [[ "$OA_ALLOW_PROCESS_LIMIT" == true ]]; then
      warn "Android's phantom-process restriction is active; the fallback guard limits desktop capacity."
    else
      die "Enable Android Developer options -> Disable child process restrictions, then rerun. No ADB or wireless debugging is required. Use --allow-process-limit only for the limited fallback."
    fi
  fi

  # Detect a VITURE headset host so the installer can record and emit the
  # per-device display/input preset instead of hard-coding phone tuning.
  if [[ -f "$PROJECT_ROOT/runtime/host/device-presets.sh" ]]; then
    # shellcheck source=../runtime/host/device-presets.sh
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/runtime/host/device-presets.sh"
    OA_DEVICE_PROFILE="${OAD_DEVICE_PROFILE:-unknown}"
  fi

  if [[ "$OA_GPU" == kgsl && ! -e /dev/kgsl-3d0 ]]; then
    die "--gpu kgsl was requested, but /dev/kgsl-3d0 is unavailable."
  fi

  if ! has_command cmd || ! cmd package path com.termux.x11 >/dev/null 2>&1; then
    die "Install and open the Termux:X11 Android app before continuing."
  fi
}
