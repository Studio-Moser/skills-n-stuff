#!/usr/bin/env bash
# for-each-board.sh — Emit per-board flat key=value blocks for Trello iteration.
#
# Input: trello_boards_json (the JSON array emitted by discover-config.sh).
# Output: one block per board, separated by a literal "---" line.
#         Skills that operate on cards loop over these blocks.
#
# Usage (typical pattern in SKILL.md):
#   echo "$trello_boards_json" | jq -c '.[]' | while read -r board_json; do
#     eval "$(${CLAUDE_PLUGIN_ROOT}/scripts/for-each-board.sh "[$board_json]")"
#     # ... operate on $BOARD_ID, $LIST_*, etc.
#   done
#
# Output contract: each KEY=value line is emitted with printf %q so that
# `eval` correctly handles values containing spaces, quotes, or other
# shell-special characters (e.g. list names like "Needs Triage" or
# multi-word worker_instructions). Without %q, eval would parse only the
# first whitespace-delimited token as the assignment value and try to run
# the rest as commands.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: for-each-board.sh <trello_boards_json>" >&2
  exit 2
fi

boards_json="$1"
n="$(echo "$boards_json" | jq 'length')"

if [ "$n" -eq 0 ]; then
  exit 0
fi

# emit KEY=value with the value shell-quoted via printf %q.
emit() {
  local key="$1" value="$2"
  printf '%s=%q\n' "$key" "$value"
}

for i in $(seq 0 $((n - 1))); do
  if [ "$i" -gt 0 ]; then echo "---"; fi
  board="$(echo "$boards_json" | jq -c ".[$i]")"

  emit BOARD_ID              "$(echo "$board" | jq -r '.id')"
  emit BOARD_NAME            "$(echo "$board" | jq -r '.name')"
  emit LIST_NEEDS_TRIAGE     "$(echo "$board" | jq -r '.lists.needs_triage')"
  emit LIST_READY_FOR_AGENT  "$(echo "$board" | jq -r '.lists.ready_for_agent')"
  emit LIST_IN_PROGRESS      "$(echo "$board" | jq -r '.lists.in_progress')"
  emit LIST_REVIEW           "$(echo "$board" | jq -r '.lists.review')"
  emit LIST_DONE             "$(echo "$board" | jq -r '.lists.done')"
  emit LIST_NEEDS_CHANGES    "$(echo "$board" | jq -r '.lists.needs_changes')"
  emit LIST_BLOCKED          "$(echo "$board" | jq -r '.lists.blocked')"
  emit REVIEW_POLICY         "$(echo "$board" | jq -r '.review_policy // "self"')"
  emit APPROVAL_STEPS        "$(echo "$board" | jq -r '.approval_steps | join(",")')"
  emit WORKER_INSTRUCTIONS   "$(echo "$board" | jq -r '.worker_instructions // ""')"
done
