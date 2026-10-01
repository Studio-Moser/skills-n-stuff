---
name: canvas
description: >-
  Use for the review surface of a design exploration: a self-hosted Doop canvas
  where every variant is a live HTML frame, rows are directions, and the owner's
  element-pinned comments flow back to agents. Covers standing the one shared
  server up behind the preview router, publishing a project's snapshots to its
  canvas, and harvesting comments into the next brief. Triggers: "put the round
  on the canvas", "publish to Doop", "read the comments on the canvas", "set up
  Doop".
---

# Canvas

Figma holds images; a round of HTML variants wants a surface that runs them.
Doop (kgoedecke/doop, AGPL) is an infinite multiplayer canvas whose frames are
sandboxed iframes of real HTML, with an MCP that both writes frames and reads
comments back. One server serves every project; a project is a canvas, a
direction is a row, a variant is a viewport-sized frame the reviewer scrolls
inside, so sticky stages and scroll-driven motion behave as they did in the
browser.

## One server, many canvases

Run exactly one Doop for the developer, on the machine that already hosts
previews, through `preview:serve-preview`'s router so it gets a stable tailnet
URL and never a public one. Projects do not get their own servers: a server per
project multiplies accounts, MCP registrations, and containers without adding
any isolation a canvas name does not already give.

Canvas naming: `<Project> <exploration>` (`Acme identity exploration`). Start a
new canvas when a project starts a genuinely new exploration, not per round.

## Stand the server up (once)

1. Clone `https://github.com/kgoedecke/doop` somewhere durable on the host.
2. Copy `assets/Doop.compose.yaml` beside a `.env` (mode 0600) that sets
   `DOOP_SOURCE`, `DOOP_AUTH_SECRET` (`openssl rand -hex 32`),
   `DOOP_PUBLIC_URL` (`https://preview-doop.<tailnet>.ts.net`), and
   `DOOP_SIGNUP_DOMAINS`. Nothing from `.env` is ever committed.
3. `Preview.sh prepare doop`, then
   `docker compose --project-name agent-preview-doop -f Doop.compose.yaml up -d --build`,
   then `Preview.sh verify doop`. The image builds from source (Bun build,
   Node runtime with Chromium for frame screenshots); Postgres is a sibling
   service on a named volume.
4. Create the developer's account with `publish-canvas.mjs --signup` (or the
   web UI). Keep the password in the preview secrets folder
   (`~/.config/agent-previews/secrets/doop_password`, mode 0600), never in a
   repository or a command-line flag.
5. On every machine: `claude mcp add --transport http --scope user doop <DOOP_PUBLIC_URL>/mcp`.
   The first interactive use completes OAuth in the browser; `harness:sync`
   carries the server name to the fleet through `mcp.manifest.json`.

## Publish a project's snapshots

Snapshots are the per-direction HTML files and `Snapshots.json` manifests that
`design:capture`'s `freeze.mjs` writes, or that builders write directly in the
`html` medium.

```sh
DOOP_URL=https://preview-doop.<tailnet>.ts.net DOOP_EMAIL=… DOOP_PASSWORD="$(cat ~/.config/agent-previews/secrets/doop_password)" \
  node "${CLAUDE_PLUGIN_ROOT}/skills/canvas/scripts/publish-canvas.mjs" \
    --dir "docs/Design Directions" --canvas "<Project> identity exploration" [--only 08] [--invite you@example.com]
```

One row per direction folder (sorted), one 1440×900 frame per variant, named
`<Folder> · <X> <Title>`. Canvases are private to the publishing account;
pass `--invite you@example.com` (or `DOOP_INVITE`) so the people who review it
can open it, after they have signed up on the server. Re-running updates frames by name and re-lays the
grid. It signs in with email and password over the REST API, so it needs no
browser; the MCP is for agents working on the canvas interactively.

Frames hold complete HTML with inline CSS and no external URLs Doop cannot
reach; that is what `freeze.mjs` produces and what an `html`-medium build brief
requires. Doop strips nothing from a frame you create, so scripts you leave in
will run inside the sandbox; the freeze removes them on purpose.

## Harvest comments into the next brief

After the owner has looked, the round's harvest is what they pinned. Through
the `doop` MCP:

1. `list_canvases`, then `get_canvas` for the project's canvas to map frame
   ids to `<Folder> · <X> <Title>` names.
2. `get_comments` (newest first, up to 100) and `get_feedback`. Group by frame,
   then by direction.
3. Draft the next direction brief's **Carry forward** block from them: element,
   which variant, the owner's words as the why. Do not summarise away the
   owner's phrasing; it is the signal.
4. `reply_to_comment` with where the note landed (which brief, which line) and
   `resolve_comment` once the brief is written. `set_status` while working so
   the owner sees what the agent is doing.

Nothing here ranks variants; the owner harvests, the brief carries it forward.

## When the canvas is not the right surface

A single variant being polished in convergence belongs in the real project
preview with `design:first-draft-critic` gauntlet mode and element-level tools,
not on the canvas. A handoff to a designer who lives in Figma goes through
`figma` (code to canvas) from the chosen variant, once, at the end.
