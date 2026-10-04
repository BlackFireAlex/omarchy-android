# Device Optimizations — VITURE Pro Neckband & Luma Ultra

This guide covers per-device tuning, Bluetooth mouse/keyboard setup, and DeX
(glasses) output for the two VITURE reference devices, and how to run the host
`doctor` check. All tuning flows through a few `OMARCHY_*` variables that are
resolved **automatically on start** by `runtime/host/device-presets.sh` (loaded
before `config/runtime.conf`), so in most cases you do not need to change
anything.

## Reference per-device presets

| Device | Display | GPU | Preset applied by `device-presets.sh` |
|---|---|---|---|
| VITURE Pro Neckband | drives glasses via USB-C | Adreno 642L (Snapdragon 778G) | `1920x1080 @ 90Hz`, scale 1, monitor scale 1.0 |
| VITURE Luma Ultra | native 1920x1200 micro-OLED 120 Hz | none (panel only) | `1920x1200 @ 120Hz`, scale 1, monitor scale 1.25 |

Detection is via `getprop` (`ro.product.manufacturer/model/…`): manufacturer
`VITURE` (or a model containing `neckband`) → Neckband profile; explicit
`luma` model → Luma profile; anything else → the stock phone defaults
(dynamic 1448x1920 geometry, 120 Hz, scale 2). If detection is wrong on your
unit you can force it with `OMARCHY_DEVICE_PROFILE=neckband-pro|luma-ultra`
(see below).

### Why Neckband defaults to 1080p@90 on a 1200p panel

The Neckband's mid-range Adreno 642L keeps more GPU headroom at `1920x1080 @
90Hz` than at a full 1200p@120 output, so the compositor stays stable while the
glasses scale the feed 1:1-per-eye. Prefer the Luma (which is faster and
native-1200p) for sharpest text. To run the Neckband at its native 1200p panel
instead, set `OMARCHY_DISPLAY_RESOLUTION=1920x1200` (and optionally
`OMARCHY_REFRESH_MHZ=90000`) as shown below.

## Install / first boot

From Termux, as normal:

```sh
./install.sh --yes            # or pass the per-device flags below first
/.../.local/share/omarchy-android/bin/omarchy-android start   # after install
```

A default `./install.sh --yes` now writes `auto` for resolution/refresh/scale,
so the very first `omarchy-android start` resolves the headset preset
automatically. You can also pin a device at install time:

```sh
# Neckband Pro
./install.sh --resolution 1920x1080 --refresh 90 --scale 1
# Luma Ultra
./install.sh --resolution 1920x1200 --refresh 120 --scale 1
```

### Override the auto-detected preset

Edit the generated `~/.local/share/omarchy-android/config/runtime.conf` (or the
template `runtime/host/config.example`):

```sh
OMARCHY_DISPLAY_RESOLUTION=1920x1200   # or neckband: 1920x1080
OMARCHY_REFRESH_MHZ=90000              # millihz: 90000 = 90Hz, 120000 = 120Hz
OMARCHY_SCALE=1                        # 1 | 1.25 | 1.5 | 1.75 | 2
OMARCHY_DEVICE_PROFILE=neckband-pro    # optional manual override of detection
OMARCHY_MONITOR_SCALE=1.25             # fractional reading-comfort scale
```

Explicit values always win over the detected preset.

## Bluetooth mouse + keyboard

Input arrives through the Termux:X11 bridge into Hyprland. The recommended
tuning is already the default in `~/.config/hypr/input.lua` (BT-safe):
`repeat_rate=15`, `repeat_delay=700`, `sensitivity=0.4`, `scroll_method=edge`,
and `grp:alts_toggle` so a comma list in `OMARCHY_KEYBOARD_LAYOUT` gives an
Alt+Alt layout switcher.

```sh
# layout with Alt+Alt switching (in runtime.conf):
OMARCHY_KEYBOARD_LAYOUT=us,fr
# left-handed BT mouse (in runtime.conf):
OMARCHY_POINTER_LEFT_HANDED=1
```

Pair the devices on Android (Settings → Bluetooth) before starting the desktop;
the guest sees them as Wayland input devices. The per-device pointer presets
(sensitivity/scroll per BT-mouse vs touch vs trackpad) are applied by
`~/.config/hypr/input/pointer.lua`; it reads live device identity where
available and otherwise uses the BT baseline.

Autorepeat: the outer X11 repeat layer is disabled by `omarchy-android-start`
so Hyprland owns timing for Wayland apps. For a physical BT keyboard bypassing
that path, apply the BT-safe XKB preset to the core keyboard:

```sh
omarchy-x11-keyboard set     # alias for on 700 65 (BT-safe preset)
omarchy-x11-keyboard on 700 65
```

## DeX / glasses output

- The Luma's 1200p@120 panel is the roomiest; to ease the compositor budget
  under the Termux:X11+Weston path, drop `OMARCHY_REFRESH_MHZ=60000` (one knob
  halves both the Weston and Hyprland output cadence for the panel).
- Window snapping: `SUPER+drag` to glide a window to an edge/corner; `SUPER+ARROW`
  to nudge; `SUPER+SHIFT+F` to toggle fullscreen. Dedicate `SUPER+1..9` to apps.
- Fractional scale: `SUPER+/` (up) and `SUPER+ALT+/` (down) step monitor scale
  across 1 / 1.25 / 1.6 / 2 / 3 / 4. GDK_SCALE honors only whole integers;
  after a fractional step, close stale oversized windows with
  `SUPER+CTRL+ALT+DELETE`. Edited `monitors.lua` scales persist because
  `OMARCHY_SCALE` / `OMARCHY_MONITOR_SCALE` are re-exported each start.
- XWayland presentation: `hyprland.lua` sets `xwayland.force_zero_scaling`, so X
  apps render at native DPI and Hyprland upscales on fractional scales (crisp
  text). Prefer native-Wayland apps (Foot, Chromium with
  `--ozone-platform-hint=auto`, GDK_BACKEND=wayland), which the start script
  exports to skip the fallback blit.
- Text zoom: `omarchy display text size 16` moves shell, GTK, and terminal
  scaling together; `omarchy display text size reset` restores (Foot keeps its
  size until a new terminal is opened).
- The start script holds `termux-wake-lock`, so the glasses surface stays
  awake; on low battery dial refresh to 60 Hz and prefer fullscreen over
  maximized windows to trim on-the-fly deinterlacing/upscaling.

## Verify the resolution that will be used

```sh
./install.sh doctor                                   # host readiness
./install.sh print-config --resolution auto --refresh auto --scale auto
```

`print-config` prints the resolved `device:` profile. After start,
`omarchy-android-start` prints `Device profile: <name> (WxH @ Hz, scale …)` and
writes the effective geometry to the state dir (`~/.local/state/<container>/`).
To see the actual applied resolution on the running desktop:

```sh
omarchy-android-status
# or in-guest:
hyprctl monitors
```

## Per-device smoke checklist

**Both devices**
1. `./install.sh doctor` shows only PASS/WARN (mandatory checks green).
2. `omarchy-android start` prints a `Device profile` line.
3. `hyprctl monitors` lists one output at the expected WxH@Hz and scale.
4. Clipboard (Super+C/X/V), notifications, and OCR/screenshot capture work on
   the native-Wayland session.

**Neckband Pro** — expect `1920x1080 @ 90Hz`, scale 1, monitor 1.0.
Drop to `OMARCHY_REFRESH_MHZ=60000` if the desktop janks; bump resolution to
`1920x1200` if you prefer the native panel and have GPU headroom.

**Luma Ultra** — expect `1920x1200 @ 120Hz`, scale 1, monitor 1.25. Text is
razor sharp at 1x; use `SUPER+ALT+/` to back off the fractional scale if GTK
apps look too small, and `omarchy display text size` for extra legibility.

See `runtime/guest/home/omarchy/omarchy-android-extras/README.md` for the
full ported-feature list and how to enable reminders, battery/brightness shims,
OCR, and more.
