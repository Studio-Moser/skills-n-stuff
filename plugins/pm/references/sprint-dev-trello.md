# Sprint Dev — Trello Backend Detail

Backend-specific procedure blocks for `/pm:sprint-dev`, split out of `sprint-dev/SKILL.md` so GitHub/local users don't have to read past them. Only relevant when `backend == trello`; skip this whole file otherwise. Variables (`$trello_boards_json`, `$BOARD_ID`, `$WORKER_INSTRUCTIONS`, `$REVIEW_POLICY`, etc.) are the same ones resolved earlier in the SKILL.md flow — read this file in-session and continue where you left off.

## Phase 0.5: Reconcile in-review items — Trello

**Trello backend:**

Iterate boards and read cards in `LIST_REVIEW`. Each card whose description or comments contain a PR URL gets its PR state checked.

```bash
echo "$trello_boards_json" | jq -c '.[]' | while read -r board_json; do
  eval "$("$CLAUDE_PLUGIN_ROOT/scripts/for-each-board.sh" "[$board_json]")"
  # Agent executes:
  # mcp__trello__set_active_board({ boardId: $BOARD_ID })
  # lists = mcp__trello__get_lists({})
  # review_list_id = (find list where name == $LIST_REVIEW).id
  # cards = mcp__trello__get_cards_by_list_id({ listId: review_list_id })
  # For each card:
  #   - comments = mcp__trello__get_card_comments({ cardId: card.id })
  #   - extract first PR URL from card.desc + comments (regex: https://github\.com/[^/]+/[^/]+/pull/\d+)
  #   - state = `gh pr view <URL> --json state,mergedAt`
  #   - if merged   -> check-transition.sh review done   -> mcp__trello__move_card to LIST_DONE
  #   - if closed   -> check-transition.sh review needs_changes -> mcp__trello__move_card to LIST_NEEDS_CHANGES
  #                    -> mcp__trello__add_comment("PR closed without merge — flagged needs_changes")
  #   - if open     -> leave card in review
done
```

Backwards moves: when a PR is closed unmerged, a card sitting in `LIST_REVIEW` moves to `LIST_NEEDS_CHANGES`. From there a human can move it back to `LIST_IN_PROGRESS` (the `statuses` map allows `needs_changes -> in_progress`). This is the explicit Marv-fix.

## Phase 1.1: Load Ready Items — Trello

**Trello backend:**

Iterate boards and read each board's `LIST_READY_FOR_AGENT`:

```bash
ready_items=()
echo "$trello_boards_json" | jq -c '.[]' | while read -r board_json; do
  eval "$("$CLAUDE_PLUGIN_ROOT/scripts/for-each-board.sh" "[$board_json]")"
  # mcp__trello__set_active_board({ boardId: $BOARD_ID })
  # lists = mcp__trello__get_lists({})
  # ready_id = (find name == $LIST_READY_FOR_AGENT).id
  # cards = mcp__trello__get_cards_by_list_id({ listId: ready_id })
  # For each card append { id, name, desc, labels, board_id, board_name, worker_instructions: $WORKER_INSTRUCTIONS, review_policy: $REVIEW_POLICY }
done
```

The card's `desc` IS the spec (written by triage Phase 2). Parse the same `## Acceptance Criteria` / `## Code References` headers as the GitHub branch — the body structure is identical.

Per-board `worker_instructions` and `review_policy` (resolved via `for-each-board.sh`) flow through to sub-agent prompts in Phase 2B and to the close-vs-comment decision in Phase 2D.5.

## Phase 2D.5: Update Issue Tracker — Trello

**Trello backend:**

For each completed item, the orchestrator does three things on the card's home board:

```
mcp__trello__set_active_board({ boardId: $card_board_id })

# 1. Comment with the PR link (audit trail).
mcp__trello__add_comment({
  cardId: $card_id,
  text: "Implemented in PR {pr_url}. Tests: {pass/fail}. Spec compliance: {met/partial}."
})

# 2. Move the card based on PR state and the board's review_policy.
```

Decision matrix:

| PR state at completion | `review_policy=self` | `review_policy=judge` | `review_policy=auto` |
|---|---|---|---|
| Open (not yet merged) | move to `LIST_REVIEW` | move to `LIST_REVIEW` | move to `LIST_REVIEW` |
| Merged                | move to `LIST_DONE`   | move to `LIST_REVIEW` (human signs off) | move to `LIST_DONE` |
| Closed unmerged       | move to `LIST_NEEDS_CHANGES` | same | same |
| Skipped/failed        | leave in `LIST_IN_PROGRESS` | same | same |

Always validate first:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/check-transition.sh" \
  "$current_status" "$target_status" "$trello_statuses_json" \
  || { echo "transition rejected — leaving card in $current_status"; continue; }
```

Then:

```
mcp__trello__move_card({ cardId: $card_id, listId: $target_list_id })
```

Initial dispatch (before the sub-agent runs) also moves the card from `LIST_READY_FOR_AGENT` -> `LIST_IN_PROGRESS`, gated by the same `check-transition.sh` call.
