#!/bin/sh

# Force Hyprland to consume the protocol XML from its commit-pinned submodule.
# Every other pkg-config query is delegated unchanged to the builder system.
for argument do
  case "$argument" in
    hyprland-protocols*) exit 1 ;;
  esac
done
exec /usr/bin/pkg-config "$@"
