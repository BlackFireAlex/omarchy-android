#!/usr/bin/env bash

OA_COMPONENTS_LOCK="${PROJECT_ROOT:?}/manifest/components.lock"
OA_PATCHES_LOCK="${PROJECT_ROOT:?}/manifest/patches.lock"
OA_BUILD_DEPENDENCIES_LOCK="${PROJECT_ROOT:?}/manifest/build-dependencies.lock"
OA_ARTIFACTS_LOCK="${PROJECT_ROOT:?}/manifest/artifacts.lock"

component_record() {
  local requested="$1"
  local name type upstream revision license

  while IFS='|' read -r name type upstream revision license; do
    [[ -n "$name" && "$name" != \#* ]] || continue
    if [[ "$name" == "$requested" ]]; then
      printf '%s|%s|%s|%s|%s\n' "$name" "$type" "$upstream" "$revision" "$license"
      return 0
    fi
  done <"$OA_COMPONENTS_LOCK"

  return 1
}

list_git_components() {
  local name type upstream revision license
  while IFS='|' read -r name type upstream revision license; do
    [[ -n "$name" && "$name" != \#* ]] || continue
    [[ "$type" == git ]] && printf '%s\n' "$name"
  done <"$OA_COMPONENTS_LOCK"
}

validate_component_lock() {
  local line=0 name type upstream revision license extra
  local failures=0
  declare -A seen=()

  while IFS='|' read -r name type upstream revision license extra; do
    line=$((line + 1))
    [[ -n "$name" && "$name" != \#* ]] || continue

    if [[ -n "${extra:-}" || -z "$type" || -z "$upstream" || -z "$revision" || -z "$license" ]]; then
      printf '%s:%d: malformed component record\n' "$OA_COMPONENTS_LOCK" "$line" >&2
      failures=$((failures + 1))
      continue
    fi

    if [[ -n "${seen[$name]:-}" ]]; then
      printf '%s:%d: duplicate component %s\n' "$OA_COMPONENTS_LOCK" "$line" "$name" >&2
      failures=$((failures + 1))
    fi
    seen[$name]=1

    case "$type" in
      git)
        if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
          printf '%s:%d: git revision must be a full commit hash\n' "$OA_COMPONENTS_LOCK" "$line" >&2
          failures=$((failures + 1))
        fi
        ;;
      archive) ;;
      *)
        printf '%s:%d: unsupported component type %s\n' "$OA_COMPONENTS_LOCK" "$line" "$type" >&2
        failures=$((failures + 1))
        ;;
    esac
  done <"$OA_COMPONENTS_LOCK"

  ((failures == 0))
}

validate_build_dependency_lock() {
  local line=0 parent name type upstream revision extra
  local failures=0
  declare -A seen=()

  while IFS='|' read -r parent name type upstream revision extra; do
    line=$((line + 1))
    [[ -n "$parent" && "$parent" != \#* ]] || continue

    if [[ -n "${extra:-}" || -z "$name" || -z "$upstream" ||
          ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
      printf '%s:%d: malformed build dependency record\n' "$OA_BUILD_DEPENDENCIES_LOCK" "$line" >&2
      failures=$((failures + 1))
      continue
    fi
    if [[ "$type" != submodule && "$type" != fetch-content ]]; then
      printf '%s:%d: unsupported build dependency type %s\n' "$OA_BUILD_DEPENDENCIES_LOCK" "$line" "$type" >&2
      failures=$((failures + 1))
    fi
    if [[ -n "${seen[$parent/$name]:-}" ]]; then
      printf '%s:%d: duplicate build dependency %s/%s\n' "$OA_BUILD_DEPENDENCIES_LOCK" "$line" "$parent" "$name" >&2
      failures=$((failures + 1))
    fi
    seen[$parent/$name]=1
    component_record "$parent" >/dev/null || {
      printf '%s:%d: unknown parent component %s\n' "$OA_BUILD_DEPENDENCIES_LOCK" "$line" "$parent" >&2
      failures=$((failures + 1))
    }
  done <"$OA_BUILD_DEPENDENCIES_LOCK"

  ((failures == 0))
}

validate_artifact_lock() {
  local line=0 name version upstream expected_hash license extra failures=0
  declare -A seen=()

  while IFS='|' read -r name version upstream expected_hash license extra; do
    line=$((line + 1))
    [[ -n "$name" && "$name" != \#* ]] || continue
    if [[ -n "${extra:-}" || ! "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ||
          "$upstream" != https://* || ! "$expected_hash" =~ ^[0-9a-f]{64}$ ||
          -z "$license" ]]; then
      printf '%s:%d: malformed binary artifact record\n' "$OA_ARTIFACTS_LOCK" "$line" >&2
      failures=$((failures + 1))
      continue
    fi
    if [[ -n "${seen[$name]:-}" ]]; then
      printf '%s:%d: duplicate binary artifact %s\n' "$OA_ARTIFACTS_LOCK" "$line" "$name" >&2
      failures=$((failures + 1))
    fi
    seen[$name]=1
  done < "$OA_ARTIFACTS_LOCK"

  (( failures == 0 ))
}

validate_patch_lock() {
  local line=0 component base_revision patch_path expected_hash extra
  local record locked_revision actual_hash discovered_patch relative_patch failures=0
  declare -A seen=()

  while IFS='|' read -r component base_revision patch_path expected_hash extra; do
    line=$((line + 1))
    [[ -n "$component" && "$component" != \#* ]] || continue

    if [[ -n "${extra:-}" || ! "$expected_hash" =~ ^[0-9a-f]{64}$ ||
          "$patch_path" != patches/*.patch ]]; then
      printf '%s:%d: malformed patch record\n' "$OA_PATCHES_LOCK" "$line" >&2
      failures=$((failures + 1))
      continue
    fi
    if [[ -n "${seen[$patch_path]:-}" ]]; then
      printf '%s:%d: duplicate patch %s\n' "$OA_PATCHES_LOCK" "$line" "$patch_path" >&2
      failures=$((failures + 1))
    fi
    seen[$patch_path]=1

    record="$(component_record "$component" || true)"
    if [[ -z "$record" ]]; then
      printf '%s:%d: unknown component %s\n' "$OA_PATCHES_LOCK" "$line" "$component" >&2
      failures=$((failures + 1))
      continue
    fi
    IFS='|' read -r _ _ _ locked_revision _ <<<"$record"
    if [[ "$base_revision" != "$locked_revision" ]]; then
      printf '%s:%d: patch base does not match component lock\n' "$OA_PATCHES_LOCK" "$line" >&2
      failures=$((failures + 1))
    fi
    if [[ ! -f "$PROJECT_ROOT/$patch_path" ]]; then
      printf '%s:%d: patch is missing: %s\n' "$OA_PATCHES_LOCK" "$line" "$patch_path" >&2
      failures=$((failures + 1))
      continue
    fi
    actual_hash="$(sha256sum "$PROJECT_ROOT/$patch_path")"
    actual_hash="${actual_hash%% *}"
    if [[ "$actual_hash" != "$expected_hash" ]]; then
      printf '%s:%d: checksum mismatch for %s\n' "$OA_PATCHES_LOCK" "$line" "$patch_path" >&2
      failures=$((failures + 1))
    fi
  done <"$OA_PATCHES_LOCK"

  while IFS= read -r -d '' discovered_patch; do
    relative_patch="${discovered_patch#"$PROJECT_ROOT"/}"
    if [[ -z "${seen[$relative_patch]:-}" ]]; then
      printf '%s: unlisted patch %s\n' "$OA_PATCHES_LOCK" "$relative_patch" >&2
      failures=$((failures + 1))
    fi
  done < <(find "$PROJECT_ROOT/patches" -type f -name '*.patch' -print0)

  ((failures == 0))
}
