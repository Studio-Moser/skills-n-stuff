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

for i in $(seq 0 $((n - 1))); do
  if [ "$i" -gt 0 ]; then echo "---"; fi
  board="$(echo "$boards_json" | jq -c ".[$i]")"

  echo "BOARD_ID=$(echo "$board" | jq -r '.id')"
  echo "BOARD_NAME=$(echo "$board" | jq -r '.name')"
  echo "LIST_NEEDS_TRIAGE=$(echo "$board"     | jq -r '.lists.needs_triage')"
  echo "LIST_READY_FOR_AGENT=$(echo "$board"  | jq -r '.lists.ready_for_agent')"
  echo "LIST_IN_PROGRESS=$(echo "$board"      | jq -r '.lists.in_progress')"
  echo "LIST_REVIEW=$(echo "$board"           | jq -r '.lists.review')"
  echo "LIST_DONE=$(echo "$board"             | jq -r '.lists.done')"
  echo "LIST_NEEDS_CHANGES=$(echo "$board"    | jq -r '.lists.needs_changes')"
  echo "LIST_BLOCKED=$(echo "$board"          | jq -r '.lists.blocked')"
  echo "REVIEW_POLICY=$(echo "$board"         | jq -r '.review_policy // "self"')"
  echo "APPROVAL_STEPS=$(echo "$board"        | jq -r '.approval_steps | join(",")')"
  echo "WORKER_INSTRUCTIONS=$(echo "$board"   | jq -r '.worker_instructions // ""')"
done
