#!/usr/bin/env bash

set -Eeuo pipefail

project_root="${1:-/mnt/project}"
omarchy_source="${2:-/mnt/omarchy}"
graphics_root="${3:-/mnt/graphics}"

for path in "$project_root" "$omarchy_source" "$graphics_root"; do
  [[ "$path" == /* ]] || {
    printf 'All paths must be absolute: %s\n' "$path" >&2
    exit 2
  }
done
[[ $EUID == 0 ]] || {
  printf 'Release rootfs assembly must run as root inside the disposable builder.\n' >&2
  exit 1
}
[[ -f "$omarchy_source/shell/shell.qml" ]] || {
  printf 'Invalid patched Omarchy source: %s\n' "$omarchy_source" >&2
  exit 1
}
[[ -x "$graphics_root/hyprland/bin/Hyprland" ]] || {
  printf 'Missing staged Hyprland artifact: %s\n' "$graphics_root" >&2
  exit 1
}
(cd "$graphics_root" && sha256sum -c SHA256SUMS)

if getent passwd omarchy >/dev/null; then
  printf 'The clean builder unexpectedly already has an omarchy user.\n' >&2
  exit 1
fi

useradd --create-home --uid 1000 --user-group --shell /bin/bash \
  --comment Omarchy omarchy

install -d -m 0755 /usr/share/omarchy /opt/omarchy-android
cp -a "$omarchy_source/." /usr/share/omarchy/
rm -rf /usr/share/omarchy/.git
cp -a "$graphics_root/." /opt/omarchy-android/

command_list=/var/tmp/omarchy-release-commands.$$
find /usr/share/omarchy/bin -maxdepth 1 -type f -perm -0100 -print0 > "$command_list"
while IFS= read -r -d '' command_file; do
  command_name="${command_file##*/}"
  ln -sfn "/usr/share/omarchy/bin/$command_name" "/usr/local/bin/$command_name"
done < "$command_list"
rm -f "$command_list"

home=/home/omarchy
install -d -m 0755 \
  "$home/.config" \
  "$home/.local/share/applications" \
  "$home/.local/state/omarchy/current" \
  "$home/.config/omarchy/themes" \
  "$home/Downloads" "$home/Pictures" "$home/Videos" "$home/Projects"

# Seed only files shipped by the pinned public source tree. The Android
# compatibility templates are then overlaid as an explicit allowlist.
cp -a /usr/share/omarchy/config/. "$home/.config/"
cp -a /usr/share/omarchy/applications/. "$home/.local/share/applications/"
cp -a /usr/share/omarchy/default/bashrc "$home/.bashrc"
ln -sfn /usr/share/omarchy "$home/.local/share/omarchy"

"$project_root/runtime/guest/install-runtime.sh" /
"$project_root/builder/guest/install-artifacts.sh" "$project_root" /

# Omarchy ships the public Voxtype defaults, but normally copies them only
# after installing the optional AUR package. The Android image already carries
# the checksum-locked ARM64 binary, so seed the matching clean configuration.
install -D -m 0644 \
  /usr/share/omarchy/default/voxtype/config.toml \
  "$home/.config/voxtype/config.toml"

# Omarchy Shell uses Nerd Font private-use glyphs for its system icons and
# resolves its default family through the package-owned fontconfig policy.
install -D -m 0644 \
  /usr/share/omarchy/default/fontconfig/conf.avail/50-omarchy.conf \
  /usr/share/fontconfig/conf.avail/50-omarchy.conf
ln -sfn /usr/share/fontconfig/conf.avail/50-omarchy.conf \
  /etc/fonts/conf.d/50-omarchy.conf
fc-cache -f

# Generate the exact current-theme tree used by both Hyprland and Quickshell.
# Headless mode performs no IPC, service startup, or desktop notification.
runuser -u omarchy -- env \
  HOME="$home" \
  USER=omarchy \
  LOGNAME=omarchy \
  PATH=/usr/share/omarchy/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  OMARCHY_PATH=/usr/share/omarchy \
  OMARCHY_PROOT=1 \
  OMARCHY_THEME_HEADLESS=1 \
  OMARCHY_THEME_SKIP_BACKGROUND=1 \
  omarchy-theme-set tokyo-night

for background in "$home/.local/state/omarchy/current/theme/backgrounds/"*; do
  [[ -f "$background" ]] || continue
  ln -sfn "$background" "$home/.local/state/omarchy/current/background"
  break
done

ln -sfn "$home/.local/state/omarchy/current" "$home/.config/omarchy/current"
install -d -m 0755 "$home/.config/gtk-3.0"
: > "$home/.config/gtk-3.0/bookmarks"
for dir in Downloads Projects Pictures Videos; do
  printf 'file://%s/%s %s\n' "$home" "$dir" "$dir" >> "$home/.config/gtk-3.0/bookmarks"
done

chown -R 1000:1000 "$home"
chmod 0700 "$home"

# PRoot has no systemd PID 1. Prevent package defaults from attempting network
# or desktop service activation while keeping their libraries and CLI tools.
ln -sfn /dev/null /etc/systemd/system/dbus-org.freedesktop.NetworkManager.service
ln -sfn /dev/null /etc/systemd/system/NetworkManager.service

# A release image never carries package caches, logs, machine identity, SSH
# host keys, shell history, temporary files, or the disposable build mounts.
rm -rf \
  /var/cache/pacman/pkg/* \
  /var/log/* \
  /root/.cache \
  /root/.gnupg \
  /root/.ssh \
  /root/.bash_history \
  "$home/.cache" \
  "$home/.bash_history" \
  /etc/ssh/ssh_host_*
: > /etc/machine-id

cat > /etc/omarchy-android-release <<EOF
OMARCHY_ANDROID_FORMAT=1
OMARCHY_ANDROID_ARCH=aarch64
OMARCHY_ANDROID_UPSTREAM_REVISION=$(awk -F '|' '$1=="omarchy" {print $4}' "$project_root/manifest/components.lock")
OMARCHY_ANDROID_PATCHES_LOCK_SHA256=$(sha256sum "$project_root/manifest/patches.lock" | awk '{print $1}')
EOF

printf 'Clean Omarchy Android release rootfs assembled.\n'
