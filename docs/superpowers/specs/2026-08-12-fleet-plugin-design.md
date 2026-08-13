# Fleet plugin + personal agent repo

**Date:** 2026-08-12
**Status:** Design — pending implementation plan
**Affects:** `skills-n-stuff/plugins/fleet` (new), `skills-n-stuff/studio-baseline` (new doc), `skills-n-stuff/plugins/pm` (rubric machinery removed), a developer's private `~/.agents` repo (outside this repo)

## Background

Personal agent configuration — global instructions, skills, shared Claude Code
settings — lives loose in `~/.claude` on each machine and is tracked nowhere. A
developer working across several machines re-approves the same permissions, edits
a skill on one box and loses it on the others, and has no way to tell which
machine is behind.

The failure is not theoretical. Auditing one developer's setup for this spec found
`~/.claude/skills` and `~/.agents/skills` holding duplicate copies of 24 skills,
three of which had silently diverged after a blind `Claude`→`Codex` find-and-replace
corrupted the `~/.agents` side (`.Codex/` paths, `AGENTS.md imports AGENTS.md`, a
dead `awesome-Codex-subagents` URL). Nothing surfaced it, because nothing was
comparing the two.

The obvious fix — a git repo of markdown, pulled on each machine — is also the one
that survives contact. The reference for this approach is a walkthrough of a
multi-machine setup ([youtu.be/e1snsuY4lTI](https://youtu.be/e1snsuY4lTI)) whose
author reports building a purpose-built sync system, finding it "buggy and annoying
and had lots of annoying edge cases", and abandoning it for a repo plus `git pull`.
This spec adopts that shape and adds the two things a repo alone doesn't give you:
a documented bootstrap path for a bare machine, and drift detection for the failure
mode above.

## Goals

- One private repo per developer holding their personal agent layer; every machine
  matches it.
- A bare machine can be set up with shell and web access alone, before any plugin
  is installed.
- Detect drift rather than assume success — corrupted copies, broken links, and
  configs that are wrong rather than merely absent.
- Give the model-selection rubric a home that matches what it is: per-developer
  machine config, not project management.

## Non-Goals

- **A sync engine.** Git is the sync engine. No daemon, no watcher, no merge
  resolution beyond what git already does.
- **Syncing a teammate's personal layer.** The plugin is public and generic; the
  data each person syncs is their own private repo. Nothing in `skills-n-stuff`
  ever contains someone's personal config.
- **Syncing machine state.** Session history, per-project memory, credentials, and
  local databases stay local.
- **Fleet inventory as a product.** `fleet.yml` is an optional list of hostnames,
  not a CMDB.

## Architecture

Two surfaces, reusing the split `studio-baseline` and `pm` already demonstrate:
the plugin authors and automates, everyone consumes over raw URLs.

| | lives in | installed? | role |
|---|---|---|---|
| `studio-baseline/Machine_Setup.md` | fetchable docs | no | **Entry point.** Bare machine, shell + web only. |
| `fleet` plugin | marketplace | yes | **Ongoing.** Auto-triggering sync, drift detection, optional push. |

This split is not decoration. Fleet has a bootstrap paradox no other plugin in this
marketplace has: its job is setting up a machine, and on a fresh machine nothing is
installed. An install-gated skill cannot be the entry point for installing things.
`Rubric_Setup.md` already solves the same problem the same way.

### The private repo

```
~/.agents/
├── README.md
├── skills/                   flat; every machine gets all of them
├── claude/
│   ├── CLAUDE.md
│   ├── settings.json         permissions, hooks, statusLine, enabledPlugins
│   └── statusline-command.sh referenced by settings.json — they travel together
└── fleet.yml                 optional; only if push is used
```

Linked into place:

| link | target |
|------|--------|
| `~/.claude/skills` | `~/.agents/skills` |
| `~/.claude/CLAUDE.md` | `~/.agents/claude/CLAUDE.md` |
| `~/.claude/settings.json` | `~/.agents/claude/settings.json` |
| `~/.claude/statusline-command.sh` | `~/.agents/claude/statusline-command.sh` |

**Flat, not scoped.** No `universal/` vs `per-host/` split. Claude Code's own
`settings.local.json` already provides per-machine selection via `skillOverrides`,
so which skills are *active* is a local concern and never needs modeling in the
repo. Add scoping only if a machine genuinely diverges.

**What stays out, and why:**

| | reason |
|---|---|
| `~/.claude/settings.local.json` | machine-local by design; holds `skillOverrides` |
| `~/.claude/mcp.json` | hardcodes app paths (`/Applications/Shelby.app/…`) |
| `~/.claude/projects/` | session state and per-project memory |
| `~/.shelby/` | `hook-token` is a credential; `*.db` are per-machine state |

Consequence to state plainly: this syncs a memory tool's *configuration*, not its
*memories*. `~/.shelby/memory.db` is local to each machine.

### Repo invariants

Two rules, both learned from real breakage:

**No literal `/Users/<name>` paths in tracked files.** A hardcoded home directory
makes a synced config silently *wrong* on another machine rather than merely
absent, which is far harder to notice. Found four in one `settings.json` — three
Shelby hooks and the statusline command.

**Guard hooks that invoke an optional binary.** A machine without the tool should
degrade quietly, not error every turn:

```sh
[ -x "$HOME/.shelby/bin/shelby-hook" ] && "$HOME/.shelby/bin/shelby-hook" session-start claude-code || true
```

Three unguarded Shelby hooks fired on every SessionStart, Stop, and UserPromptSubmit.

### `fleet` plugin

**`fleet:sync`** — *"make this machine match my personal agent repo."*

1. **Link check.** Are the four links still links? `CLAUDE.md` and `settings.json`
   are both actively rewritten — by a memory tool's bootstrap block and by Claude
   Code on plugin toggle. A writer doing atomic-replace (temp + rename) rather than
   write-in-place silently converts a symlink back into a real file, and sync stops
   with no signal. On finding an orphaned real file: diff it against the repo, show
   the delta, re-link. This is cheaper and more honest than a copy-and-merge engine.
2. **Pull.** Clone on first run (prompt for the repo URL), `git pull` after.
3. **Portability lint.** Fail on any literal `/Users/<name>`. Must check **both**
   file contents *and* symlink targets — `git ls-files -s` for mode `120000`, then
   `readlink` each. A content grep alone follows the link and reads the target's
   contents, so an absolute symlink target passes a naive lint. This is exactly how
   a symlink to `/Users/<name>/.codex/superpowers/skills` survived one.
4. **Report** what changed.
5. **Push (optional).** Only if `fleet.yml` exists: `ssh <host> 'cd ~/.agents && git pull'`
   per machine, skipping unreachable hosts, reporting partial failure. Never the
   default, never silent.

**`fleet:model-rubric`** — create or refresh the personal model rubric. Lifted from
`pm`, behavior unchanged.

Scripts move here from `pm`: `rubric-path.sh`, `fetch-model-data.sh`, and
`tests/rubric-path.bats`. `fetch-model-data.sh` must move at its current head —
it was fixed for the AA v2 nested schema in #23 and a stale copy would silently
mis-parse.

### Changes to `pm`

`pm` becomes a pure consumer of the rubric.

- `pm:setup` stops creating it; points at `fleet:model-rubric`, falling back to
  `studio-baseline/Rubric_Setup.md` (which already works with no plugin installed).
- `reconcile` drops Phase 5.5. Freshness checking is maintenance — fleet's job.
- **`pm` keeps no copy of `rubric-path.sh`.** The path is a one-line constant, so
  consumers (`dev-task`, `sprint-dev`, `ingest`, `codex-*`) read
  `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml` inline. No hard
  dependency on `fleet`, and no duplicated script to drift.

`studio-baseline/Rubric_Setup.md` does not move. It is the zero-plugin path and
must stay fetchable.

## Migration

The procedure `Machine_Setup.md` documents and `fleet:sync` automates for a machine
that already has loose config. Ordered, because step 1 is destructive if run second.

Steps 1–5 have been executed by hand on the author's primary machine, which is where
the corruption and lint findings above came from; step 6 is outstanding.

1. **Repair before consolidating.** Where duplicate skill copies exist, diff them
   and establish which side is clean *before* deleting either. A newer mtime is not
   evidence of a newer version — in the observed case it was the timestamp of the
   corruption.
2. Verify remaining pairs byte-identical; delete duplicates.
3. `git init`; commit the skills tree as a restore point before anything moves.
4. Move `CLAUDE.md`, `settings.json`, `statusline-command.sh` in. Lift
   `skillOverrides` into `settings.local.json` by **merge**, not overwrite — that
   file already holds `permissions`, `enabledPlugins`, `disabledMcpjsonServers`.
   Apply the two repo invariants.
5. Replace originals with symlinks. Verify skills resolve and settings parse
   **before** deleting anything unrecoverable.
6. Add a private remote and push.

Restart running sessions afterwards: they hold the old settings in memory, and one
of them writing settings will replace a fresh symlink with a real file.

## Testing

- `bats` for the moved scripts; `rubric-path.bats` moves as-is.
- `fleet:sync --dry-run` prints the link plan, lint result, and drift report without
  touching the filesystem. This is the runnable check the sync logic leaves behind.
- Lint fixture: a repo containing both a file with a literal home path and a symlink
  with an absolute target. The naive implementation passes the second; the correct
  one fails both.

## Risks

**Symlink replacement is silent.** Mitigated by the step-1 link check, but only
detected on the next `fleet:sync`. A developer who never runs it drifts unnoticed.
Accepted: the alternative is a filesystem watcher, which is the custom sync engine
this design exists to avoid.

**`fleet.yml` push is fire-and-forget.** `ssh … git pull` reports its own failure
but cannot verify the remote machine relinked correctly. Push reports what it
attempted, not what succeeded. Treated as a convenience over running sync on each
machine, not a guarantee.

**Splitting the rubric across two plugins during migration.** If `fleet` ships
before `pm` is updated, both create the rubric. Sequencing: land the `pm` removal
and the `fleet` addition in the same release, or `fleet` first with `pm:setup`
detecting an existing rubric and skipping (which it already does).

## Open Issues

- **Repo naming.** `~/.agents` is already in use as a cross-tool skills directory
  (Codex reads it too). Confirm this is intended rather than Claude-specific.
- **Bootstrap chicken-and-egg for the private repo URL.** `Machine_Setup.md` is
  public and cannot name a private repo. It has to prompt.
- **Whether `enabledPlugins` belongs in shared `settings.json` at all.** A plugin
  enabled globally but disabled locally on one machine (to resolve a skill name
  collision) reappears on every new machine. May argue for moving `enabledPlugins`
  local alongside `skillOverrides`.
