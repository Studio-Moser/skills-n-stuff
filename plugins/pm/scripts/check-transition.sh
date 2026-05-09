#!/usr/bin/env bash
# check-transition.sh — Validate a status transition against the configured map.
#
# Usage: check-transition.sh <from_status> <to_status> <statuses_json>
#   statuses_json: a JSON object mapping each status name to an array of
#                  allowed next statuses (the .trello.statuses block).
#
# Exits 0 if the transition is allowed, 1 if not, 2 on usage error.

set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: check-transition.sh <from> <to> <statuses_json>" >&2
  exit 2
fi

from="$1"
to="$2"
statuses_json="$3"

# Verify the from-status exists in the map.
if ! echo "$statuses_json" | jq -e --arg k "$from" 'has($k)' >/dev/null 2>&1; then
  echo "unknown status: $from" >&2
  exit 1
fi

# Check whether $to is in the allowed list for $from.
allowed=$(echo "$statuses_json" | jq -r --arg k "$from" '.[$k][]')
for next in $allowed; do
  if [ "$next" = "$to" ]; then
    exit 0
  fi
done

echo "invalid transition: $from -> $to (allowed: $allowed)" >&2
exit 1
