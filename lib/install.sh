#!/usr/bin/env bash

OA_INSTALL_TEMP=''
OA_INSTALL_LOCK=''
OA_CREATED_CONTAINER=false
OA_CREATED_PREFIX=false

cleanup_install() {
  local status=$?

  if (( status != 0 )); then
    warn 'Installation failed; rolling back only the new Omarchy Android targets.'
    if [[ "$OA_CREATED_CONTAINER" == true ]]; then
      proot-distro remove "$OA_CONTAINER" >/dev/null 2>&1 || true
    fi
    if [[ "$OA_CREATED_PREFIX" == true && -d "$OA_PREFIX" ]]; then
      find "$OA_PREFIX" -depth -delete 2>/dev/null || true
    fi
  fi

  if [[ -n "$OA_INSTALL_TEMP" && "$OA_INSTALL_TEMP" == "${PREFIX:-/invalid}/tmp/"* && -d "$OA_INSTALL_TEMP" ]]; then
    find "$OA_INSTALL_TEMP" -depth -delete 2>/dev/null || true
  fi
  if [[ -n "$OA_INSTALL_LOCK" && -d "$OA_INSTALL_LOCK" ]]; then
    rmdir "$OA_INSTALL_LOCK" 2>/dev/null || true
  fi
  return "$status"
}

confirm_install() {
  [[ "$OA_ASSUME_YES" == true ]] && return 0
  printf 'Create container %s and host runtime %s? [y/N] ' "$OA_CONTAINER" "$OA_PREFIX"
  read -r answer
  case "$answer" in y|Y|yes|YES) ;; *) die 'Installation cancelled.' ;; esac
}

install_host_dependencies() {
  info 'Installing required Termux packages'
  pkg install -y x11-repo
  pkg install -y \
    proot-distro \
    termux-x11-nightly \
    weston \
    pulseaudio \
    xorg-xwininfo \
    mesa-vulkan-icd-freedreno \
    virglrenderer-android \
    tar \
    curl

  local required
  for required in proot-distro termux-x11 weston pulseaudio xwininfo tar sha256sum; do
    has_command "$required" || die "Required host command is still missing: $required"
  done
}

release_field() {
  local key="$1"
  awk -F '=' -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; found=1; exit} END {if (!found) exit 1}' \
    "$PROJECT_ROOT/manifest/release.lock"
}

download_release_bundle() {
  local url asset target
  url="$(release_field url)" || die 'Release lock has no download URL.'
  asset="$(release_field asset)" || die 'Release lock has no asset name.'
  target="$OA_INSTALL_TEMP/$asset"

  info "Downloading verified stable ARM64 release"
  if ! curl --fail --location --retry 3 --output "$target" "$url"; then
    die 'Release download failed. Check the network connection or pass a local file with --bundle PATH.'
  fi
  printf '%s' "$target"
}

expected_bundle_checksum() {
  local bundle="$1" sidecar checksum
  if [[ -n "$OA_BUNDLE" ]]; then
    sidecar="$bundle.sha256"
    [[ -f "$sidecar" ]] || die "Local bundles require the generated checksum sidecar: $sidecar"
    read -r checksum _ < "$sidecar"
  else
    checksum="$(release_field sha256)" || die 'Release lock has no SHA-256 checksum.'
  fi
  [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || die 'Invalid bundle SHA-256 checksum.'
  printf '%s' "$checksum"
}

verify_and_extract_bundle() {
  local bundle="$1" expected actual member manifest_version packages_file packages_checksum
  expected="$(expected_bundle_checksum "$bundle")"
  actual="$(sha256sum "$bundle" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || die "Release checksum mismatch: expected $expected, got $actual"

  while IFS= read -r member; do
    case "$member" in
      /*|../*|*/../*|*/..) die "Unsafe path in release bundle: $member" ;;
    esac
  done < <(tar -tf "$bundle")

  mkdir -p "$OA_INSTALL_TEMP/unpacked"
  tar -xf "$bundle" -C "$OA_INSTALL_TEMP/unpacked"
  [[ -f "$OA_INSTALL_TEMP/unpacked/BUNDLE-MANIFEST" ]] || die 'Bundle manifest is missing.'
  [[ -f "$OA_INSTALL_TEMP/unpacked/SHA256SUMS" ]] || die 'Bundle file checksums are missing.'
  (
    cd "$OA_INSTALL_TEMP/unpacked" || exit
    sha256sum -c SHA256SUMS
  )

  [[ "$(awk -F= '$1=="format" {print $2}' "$OA_INSTALL_TEMP/unpacked/BUNDLE-MANIFEST")" == 1 ]] || \
    die 'Unsupported bundle format.'
  [[ "$(awk -F= '$1=="architecture" {print $2}' "$OA_INSTALL_TEMP/unpacked/BUNDLE-MANIFEST")" == aarch64 ]] || \
    die 'Release bundle is not ARM64.'
  manifest_version="$(awk -F= '$1=="version" {print $2}' "$OA_INSTALL_TEMP/unpacked/BUNDLE-MANIFEST")"
  [[ "$manifest_version" =~ ^[A-Za-z0-9._-]+$ ]] || die 'Release bundle has an invalid version.'
  packages_file="$OA_INSTALL_TEMP/unpacked/manifest/packages-aarch64-$manifest_version.lock"
  [[ -f "$packages_file" ]] || die 'Release package inventory is missing.'
  packages_checksum="$(awk -F= '$1=="packages_lock_sha256" {print $2}' "$OA_INSTALL_TEMP/unpacked/BUNDLE-MANIFEST")"
  [[ "$packages_checksum" =~ ^[0-9a-f]{64}$ ]] || die 'Release package inventory checksum is missing.'
  [[ "$(sha256sum "$packages_file" | awk '{print $1}')" == "$packages_checksum" ]] || \
    die 'Release package inventory checksum mismatch.'
  [[ -f "$OA_INSTALL_TEMP/unpacked/rootfs.tar.xz" ]] || die 'Release rootfs is missing.'
  [[ -f "$OA_INSTALL_TEMP/unpacked/host/opt/weston/lib/libweston-14/x11-backend.so" ]] || \
    die 'Patched Weston backend is missing.'
  [[ -x "$OA_INSTALL_TEMP/unpacked/host/bin/omarchy-process-guard" ]] || \
    die 'Native process guard is missing.'
  [[ -x "$OA_INSTALL_TEMP/unpacked/host/bin/omarchy-x11-keyboard" ]] || \
    die 'Native keyboard helper is missing.'
  [[ -f "$OA_INSTALL_TEMP/unpacked/host/share/licenses/omarchy-android/LICENSE" ]] || \
    die 'Omarchy Android license is missing from the bundle.'
  [[ -f "$OA_INSTALL_TEMP/unpacked/host/share/licenses/weston/COPYING" ]] || \
    die 'Weston license is missing from the bundle.'
}

write_runtime_config() {
  local gpu_mode resolution refresh audio
  case "$OA_GPU" in
    auto)
      if [[ -r /dev/kgsl-3d0 && -w /dev/kgsl-3d0 ]]; then gpu_mode=kgsl; else gpu_mode=virgl; fi
      ;;
    kgsl) gpu_mode=kgsl ;;
    software) gpu_mode=virgl ;;
  esac
  resolution="$OA_RESOLUTION"
  if [[ "$OA_REFRESH" == auto ]]; then refresh=120000; else refresh=$((OA_REFRESH * 1000)); fi
  if [[ "$OA_AUDIO" == true ]]; then audio=1; else audio=0; fi

  cat > "$OA_PREFIX/config/runtime.conf" <<EOF
# Generated by Omarchy Android installer. Values are shell-safe validated enums.
OMARCHY_CONTAINER=$OA_CONTAINER
OMARCHY_GPU_MODE=$gpu_mode
OMARCHY_COMPOSITOR_GL_DRIVER=kgsl
OMARCHY_DISPLAY_RESOLUTION=$resolution
OMARCHY_REFRESH_MHZ=$refresh
OMARCHY_SCALE=$OA_SCALE
OMARCHY_KEYBOARD_LAYOUT=$OA_KEYBOARD
OMARCHY_SHARE=$OA_SHARE
OMARCHY_AUDIO=$audio
EOF
}

install_host_runtime() {
  local unpacked="$OA_INSTALL_TEMP/unpacked"
  OA_CREATED_PREFIX=true
  install -d -m 0755 "$OA_PREFIX/bin" "$OA_PREFIX/config" "$OA_PREFIX/opt/weston/lib/libweston-14"

  install -m 0755 \
    "$PROJECT_ROOT/runtime/host/omarchy-android-start" \
    "$PROJECT_ROOT/runtime/host/omarchy-android-stop" \
    "$PROJECT_ROOT/runtime/host/omarchy-android-status" \
    "$PROJECT_ROOT/runtime/host/omarchy-android-hyprctl" \
    "$OA_PREFIX/bin/"
  install -m 0755 \
    "$unpacked/host/bin/omarchy-process-guard" \
    "$unpacked/host/bin/omarchy-x11-keyboard" \
    "$OA_PREFIX/bin/"
  install -m 0755 \
    "$unpacked/host/opt/weston/lib/libweston-14/x11-backend.so" \
    "$OA_PREFIX/opt/weston/lib/libweston-14/x11-backend.so"
  write_runtime_config

  cat > "$OA_PREFIX/bin/omarchy-android" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
case "${1:-start}" in
  start) shift || true; exec "$script_dir/omarchy-android-start" "$@" ;;
  stop) shift || true; exec "$script_dir/omarchy-android-stop" "$@" ;;
  status) shift || true; exec "$script_dir/omarchy-android-status" "$@" ;;
  hyprctl) shift || true; exec "$script_dir/omarchy-android-hyprctl" "$@" ;;
  *) printf 'usage: %s {start|stop|status|hyprctl}\n' "$0" >&2; exit 2 ;;
esac
EOF
  chmod 0755 "$OA_PREFIX/bin/omarchy-android"
}

smoke_test_install() {
  local guest_mesa=/opt/omarchy-android/mesa/root/usr
  local guest_aquamarine=/opt/omarchy-android/aquamarine
  local guest_hyprland=/opt/omarchy-android/hyprland

  info 'Running installed-image smoke tests'
  # The single-quoted program is intentionally expanded by guest Bash.
  # shellcheck disable=SC2016
  proot-distro login --isolated --user omarchy \
    -e LD_LIBRARY_PATH="$guest_mesa/lib:$guest_aquamarine/lib" \
    -e PATH="$guest_hyprland/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "$OA_CONTAINER" -- bash --noprofile --norc -euc '
      test "$HOME" = /home/omarchy
      runtime_dir="$(mktemp -d)"
      trap '\''rmdir "$runtime_dir" 2>/dev/null || true'\'' EXIT
      chmod 0700 "$runtime_dir"
      export XDG_RUNTIME_DIR="$runtime_dir"
      test -f /etc/omarchy-android-release
      test -f "$HOME/.config/hypr/hyprland.lua"
      test -f "$HOME/.config/omarchy/proot-session-bus.conf"
      test -f "$HOME/.local/state/omarchy/current/theme/shell.toml"
      test -x /opt/omarchy-android/hyprland/bin/Hyprland
      test -f /opt/omarchy-android/mesa/root/usr/lib/libvulkan_freedreno.so
      test -f /usr/share/licenses/aquamarine/LICENSE
      test -f /usr/share/licenses/hyprland/LICENSE
      test -f /usr/share/licenses/mesa/license.rst
      test -f /usr/share/omarchy/LICENSE
      command -v quickshell
      command -v chromium
      command -v nautilus
      command -v foot
      command -v awk
      command -v uwsm-app
      command -v omarchy-launch-shell
      test "$(awk '\''BEGIN { print 42 }'\'')" = 42
      OMARCHY_PROOT=1 uwsm-app -- true
      locale -a | grep -Fxi "C.utf8"
      fc-match monospace | grep -F "JetBrainsMono Nerd Font"
      test ! -e /usr/share/omarchy/.git
      test ! -e "$HOME/.ssh"
      for browser_state in History Cookies "Login Data" "Web Data"; do
        test ! -e "$HOME/.config/chromium/Default/$browser_state"
      done
      test ! -e "$HOME/.bash_history"
      test ! -s /etc/machine-id
      ! find /var/cache/pacman/pkg /var/log -type f -print -quit 2>/dev/null | grep -q .
      ! ldd /opt/omarchy-android/hyprland/bin/Hyprland | grep -F "not found"
      /opt/omarchy-android/hyprland/bin/Hyprland --version
      chromium --version
      foot --version
      pacman -Q nautilus
      quickshell --version
    '
}

perform_install() {
  local target_root bundle expected actual
  target_root="${PREFIX:?}/var/lib/proot-distro/containers/$OA_CONTAINER/rootfs"
  [[ ! -e "$target_root" ]] || die "Target container already exists: $OA_CONTAINER"
  [[ ! -e "$OA_PREFIX" ]] || die "Host runtime path already exists: $OA_PREFIX"

  confirm_install
  install_host_dependencies

  OA_INSTALL_LOCK="${OA_PREFIX}.install-lock"
  mkdir -p "$(dirname -- "$OA_PREFIX")"
  mkdir "$OA_INSTALL_LOCK" 2>/dev/null || die "Another installer owns the lock: $OA_INSTALL_LOCK"
  OA_INSTALL_TEMP="$(mktemp -d "${PREFIX:?}/tmp/omarchy-android-install.XXXXXX")"
  trap cleanup_install EXIT

  if [[ -n "$OA_BUNDLE" ]]; then
    bundle="$(cd -- "$(dirname -- "$OA_BUNDLE")" && pwd -P)/$(basename -- "$OA_BUNDLE")"
    [[ -f "$bundle" ]] || die "Local bundle does not exist: $bundle"
  else
    bundle="$(download_release_bundle)"
  fi
  verify_and_extract_bundle "$bundle"

  info "Creating isolated PRoot container $OA_CONTAINER"
  OA_CREATED_CONTAINER=true
  proot-distro install --name "$OA_CONTAINER" --architecture aarch64 \
    "$OA_INSTALL_TEMP/unpacked/rootfs.tar.xz"
  # The release archive intentionally excludes live /run bind mounts. Ensure
  # the guest-side mount point exists before the runtime binds Termux's private
  # session directory onto it.
  install -d -m 0755 "$target_root/run/user/1000"

  install_host_runtime
  smoke_test_install

  expected="$(expected_bundle_checksum "$bundle")"
  actual="$(sha256sum "$bundle" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || die 'Bundle changed while it was being installed.'
  cat > "$OA_PREFIX/INSTALL-MANIFEST" <<EOF
format=1
bundle_sha256=$actual
container=$OA_CONTAINER
gpu=$OA_GPU
resolution=$OA_RESOLUTION
refresh=$OA_REFRESH
scale=$OA_SCALE
keyboard=$OA_KEYBOARD
sharing=$OA_SHARE
audio=$OA_AUDIO
EOF

  OA_CREATED_CONTAINER=false
  OA_CREATED_PREFIX=false
  success 'Omarchy Android installed and passed the clean-image smoke tests.'
  printf '\nStart it with:\n  %s/bin/omarchy-android start\n' "$OA_PREFIX"
}
