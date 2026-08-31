# Clean build pipeline

The host and guest graphics stacks are built separately because Termux uses
Android/Bionic while the PRoot guest uses Arch Linux ARM/glibc.

- `host/build-weston.sh` builds the patched nested X11 backend in Termux.
- `guest/build-graphics.sh` runs inside a disposable Arch Linux ARM builder and
stages the pinned Mesa/KGSL, Aquamarine, and Hyprland builds under
`/opt/omarchy-android`. `guest/audit-graphics.sh` rejects missing/non-ARM64
drivers, incorrect package prefixes, a misplaced Turnip ICD, and unexpected
Aquamarine linkage before checksums are emitted.

Both scripts refuse to reuse build directories. Source checkouts must already
be at the revisions in `manifest/components.lock` with the reviewed patch
series applied. Transitive custom-source dependencies are recorded separately in
`manifest/build-dependencies.lock`; Hyprland's tree pins its Git submodules and
its CMake file pins the Glaze release represented there. The orchestrated build
verifies each resulting commit and forces the pinned Glaze fetch instead of
accepting a coincidentally compatible system package. A scoped pkg-config
wrapper likewise forces Hyprland's protocol XML to come from its pinned
submodule while delegating every other lookup to Arch. Release assembly invokes
these scripts in a fresh builder;
it never compiles inside or copies files from a user's existing Omarchy guest.

Run `host/prepare-guest-builder.sh` from Termux to create the disposable,
native-ARM64 Arch builder and install the dependencies in `guest/packages.txt`.
The bootstrap also applies the pacman 7 settings required under PRoot; it does
not modify the user's Omarchy container. The source image and its primary OCI
layer digest are pinned to `danhunsaker/archlinuxarm:20260517`; the builder
refuses a mismatched base.

Then run `host/build-guest-graphics.sh`. It mounts only this project, the
separate local forks, and the artifact destination into an isolated PRoot
session. The guest creates disposable writable source clones, checks out the
locked upstream revisions, reapplies the reviewed patch series, initializes pinned
submodules, and performs a clean build. Its default output is ignored under
`.work/guest-artifacts/graphics`.

The host runtime uses Termux's packaged Weston executable and GL renderer. The
builder therefore compiles and installs only the patched `x11-backend.so`
module used through `WESTON_MODULE_MAP`; unrelated Weston backends, clients,
and renderers are not release artifacts.

`host/build-release.sh VERSION` assembles the sanitized rootfs, requires the
exact `manifest/packages-aarch64-VERSION.lock` package closure, adds the project
and Weston license texts, records component/patch/package checksums, and emits
the outer bundle plus SHA-256 sidecar under `.work/releases/`.

## GitHub Actions image rebuild

`.github/workflows/build-image.yml` performs a clean, native ARM64 rebuild on
GitHub's `ubuntu-24.04-arm` runner. It verifies the locked Arch Linux ARM OCI
manifest, fetches only the pinned source revisions, reapplies the reviewed patch
series, rebuilds Mesa/Aquamarine/Hyprland, assembles and privacy-audits the
guest, and uploads these workflow artifacts:

- the compressed ARM64 rootfs image;
- its exact generated package inventory;
- the image manifest and SHA-256 checksums; and
- the rootfs member list used by the structural audit.

The generated closure must exactly match
`manifest/packages-aarch64-edge.lock`. If Arch Linux ARM changes, CI fails and
uploads the newly resolved inventory as a small `package-drift-*` artifact for
review; it never silently publishes a different image.

Every push to `main` rebuilds the guest image. A semantic release tag such as
`v0.1.1` additionally downloads the checksum-pinned Android/Bionic host payload,
assembles the complete installer bundle, publishes both the bundle and SHA-256
sidecar as a GitHub Release, verifies GitHub's uploaded-asset digest, and then
atomically updates `manifest/release.lock` on `main`. End users only download
the resulting precompiled bundle; they do not run this build pipeline.

The host payload contains only the patched Weston module, two small Termux
helpers, and their required license texts. It was extracted and byte-verified
from the accepted `v0.1.0` release by `host/package-host-bootstrap.sh`; its URL,
checksum, and source-bundle checksum are locked in
`manifest/host-artifacts.lock`. Future host changes must be rebuilt and tested
from Termux before publishing and pinning a new payload.
