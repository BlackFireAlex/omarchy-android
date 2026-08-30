# Security policy

## Supported releases

Security fixes are provided for the latest `0.1.x` release while the project is
in that series. Older release assets may remain downloadable for rollback, but
should not be treated as supported after a security update is published.

## Reporting a vulnerability

Use **Report a vulnerability** in the repository's **Security** tab. This sends
the report privately through GitHub's private vulnerability reporting flow.
Do not include exploit details, credentials, device identifiers, or private
logs in a public issue.

Include the affected release, Android and device model, GPU, reproduction
steps, impact, and the smallest redacted diagnostic output needed to reproduce
the problem.

## Security model

- Omarchy Android does not require root and does not modify Android system
  partitions.
- PRoot is a compatibility layer, not a virtual machine or sandbox. Android's
  Termux application sandbox is the outer security boundary.
- The default `--share none` mode does not bind Termux home or Android shared
  storage into the guest. Enabling another share mode expands what guest
  applications can access.
- Direct KGSL acceleration requires Chromium to run without its normal Linux
  process and GPU sandboxes. Treat browser content accordingly and keep the
  project, Chromium, Termux, and Termux:X11 updated.
- The installer refuses to overwrite an existing target container and verifies
  the release bundle before extraction.
