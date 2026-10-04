-- autostart-addons.lua — feature daemons for the Omarchy Android port.
--
-- Loaded from ~/.config/hypr/hyprland.lua (only when this file exists). Each
-- helper below is a no-op when its backing tooling is absent, so a stock tree
-- boots unchanged. Paths resolve under $HOME so this works whether the extras
-- live in place or are linked elsewhere by extras/install.sh.
local extras_bin = os.getenv("HOME") .. "/omarchy-android-extras/bin"

hl.on("hyprland.start", function()
  -- Reminders: foreground sleep-loop replacing the systemd user timer.
  hl.exec_cmd(extras_bin .. "/omarchy-reminder-daemon start")
  -- AI-agent usage regenerator: replaces the 15-minute systemd timer.
  hl.exec_cmd(extras_bin .. "/omarchy-agents-usage-daemon start")
end)
