# Third-party software

The MIT license in [`LICENSE`](LICENSE) covers the original installer, Android
runtime integration, build orchestration, tests, and documentation in this
repository. It does not replace the licenses of Omarchy or any bundled
dependency.

## Patched upstream components

Exact upstream URLs and revisions are recorded in
[`manifest/components.lock`](manifest/components.lock). The repository's patch
series and build scripts provide the corresponding Android changes for:

- Omarchy
- Hyprland
- Aquamarine
- Weston
- Mesa/Turnip
- Termux:X11

Their upstream copyright and license terms continue to apply. The release
rootfs retains Omarchy's license at `/usr/share/omarchy/LICENSE` and packaged
license texts under `/usr/share/licenses`. The outer bundle includes the
Omarchy Android and patched Weston license texts under
`host/share/licenses`.

## Arch Linux ARM package closure

The release image contains an Arch Linux ARM userspace and its transitive
dependencies. The exact package names and versions for `v0.1.0` are recorded in
[`manifest/packages-aarch64-0.1.0.lock`](manifest/packages-aarch64-0.1.0.lock)
and copied into the release bundle. Package metadata remains in the rootfs at
`/var/lib/pacman/local`, with applicable license texts under
`/usr/share/licenses`.

The clean build pipeline verifies the digest-pinned base layer, pinned custom
source revisions, patch checksums, graphics artifact checksums, package
inventory, and final bundle checksum. Because Arch package repositories roll
forward, recording a package version does not guarantee that an old binary
will remain indefinitely available from every upstream mirror.

Source requests or a suspected missing notice should be reported through a
repository issue. Security-sensitive reports should follow
[`SECURITY.md`](SECURITY.md).
