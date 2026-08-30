#!/usr/bin/env bash

set -Eeuo pipefail

mesa_source="${1:-}"
aquamarine_source="${2:-}"
hyprland_source="${3:-}"
artifact_root="${4:-/opt/omarchy-android}"
build_root="${5:-/var/tmp/omarchy-android-build}"
install_root="${OMARCHY_INSTALL_ROOT:-/opt/omarchy-android}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ -z "$mesa_source" || -z "$aquamarine_source" || -z "$hyprland_source" ]]; then
  printf 'usage: %s MESA_SOURCE AQUAMARINE_SOURCE HYPRLAND_SOURCE [ARTIFACT_ROOT] [BUILD_ROOT]\n' "$0" >&2
  exit 2
fi
[[ -r /etc/arch-release ]] || {
  printf 'This builder must run inside Arch Linux ARM.\n' >&2
  exit 1
}
for path in "$mesa_source" "$aquamarine_source" "$hyprland_source" "$artifact_root" "$build_root" "$install_root"; do
  [[ "$path" == /* ]] || {
    printf 'All paths must be absolute: %s\n' "$path" >&2
    exit 2
  }
done
[[ -f "$mesa_source/meson.build" ]] || { printf 'Invalid Mesa source.\n' >&2; exit 1; }
[[ -f "$aquamarine_source/CMakeLists.txt" ]] || { printf 'Invalid Aquamarine source.\n' >&2; exit 1; }
[[ -f "$hyprland_source/CMakeLists.txt" ]] || { printf 'Invalid Hyprland source.\n' >&2; exit 1; }
[[ "${OMARCHY_GLAZE_REVISION:-}" =~ ^[0-9a-f]{40}$ ]] || {
  printf 'OMARCHY_GLAZE_REVISION must be set from manifest/build-dependencies.lock.\n' >&2
  exit 2
}
[[ ! -e "$artifact_root" ]] || {
  printf 'Refusing to overwrite artifact root: %s\n' "$artifact_root" >&2
  exit 1
}
[[ ! -e "$build_root" ]] || {
  printf 'Refusing to reuse build root: %s\n' "$build_root" >&2
  exit 1
}

jobs="${OMARCHY_BUILD_JOBS:-$(nproc)}"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || {
  printf 'OMARCHY_BUILD_JOBS must be a positive integer.\n' >&2
  exit 2
}
(( jobs > 4 )) && jobs=4

mesa_build="$build_root/mesa"
mesa_stage="$artifact_root/mesa"
mesa_build_pkgconfig="$build_root/mesa-build-pkgconfig"
aquamarine_build="$build_root/aquamarine"
aquamarine_stage="$artifact_root/aquamarine"
aquamarine_prefix="$install_root/aquamarine"
aquamarine_destdir="$build_root/aquamarine-destdir"
aquamarine_build_pkgconfig="$build_root/aquamarine-build-pkgconfig"
hyprland_build="$build_root/hyprland"
hyprland_stage="$artifact_root/hyprland"
hyprland_prefix="$install_root/hyprland"
hyprland_destdir="$build_root/hyprland-destdir"
mkdir -p "$build_root" "$mesa_stage/root"

meson setup "$mesa_build" "$mesa_source" \
  --prefix=/usr \
  -Dplatforms=x11,wayland \
  -Dgallium-drivers=freedreno,zink,virgl,llvmpipe \
  -Dgallium-va=disabled \
  -Dgallium-mediafoundation=disabled \
  -Dvulkan-drivers=freedreno \
  -Dvulkan-layers= \
  -Degl=enabled \
  -Dgles2=enabled \
  -Dglvnd=enabled \
  -Dglx=dri \
  -Dlibunwind=disabled \
  -Dintel-rt=disabled \
  -Dmicrosoft-clc=disabled \
  -Dvalgrind=disabled \
  -Dgles1=disabled \
  -Dfreedreno-kmds=kgsl \
  -Dbuildtype=release
meson compile -C "$mesa_build" -j "$jobs"
DESTDIR="$mesa_stage/root" meson install -C "$mesa_build"

# Build every consumer against the Mesa artifact we just produced, rather than
# whichever Mesa happens to be installed in the disposable builder image.
export CMAKE_PREFIX_PATH="$mesa_stage/root/usr${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export LD_LIBRARY_PATH="$mesa_stage/root/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Mesa is deliberately packaged under mesa/root/usr. Its release metadata must
# retain prefix=/usr for that nested userspace, while consumers in this build
# need the staged headers and libraries rather than Arch's system Mesa.
mkdir -p "$mesa_build_pkgconfig"
for pkgconfig_file in "$mesa_stage/root/usr/lib/pkgconfig"/*.pc; do
  sed \
    -e "s|^prefix=.*|prefix=$mesa_stage/root/usr|" \
    -e "s|^includedir=.*|includedir=$mesa_stage/root/usr/include|" \
    -e "s|^libdir=.*|libdir=$mesa_stage/root/usr/lib|" \
    -e "s|^dridriverdir=.*|dridriverdir=$mesa_stage/root/usr/lib/dri|" \
    -e "s|^gbmbackendspath=.*|gbmbackendspath=$mesa_stage/root/usr/lib/gbm|" \
    "$pkgconfig_file" >"$mesa_build_pkgconfig/${pkgconfig_file##*/}"
done
export PKG_CONFIG_PATH="$mesa_build_pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

installed_icd="$(find "$mesa_stage/root/usr/share/vulkan/icd.d" -maxdepth 1 -type f -name '*freedreno*.json' -print -quit)"
[[ -n "$installed_icd" ]] || { printf 'Mesa did not install a Freedreno ICD.\n' >&2; exit 1; }
python - "$installed_icd" "$mesa_stage/freedreno_icd.json" "$install_root/mesa/root/usr/lib/libvulkan_freedreno.so" <<'PY'
import json
import sys

source, destination, library = sys.argv[1:]
with open(source, encoding="utf-8") as stream:
    document = json.load(stream)
document["ICD"]["library_path"] = library
with open(destination, "w", encoding="utf-8") as stream:
    json.dump(document, stream, indent=4)
    stream.write("\n")
PY

cmake -S "$aquamarine_source" -B "$aquamarine_build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$aquamarine_prefix"
cmake --build "$aquamarine_build" --parallel "$jobs"
DESTDIR="$aquamarine_destdir" cmake --install "$aquamarine_build"
mkdir -p "$aquamarine_stage"
cp -a "$aquamarine_destdir$aquamarine_prefix/." "$aquamarine_stage/"

# Keep the shipped pkg-config prefix relocatable to its final guest location,
# but give the following build a private view of the staged headers/library.
mkdir -p "$aquamarine_build_pkgconfig"
sed \
  -e "s|^prefix=.*|prefix=$aquamarine_stage|" \
  -e "s|^includedir=.*|includedir=$aquamarine_stage/include|" \
  -e "s|^libdir=.*|libdir=$aquamarine_stage/lib|" \
  "$aquamarine_stage/lib/pkgconfig/aquamarine.pc" \
  >"$aquamarine_build_pkgconfig/aquamarine.pc"

# Hyprland discovers Aquamarine through pkg-config. Do not add its final-prefix
# metadata directory to CMAKE_PREFIX_PATH here: CMake would prioritize the
# shipped .pc file over the build-only staged view below.
export PKG_CONFIG_PATH="$aquamarine_build_pkgconfig:$PKG_CONFIG_PATH"
export LD_LIBRARY_PATH="$aquamarine_stage/lib:$LD_LIBRARY_PATH"
export GIT_COMMIT_HASH
GIT_COMMIT_HASH="$(git -C "$hyprland_source" rev-parse HEAD 2>/dev/null || printf unknown)"

cmake -S "$hyprland_source" -B "$hyprland_build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_DISABLE_FIND_PACKAGE_glaze=TRUE \
  -DPKG_CONFIG_EXECUTABLE="$script_dir/pkg-config-pinned-sources.sh" \
  -DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH" \
  -DCMAKE_INSTALL_PREFIX="$hyprland_prefix"
actual_glaze_revision="$(git -C "$hyprland_build/_deps/glaze-src" rev-parse HEAD)"
[[ "$actual_glaze_revision" == "$OMARCHY_GLAZE_REVISION" ]] || {
  printf 'Locked Glaze mismatch: expected %s, got %s\n' \
    "$OMARCHY_GLAZE_REVISION" "$actual_glaze_revision" >&2
  exit 1
}
cmake --build "$hyprland_build" --parallel "$jobs"
DESTDIR="$hyprland_destdir" cmake --install "$hyprland_build"
mkdir -p "$hyprland_stage"
cp -a "$hyprland_destdir$hyprland_prefix/." "$hyprland_stage/"

"$script_dir/audit-graphics.sh" "$artifact_root" "$install_root"

checksum_file="$build_root/graphics-SHA256SUMS"
(cd "$artifact_root" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum) \
  >"$checksum_file"
mv "$checksum_file" "$artifact_root/SHA256SUMS"
printf 'Graphics artifact staged at %s\n' "$artifact_root"
