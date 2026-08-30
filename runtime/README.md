# Runtime payload

`host/` contains the parameterized Termux launch stack and two small native
helpers. `host/build-helpers.sh` compiles those helpers for the current ARM64
Termux environment.

`guest/` contains only curated compatibility templates installed into a newly
assembled guest. It is an explicit allowlist, not a copy of a development
home directory. The files cover nested display sizing, keyboard mapping,
input-safe menu shortcuts, compositor performance settings, the restricted
session bus, and reliable Nautilus MIME launching.

The stable runtime defaults are native-aspect automatic sizing capped to a
1920-pixel long edge, 120 Hz, scale 2, automatic KGSL/compatibility selection,
and audio enabled. Installer options generate `config/runtime.conf` without
rewriting the templates.
