# Privacy and isolation

The distribution build must never depend on a developer's existing guest or
home directory. Inputs are limited to public upstream source, repository-owned
patches/templates, and explicit build parameters.

The repository and release pipeline exclude:

- browser profiles, cookies, history, saved passwords, and crash databases;
- SSH/GPG keys, tokens, credential stores, and machine identifiers;
- shell history, editor state, AI-agent state, project directories, and logs;
- private screenshots, profiling captures, personal themes, and device
  backups (the repository's documentation images come from a fresh disposable
  release container);
- `/home` or rootfs snapshots from a development phone.

Release root filesystems are assembled from a digest-pinned Arch Linux ARM
container layer and pinned custom-source inputs. The exact installed package
closure is recorded with each bundle. The image finalizer removes package
caches, temporary files, host keys, machine IDs, and build directories before
creating the release manifest.

At runtime the PRoot guest starts isolated. Termux home and Android shared
storage are visible only when selected with `--share`.

PRoot is a compatibility layer, not an additional security boundary. Android's
application sandbox remains the outer boundary around Termux and the guest.
Direct KGSL acceleration also requires Chromium's Linux process sandbox to be
disabled in this build; the browser displays a warning banner for that reason.
Keep the default `--share none` unless browser access to Termux or phone files
is intentionally required.
