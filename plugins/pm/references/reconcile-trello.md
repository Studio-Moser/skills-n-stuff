# Reconcile — Trello Backend Detail

Backend-specific procedure blocks for `/pm:reconcile`, split out of `reconcile/SKILL.md` so GitHub/local users don't have to read past them. Only relevant when `backend == trello`; skip this whole file otherwise. Variables ($BOARD_ID, $trello_boards_json, etc.) are the same ones resolved earlier in the SKILL.md flow — read this file in-session and continue where you left off.

## Phase 0: Discover Config — board validation

**Trello backend:**

```bash
# Multi-board: every reconcile pass walks every configured board.
boards_count="$(echo "$trello_boards_json" | jq 'length')"
[ "$boards_count" -lt 1 ] && echo "ERROR: no boards configured" && exit 0
```

## Phase 1.2T: Completion tracking — Trello

Loop over boards. On each board, read `LIST_REVIEW` cards and reconcile their PR state.

```bash
echo "$trello_boards_json" | jq -c '.[]' | while read -r board_json; do
  eval "$("$CLAUDE_PLUGIN_ROOT/scripts/for-each-board.sh" "[$board_json]")"
  # Agent executes:
  # mcp__trello__set_active_board({ boardId: $BOARD_ID })
  # lists = mcp__trello__get_lists({})
  # review_id = (find name == $LIST_REVIEW).id
  # cards = mcp__trello__get_cards_by_list_id({ listId: review_id })
  # For each card:
  #   comments = mcp__trello__get_card_comments({ cardId: card.id })
  #   pr_url = first PR URL from card.desc + comments
  #   if pr_url and `gh pr view <pr_url> --json state` == "MERGED":
  #     present to user: "Card '{name}' on '{BOARD_NAME}' — PR merged. Move to Done? (yes/skip)"
  #     if yes:
  #       check-transition.sh review done $trello_statuses_json
  #       mcp__trello__move_card({ cardId: card.id, listId: <done id> })
  #       mcp__trello__add_comment({ cardId: card.id, text: "Moved to Done by /pm:reconcile — PR <pr_url> merged." })
done
```

## Phase 2.1: Stale detection — Trello

**Trello backend:**

The MCP server's card objects include a `dateLastActivity` field returned by `get_card`. To find stale cards, walk every non-terminal list on every board and check that field. (`done` is excluded — completed cards aren't stale.)

```bash
cutoff=$(date -u -v-${stale_threshold}d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -d "${stale_threshold} days ago" +%Y-%m-%dT%H:%M:%SZ)

stale_cards=()
echo "$trello_boards_json" | jq -c '.[]' | while read -r board_json; do
  eval "$("$CLAUDE_PLUGIN_ROOT/scripts/for-each-board.sh" "[$board_json]")"
  # Agent executes for each non-done list (needs_triage, ready_for_agent, in_progress, review, needs_changes, blocked):
  # mcp__trello__set_active_board({ boardId: $BOARD_ID })
  # lists = mcp__trello__get_lists({})
  # for each list_name in [LIST_NEEDS_TRIAGE, LIST_READY_FOR_AGENT, LIST_IN_PROGRESS, LIST_REVIEW, LIST_NEEDS_CHANGES, LIST_BLOCKED]:
  #   list_id = lookup
  #   cards = mcp__trello__get_cards_by_list_id({ listId: list_id })
  #   for each card with dateLastActivity < cutoff:
  #     append { id, name, list_name, dateLastActivity, BOARD_ID, BOARD_NAME }
done
```

The "exclude epic/monitor/blocker" rule from the GitHub branch translates to: skip cards whose labels include `epic` or `monitor`. Cards in `LIST_BLOCKED` are explicitly long-lived and are skipped from stale flagging by virtue of the calling list filter — `LIST_BLOCKED` is included in the loop, but the user can choose `skip` to keep them as-is.

## Phase 2.2: Stale item actions — Trello

**Trello (retriage):** validate then move card back to `LIST_NEEDS_TRIAGE`.

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/check-transition.sh" \
  "$card_current_list_key" "needs_triage" "$trello_statuses_json" \
  || echo "warning: transition $card_current_list_key -> needs_triage not allowed in current statuses map; skipping"
```

```
mcp__trello__move_card({ cardId: $card_id, listId: $needs_triage_list_id })
mcp__trello__add_comment({ cardId: $card_id, text: "Re-triaged by /pm:reconcile — stale for {N} days." })
```

If the configured `statuses` map does not allow this transition, surface the violation; do NOT silently override. The user can either widen the statuses map (back-edge from any list to `needs_triage`) or pick a different action.

**Trello (close):** archive the card.

```
mcp__trello__add_comment({ cardId: $card_id, text: "Closed as stale by /pm:reconcile — no activity for {N} days." })
mcp__trello__archive_card({ cardId: $card_id })
```

**Trello (demote):** Trello has no first-class priority. Apply or update a `P{N+1}` label via `update_card_details` and, if `planning/todos.md` exists, demote the row from `Ready` to `Monitor` (same as GitHub).

```
mcp__trello__update_card_details({
  cardId: $card_id,
  labels: ["P{next}", ...preserve other labels except old P{current}]
})
```

## Phase 3: Deferred blocker handling — Trello fallback

Phase 3 (deferred blocker handling) is GitHub-specific (uses sub-issues). The Trello
equivalent—child cards or blocking checklists—is out of scope for this plan. If a
Harness Result reports a `spawned-during-sprint` finding while running on Trello, PM
adds it to `LIST_NEEDS_TRIAGE` with `mcp__trello__add_card_to_list` and the
`spawned-during-sprint` label. Reconcile-time triage then handles it like any other
incoming item.
