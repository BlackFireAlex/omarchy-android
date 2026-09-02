#!/usr/bin/env bash
#
# install.sh — enable the Omarchy Android feature extras in this PRoot guest.
#
# Idempotent and non-destructive: it never overwrites an existing file under
# ~/.config/omarchy and never removes anything. Run it once inside the guest
# after first boot (or from a host shell via `proot-distro login ...`).
#
# What it does:
#   1. Makes every helper in bin/ executable in place.
#   2. Installs each helper into ~/.local/bin (chmod 0755, install -D).
#   3. Prepends ~/.local/bin to $PATH in ~/.bashrc so the PROot reminder client
#      and battery/brightness shims shadow any systemd-only counterparts.
#   4. Installs the sample battery-low hook unless it already exists.

set -euo pipefail

extras_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
bin_dir="$extras_root/bin"
local_bin="$HOME/.local/bin"
bashrc="$HOME/.bashrc"

mkdir -p "$local_bin"

if [[ ! -d "$bin_dir" ]]; then
  echo "extras/bin not found at $bin_dir" >&2
  exit 1
fi

echo "Enabling Omarchy Android extras in $HOME"

# 1 + 2. Install helpers.
for helper in "$bin_dir"/*; do
  [[ -f "$helper" ]] || continue
  chmod 0755 "$helper"
  name="$(basename -- "$helper")"
  install -D -m 0755 "$helper" "$local_bin/$name"
  echo "  - installed $local_bin/$name"
done

# 3. Ensure ~/.local/bin precedes the systemd-based copies on PATH.
# shellcheck disable=SC2016  # literal text written to the guest bashrc
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$bashrc" 2>/dev/null; then
  printf '\n# Omarchy Android extras\n%s\n' 'export PATH="$HOME/.local/bin:$PATH"' >> "$bashrc"
  echo "  - prepended ~/.local/bin to PATH in $bashrc"
fi
export PATH="$HOME/.local/bin:$PATH"

# 4. Sample battery-low hook (only if absent).
hooks_dir="$HOME/.config/omarchy/hooks/battery-low.d"
if [[ -f "$extras_root/hooks/battery-low.d/010-notify" && ! -e "$hooks_dir/010-notify" ]]; then
  mkdir -p "$hooks_dir"
  install -D -m 0755 "$extras_root/hooks/battery-low.d/010-notify" "$hooks_dir/010-notify"
  echo "  - installed $hooks_dir/010-notify"
fi

echo
echo "Done. Features available now:"
echo "  - omarchy-reminder set/list/clear   (PROot reminders daemon)"
echo "  - omarchy-reminder-daemon           (started automatically on the next Hyprland session)"
echo "  - omarchy-agents-usage-daemon       (starts with the session; regenerates agent usage)"
echo "  - omarchy-battery-status            (Android battery shim; power panel + notices)"
echo "  - omarchy-notification-battery      (Super+Ctrl+Alt+B battery notice)"
echo "  - omarchy-battery-low               (runs battery-low hooks; wire to a periodic caller)"
echo "  - omarchy-brightness                (Android display brightness via Termux:Brightness)"
echo
echo "Open a new Hyprland session (or restart omarchy) for the autostart daemons."
