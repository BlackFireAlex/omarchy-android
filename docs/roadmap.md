# Roadmap

## Shipped in v0.1.0

- [x] Clean installer with doctor, dry-run, safety checks, and rollback.
- [x] Native ARM64 guest with no QEMU CPU emulation.
- [x] Pinned Omarchy, Hyprland, Aquamarine, Weston, Mesa, and Termux:X11
  revisions with reviewed Android patch series.
- [x] Digest-pinned Arch Linux ARM base and recorded 555-package closure.
- [x] Checksum-verified release bundle assembled without development-phone
  home directories, profiles, histories, credentials, or machine identity.
- [x] Fresh-container install, desktop boot, application launch, input, audio,
  display scaling, 120 Hz output, and Adreno 840 GPU-path acceptance.
- [x] Public validation workflow and security-reporting policy.

## Next

- [ ] Expand the compatibility matrix across Android versions, Qualcomm GPU
  families, and non-Adreno fallback devices.
- [ ] Add hardware video decode/encode where Chromium and Android permit it.
- [ ] Publish a machine-readable SBOM alongside the package inventory.
- [ ] Add signed provenance/attestations for release artifacts.
- [ ] Reduce remaining PRoot filesystem and nested-presentation overhead.
- [ ] Extend Android replacements for Omarchy features that assume systemd.
