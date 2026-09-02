-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- The nested PRoot compositor can deliver hyprland.start twice. Replace the
-- stock PRoot autostart module with an idempotent shell launch so only one
-- Quickshell/bar process can own the session at a time.
if os.getenv("OMARCHY_PROOT") == "1" then
  package.preload["default.hypr.autostart"] = function()
    hl.on("hyprland.start", function()
      hl.exec_cmd("flock -n ${XDG_RUNTIME_DIR:-/tmp}/omarchy-shell-launch.lock omarchy-launch-shell")
    end)
  end
end

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- DeX/glasses: on fractional monitor scale (e.g. the Luma Ultra at 1.25) X11
-- clients would otherwise present through XWayland and go soft. Present X apps
-- at native DPI and let Hyprland do the upscale, keeping text crisp.
hl.config({ xwayland = { force_zero_scaling = true } })

-- Device-aware pointer presets (per-device sensitivity / scroll). Safe to load:
-- it degrades to the shared input.lua baseline on any Hyprland build.
dofile(os.getenv("HOME") .. "/.config/hypr/input/pointer.lua")

-- Optional feature extras installed under ~/omarchy-android-extras (reminders
-- daemon, battery/notification shims, agents-usage regenerator). Loaded only
-- when present so a stock tree runs untouched.
local extras_autostart = os.getenv("HOME") .. "/omarchy-android-extras/autostart-addons.lua"
if io.open(extras_autostart, "r") then
  dofile(extras_autostart)
end

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })
