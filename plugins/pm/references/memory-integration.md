# Memory integration (optional)

dev-task uses a memory MCP only if one is connected. Detection: look for tools
matching `mcp__shelby-memory__*` (or generic `get_brief` / `search_thoughts` /
`capture_thought`). If none are present, skip every memory step silently — never
error, never block the workflow.

## At Frame
- `search_thoughts` (or `get_brief`) for prior decisions, conventions, or gotchas
  relevant to this task/area. Surface anything load-bearing to the user in one line.

## At Wrap
- If you learned a reusable convention, gotcha, or decision, `capture_thought`
  with a one-line summary, a `type` (decision/insight/reference), and topics.
- Do not save secrets, one-off details, or anything already in the repo.
