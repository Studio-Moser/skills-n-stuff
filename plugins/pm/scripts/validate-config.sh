#!/usr/bin/env bash
# validate-config.sh — Validate .pm/config.yml against backend-specific invariants.
#
# Usage: validate-config.sh <path-to-config.yml>
# Exits 0 on success, 1 on validation failure, 2 on usage error.

set -euo pipefail

if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "usage: validate-config.sh <path-to-.pm/config.yml>" >&2
  exit 2
fi

cfg="$1"
backend="$(yq '.backend // ""' "$cfg")"
errors=()

case "$backend" in
  github)
    [ "$(yq '.github.owner // ""' "$cfg")" = "" ] && errors+=("missing github.owner")
    [ "$(yq '.github.repo  // ""' "$cfg")" = "" ] && errors+=("missing github.repo")
    ;;
  local)
    : # items_dir has a default; nothing to enforce
    ;;
  trello)
    # boards[] non-empty
    n_boards="$(yq '.trello.boards | length' "$cfg")"
    [ "${n_boards:-0}" -lt 1 ] && errors+=("trello.boards must have at least one entry")

    # Each board has all required list keys.
    REQUIRED_LISTS=(needs_triage ready_for_agent in_progress review done needs_changes blocked)
    for i in $(seq 0 $((n_boards - 1))); do
      for k in "${REQUIRED_LISTS[@]}"; do
        v="$(yq ".trello.boards[$i].lists.$k // \"\"" "$cfg")"
        if [ -z "$v" ]; then
          errors+=("board[$i] missing required list key: $k")
        fi
      done
    done

    # statuses map: required keys present.
    for k in "${REQUIRED_LISTS[@]}"; do
      if [ "$(yq ".trello.statuses.$k // \"MISSING\"" "$cfg")" = "MISSING" ]; then
        errors+=("trello.statuses missing key: $k")
      fi
    done

    # Bidirectional invariants: done MUST include needs_changes,
    # and needs_changes MUST include in_progress.
    done_to="$(yq -o=json '.trello.statuses.done // []' "$cfg")"
    if ! echo "$done_to" | jq -e 'index("needs_changes")' >/dev/null 2>&1; then
      errors+=("trello.statuses.done must list \"needs_changes\" (back-edge done -> needs_changes)")
    fi
    nc_to="$(yq -o=json '.trello.statuses.needs_changes // []' "$cfg")"
    if ! echo "$nc_to" | jq -e 'index("in_progress")' >/dev/null 2>&1; then
      errors+=("trello.statuses.needs_changes must list \"in_progress\" (back-edge needs_changes -> in_progress)")
    fi
    ;;
  "")
    errors+=("backend is required")
    ;;
  *)
    errors+=("unknown backend: $backend")
    ;;
esac

if [ ${#errors[@]} -gt 0 ]; then
  echo "config invalid ($cfg):" >&2
  for e in "${errors[@]}"; do echo "  - $e" >&2; done
  exit 1
fi

echo "config valid: backend=$backend"
