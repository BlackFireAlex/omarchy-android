-- The PRoot session is nested in a Weston surface whose dimensions follow
-- the current Termux:X11 display. A wildcard keeps this correct across fold,
-- unfold, and rotation instead of retaining the old QEMU Virtual-1 mode.
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

hl.monitor({ output = "", mode = output_mode, position = "auto", scale = omarchy_monitor_scale, transform = 0 })
