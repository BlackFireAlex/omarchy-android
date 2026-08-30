# Installer options

The installer is conservative by default: it creates a new container, shares
no host files, uses automatic display detection, and refuses unsupported
architectures.

## Graphics

- `--gpu auto` selects KGSL when a compatible render device and Mesa stack are
  available, otherwise it selects the software fallback.
- `--gpu kgsl` requires direct KGSL acceleration and fails instead of silently
  falling back.
- `--gpu software` is the compatibility path.

On supported Adreno devices, Chromium renders through ANGLE/Vulkan and the
pinned Turnip driver, with XWayland used only for local presentation. PRoot
cannot provide Chromium's normal Linux namespace/GPU sandbox around direct
KGSL access, so accelerated Chromium displays an unsupported-flag warning.
Android's Termux application sandbox remains in effect; see
[`privacy.md`](privacy.md).

GPU rendering does not imply hardware media decoding. Chromium video decode
and encode remain software paths in `v0.1.0`.

Resolution defaults to the current unfolded/folded Android window geometry,
preserves its aspect ratio, and caps the long edge at 1920 pixels for smooth
rendering. Explicit modes use `WIDTHxHEIGHT`. Refresh can be automatic or
30-240 Hz. Scale affects logical UI size, not the physical output pixel count.

`--keyboard auto` maps French Android locales to `fr` and otherwise uses `us`.
Pass an XKB layout such as `--keyboard fr` when the physical keyboard differs
from the phone locale.

## Sharing

- `none`: the guest cannot see Termux home or phone storage.
- `termux`: exposes Termux home at `~/Host/Termux`.
- `storage`: exposes Android shared storage at `~/Host/Phone`.
- `both`: enables both explicit mounts.

Sharing is never enabled merely because Termux has storage permission.

## Android process restriction

Full Omarchy needs Android Developer options -> **Disable child process
restrictions** enabled. The installer checks the same persistent property used
by the proven runtime and stops early when the restriction is active. This is
a local Android setting; ADB and wireless debugging are not required.

`--allow-process-limit` explicitly accepts the reduced-capacity fallback. The
native process guard then protects the session from Android's phantom-process
reaper, but larger application sets may still be unable to run together.

## Verification and reproducibility

The installer downloads a release bundle and verifies its manifest and pinned
SHA-256 checksum before extraction. Custom graphics and shell components build
from the exact revisions in `manifest/components.lock`; the release also
records the complete Arch package name/version closure. Arch repositories are
rolling, so bit-for-bit reconstruction additionally depends on continued
availability of those recorded package versions. See
[`builder/README.md`](../builder/README.md) and
[`THIRD_PARTY.md`](../THIRD_PARTY.md).
