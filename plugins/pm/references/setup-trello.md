# Trello Backend Setup for /pm:setup

Load this only when the user selects the Trello backend. It covers the backend
interview, Phase 3 config generation, and Phase 6 provisioning. Return to the
main skill between sections.

## Backend Interview

Ask these in sequence. Each step uses an MCP tool; do not proceed past a failed call.

1. **Authenticate.** Confirm `TRELLO_API_KEY` and `TRELLO_TOKEN` are exported in the user's shell. If either is missing:

   "I need a Trello API key and token. Get them at https://trello.com/app-key (key) and the 'Token' link on that page. Add to your shell profile:

   ```bash
   export TRELLO_API_KEY=...
   export TRELLO_TOKEN=...
   ```

   Then re-run /pm:setup."

   Stop the wizard if either is missing.

2. **List boards.** Call:

   ```
   mcp__trello__list_boards({})
   ```

   Present the result as a numbered menu:

   ```
   Available Trello boards:
     [1] Moby App        — id abc123def456
     [2] Moby Website    — id xyz789...
     [3] Personal        — id ...
   ```

3. **Pick boards.** Ask: "Which board(s) should PM manage? Comma-separated numbers, or 'all'."

   Capture the chosen board(s) into `selected_boards`.

4. **For each selected board**, ask the per-board questions:

   ```
   For board "{name}" (id {id}):
   - Approval steps (comma-separated, e.g. "tech_lead,product"; blank = none):
   - Review policy (self | judge | auto, default self):
   - Worker instructions (one paragraph, blank to skip):
   ```

5. **List names.** For each selected board, call:

   ```
   mcp__trello__set_active_board({ boardId: $BOARD_ID })
   mcp__trello__get_lists({})
   ```

   Compare the existing list names against the seven required keys (`needs_triage`, `ready_for_agent`, `in_progress`, `review`, `done`, `needs_changes`, `blocked`). For each match found, propose the existing name as the value. For each missing name, ask the user what name to use (suggest the title-case default e.g. "Needs Triage", "Ready", etc.) — these go into `boards[i].lists`. Lists that don't yet exist will be created in Phase 6T.

6. **Webhook URL.** Ask: "What URL should Trello send card events to? (Leave blank to skip — events won't reach Shelby until you fill this in. Example: https://shelby.example.com/webhooks/trello.)"

   Store as `trello.webhook_url`.

## Generate .pm/config.yml

Use these values in the backend-specific placeholder in the main skill's shared
config. Copy the canonical example from
`plugins/pm/schemas/pm-config.trello.example.yml` for fields the user did not
customize.

```yaml
backend: trello

trello:
  webhook_url: "{webhook URL from interview step 6, or empty string}"
  boards:
    {for each selected board, emit:}
    - id: "{board id}"
      name: "{board name}"
      lists:
        needs_triage:    "{user-confirmed name}"
        ready_for_agent: "{user-confirmed name}"
        in_progress:     "{user-confirmed name}"
        review:          "{user-confirmed name}"
        done:            "{user-confirmed name}"
        needs_changes:   "{user-confirmed name}"
        blocked:         "{user-confirmed name}"
      approval_steps: [{from interview}]
      review_policy: "{from interview, default self}"
      worker_instructions: "{from interview, default empty}"
  statuses:
    needs_triage:    [ready_for_agent, rejected]
    ready_for_agent: [in_progress]
    in_progress:     [review, blocked, needs_changes]
    review:          [done, needs_changes]
    done:            [needs_changes]
    needs_changes:   [in_progress]
    blocked:         [in_progress, cancelled]
```

## Phase 6T: Set Up Trello Lists, Labels & Webhook (skip if backend != trello)

Skip this entire phase if `backend != trello`.

### 6T.1 For each board, create missing lists

For each `boards[i]` in the freshly-written config, call:

```
mcp__trello__set_active_board({ boardId: $BOARD_ID })
existing = mcp__trello__get_lists({})
```

For each of the seven required list names from `boards[i].lists`, if the name is not in `existing`, call:

```
mcp__trello__add_list_to_board({ name: $LIST_NAME })
```

Track which lists were created (for the summary) vs already existed.

### 6T.2 Validate board access

After list creation, call `mcp__trello__get_active_board_info({})` and confirm the response. If it errors with "board not found" or auth failure, instruct the user to verify their token's read/write scopes for the board and stop.

### 6T.3 Register webhook (idempotent)

If `trello.webhook_url` is non-empty, register a webhook for the board.

**This step is idempotent.** Trello's `POST /1/webhooks` does NOT dedupe by `(idModel, callbackURL)` — re-running `/pm:setup` would otherwise create one duplicate webhook per board per run, and your receiver would see N copies of every event. Always list-then-create:

**Step 1 — List existing webhooks for this token (once, outside the per-board loop):**

```bash
existing_webhooks_json="$(curl -fsS \
  "https://api.trello.com/1/tokens/$TRELLO_TOKEN/webhooks?key=$TRELLO_API_KEY&token=$TRELLO_TOKEN")"
```

The response is a JSON array of webhook objects, each with at least `id`, `idModel`, `callbackURL`, and `active`.

**Step 2 — Per board, check whether a matching webhook already exists:**

A webhook is considered a match when `idModel == $BOARD_ID` AND `callbackURL == $webhook_url` (active OR inactive — re-using inactive webhooks avoids hitting Trello's per-token webhook cap).

```bash
match="$(echo "$existing_webhooks_json" \
  | jq -c --arg board "$BOARD_ID" --arg url "$webhook_url" \
      '.[] | select(.idModel == $board and .callbackURL == $url)' \
  | head -n1)"
```

**Step 3 — Create only if no match:**

```bash
if [ -n "$match" ]; then
  echo "skipped webhook for $BOARD_NAME (already registered: id=$(echo "$match" | jq -r .id))"
  skipped=$((skipped + 1))
else
  curl -fsS -X POST "https://api.trello.com/1/webhooks/" \
    -d "key=$TRELLO_API_KEY" \
    -d "token=$TRELLO_TOKEN" \
    -d "callbackURL=$webhook_url" \
    -d "idModel=$BOARD_ID" \
    -d "description=Shelby PM webhook for $BOARD_NAME" \
    && created=$((created + 1)) \
    || echo "warning: webhook registration failed for $BOARD_NAME (board id $BOARD_ID). Re-run /pm:setup once the webhook URL is reachable."
fi
```

**Step 4 — After the loop, report:**

```
Webhooks: created $created new; skipped $skipped (already registered).
```

Trello does a HEAD request against `callbackURL` before accepting a new webhook — if the URL is not reachable yet (the receiving route is owned by Shelby's W1e workstream), POST returns an error. That is expected; the warning above tells the user how to retry. The card-as-conversation flow only activates once the webhook is live, but all other PM operations work today using direct MCP calls. Re-running `/pm:setup` after the URL is live will create only the missing webhooks (idempotent).

If `trello.webhook_url` is empty, skip this step and emit:

```
note: no webhook_url configured — Shelby will not receive Trello events.
      Run /pm:setup again after deploying the webhook ingress (W1e) to register.
```

### 6T.4 Summary line for Phase 8

Record for the final summary:
- Boards configured: $N
- Lists created (vs already existed): $created / $existing
- Webhook registered: yes / no / failed (with reason)
