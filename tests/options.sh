#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

output="$("$ROOT/install.sh" print-config --gpu software --resolution 1920x1448 --refresh 120 --scale 1.5 --keyboard fr --share both --no-audio --dry-run)"

grep -F 'gpu:          software' <<<"$output" >/dev/null
grep -F 'resolution:   1920x1448' <<<"$output" >/dev/null
grep -F 'refresh:      120' <<<"$output" >/dev/null
grep -F 'scale:        1.5' <<<"$output" >/dev/null
grep -F 'keyboard:     fr' <<<"$output" >/dev/null
grep -F 'sharing:      both' <<<"$output" >/dev/null
grep -F 'audio:        false' <<<"$output" >/dev/null
grep -F 'process limit override: false' <<<"$output" >/dev/null

if "$ROOT/install.sh" print-config --refresh 999 >/dev/null 2>&1; then
  printf 'invalid refresh was accepted\n' >&2
  exit 1
fi

if "$ROOT/install.sh" print-config --name '../unsafe' >/dev/null 2>&1; then
  printf 'unsafe container name was accepted\n' >&2
  exit 1
fi

if "$ROOT/install.sh" print-config --keyboard '../unsafe' >/dev/null 2>&1; then
  printf 'unsafe keyboard layout was accepted\n' >&2
  exit 1
fi

printf 'option tests passed\n'
