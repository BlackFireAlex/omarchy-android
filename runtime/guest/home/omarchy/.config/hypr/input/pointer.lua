-- pointer.lua — device-aware pointer presets for the Omarchy Android port.
--
-- Loaded from hyprland.lua (after hypr/input.lua). input.lua holds the shared
-- baseline; this file refines sensitivity / scroll per connected input device
-- when Hyprland exposes a live device list, and otherwise falls back to the
-- env-driven presets shipped with the Android runtime.
--
-- Preset table (BT mouse vs. touch vs. trackpad) mirrors the tuning guidance:
--   BT mouse   : sensitivity 0.4, scroll_factor 1.0, edge scroll
--   touch      : lower accel, edge scroll, no tap-to-drag surprises
--   trackpad   : tap_to_click off, natural_scroll off

local left_handed = os.getenv("OMARCHY_POINTER_LEFT_HANDED") == "1"

local function looks_like_touchpad(name)
  if not name then return false end
  local n = string.lower(name)
  return n:find("touchpad", 1, true) and true or false
end

local function looks_like_touchscreen(name)
  if not name then return false end
  local n = string.lower(name)
  return (n:find("touch", 1, true)) and true or false
end

-- Apply a per-pointer source baseline; device-specific tuning is layered on top.
local function apply_pointer_preset(device_name)
  local preset = { sensitivity = 0.4, scroll_factor = 1.0, scroll_method = "edge" }
  if looks_like_touchpad(device_name) then
    preset.sensitivity = 0.25
    preset.scroll_factor = 0.8
  elseif looks_like_touchscreen(device_name) then
    -- Android touch feeds the same pointer path; keep moves gentle so a long
    -- terminal drag does not over-shoot.
    preset.sensitivity = 0.3
    preset.scroll_factor = 0.8
  end
  hl.config({
    input = {
      sensitivity = preset.sensitivity,
      left_handed = left_handed,
      scroll_method = preset.scroll_method,
      scroll_factor = preset.scroll_factor,
    },
  })
end

-- Prefer live device identity via the Hyprland devices API when available;
-- otherwise apply the BT-facing baseline directly. Everything is wrapped in
-- pcall so a Hyprland build without a given API degrades to the baseline.
local devices_ok, devices = pcall(function() return hl.devices() end)
if devices_ok and type(devices) == "table" then
  local applied = false
  for _, dev in ipairs(devices or {}) do
    if dev and dev.name and (looks_like_touchpad(dev.name) or looks_like_touchscreen(dev.name)) then
      apply_pointer_preset(dev.name)
      applied = true
      break
    end
  end
  if not applied then
    apply_pointer_preset("bt-mouse")
  end
else
  apply_pointer_preset("bt-mouse")
end
