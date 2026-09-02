-- input.lua — shared keyboard/pointer baseline for the Omarchy Android port.
--
-- BT mouse + keyboard arrive through the Termux:X11 input bridge into Hyprland.
-- kb_layout stays env-driven (OMARCHY_KEYBOARD_LAYOUT, "us" fallback).
-- compose:caps is preserved; grp:alts_toggle turns a comma list in
-- OMARCHY_KEYBOARD_LAYOUT (already allowed by the regex in
-- omarchy-android-start) into an Alt+Alt runtime layout switcher.
--
-- omarchy-android-start disables the outer X11 repeat layer and lets Hyprland
-- advertise repeat timing to Wayland apps; repeat_delay/repeat_rate here are
-- that authoritative pair, tuned for BT latency.
--
-- Device-aware refinements (per-device sensitivity / scroll) live in
-- hypr/input/pointer.lua, loaded from hyprland.lua.

local keymap = os.getenv("OMARCHY_KEYBOARD_LAYOUT") or "us"
-- Optional: flip to 1 for a BT mouse held in the left hand.
local left_handed = os.getenv("OMARCHY_POINTER_LEFT_HANDED") == "1"

hl.config({
  input = {
    kb_layout  = keymap,
    -- Preserve compose:caps; both_capslock_cancel + grp:alts_toggle give a
    -- per-keymap release fallback when the BT keyboard drops combo events.
    kb_options = "compose:caps,shift:both_capslock_cancel,grp:alts_toggle",
    -- BT latency-safe auto-repeat (XKB delay 700ms / interval 65ms ~ 15/sec).
    repeat_rate  = 15,
    repeat_delay = 700,
    -- Moderate pointer boost; BT mice often need faster apparent accel.
    sensitivity  = 0.4,
    left_handed  = left_handed,
    scroll_method = "edge",
    scroll_button = 0, -- no dedicated middle-button scroll
    scroll_factor  = 1.0,
    touchpad = {
      natural_scroll     = false,
      disable_while_typing = true,
      scroll_factor      = 0.8,
      -- Phone has no physical touchpad; keep TapToClick off to avoid the
      -- Termux:X11 touch->pointer translation double-firing drag/tap.
      tap_to_click       = false,
    },
  },
})
