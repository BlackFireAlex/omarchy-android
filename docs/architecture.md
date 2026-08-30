# Architecture

The public installer and the heavy build pipeline are intentionally separate.

```text
official upstream sources
        |
        v
pinned revisions + reviewed Android patches
        |
        v
ARM64 package/rootfs builder ----> checksummed release bundle
                                      |
                                      v
one-script Termux installer ----> isolated PRoot guest
                                      |
                    Termux:X11 <- Weston <- Hyprland <- Omarchy Shell/apps
```

The normal user path downloads verified ARM64 artifacts. Maintainers can run
the separate clean build pipeline on ARM64 devices with enough storage and
time.

## Local fork workflow

`scripts/fetch-sources.sh` materializes pristine pinned checkouts under the
ignored `.work/` directory. `scripts/create-local-forks.sh` creates independent
Git repositories beside this project, each with an `upstream` remote and an
`omarchy-android` branch. It never creates or pushes a public remote.

## Runtime layers

1. Termux:X11 owns the Android surface and input bridge.
2. Patched Weston provides a nested Wayland parent with accurate XRandR refresh
   timing.
3. Patched Aquamarine/Hyprland handle the Android/KGSL buffer constraints.
4. Omarchy Shell supplies the bar, launcher, notifications, and OSD.
5. Applications use native ARM64 binaries inside PRoot. The shell and regular
   applications use Wayland; Chromium uses a local XWayland presentation bridge
   because its Vulkan compositor rejects this DRM-less KGSL Wayland path.

PRoot translates filesystem paths and intercepts guest system calls. It does
not emulate the ARM64 CPU. The design therefore minimizes filesystem chatter,
service auto-activation, and unnecessary helper processes.
