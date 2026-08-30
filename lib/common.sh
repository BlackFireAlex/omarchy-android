#!/usr/bin/env bash

if [[ -n "${OA_COMMON_LOADED:-}" ]]; then
  return 0
fi
OA_COMMON_LOADED=1

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  OA_BOLD=$'\033[1m'
  OA_BLUE=$'\033[34m'
  OA_GREEN=$'\033[32m'
  OA_RED=$'\033[31m'
  OA_YELLOW=$'\033[33m'
  OA_RESET=$'\033[0m'
else
  OA_BOLD=''
  OA_BLUE=''
  OA_GREEN=''
  OA_RED=''
  OA_YELLOW=''
  OA_RESET=''
fi

info() {
  printf '%s==>%s %s\n' "$OA_BLUE$OA_BOLD" "$OA_RESET" "$*"
}

warn() {
  printf '%swarning:%s %s\n' "$OA_YELLOW$OA_BOLD" "$OA_RESET" "$*" >&2
}

success() {
  printf '%s==>%s %s\n' "$OA_GREEN$OA_BOLD" "$OA_RESET" "$*"
}

die() {
  printf '%serror:%s %s\n' "$OA_RED$OA_BOLD" "$OA_RESET" "$*" >&2
  exit 1
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

shell_quote() {
  local item
  for item in "$@"; do
    printf '%q ' "$item"
  done
  printf '\n'
}

join_by() {
  local separator="$1"
  shift
  local first=true item
  for item in "$@"; do
    if [[ "$first" == true ]]; then
      first=false
    else
      printf '%s' "$separator"
    fi
    printf '%s' "$item"
  done
}

