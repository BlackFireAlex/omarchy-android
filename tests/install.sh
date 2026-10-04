#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$ROOT"
export PROJECT_ROOT

# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/install.sh
source "$ROOT/lib/install.sh"

OA_INSTALL_TEMP="$(mktemp -d)"
trap 'find "$OA_INSTALL_TEMP" -depth -delete' EXIT

# Stub the downloader so the test stays offline and deterministic.
curl() {
  local output=''
  while (($#)); do
    case "$1" in
      --output)
        output="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  [[ -n "$output" ]] || {
    printf 'curl stub: missing --output\n' >&2
    return 2
  }
  printf 'stub bundle\n' >"$output"
}

bundle="$(download_release_bundle)"
asset="$(release_field asset)"

# The capture must be exactly the downloaded path: any progress line printed
# to stdout by download_release_bundle ends up inside the bundle variable and
# later makes sha256sum treat the log output as part of the file name.
if [[ "$bundle" != "$OA_INSTALL_TEMP/$asset" ]]; then
  printf 'captured bundle path is polluted: %q\n' "$bundle" >&2
  exit 1
fi

printf 'install tests passed\n'
