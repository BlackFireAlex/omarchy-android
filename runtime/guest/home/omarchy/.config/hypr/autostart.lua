-- Extra processes started with the nested session.
hl.on("hyprland.start", function()
  -- Do not start spice-vdagent. Its X11 clipboard path cannot connect to this
  -- native-Wayland session and can cause duplicate-agent churn under PRoot.
  -- Voxtype is optional until a model has been downloaded. Its small manager
  -- is a no-op without a model and replaces the unavailable systemd user unit.
  hl.exec_cmd("omarchy-voxtype-daemon start")
end)
