# Trello Backend Procedures for /pm:ingest

Load this file only when the configured ingest backend is `trello`. The main skill
owns extraction, shared filtering, the candidate body, and watermarks.

## Phase 3: Collect Existing Open Work

For each configured board, activate it and collect cards from `needs_triage`,
`ready_for_agent`, `in_progress`, `review`, `needs_changes`, and `blocked`.
Exclude `done`.

```text
mcp__trello__set_active_board({ boardId: BOARD_ID })
lists = mcp__trello__get_lists({})
cards = mcp__trello__get_cards_by_list_id({ listId: NON_TERMINAL_LIST_ID })
```

Return each card title and description to the shared similarity check in ingest
Phase 3. Include the board name when recording a duplicate.

## Phase 4: Create the Candidate

Ingest creates cards on the first configured board. Activate it once, resolve its
configured `needs_triage` list, then create each survivor with the neutral title
and body prepared by the main skill:

```text
mcp__trello__set_active_board({ boardId: FIRST_BOARD_ID })
lists = mcp__trello__get_lists({})
card = mcp__trello__add_card_to_list({
  listId: NEEDS_TRIAGE_LIST_ID,
  name: "{candidate title}",
  desc: "{candidate body}",
  labels: ["status/needs-triage"]
})
mcp__trello__add_comment({
  cardId: card.id,
  text: "Ingested by /pm:ingest from `{source.report}` on {DATE}. Proposed outcome requires triage."
})
```

Do not add size or priority labels. Capture `card.id` and `card.shortUrl`. In the
final summary, name the first board and its configured needs-triage list.

## Errors

If no boards are configured, stop and direct the user to `/pm:setup`. On an MCP
authentication, rate-limit, read, or create failure, print the error and stop
without switching backends.
