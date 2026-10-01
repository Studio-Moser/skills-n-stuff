---
name: canvas
description: >-
  Use when people without a checkout need to review and comment on a design
  exploration (the local default is design:gallery): a self-hosted Doop canvas
  where every direction is a canvas led by a cover, every variant is a
  full-height HTML frame, and the owner's
  element-pinned comments flow back to agents. Covers standing the one shared
  server up behind the preview router, publishing a project's snapshots to its
  canvas, and harvesting comments into the next brief. Triggers: "put the round
  on the canvas", "publish to Doop", "read the comments on the canvas", "set up
  Doop".
---

# Canvas

The default review surface is `design:gallery`, which needs no server. Use the
canvas in addition when reviewers have no checkout or comments must be pinned
to elements and read back by agents.

Figma holds images; a round of HTML variants wants a surface that runs them.
Doop (kgoedecke/doop, AGPL) is an infinite multiplayer canvas whose frames are
sandboxed iframes of real HTML, with an MCP that both writes frames and reads
comments back. One server serves every project; a direction is a canvas led
by a cover, a variant is one full-height frame.

**Frames do not scroll.** On the canvas a frame is a design object: the wheel
pans the canvas, hover selects elements for comments, and resizing a frame
changes the page's viewport rather than revealing more of it. So a variant goes
on the canvas as **plates** (`design:capture` § Freeze): every screen laid out
in its settled state in one long file, with the frame as tall as the file.
**Present** (select a frame, press ▶) shows one frame full-screen and does
scroll, with scripts running; a variant that has a live page gets a second,
one-screen frame above its plates for that.

## One server, many canvases

Run exactly one Doop for the developer, on the machine that already hosts
previews, through `preview:serve-preview`'s router so it gets a stable tailnet
URL and never a public one. Projects do not get their own servers: a server per
project multiplies accounts, MCP registrations, and containers without adding
any isolation a canvas name does not already give.

Canvas naming: `<Project> · <Direction folder>` (`Acme · 03 Ledger`), which is
what `--canvas "<Project>" --per-direction` produces. A later round in the same
folder gets its own canvas, so no canvas grows past one round's frames.

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

Snapshots are the per-direction `.plates.html` files and `Snapshots.json`
manifests that `design:capture`'s `freeze.mjs` writes, from running routes or
from the self-contained pages builders write in the `html` medium.

```sh
node "${CLAUDE_PLUGIN_ROOT}/skills/canvas/scripts/cover.mjs" --dir "docs/Design Directions" --project "<Project>"
DOOP_URL=https://preview-doop.<tailnet>.ts.net DOOP_EMAIL=… DOOP_PASSWORD="$(cat ~/.config/agent-previews/secrets/doop_password)" \
  node "${CLAUDE_PLUGIN_ROOT}/skills/canvas/scripts/publish-canvas.mjs" \
    --dir "docs/Design Directions" --canvas "<Project>" --per-direction [--only 08] [--invite you@example.com]
```

One block per direction folder (sorted), eight frames to a line
(`--per-line`), one full-height frame per variant named
`<Folder> · <X> <Title>`, plus `<…> (live)` above it when the variant has a
live page: its own self-contained file (`live` in the manifest), or a durable
address (`liveUrl`, or the address it was frozen from with `--embed-source`).

**One canvas per direction.** A browser holds every frame of a canvas in
memory at once. A whole exploration on one canvas (a hundred long frames)
loads, then reloads, then gives up. Publish with `--per-direction`: each
direction gets its own canvas, `<name> · <Direction folder>`, and a folder
holding more than one round gets one per round. Embedded live builds stay
unloaded behind a poster until the frame is presented, because a frame on the
canvas never receives input and twenty running pages are what kills the tab.

**Give each canvas a cover.** Doop shows a canvas's most recently updated
frame as its dashboard thumbnail, so a dashboard of published directions is a
wall of whatever was written last. `cover.mjs --dir <directions dir> --project
"<name>"` writes a `Cover.html` per direction (number and name in large type,
premise, a labelled thumbnail of every variant); `publish-canvas.mjs` puts it
first on the canvas and writes it last. Add `--rebuild` the first time on a
canvas that already has frames so the cover leads the layers list. A cover is
self-contained (system fonts, inlined thumbnails) because the server that
renders thumbnails cannot reach the asset host.

**Keep the canvas light.** A canvas is loaded whole, so fifty self-contained
files (every one with its fonts and photographs inlined) is a hundred
megabytes and a minute before anything draws. Publish with
`--assets-dir <dir> --assets-url <url>`: fonts and images are written once to a
directory a static preview serves (`up-static`), frames reference them by URL,
and the canvas carries only text and structure. The files on disk stay
self-contained; `--prune` removes frames the manifests no longer describe.

**Keeping a framework build playable.** A variant built as a route in a real
stack cannot go in a frame as a file: its motion is its scripts. Build the
branch as a production static site, serve it with
`preview:serve-preview up-static` at a stable address, and let the live frame
embed that address; Present then scrolls the real build with its motion
running. Use a URL that needs no redirect (a trailing slash for a
directory-style export: a redirect to `http://` behind the TLS proxy is
blocked as mixed content). The static host must send
`Access-Control-Allow-Origin`, because the page inside a sandboxed frame has
an opaque origin and fonts and CSS `mask-image` are fetched in CORS mode; a
masked logo that vanishes is the symptom.

**Access and re-runs.** Canvases are private to the publishing account; pass
`--invite you@example.com` (or `DOOP_INVITE`) so the people who review it can
open it, after they have signed up on the server. Re-running updates frames by
name and re-lays the grid. It signs in with email and password over the REST
API, so it needs no browser; the MCP is for agents working on the canvas
interactively.

The files on disk are complete HTML with inline CSS and no external URLs; that
is what `freeze.mjs` produces and what an `html`-medium build brief requires of
the live page. A published plates frame carries URLs only for the asset host,
and only when `--assets-url` is set. Scripts in a frame run inside its sandbox (no same-origin access,
no storage), which is what lets a live frame animate in Present; plates carry
none.

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
