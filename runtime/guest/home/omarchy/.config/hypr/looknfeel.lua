hl.config({
  decoration = {
    blur   = { enabled = false },
    shadow = { enabled = false },
  },
})

-- VM compatibility: avoid virtio-gpu fence and cursor stalls.
hl.config({
  render = { direct_scanout = false },
  -- The nested Wayland backend supports a hardware cursor plane. Keep the
  -- cursor image CPU-backed for VirGL compatibility, but avoid repainting the
  -- full 1920x1200 desktop for every pointer movement.
  cursor = {
    -- Weston reports no cursor plane for its X11 output on this device.
    -- Composite the cursor into Hyprland's output so it remains visible.
    no_hardware_cursors = true,
    use_cpu_buffer = true,
    hide_on_key_press = false,
    hide_on_touch = false,
    inactive_timeout = 0,
  },
  -- Keep native Wayland for the shell and regular apps. Chromium uses this
  -- local XWayland bridge because its Vulkan presentation path explicitly
  -- rejects Ozone/Wayland when Android provides KGSL without a DRM node.
  xwayland = { enabled = true },
  -- Track changed regions so pointer motion and small animations do not redraw
  -- the full 1920x1200 desktop through every nested graphics layer.
  debug = {
    damage_tracking = 2,
    -- The nested Wayland backend can lose the final idle-frame wakeup when VFR
    -- stops its render loop. Keep frame pacing continuous so the last key or
    -- client commit is presented without waiting for another input event. The
    -- Android SHM renderbuffer skips undamaged readbacks, so idle frames do not
    -- copy the full 1920x1200 output.
    vfr = false,
  enable_stdout_logs = false,
  },
})

-- Avoid Qt/GTK accessibility helper daemons in a container with no host
-- accessibility bus. Core keyboard and pointer input are unaffected.
hl.env("NO_AT_BRIDGE", "1")
hl.env("QT_ACCESSIBILITY", "0")
hl.env("GTK_A11Y", "none")
hl.env("LANG", "C.UTF-8")
hl.env("LC_ALL", "C.UTF-8")
hl.env("DISPLAY", ":0")
hl.env("XCURSOR_THEME", "Adwaita")
hl.env("XCURSOR_SIZE", "36")
hl.env("HYPRCURSOR_SIZE", "36")
hl.env("PULSE_SERVER", "tcp:127.0.0.1:4715")
