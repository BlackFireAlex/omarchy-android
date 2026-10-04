#!/usr/bin/env bash

declare -a OA_PLAN=()

plan_add() {
  OA_PLAN+=("$1")
}

build_install_plan() {
  OA_PLAN=()
  plan_add "Acquire an exclusive installer lock under $OA_PREFIX"
  plan_add "Install missing Termux host packages: PRoot Distro, Termux:X11, Weston, PulseAudio, and the Freedreno/Turnip runtime"
  plan_add "Verify that the Termux:X11 Android companion app is installed"
  plan_add "Verify Android's Disable child process restrictions setting; use the native safety guard only for an explicitly accepted fallback"

  if [[ -n "$OA_BUNDLE" ]]; then
    plan_add "Verify the local release bundle and checksums: $OA_BUNDLE"
  else
    plan_add "Download and verify the stable ARM64 release manifest and bundle"
  fi

  plan_add "Create a new isolated PRoot container named $OA_CONTAINER from the checksum-verified Arch Linux ARM rootfs"
  plan_add "Install the pinned Omarchy runtime and Android compatibility packages inside the new container"
  plan_add "Install host start, stop, status, and Hyprland-control commands under $OA_PREFIX/bin"
  plan_add "Configure display=$OA_RESOLUTION refresh=$OA_REFRESH scale=$OA_SCALE device=${OA_DEVICE_PROFILE:-auto} keyboard=$OA_KEYBOARD gpu=$OA_GPU audio=$OA_AUDIO"
  plan_add "Configure optional host sharing mode: $OA_SHARE"
  plan_add "Run image, graphics-linkage, shell, browser, terminal, file-manager, and privacy smoke tests"
  plan_add "Write an installation manifest containing versions and checksums only"
}

print_install_plan() {
  local index=1 item
  info "Installation plan"
  for item in "${OA_PLAN[@]}"; do
    printf '  %2d. %s\n' "$index" "$item"
    index=$((index + 1))
  done
}
