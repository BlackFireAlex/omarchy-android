# Contributing

Bug reports and focused pull requests are welcome.

Before filing a bug, run:

```bash
./install.sh doctor
~/.local/share/omarchy-android/bin/omarchy-android status
```

Include the Android version, device model, GPU, selected installer options,
and redacted output. Never attach credentials, browser profiles, complete home
directories, or unreviewed diagnostic archives.

Before opening a pull request, run:

```bash
./scripts/validate.sh
git diff --check
```

Changes to pinned source patches must also update `manifest/patches.lock`.
Changes to release inputs must keep the clean-builder, relocation, license,
and privacy checks passing. Generated build directories and device-specific
runtime state belong under ignored `.work/` paths, not in the repository.
