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

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })
