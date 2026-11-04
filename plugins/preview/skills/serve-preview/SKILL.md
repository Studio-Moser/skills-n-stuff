---
name: serve-preview
description: >-
  Creates, checks, or stops a temporary private Tailscale preview of a local website on macOS. Use when a local site needs to outlive the chat and be opened as a real page on the owner's other devices: getting a tailnet URL for localhost, checking a site in another browser or on an iPad, or stopping or pruning a preview. Not for public deploys such as Railway, or for anyone outside the owner's tailnet.
---

# Serve Preview

A preview is a process on this Mac's loopback, published with the host's own
`tailscale serve`. It outlives the agent session because launchd owns the process, and
it ends at `down`, `prune`, logout, or reboot. Previews are temporary: they exist while
the owner works on something and stop once that work merges.

Resolve the controller from this skill's installed location. A Claude plugin install
exposes it at `skills/serve-preview/scripts/Preview.sh` inside the newest
`$HOME/.claude/plugins/cache/*/preview/*/` directory; a Harness-managed skills install
normally exposes it at `${AGENTS_REPO:-$HOME/.agents}/skills/serve-preview/scripts/Preview.sh`.
If neither applies, use the `scripts/Preview.sh` next to this `SKILL.md`. Set that
absolute path as `preview`.

## Start one

Pick the command that matches what is being served, then always run `verify`:

```bash
"$preview" up-static <name> <dir>                  # a folder of built files
"$preview" up-cmd <name> <dir> <port> -- <cmd...>  # an app the job should run
"$preview" up-port <name> <port> [dir]             # something already running
"$preview" verify <name>
```

- `up-static` picks a free port from 3500 to 3599 and adds the CORS header that fonts
  and CSS masks need inside sandboxed frames.
- `up-cmd` passes `PORT` and restarts the app after a crash. Wrap shell syntax in
  `sh -c '...'`. Make the app listen on `127.0.0.1`, for example
  `pnpm start --hostname 127.0.0.1 --port 3510`.
- `up-port` publishes a project's own stack, such as a Compose service on `localhost:9080`,
  and never starts or stops that stack. Pass the project folder so `prune` can see its branch.

Serve a production build (`next build && next start`, or `up-static` on an export) when
the owner is only reviewing. Run a development server only while someone is editing,
because each one holds hundreds of megabytes to gigabytes.

Report the URL, the `verify` result, and the `down <name>` command.

## Manage them

```bash
"$preview" list              # name, live/starting/dead, URL, folder, branch
"$preview" down <name>       # stop it and remove its tailnet entry
"$preview" prune --dry-run   # name what prune would remove, and why
"$preview" prune             # remove those previews
```

`prune` removes a preview when its folder is gone, when it is no longer running, or when
a merged PR's head equals its branch's current tip. If GitHub cannot be reached, it keeps
the preview and warns. `/pm:tidy-up` offers these same removals after work merges.

## Invariants

- Keep previews private to the tailnet. Never enable Funnel: it exposes the preview to
  the public internet.
- Keep job processes on loopback. `verify` warns when a port also listens beyond it,
  which exposes the preview to the local network.
- Leave serve entries the controller did not record alone. T3 Code and other tools own
  theirs, and `--https=443` in particular is never touched.
- Previews run as the owner with full access to their files, so only serve the owner's
  own projects.
- Use the printed `https://<machine>.<tailnet>.ts.net:<port>` URL. The viewing device must
  be on the same tailnet.
