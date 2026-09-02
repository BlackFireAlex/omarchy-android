-- monitors.lua — display/monitor configuration (DeX-oriented) for Omarchy Android.
--
-- The PRoot session is nested in a Weston surface whose dimensions follow the
-- current Termux:X11 display. A wildcard keeps this correct across fold,
-- unfold, and rotation instead of retaining the old QEMU Virtual-1 mode.
--
-- DeX/glasses notes:
--   * The base scale (OMARCHY_SCALE) is device-resolved by device-presets.sh
--     and exported into the guest; it drives the integer GDK_SCALE for GTK apps.
--   * A per-device fractional monitor scale (OMARCHY_MONITOR_SCALE) adds reading
--     comfort on the dense micro-OLED panels (e.g. 1.25 on the Luma Ultra) while
--     GDK_SCALE stays a whole integer, matching original Omarchy conventions.
--   * XWayland clients present at native DPI on fractional scales via
--     xwayland.force_zero_scaling (set in hyprland.lua), so X apps stay crisp.
local output_width = tonumber(os.getenv("OMARCHY_OUTPUT_WIDTH"))
local output_height = tonumber(os.getenv("OMARCHY_OUTPUT_HEIGHT"))
local refresh_mhz = tonumber(os.getenv("OMARCHY_REFRESH_MHZ"))
-- Keep Omarchy's conventional variable names: its Display panel updates
-- these declarations in place, which lets scale changes survive a restart.
local omarchy_monitor_scale = tonumber(os.getenv("OMARCHY_SCALE")) or 2
local omarchy_gdk_scale = math.floor(omarchy_monitor_scale + 0.5)
local output_mode = "preferred"

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

if output_width and output_height and refresh_mhz then
  output_mode = string.format("%dx%d@%.3f", output_width, output_height, refresh_mhz / 1000)
end

-- A device-monitor override (comma-free number) nudges only the Hyprland monitor
-- scale for extra fractional comfort; GDK_SCALE above keeps the integer. Unset
-- or zero keeps the baseline OMARCHY_SCALE value (stock phone behavior).
local monitor_scale_override = tonumber(os.getenv("OMARCHY_MONITOR_SCALE") or "")
if monitor_scale_override and monitor_scale_override > 0 then
  omarchy_monitor_scale = monitor_scale_override
end

hl.monitor({ output = "", mode = output_mode, position = "auto", scale = omarchy_monitor_scale, transform = 0 })
