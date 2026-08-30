#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export PROJECT_ROOT

# shellcheck source=lib/common.sh
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck source=lib/options.sh
source "$PROJECT_ROOT/lib/options.sh"
# shellcheck source=lib/platform.sh
source "$PROJECT_ROOT/lib/platform.sh"
# shellcheck source=lib/doctor.sh
source "$PROJECT_ROOT/lib/doctor.sh"
# shellcheck source=lib/plan.sh
source "$PROJECT_ROOT/lib/plan.sh"
# shellcheck source=lib/install.sh
source "$PROJECT_ROOT/lib/install.sh"

main() {
  parse_options "$@"

  case "$OA_ACTION" in
    help)
      print_help
      ;;
    doctor)
      run_doctor
      ;;
    print-config)
      print_config
      ;;
    install)
      platform_preflight
      print_config
      build_install_plan
      print_install_plan

      if [[ "$OA_DRY_RUN" == true ]]; then
        success "Dry run complete; no system state was changed."
        return 0
      fi

      perform_install
      ;;
    *)
      die "Internal error: unsupported action '$OA_ACTION'."
      ;;
  esac
}

main "$@"
