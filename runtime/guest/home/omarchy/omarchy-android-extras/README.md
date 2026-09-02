# Omarchy Android Feature Extras

This directory holds the Android-port (PRoot guest) substitutes and helper
scripts for Omarchy features whose upstream implementation depends on systemd
or desktop-only hardware. The whole upstream Omarchy source is already copied
into the guest at `/usr/share/omarchy` (with every `bin/omarchy-*` linked into
`/usr/local/bin`) and Hyprland + Quickshell + Weston + PipeWire ship in the
image, so the **majority of Omarchy already runs unmodified**. This document
enumerates the port status of every portable feature, which file provides it,
and how to enable it.

## Enable everything

Inside the guest run once:

```sh
~/omarchy-android-extras/install.sh
```

It makes `bin/*` executable, installs them into `~/.local/bin` (prepended to
`$PATH`), and installs a sample battery-low hook. The background daemons
(reminders, agents-usage) start with the next Hyprland session via
`autostart-addons.lua`, which `~/.config/hypr/hyprland.lua` loads only when
this file is present. Restart Omarchy (`omarchy-android stop` then `start`)
after installing.

## Part A — Already ported (ships via the wholesale Omarchy copy)

These need **no extra work**; they were already installed by the fork because
the entire original source tree is present at `/usr/share/omarchy`. Enable or
verify each with its `omarchy` subcommand / hotkey.

| Feature | File (in the guest) | How to enable / verify |
|---|---|---|
| Omarchy CLI router, groups, help | `/usr/share/omarchy/bin/omarchy` | `omarchy --help` |
| Clipboard copy/cut/paste (Super+C/X/V), history (Super+Ctrl+V), search | `/usr/share/omarchy/bin/omarchy-clipboard-*`, `shell/plugins/clipboard/` | Native Wayland; verify via `wl-copy`/`omarchy menu clipboard` |
| Clipboard open / paste-file / paste-text | `/usr/share/omarchy/bin/omarchy-clipboard-open`, `-paste-file`, `-paste-text` | `omarchy clipboard paste-file` |
| Weather notice + forecast (Super+Ctrl+Alt+W) | `bin/omarchy-notification-weather` | Needs guest network (works; see notes) |
| Weather location set/get/clear | `bin/omarchy-weather-location` | `omarchy weather-location --set Malibu 34,-118` |
| Weather icon/status (bar widget) | `bin/omarchy-weather-status`, `-icon` | Bar weather widget |
| OCR text → clipboard (Super+Ctrl+PrtScr) | `bin/omarchy-capture-text` | `grim`+`slurp`+`tesseract`; needs `tesseract` (Part C) |
| QR capture/decode (Super+Ctrl+C menu) | `bin/omarchy-capture-qr` | Needs `zbar` (Part C) |
| Color picker → clipboard (Super+PrtScr) | `bin/omarchy-capture-qr` color path | Needs `hyprpicker` (Part C) |
| Screenshot smart/region/window/fullscreen | `bin/omarchy-capture-screenshot` | `grim`+`slurp`; PNG to `~/Pictures` + clipboard |
| Screen recording + post-processing | `bin/omarchy-capture-screenrecording` | Needs `gpu-screen-recorder`/`wf-recorder` (Part C) |
| Recording stop + bar indicator | `shell/plugins/indicators/`, `~/.local/state/omarchy` | Bar indicator; click to stop (`pkill gpu-screen-recorder`) |
| Webcam overlay sizing | `bin/omarchy-capture-webcam-resize`, `-list` | Script is portable; device itself is Android-limited (mic/cam → see Part D) |
| Transcode media (Super+Ctrl+.) | `bin/omarchy-transcode` | `ffmpeg`; fuzzy picker over `~/Pictures`,`~/Videos` |
| Transcode to ASCII art | `bin/omarchy-transcode ascii` | `imagemagick` bundled |
| ASCII FIGlet text | `omarchy ascii "..."` | Screensaver/about branding |
| Nightlight toggle (Super+Ctrl+N) | `bin/omarchy-toggle-nightlight`, `~/.config/hypr/hyprsunset.conf` | Needs `hyprsunset` (Part C) |
| Do-not-disturb (Super+Ctrl+,) | `bin/omarchy-toggle-notification-silencing` | Flag file + shell notification suppress |
| Stay-awake / idle-lock toggle | `bin/omarchy-toggle-idle` | Flag `~/.local/state/omarchy/toggles/idle-off` |
| Screensaver toggle | `bin/omarchy-toggle-screensaver` | Flag toggles/screensaver-off |
| Top-bar toggle (Super+Shift+Space) | `bin/omarchy-toggle-bar` | Hides/shows bar without killing Quickshell |
| Toggle menu + status | `bin/omarchy-toggle`, `-toggle-enabled` | Flag-file based |
| Touchpad / touchscreen toggles | `bin/omarchy-toggle-touchpad`, `-touchscreen` | via `hyprctl`; no-op if no such device |
| Idle screensaver (default 150s) + idle lock | `shell.json` idle block, `bin/omarchy-screensaver`, lock plugin | Quickshell |
| Lock screen (Super+Ctrl+L) | `shell/plugins/lock/` | Resets kb layout to first |
| Branding / About / screensaver text | `~/.config/omarchy/branding/*` | Style>About/Screensaver |
| Theme set/list/install/remove/switcher (22 themes) | `/usr/share/omarchy/themes`, `bin/omarchy-theme-*` | Style>Theme |
| Theme background pick/install/rotate | `bin/omarchy-theme-bg-*` | Super+Ctrl+Space |
| Making your own theme, hooks, per-app theme | `bin/omarchy-theme-*`, themed `*.tpl` | Docs in theme helper |
| Font set + install | `bin/omarchy-font-*`, `fontconfig/50-omarchy.conf` | Style>Font (JetBrainsMono Nerd ships) |
| Display text size (`omarchy display text size <9-20>`) | fork patch 0003 + `bin/omarchy-display-*` | Already active on fork |
| Monitor scaling step-through (Super+//Super+Alt+/) + persistence | `~/.config/hypr/monitors.lua` | Already active; scale persists |
| Monitor config | `~/.config/hypr/monitors.lua` | Setup>Monitors |
| Hyprland window mgmt (tiling/floating/layouts/group/scratchpad, etc.) | `default/hypr/*`, `bin/omarchy-hyprland-*` | Works as-is |
| Windows gaps/rounding/no-gaps/single-window-aspect | bindings + `looknfeel.lua` | Already active |
| Workspace-layout toggle (Super+L), window width save/restore | `bin/omarchy-hyprland-*` | Already active |
| Bar position/transparency/widgets; hide + panels (audio/display/clock) | `shell.json`, `bin/omarchy bar` | Audio/display/clock patched for AAudio/Android |
| Indicators widget | `shell/plugins/indicators/` | Bar |
| Notifications send/wait/dismiss/history/invoke | `bin/omarchy-notification-*` | libnotify; history via shell plugin |
| System tray | Quickshell tray plugin | Android XDG apps |
| Power panel (battery, system info) | Needs Android battery shim — use `omarchy-battery-status` (Part B) | See battery below |
| `omarchy update` (packages/config/migrations/keyring/orphans) | `bin/omarchy-update-system-pkgs`, `-keyring`, `-orphan-pkgs`, `-pacman-guard` | pacman+guard work in guest; PRoot strips snapshot/reboot |
| Channel set/current | `bin/omarchy-channel-*` | stable/rc/edge/dev |
| Update-available check + badge | `bin/omarchy-update-available`, `SystemUpdate.qml` | Fork-patched for PRoot |
| Update lock/free-space/confirm/dev/self | `bin/omarchy-update-*` | Lock + `df` checks |
| Migrate runner + notify | `omarchy-migrate`, `omarchy-migrate-notify` | Re-home notify to `autostart-addons.lua` |
| Reinstall / reinstall-configs / refresh-* | `bin/omarchy-reinstall*`, `-refresh-*` | Resets shipped defaults |
| Shell plugin management | `bin/omarchy plugin …` | Quickshell IPC; fork-patched |
| Menu extension rows | `omarchy-menu.jsonc` | shell.json/menu JSON |
| Hooks (post-boot, post-update, theme-set, font-set, battery-low) | `~/.config/omarchy/hooks/<event>.d` | bash runners (no systemctl) |
| Custom autostart apps | `~/.config/hypr/autostart.lua` `o.launch_on_start` | Fork ships this |
| Dotfiles (hyprland/input/bindings/monitors, shell.json, foot.ini, .XCompose, bashrc) | `~/.config/*` | Already shipped |
| Shell aliases/functions/env (fzf, zoxide, eza, fd, bat, tldr, starship, tmux, git, rsync, ssh) | `default/bash/*`, `~/.config/starship.toml` | Pure bash |
| Terminals (Foot default; Alacritty/Kitty/Ghostty install) | `bin/omarchy-install-terminal`, `xdg-terminal-exec` | Fork ships Foot |
| Tmux ergonomic config + cheatsheet | `default/tmux/tmux.conf` | Super+Alt+K |
| Neovim omarchy-nvim (LazyVim) | install `omarchy-nvim` | `n`, `n file` |
| Editors install + theme match + default editor | `bin/omarchy-install-editor*` | AUR/local |
| Dev environments via mise | `~/.local/bin` mise stubs, `bin/omarchy-mise-install` | portable |
| AI agents lazy-load mise stubs + panel/usage | `bin/omarchy-agent*` | usage regenerator in Part B |
| Desktop AI apps (ChatGPT/Grok/Hermes), Local LLMs (LM Studio/Ollama) | `bin/omarchy-install-ai-*` | LM Studio GUI; Ollama foreground |
| Agent skill symlinks | `~/.claude…/agents/skills` | portable |
| Crash diagnosis by PID (manual) | `bin/omarchy agent crash <pid>` | Android logcat adapter (see Part D) |
| TUI install/add/remove | `bin/omarchy-tui-*` | launcher JSON + desktop entries |
| Disk Usage, Activity (btop), Lazygit, Lazydocker, Fastfetch, Cliamp, Omacalc, speedtest | `bin/omarchy-*` user binaries | `dua`, `btop`, etc. |
| Speed tests (network/disk) | `omarchy network speedtest`, `disk speedtest` | portable |
| Herdr terminal workspaces | Herdr session manager | foreground |
| Web app add/remove + shipped web apps | `bin/omarchy-webapp-*`, Chrome windows | Chromium + fork launch-webapp patch |
| Browser install/remove + default via xdg | `bin/omarchy-install-browser*`, `xdg-settings` | portable |
| Chromium Copy URL + Download Video extensions/native hosts | `default/chromium/extensions/*` | portable |
| Chromium Google-account sign-in | `bin/omarchy-install-chromium-google-account` | installs creds |
| WhatsApp slim extension | `default/chromium/extensions/whatsapp-slim` | portable |
| Files (Nautilus) + send-via-LocalSend/transcode extensions | Nautilus + `nautilus-python` | MIME launch; usb via Termux storage |
| LocalSend share menu (Super+Ctrl+S) | `bin/omarchy share …` | LocalSend app; Android firewall caveat |
| Obsidian + theme sync | `bin/omarchy-install-obsidian` | portable |
| Omawrite, Pinta, LibreOffice, mpv, OBS, Kdenlive, Omacut | `bin/omarchy-install-*` | installs |
| PDF filling / Xournal++ annotate | evince (ships) + `xournalpp` | portable |
| Gaming installs | `bin/omarchy-install-*` | portable as installs (GPU-bound on phone) |
| Sunshine host | launch foreground (no systemd service) | Android ports; partial |
| 1Password + Bitwarden + Spotify + Signal + Dropbox + ONCE | `bin/omarchy-install-*` | re-home services to `autostart-addons.lua` / `o.launch_on_start` |
| Passwordless sudo, username/signing key | guest sudo / PRoot-root | portable-with-guest-sudo caveat |
| System stats (`--bar-widget`) | `bin/omarchy-system-stats` | reads /proc |
| Monitor/watch state helpers | `bin/omarchy-monitor-state`, `-watch` | hyprctl |
| Hardware detection helpers | `bin/omarchy-hw-*` | match no-ops on Android |
| Audio output/sink/input-mute panels | PipeWire/WirePlumber + AAudio sink | fork wires `PULSE_SERVER=tcp:127.0.0.1:4715`; mic muted by design |
| Audio tuning status/off | `bin/omarchy-audio-tuning` | degrades to no-op |
| Backups substitute | restic/tar → `~/.local/state` + Android backup | see Part C `restic` |
| Pacman/AUR package install/remove | `bin/omarchy-pkg-*` | pacman works; AUR needs base-devel+git (Part C) |
| Upload-log / debug | `bin/omarchy-debug`, `-upload-log` | portable |
| Version/branch/channel/pkgs | `bin/omarchy-version*` | reads package/state files |
| Wayland session bus / dconf DBus service | fork ships `proot-session-bus.conf`, `omarchy-dbus-service` | Already active |

## Part B — New Android substitutes in this repo (this directory)

| Feature | File(s) | What changed vs. upstream | How to enable |
|---|---|---|---|
| Reminders set/list/clear (Super+Ctrl+R) | `bin/omarchy-reminder`, `bin/omarchy-reminder-daemon` | Replaces `systemd-run --user --on-active` timers with a foreground `sleep`+notify daemon; state at `~/.local/state/omarchy/reminders.json` | `install.sh`, then `omarchy-reminder set 5 "stand up"` |
| Agents-usage 15-min regenerator | `bin/omarchy-agents-usage-daemon` | Replaces the systemd timer with a sleep-loop calling `omarchy agent usage-update` every 900s | `install.sh`; starts with session |
| Battery status/notice (Super+Ctrl+Alt+B) | `bin/omarchy-battery-status`, `bin/omarchy-notification-battery` | Android shim: reads `termux-battery-status` (termux-api), falls back to sysfs battery, else "unknown" | `install.sh`; `omarchy-battery-status` |
| Battery-low hooks | `bin/omarchy-battery-low`, `hooks/battery-low.d/010-notify` | Runs `~/.config/omarchy/hooks/battery-low.d/` from a periodic caller | wire `omarchy-battery-low` to a loop; sample hook auto-installed |
| Brightness (display) | `bin/omarchy-brightness` | Android brightness via Termux:Brightness; no-op otherwise | `install.sh`; `omarchy-brightness set 128` |
| Reminder/agents daemon autostart | `autostart-addons.lua` | Re-homes the two systemd timers into `hl.on("hyprland.start")` | loaded automatically by `hyprland.lua` when present |
| Extras installer | `install.sh` | Installs/linked the above and prepends `~/.local/bin` to PATH | run once in guest |

## Part C — Optional packages

Most of these features are scripted and portable but pull in a CLI tool. The
Arch-repo ones were added to `builder/guest/runtime-packages.txt` and appear in
the image after the rootfs is rebuilt; until then (or for AUR-only helpers)
install them manually in the guest.

| Feature | Package | In clean image? |
|---|---|---|
| OCR capture | `tesseract`, `tesseract-data-eng` | yes (`runtime-packages.txt`) |
| QR decode | `zbar` | yes |
| Color picker | `hyprpicker` | yes |
| Screen recording (Wayland) | `wf-recorder` | yes (`gpu-screen-recorder`/`tensaku` are AUR-only) |
| Nightlight | `hyprsunset` | yes |
| Disk Usage TUI | `dua-cli` | yes |
| Backup substitute | `restic` | yes |
| AUR building | `base-devel` + `git` (git already ships) | yes |
| Screenshot/Screen-record GPU tools | `gpu-screen-recorder`, `tensaku`, `lazydocker`, `paru` | AUR-only — install from the AUR in the guest |

## Part D — Deferred / blocked on Android

Bootloader/Limine/mkinitcpio, Plymouth/LUKS unlock, system reboot/shutdown/
suspend/hibernate, NetworkManager Wi-Fi/DNS overrides, Bluetooth panel
(Android owns BT), brightness via sysfs, power profiles, fwupd firmware,
Docker/Windows-VM (no KVM), SSHD+PAM/faillock, fingerprint/FIDO2, hybrid-GPU
and x86-laptop/Mac hardware, systemd-coredump crash-watch (use Android logcat
instead), USB printers, plocate timers, Tailscale/NordVPN host (use the Android
apps). See `docs/device-optimizations.md` for the nearest Android-native
replacements.

## Status

`./install.sh doctor` and `scripts/validate.sh` should remain green; the fork
acceptance flow (`tests/runtime.sh`, `audit-graphics.sh`) validates that the
shell/bar/clipboards/notifications/OCR/screenshots still work on the
native-Wayland session after these additions.
