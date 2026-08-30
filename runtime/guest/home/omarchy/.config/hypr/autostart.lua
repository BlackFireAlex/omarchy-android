-- Extra processes started with the nested session.
hl.on("hyprland.start", function()
  -- Do not start spice-vdagent. Its X11 clipboard path cannot connect to this
  -- native-Wayland session and can cause duplicate-agent churn under PRoot.
end)
