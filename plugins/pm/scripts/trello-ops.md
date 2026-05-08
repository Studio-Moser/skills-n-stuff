# Trello Operation Reference

When `backend=trello`, every PM skill performs a small set of operations. This file is the canonical mapping from operation verb to Trello MCP tool call. Each SKILL.md's Trello conditional block links here for full call shapes; the call itself is described inline in that skill so the agent can execute it without re-reading.

The MCP server in use is `@delorenj/mcp-server-trello`. Tools are invoked through Claude Code's MCP integration as `mcp__trello__<tool>`.

## Active board

Every skill MUST call `mcp__trello__set_active_board` with the current board's id at the start of each board iteration. Many tools below operate on the "active" board implicitly.

```
mcp__trello__set_active_board({ boardId: $BOARD_ID })
```

## Operation map

| PM verb | MCP tool | Notes |
|---|---|---|
| Discover boards | `mcp__trello__list_boards` | Setup only |
| Read all lists on a board | `mcp__trello__get_lists` | Setup validation; reconcile scan |
| Create a list | `mcp__trello__add_list_to_board` | Setup if a configured list name is missing |
| Read cards in a list | `mcp__trello__get_cards_by_list_id` | `listId` is the Trello list id (resolved from list name via `get_lists`) |
| Read full card | `mcp__trello__get_card` | Includes labels, comments, checklists |
| Create card in list (e.g. "Needs Triage") | `mcp__trello__add_card_to_list` | `listId`, `name`, optional `desc`, `labels` |
| Edit card description / labels | `mcp__trello__update_card_details` | Use to write specs into card descriptions |
| Move card between lists (status transition) | `mcp__trello__move_card` | MUST be preceded by `check-transition.sh` validation |
| Archive card (reject) | `mcp__trello__archive_card` | Triage rejection target |
| Add comment | `mcp__trello__add_comment` | Source attribution, PR links, audit trail |
| Read comments | `mcp__trello__get_card_comments` | Approval-cue parsing in triage; activity in reconcile |
| Recent activity (board-wide) | `mcp__trello__get_recent_activity` | Reconcile completion + stale detection |

## Resolving list names to list ids

Skills receive list NAMES from config (e.g. `LIST_NEEDS_TRIAGE="Needs Triage"`). Tools that take `listId` need the Trello id, not the name. Resolve once per board iteration:

```
lists = mcp__trello__get_lists({})        # returns [{ id, name, ... }, ...]
LIST_ID_NEEDS_TRIAGE = (find list where name == $LIST_NEEDS_TRIAGE).id
LIST_ID_READY_FOR_AGENT = ...
# ...for all seven required lists
```

Cache the resolved ids for the duration of the skill run.

## Status-transition gate

Before any `mcp__trello__move_card`, run:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/check-transition.sh" "$from_status" "$to_status" "$trello_statuses_json"
```

If exit code != 0, abort the move and surface the error to the user. This keeps Marv-style backwards moves working (they pass) while blocking truly invalid moves (e.g. `done -> in_progress` directly, which must go through `needs_changes`).

## Approval cue parsing (triage)

When a triage operation needs to know "did the user approve this?", read recent comments via `mcp__trello__get_card_comments` and look for natural-language approval cues, in priority order:

1. Most recent comment from the human is one of: "yes", "approve", "approved", "lgtm", ":+1:", ":thumbsup:", "ship it", "go", "promote".
2. The card was just moved into `LIST_READY_FOR_AGENT` by a non-bot user — implicit approval.

If neither holds, the item stays in its current list and the skill moves on.

## Card-as-conversation

Each card maps to one Shelby topical session (`session_id = "trello:" + cardId`). Inbound comment events resume that session with the comment as user input. Skills that POST a card response do so via `mcp__trello__add_comment` on the same card. This contract is owned by Shelby (W1d/W1e); skills only need to know that comments are the response channel.

## Webhook gap

The MCP server does NOT expose webhook registration. Setup registers webhooks via the Trello REST API directly:

```bash
curl -fsS -X POST "https://api.trello.com/1/webhooks/" \
  -d "key=$TRELLO_API_KEY" \
  -d "token=$TRELLO_TOKEN" \
  -d "callbackURL=$webhook_url" \
  -d "idModel=$BOARD_ID" \
  -d "description=Shelby PM webhook for $BOARD_NAME"
```

This is the single use of the REST API in the plugin; everything else goes through MCP.
