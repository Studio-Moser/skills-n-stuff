# Triage — Trello Backend Detail

Backend-specific procedure blocks for `/pm:triage`, split out of `triage/SKILL.md` so GitHub/local users don't have to read past them. Only relevant when `backend == trello`; skip this whole file otherwise. Variables (`$trello_boards_json`, `$card_id`, etc.) are the same ones resolved earlier in the SKILL.md flow — read this file in-session and continue where you left off.

## Phase 0.2: Pull Needs-Triage Items — Trello

Iterate boards. For each board, resolve the `LIST_NEEDS_TRIAGE` list id and load its cards.

```bash
triage_items=()
echo "$trello_boards_json" | jq -c '.[]' | while read -r board_json; do
  eval "$("$CLAUDE_PLUGIN_ROOT/scripts/for-each-board.sh" "[$board_json]")"
  # Agent executes:
  # mcp__trello__set_active_board({ boardId: $BOARD_ID })
  # lists = mcp__trello__get_lists({})
  # list_id = (find list where name == $LIST_NEEDS_TRIAGE).id
  # cards  = mcp__trello__get_cards_by_list_id({ listId: list_id })
  # For each non-epic card, append
  # { id, shortUrl, name, desc, labels, board_id, board_name } to triage_items.
done
```

Cards carrying the `epic` label are goal containers, not triage work. Exclude them from
`triage_items` even though Trello requires every card to remain in a list.

## Phase 0.3: Load Existing Open Items (dedup pool) — Trello

The same loop as Phase 0.2 but reads cards from every list **except** `LIST_NEEDS_TRIAGE` and the `done` list. Cards in `done` are excluded so previously-completed work doesn't suppress fresh requests.

## Phase 1: Process rejections — Trello

Write the same `oos_file` markdown to `$oos_dir/${slug}.md` (this is backend-agnostic), then archive the card:

```
# Agent executes (board context already set during loop):
mcp__trello__add_comment({
  cardId: $card_id,
  text: "Rejected during triage. See `.pm/out-of-scope/${slug}.md` for the decision record."
})
mcp__trello__archive_card({ cardId: $card_id })
```

We use `archive_card` rather than moving to a "Rejected" list because rejection is terminal — archived cards remain searchable for the dedup pool but vanish from the active board. (If a project later wants a visible Rejected list, that is a per-board configuration concern handled in /pm:setup; for now, archive is the canonical reject.)

## Phase 1: Process duplicates — Trello

```
mcp__trello__add_comment({
  cardId: $card_id,
  text: "Duplicate of card {duplicate_card_short_url}. Closing."
})
mcp__trello__archive_card({ cardId: $card_id })
```

## Phase 2, Step 2b.1: Create XL epic and children — Trello

Run only after the user approves the displayed XL split. Trello has no parent-card
operation in the configured MCP, so preserve an explicit bidirectional representation:
each child description links the epic, and the epic receives one audit comment per
child. Keep the epic card on its current list because Trello requires a list, replace
its labels with `epic`, and exclude it from later Phase 0 scans as described above.

```
epic_card_id = $card_id
epic_short_url = $card_short_url
mcp__trello__set_active_board({ boardId: $card_board_id })
mcp__trello__update_card_details({
  cardId: epic_card_id,
  desc: "{confirmed Goal/Why body}",
  labels: ["epic"]
})

lists = mcp__trello__get_lists({})
needs_triage_list_id = (find list where name == $LIST_NEEDS_TRIAGE).id
xl_child_ids = []
xl_child_urls = []
```

Create each confirmed child on the epic's home board in blocker-first order. Each child
starts in the existing `status/needs-triage` state; use earlier values from
`xl_child_urls` for its `Blockers` field.

```
child = mcp__trello__add_card_to_list({
  listId: needs_triage_list_id,
  name: "{child title}",
  desc: "Part of epic: {epic_short_url}\n\n{child spec content}",
  labels: ["status/needs-triage", "size/{child_size}"]
})
mcp__trello__add_comment({
  cardId: epic_card_id,
  text: "Child: {child.shortUrl}"
})
xl_child_ids.push(child.id)
xl_child_urls.push(child.shortUrl)
```

Return the cards in `xl_child_ids` to the shared flow as the Phase 3 carry-forward
items. Do not return `epic_card_id` as an implementation item.

## Phase 2, Step 2c: Write spec to backend — Trello

Update the card description with the spec content:

```
mcp__trello__update_card_details({
  cardId: $card_id,
  desc:   "{spec content}"     # same structured Markdown body as the GitHub template
})
```

Trello card descriptions support full Markdown. Use the canonical spec content from
`references/triage-spec-flow.md` (§ Step 2c), the same source every backend uses.

Multi-board: specs always go on the card's home board. Do not duplicate the spec across boards.

## Phase 4.2: Update backend (promote) — Trello

Promotion = move card from `LIST_NEEDS_TRIAGE` to `LIST_READY_FOR_AGENT` on the card's home board. Validate the transition first.

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/check-transition.sh" \
  "needs_triage" "ready_for_agent" "$trello_statuses_json" \
  || { echo "transition check failed — aborting promote"; continue; }
```

Then the agent executes:

```
mcp__trello__set_active_board({ boardId: $card_board_id })
lists = mcp__trello__get_lists({})
ready_list_id = (find list where name == $LIST_READY_FOR_AGENT).id

mcp__trello__move_card({
  cardId: $card_id,
  listId: ready_list_id
})

# Apply size/priority labels via update_card_details (Trello labels are board-scoped strings):
mcp__trello__update_card_details({
  cardId: $card_id,
  labels: ["{size_label}", "priority/p{priority}"]   # combined with any existing labels — preserve "status/ready" + "{owner_label}" if the board uses status/owner labels too
})
```

## Phase 4: Approval cues — Trello

The "user confirmation" gate in Phase 1 step "Confirm? (yes / reject / keep / duplicate / skip)" works in two modes for Trello:

1. **Synchronous** — the user is at the keyboard and answers the prompt directly. Same as GitHub/local.
2. **Asynchronous** — the user moved the card themselves (e.g., dragged it from "Needs Triage" to "Ready") between sessions. When the skill loads a card, check its current list. If the card is in `LIST_READY_FOR_AGENT` already, treat it as approved and skip the prompt — proceed to label the card and update planning files.

Additionally, when reading a card's comments via `mcp__trello__get_card_comments`, look for natural-language approval cues from the most recent human comment, in priority order: `"yes"`, `"approve(d)"`, `"lgtm"`, `":+1:"`, `":thumbsup:"`, `"ship it"`, `"go"`, `"promote"`. Treat as confirmation. If a more recent comment from the human says `"hold"`, `"wait"`, `"not yet"`, `"reject"`, the skill must ask for explicit confirmation.

This implements the spec's "card-to-Ready move = approval" pattern (W2c) without losing the explicit-confirm mode for sit-down sessions.
