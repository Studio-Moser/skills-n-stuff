---
name: sync
description: >-
  Make this machine match your personal agent repo — the private repo holding your
  skills, global CLAUDE.md, and shared Claude Code settings. On first run it clones
  an existing private repo or safely creates one from loose configuration; after
  that it ingests the current remote before reconciliation, then commits and pushes
  this machine's changes. Re-links anything that drifted back into ~/.claude, lints for paths
  that would be wrong on another machine, and optionally triggers a pull on your
  other machines. Trigger: "sync my config", "sync my machines", "update my skills from
  my repo", "is this machine up to date", or /harness:sync.
  Do NOT use as the first-time user-facing setup workflow (that's
  /harness:setup), for creating the model rubric (that's /harness:model-rubric),
  or for anything in a project repo — sync only touches this developer's
  user-global agent config. Harness setup invokes this skill internally for its
  existing repository, link, and portability mechanics.
effort: low
allowed-tools: "Bash Read Edit"
---

# Harness — Sync

Makes this machine match your personal agent repo.

## Composition boundary

`harness:setup` invokes this skill for repository discovery or cloning, link
reconciliation, and portability checks. Run the same phases and preserve every
existing prompt, conflict stop, authentication boundary, and report field. Return
the Phase 4 report to Setup; do not make rubric decisions or capability claims on
Setup's behalf.

**Default repo:** `$HOME/.agents`. If `$AGENTS_REPO` is set, use that instead.

---

## Dry run

If the user asks what would change, or passes `--dry-run`, run **only the
read-only pieces** — `link-plan.sh` (Phase 1's command),
`reconcile_shared_settings.py --check` for the shared settings file,
`mcp-manifest.sh --check` for the portable MCP manifest, Phase 2.5's MCP
reconcile block (table and plan only, no question), Phase 2.6's step 0
*detection* block (the `git
ls-files --error-unmatch` tracked-check and the `.gitignore` presence
check — not the fix block right after it) and step 1 (the
`skills-reconcile.sh` call, nothing that follows it),
`portability-lint.sh` (Phase 3's command), and `rubric-audit.sh` (Phase 3.5's
command — it only reads transcripts) — then print the report from
Phase 4 and stop. Phase 2.5's MCP block only reads the portable manifest and Claude Code's
machine-local user registry, then prints the per-host table and plan lines;
it belongs in a dry run because that's exactly the kind of thing someone
previewing a sync wants to see. The match / replace / merge question is not
asked and nothing is installed, removed, or imported.
Phase 2.6's step 0 detection and step 1 are the same shape: `git ls-files
--error-unmatch` and `grep` only read, and `skills-reconcile.sh` only
reads the manifest, `.fleet-local.json`, and `npx skills list -g --json`
output — all of them print findings without touching disk.

Skip everything else, explicitly:

- **Phase 2.2** (render `codex/AGENTS.md`) — a write; report
  `Derived: [skipped in dry run]`.
- **Phase 2's reconciliation and Phase 3.75's final transaction** — they write
  shared settings, manifests, the repo, or the remote.
- **Phase 0.5's remote preflight** — it may fetch and fast-forward the repo.
- **Phase 2.5's plugin half** (marketplace add / plugin install) — installs
  software. Run only its MCP reconcile block's table and plan, not the question or anything after it.
- **Phase 2.6's step 0 fix block** (the `.gitignore` write and `git rm
  --cached`) — a write, and a one-time repo migration, not
  something a preview should perform. Only step 0's detection block above
  it belongs in a dry run.
- **Phase 2.6's step 2 (installs, removals, override writes) and step 3
  (the `skills-manifest.sh` regeneration)** — running either would write
  real files or install real software; skip both. Only step 1's read/
  compare/report belongs in a dry run.
- Phase 1's action column (create/re-link/remove) and Phase 3's fix
  suggestions — both are writes, not part of the dry run.

Nothing is created, installed, moved, or removed. The read-only pieces that do
run are read-only, so this is safe to offer unprompted when the user seems
unsure.

---

## Phase 0: Locate the repo

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[ -d "$repo/.git" ] && echo "found" || echo "absent"
```

`link-plan.sh` resolves `$claude` the same way internally — use this `$claude`
variable everywhere below instead of hardcoding `~/.claude` or `$HOME/.claude`,
so the skill and the script always agree on which directory is being managed.

**Each phase below may run as a separate command, in a separate shell.**
Nothing set in one command block — `repo=`, `claude=`, and later
`diff_status=`, `$diff_err`'s path — persists into the next. Re-resolve
`repo=`/`claude=` at the top of any later block that references them, rather
than assuming Phase 0's values are still set. Same rule for the diff
sequence in Phase 1: run the `diff`, the `$diff_err` check, the resulting
removal, and the `rm -f "$diff_err"` cleanup as one command block, not as
separately-issued commands — splitting them loses the temp file's path and
the `diff_status` value in between.

**absent** — first run on this machine. Do not assume a remote already exists.
Continue through First-run safety and adoption below.

**found** — continue to Phase 0.5.

---

## First-run safety and adoption

Run this section only when Phase 0 reported `absent`. It is the one path allowed
to create the personal repository; ordinary Sync runs never re-bootstrap it.

### 0.1 Back up the live configuration before any destructive step

Create a new timestamped archive under `$HOME` containing every present live entry
managed by `link-plan.sh`: `skills`, `output-styles`, `CLAUDE.md`, `settings.json`,
`statusline-command.sh`, the cross-tool `studio-moser` config directory, and Codex
`AGENTS.md`. Back up a present legacy `$claude/mcp.json` separately in the same
archive before cleaning it up, but never copy Claude Code's global `.claude.json`
state or adopt either file into Git. Resolve configured roots exactly as Phase 1 does.

Append each present entry to the archive separately. Missing optional entries are
normal and must not make the archive fail. Never overwrite an earlier backup, and
keep the new archive until Phase 1 reports every expected link resolved and
`settings.json` parses. No live path may be removed or replaced before its content
is either in this archive or explicitly declined after a shown diff.

### 0.2 Choose the source of truth

Ask one question:

- **Existing private repository** — ask for its exact URL; never guess it. Clone it
  into `$repo`, run Phase 0.5, then use Phase 1's recursive diff and keep/discard
  prompts for every live file or directory that conflicts with the clone.
- **Loose configuration with no repository yet** — adopt the current machine using
  the procedure below.

For an existing repository:

```bash
git clone <url> "${AGENTS_REPO:-$HOME/.agents}"
```

If the clone fails on authentication, say so plainly and stop — do not fall back
to another protocol without asking. A common cause is an SSH remote with no key
loaded (`ssh-add -l` reports no identities); `gh auth status` will show whether
HTTPS is the configured protocol instead.

For loose configuration:

1. If skills exist in more than one live location, compare each duplicated pair
   recursively and read the differences. A newer modification time is not proof
   that a copy is correct. Resolve the winning content before consolidation.
2. Localize machine-only skill routing before copying shared `settings.json`:

```bash
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
[ ! -e "$claude/settings.json" ] || "$harness/scripts/localize-skill-overrides.py" "$claude/settings.json" "$claude/settings.local.json"
```

   This removes only `skillOverrides` from the shared file and merges it into
   live `settings.local.json`, preserving every other local key.
3. Initialize an otherwise empty `$repo` on `main`. Do not copy any managed entry
   into it yet.
4. After the archive and duplicate inspection establish the intended loose source,
   ask for the exact private remote URL and configure it as `origin`; never invent
   one. Confirm the remote is private and its target branch is absent. If the branch
   already exists, stop and use the existing-repository clone path instead. On
   authentication failure, stop rather than silently switching protocols. A full
   Sync cannot continue without a remote because preflight must bind the final push
   before any repository content is adopted.
5. **Continue to Phase 0.5**, not Phase 1. Do not copy, link, render, reconcile, or
   otherwise write repository content until preflight reports ready.

---

## Phase 0.5: Ingest the remote before any reconciliation

Run this exactly once on every full Sync after locating a normal repository,
cloning an existing repository, or initializing an empty loose-adoption
repository. It is the single join point before Phase 1 or any newly adopted
content can write shared state. Do not run it in dry-run mode because a clean
repository may be fetched and fast-forwarded.

```bash
set -euo pipefail
repo="${AGENTS_REPO:-$HOME/.agents}"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/sync-preflight.sh" "$repo"
```

The helper queries the actual remote branch. A clean repository is fetched and
fast-forwarded before any derived output is computed. Local work may continue
only while that remote still matches the already-known tracking SHA. If both
local work and a newer remote exist, it stops with an explicit instruction to
commit or stash the local work, ingest the remote, and rerun Sync. Divergence
also stops; never merge, rebase, or force automatically. A remote branch that
does not exist yet is a valid first-push state.

If the remote moves after this preflight, Phase 3.75 queries the actual remote
again and stops before commit or push. It never pulls after the derived files
and scans have run.

---

## Complete loose-config adoption after preflight

Run this section only for the loose-configuration path after Phase 0.5 reports
ready. Normal and cloned repositories skip directly to Phase 1.

1. Create `skills/`, `claude/`, `config/studio-moser/`, and `codex/` under `$repo`
   as needed. Copy every present managed entry into its Phase 1 repo path except
   machine-local MCP state; copy, do not move, so the originals remain recoverable
   until verification. Generate the secret-free `$repo/mcp.manifest.json`
   by reading each top-level `mcpServers` entry's secret-free shape from Claude Code's global
   `.claude.json` state. Never copy that state file. Do not adopt Codex `AGENTS.md` as a source:
   preserve any unique instruction in `House Style.md` or `CLAUDE.md`, then let
   Phase 2.2 render the derived file.
2. Keep local-only state out of Git: `claude/mcp.json`, `settings.local.json`,
   runtime project/session stores, credentials, secret-bearing profiles, resolved
   machine paths, approvals, temporary evidence, Shelby state,
   `.fleet-local.json`, and `.skill-lock.json`.
3. Continue to Phase 1 and replace only verified originals with links; the backup
   remains the recovery copy. Complete every later reconciliation and Phase 3's
   portability rules before Phase 3.75 stages and synchronizes the full result.

---

## Phase 1: Link check

**Remote ingestion must already be complete.** `CLAUDE.md` and `settings.json` are both rewritten by
tooling — a memory tool's bootstrap block edits one, Claude Code writes the other
on plugin toggle. A writer that does atomic-replace (temp file + rename) rather
than write-in-place silently converts a symlink back into a real file, and sync
stops working with no signal. This phase is how that gets noticed.

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/link-plan.sh" "$repo"
```

Each line ends in a state:

| state | meaning | action |
|---|---|---|
| `ok` | correct symlink | nothing |
| `ABSENT` | no such path in `$claude` | create the link |
| `REAL-FILE` | a real file (or directory — `skills`, `output-styles`, and `studio-moser` are directories among the seven portable entries) sits where the link should be | **diff first** (below) |
| `RELINK(->X)` | symlink points somewhere else | show `X`, confirm, re-link |
| `MISSING-IN-REPO` | the repo has no such file | report; do not create anything |

Claude Code's global `.claude.json` state is deliberately absent from this table.
Commands, arguments, environment variables, credentials, OAuth data, and application
state are machine-local. Phase 2.5 compares its top-level user-scope MCP servers
to the portable `mcp.manifest.json`; Sync never copies, links, prints, or tracks the
global state file.

**`MISSING-IN-REPO` is checked first and masks the other states.** If the
repo lacks the file, `link-plan.sh` reports `MISSING-IN-REPO` for that entry
no matter what `$claude` currently has there (a real file, a drifted
symlink, or nothing) — the five states are not independent signals about
both sides at once. Don't infer "no real file exists on this machine" from a
`MISSING-IN-REPO` line.

`link-plan.sh` resolves both paths before comparing them, so equivalent relative
and absolute targets both report `ok`. A `RELINK(->X)` result therefore means the
resolved target is genuinely different.

**On `REAL-FILE`, never overwrite silently.** That file may hold edits made on
this machine since the link broke. `skills` is a *directory*, so the diff must
be recursive:

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
diff_err="$(mktemp)"
diff -ru "$repo/<rel>" "$claude/<name>" 2>"$diff_err"
diff_status=$?
```

`diff_status`, not `status` — `status` is a read-only special variable in
zsh (an alias for `$?`), and assigning to it aborts the command with
`read-only variable: status` instead of setting anything. Since this skill
runs its Bash blocks through whatever shell the agent's tool uses, which may
be zsh, name it something the shell won't reject.

**First, before looking at `diff_status` at all: if `$diff_err` is
non-empty, stop and report.** Do not remove or re-link anything, and do not
fall through to the status bullets below — a stderr line means part of the
comparison didn't happen, so no status value is trustworthy:

```bash
if [ -s "$diff_err" ]; then cat "$diff_err"; rm -f "$diff_err"; exit 1; fi
```

This matters because BSD `diff -r` (macOS's default `diff`) can leave a
non-empty `diff_err` — a `diff: …: Permission denied` line from a
subdirectory it can't read — under two distinct exit codes. If that
unreadable subtree is the *only* difference, `diff -r` exits **0**
("identical") even though part of the tree was never compared, which would
otherwise walk straight into the keep/discard prompt below and `rm -r` a
tree that was never actually fully compared. If a *different*, readable part
of the same tree also genuinely differs, `diff -r` instead exits **1**
(`diff_status=1`) for that real difference, while the unreadable subtree is
still unchecked. Either exit code is untrustworthy once `diff_err` is
non-empty, which is why it's checked first and unconditionally, before
`diff_status` is read at all — removing the need to repeat the check on
every status branch.

Once `$diff_err` is confirmed empty, branch on `diff_status`:

- **`diff_status` = 0 (identical)** → remove the stray file (or `rm -r` the
  stray directory) and re-link.
- **`diff_status` = 1 (differs)** → show the diff and ask: keep the machine's
  version, or discard it. Never pick for the user. **Either way, remove the
  stray path before re-linking** — re-linking does not itself replace a real
  file or directory (see the `ln -sfn` note below), so skipping the removal
  step lands the new link inside the surviving path instead of replacing it,
  and the run reports success while the drift persists:
  - *keep, file*: `cp "$claude/<name>" "$repo/<rel>"` (commit it in the repo
    if the user wants it tracked), **then `rm "$claude/<name>"`**, then
    `ln -sfn`.
  - *keep, directory (e.g. `skills`)*: copy **contents**, not the directory
    itself — `cp -R "$claude/<name>/." "$repo/<rel>/"`. A plain
    `cp -R "$claude/<name>" "$repo/<rel>"` nests one level too deep
    (`$repo/<rel>/<name>/…`) because both sides already exist as
    directories, so the file ends up somewhere the repo's own `<rel>` path
    doesn't cover — "keep the machine's version" would silently not happen
    even though the command succeeds. **Then `rm -r "$claude/<name>"`**, then
    `ln -sfn`.
  - *discard*: **`rm -r "$claude/<name>"`**, then `ln -sfn` to the repo's
    version.
- `diff_status` >= 2 without a `diff_err` message is not expected from
  `diff`, but treat it the same as the stderr case above: stop and report,
  take no action.

**Whichever branch fires, clean up the temp file once done:**
`rm -f "$diff_err"`. All three branches above create and leave `$diff_err`
behind — this isn't specific to the `>= 2` case.

A plain `diff -u` here is a data-loss trap: non-recursive `diff` against
two directories prints only `Common subdirectories: …` and exits 0 even
when their contents differ, so the "no differences" branch would fire and
delete a `skills` tree that might hold this machine's only copy of local
edits. `-r` is required, not optional.

To create or re-link, use:

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
ln -sfn "$repo/<rel>" "$claude/<name>"
```

An absolute or relative target is accepted; `link-plan.sh` compares canonical
resolved paths. Prefer a relative target when the link itself will be tracked,
because Phase 3 rejects absolute targets in Git.

**The `studio-moser` entry lives under `${XDG_CONFIG_HOME:-$HOME/.config}`, not `$claude`.**
For it, the link is `"${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser"` and the target is
`"$repo/config/studio-moser"`. Create the parent first — `mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}"` —
a fresh machine may not have it. The REAL-FILE diff/keep/merge procedure applies to it exactly
as it does to `skills` (both are directories). When keeping the machine's copy, also ensure
`$repo/.gitignore` covers `config/studio-moser/*.bak*` so local backup files never sync.

**The `AGENTS.md` entry lives under `${CODEX_HOME:-$HOME/.codex}`, not `$claude`.**
For it, the link is `"${CODEX_HOME:-$HOME/.codex}/AGENTS.md"` and the target is
`"$repo/codex/AGENTS.md"`. Create the parent first — `mkdir -p "${CODEX_HOME:-$HOME/.codex}"` —
a fresh machine may not have Codex installed yet, and the link is still correct to create.
It is a single file, so on REAL-FILE the diff is a plain `diff -u` (not
`-r`). The target is generated by Phase 2.25, so **never `cp` a real
`~/.codex/AGENTS.md` into the repo** — the render would overwrite it before
commit and the machine's hand-written instructions would silently vanish.
Instead: show the diff, move the file aside (`mv "$link"
"$link.bak-$(date +%F)"` — the backup lives under `~/.codex`, not the repo),
tell the operator that anything worth keeping belongs in `House Style.md` or
`CLAUDE.md` (the sources), then link.

**For a real `settings.json` whose machine version is kept, localize before the
keep-file `cp`.** Run this in the same command block as the copy so the sanitized
file, never its machine-only routing, becomes the repo copy:

```bash
set -euo pipefail
repo="${AGENTS_REPO:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/localize-skill-overrides.py" "$claude/settings.json" "$claude/settings.local.json"
cp "$claude/settings.json" "$repo/claude/settings.json"
```

`-sfn` only repoints an **existing symlink** (that's what its `-n` guards —
it treats the destination as the link itself, not as a directory to drop the
link into). It does **not** replace a real file or a real directory: run
against a real path — including a `REAL-FILE` directory like `skills`, or a
`skills` directory left over after only *part* of a `diff_status` = 1 cleanup ran —
`ln -sfn` creates `"$claude/<name>/<basename of $repo/<rel>>"` inside the
surviving path and exits 0, reporting success while nothing was actually
replaced. The real file or directory **must be removed (or moved aside)
first**, on every branch that re-links over an existing path, not only the
symlink-to-directory case.

---

## Phase 2: Reconcile shared and derived state

The Git transaction occurs only in Phase 3.75. Phase 2 prepares every shared write
so validation can see the complete staged result before anything reaches the remote.

### 2.1 Reconcile shared settings

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
[ ! -e "$repo/claude/settings.json" ] || "$harness/scripts/localize-skill-overrides.py" "$repo/claude/settings.json" "$claude/settings.local.json"
[ ! -e "$repo/claude/settings.json" ] || "$harness/scripts/reconcile_shared_settings.py" "$repo/claude/settings.json"
git -C "$repo" status --short
```

The localization command removes machine-only skill routing from the shared file.
The settings reconciliation then removes `machine@studio-moser` and requires
`harness@studio-moser: true`. Both run before staging. In dry-run mode, use
`--check` for the shared settings helper and do not run either writer.

### 2.2 Render derived files

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/render-codex-agents.sh" "$repo"
```

`codex/AGENTS.md` is Codex's global instructions and is **generated** from the
Claude-side sources (`claude/output-styles/House Style.md` and `claude/CLAUDE.md`)
so House Style stays the one file you edit. It runs here — after settings
reconciliation and before staging — so a machine whose sources moved
gets one fresh render in the same transaction. If it prints
`RENDER_STATE=regenerated`, leave it uncommitted for Phase 3.75.
`RENDER_STATE=failed: <reason>` (exit 3) means a source or a required section is
missing — nothing was written; carry the reason into the report and continue.
Never hand-edit `codex/AGENTS.md`; the next sync overwrites it.

**If Phase 1 reported `AGENTS.md -> codex/AGENTS.md MISSING-IN-REPO`**, the file
exists now (pulled or rendered): create the link here — `mkdir -p
"${CODEX_HOME:-$HOME/.codex}"` then `ln -s "$repo/codex/AGENTS.md"
"${CODEX_HOME:-$HOME/.codex}/AGENTS.md"` — unless a real file sits there, in which
case follow the Phase 1 `AGENTS.md` REAL-FILE rule (move it aside, then link).

### 2.3 Generate the portable MCP inventory and clean up the legacy tracked file

Claude Code stores user-scope MCP servers in the top-level `mcpServers` object of
`${CLAUDE_CONFIG_DIR}/.claude.json` when `CLAUDE_CONFIG_DIR` is set, or
`$HOME/.claude.json` otherwise. Read that file only to generate
`mcp.manifest.json`: each server's portable shape (`type`, `command`, `args`,
`url`, `env`, `headers`) with every env and header value replaced by a `${NAME}`
reference, plus a `machines` list naming the hosts that have it. The generator
adds this host to every server present here and removes it from every server
that is not. Never copy, link, print, stage, or commit the state file.

A names-only `mcp.manifest` from an older sync is migrated once: its names
become shapeless entries (`{"machines": []}`), the old file is untracked and
deleted, and the generator prints `MCP_MANIFEST_STATE=migrated`. A shapeless
entry shows as `NO-CONFIG` in Phase 2.5 until a machine that has the server
syncs.

The generator fails, naming the server only, when an arg looks like a token or
a `--flag=value` with a long value, or when `command` or an arg is an absolute
home path. Fix the server locally (move the secret to `env`, or the binary onto
`PATH`) and rerun.

`$claude/mcp.json` is a legacy path. If an older repo tracks it or the live legacy
path is a symlink into the repo, preserve its resolved bytes as a regular live file
before untracking it. Never print its command, args, URL, headers, or environment:

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
runtime_mcp="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
legacy_runtime="$claude/mcp.json"
if [ -L "$legacy_runtime" ]; then
  temporary="$(mktemp "$claude/.mcp.json.migrate.XXXXXX")"
  trap 'rm -f "$temporary"' EXIT HUP INT TERM
  cp -pL "$legacy_runtime" "$temporary"
  unlink "$legacy_runtime"
  mv "$temporary" "$legacy_runtime"
  temporary=""
  trap - EXIT HUP INT TERM
fi
if [ -f "$runtime_mcp" ]; then
  "$harness/scripts/mcp-manifest.sh" "$runtime_mcp" "$repo/mcp.manifest.json" || exit $?
else
  echo "MCP_STATE=not configured"
fi
grep -qxF 'claude/mcp.json' "$repo/.gitignore" 2>/dev/null || printf '%s\n' 'claude/mcp.json' >> "$repo/.gitignore"
git -C "$repo" rm --cached claude/mcp.json --ignore-unmatch -q
```

If the user registry is missing, report `MCP_STATE=not configured` and do not
invent a manifest. In dry-run mode, do not run this block; validate an existing
manifest with `mcp-manifest.sh --check "$repo/mcp.manifest.json"` and run Phase
2.5's reconcile block read-only.

---

## Phase 2.5: Reconcile installed plugins and MCP servers

This phase reconciles machine state before the final Git transaction. Plugin
operations may rewrite shared settings, so they must complete before Phase 3.75
stages and validates the final result. MCP comparison is read-only until the user
chooses how to reconcile the plan.

### Plugins — install what's missing, automatically

The plugin inventory is already in the tracked `settings.json` — read the
**repo's** copy (`$repo/claude/settings.json`), not the possibly-drifted live file
at `$claude/settings.json`
(Phase 1 runs first and would have already flagged or fixed any such drift,
but reading the repo copy here keeps both halves of this phase consistent on
principle rather than by coincidence). `extraKnownMarketplaces` names the
marketplaces this developer's config expects; `enabledPlugins` names the
plugins. **Merge `settings.local.json` over it** — `settings.local.json` is
never tracked (it's machine-local by design, per the "keep machine-local
things local" table), so it's always read from `$claude`, live. A local
`false` for a plugin the shared file marks `true` is a deliberate per-machine
override (how a local fork wins over a marketplace plugin of the same name),
and installing it anyway would overwrite that choice. Local wins.

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

plugin_reconcile_script='import json, re, shutil, subprocess, sys

def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

if shutil.which("claude") is None:
    print("PLUGINS_STATE=skipped: claude CLI not on PATH")
    raise SystemExit(0)

settings = load(sys.argv[1])
local = load(sys.argv[2])

marketplaces = settings.get("extraKnownMarketplaces", {})
enabled = dict(settings.get("enabledPlugins", {}))
enabled.update(local.get("enabledPlugins", {}))  # local wins over shared

def names(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        cmd_str = " ".join(cmd)
        print(f"PLUGINS_STATE=failed: running {cmd_str} exited {r.returncode}: {(r.stderr or r.stdout).strip()}")
        raise SystemExit(0)
    return {m.group(1) for m in re.finditer(r"❯\s+(\S+)", r.stdout)}

have_marketplaces = names(["claude", "plugin", "marketplace", "list"])
have_plugins = names(["claude", "plugin", "list"])

added_marketplaces = []
for name, cfg in marketplaces.items():
    if name in have_marketplaces:
        continue
    repo = cfg.get("source", {}).get("repo")
    if not repo:
        continue
    r = subprocess.run(["claude", "plugin", "marketplace", "add", repo], capture_output=True, text=True)
    if r.returncode == 0:
        added_marketplaces.append(name)
        have_marketplaces.add(name)
    else:
        print(f"marketplace add failed: {name} ({repo}): {(r.stderr or r.stdout).strip()}", file=sys.stderr)

installed_plugins = []
for name, on in enabled.items():
    if not on or name in have_plugins:
        continue
    r = subprocess.run(["claude", "plugin", "install", name], capture_output=True, text=True)
    if r.returncode == 0:
        installed_plugins.append(name)
        have_plugins.add(name)
    else:
        print(f"plugin install failed: {name}: {(r.stderr or r.stdout).strip()}", file=sys.stderr)

# Update pass: refresh every marketplace, then bring each enabled plugin to the
# latest version the marketplace resolves. Third-party marketplaces have
# auto-update OFF by default, so without this a machine only ever gets the
# version it first installed.
r = subprocess.run(["claude", "plugin", "marketplace", "update"], capture_output=True, text=True)
if r.returncode != 0:
    print(f"marketplace update failed: {(r.stderr or r.stdout).strip()}", file=sys.stderr)

updated_plugins = []
for name, on in enabled.items():
    if not on or name not in have_plugins:
        continue
    r = subprocess.run(["claude", "plugin", "update", name], capture_output=True, text=True)
    out = (r.stdout or "") + (r.stderr or "")
    if r.returncode != 0:
        print(f"plugin update failed: {name}: {out.strip()}", file=sys.stderr)
    elif "updated from" in out:
        updated_plugins.append(name)

# Orphans: registered on this machine but not declared in shared settings.
# Report only — removal uninstalls the marketplace plugins, so the user runs it.
for name in sorted(have_marketplaces - set(marketplaces) - {"claude-plugins-official"}):
    print(f"orphan marketplace: {name} registered here but not in shared settings — remove with: claude plugin marketplace remove {name}  (also uninstalls its plugins)", file=sys.stderr)

if not added_marketplaces and not installed_plugins and not updated_plugins:
    print("PLUGINS_STATE=up to date")
else:
    print(f"PLUGINS_STATE=added {len(added_marketplaces)} marketplace(s), installed {len(installed_plugins)}, updated {len(updated_plugins)} — restart or /reload-plugins to apply")
'

printf '%s\n' "$plugin_reconcile_script" | python3 - "$repo/claude/settings.json" "$claude/settings.local.json"
```

`names()` fails closed: a non-zero exit from `claude plugin list` or
`claude plugin marketplace list` reports `PLUGINS_STATE=failed: ...` and
stops rather than treating empty/error output as "nothing installed," which
would otherwise try to install everything. The `claude` CLI itself missing
from `$PATH` is checked up front the same way, before any subprocess call.

Anything printed to stderr above (a failed marketplace add or plugin install)
is a finding — carry it into the Phase 4 report the same way an unfixed lint
finding is carried, never silently. **Plugin installs need a restart to take
effect** — the `PLUGINS_STATE` line already says so whenever it installed
anything; repeat it in the report.

The update pass runs every time: `claude plugin marketplace update` refreshes all
registered marketplaces, then `claude plugin update <name>` runs for each enabled
plugin. This exists because third-party marketplaces have auto-update **off** by
default — a machine that only installs would stay on its first-installed version
forever. `updated K` in `PLUGINS_STATE` counts plugins whose version actually
changed; a `plugin update failed:` line is a finding. An `orphan marketplace:`
line means this machine has a marketplace registered that shared settings no
longer declare (a retired plugin's source, typically). Sync never removes it —
removal also uninstalls that marketplace's plugins — so carry the printed
`claude plugin marketplace remove <name>` command into the report for the user
to run.

### MCP servers — compare, choose, apply

Read the tracked `mcp.manifest.json` and the machine-local user registry
(`${CLAUDE_CONFIG_DIR}/.claude.json` when configured, otherwise
`$HOME/.claude.json`). Validate the manifest first. The reconcile script is
read-only: it prints a table with one column per host that has ever synced plus
`here`, a blank line, then plan lines. Honour `disabledMcpjsonServers` in
`settings.local.json`; a server disabled here is not a finding. Never print a
command, URL, header, env value, or credential; findings name servers and
variable names only.

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
runtime_mcp="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
[ ! -e "$repo/mcp.manifest.json" ] || "$harness/scripts/mcp-manifest.sh" --check "$repo/mcp.manifest.json"
[ -f "$runtime_mcp" ] || { echo "MCP_STATE=not configured"; runtime_mcp=/dev/null; }
"$harness/scripts/mcp-reconcile.sh" "$repo" "$runtime_mcp" "$claude/settings.local.json"
```

`/dev/null` as the registry makes the planner treat this machine as empty, so
every declared server shows as `INSTALL` or `NO-CONFIG`; that is the correct
picture for a machine that has never added a server.

**Read the plan here; do not carry it in a shell variable** (nothing persists
between blocks, see Phase 0). The plan line kinds:

| line | meaning |
|---|---|
| `INSTALL <name>` | declared with a shape, not here |
| `NO-CONFIG <name>` | declared without a shape; nothing to install from until a machine that has it syncs |
| `SKIP <name>` | declared, not here, recorded in `.fleet-local.json` `skipMcp` |
| `EXTRA <name>` | here, not declared |
| `KEEP-LOCAL <name>` | here, not declared, recorded in `keepLocalMcp` |
| `NEEDS-SECRET <name> <VAR>` | installable, but `VAR` has no value on this machine |
| `UNRESOLVED <name>` | here, command not on `PATH` |

**In a dry run, stop after the table and plan.** Otherwise, if there is no
`INSTALL`, `NO-CONFIG`, `EXTRA`, or `UNRESOLVED` line, print `MCP_STATE=up to date` and
continue to Phase 2.6. If there is, ask **one** question with exactly these
three options, listing the affected names under each:

1. **Match this machine to the repo** — install every `INSTALL` server here,
   then list the `EXTRA` servers and ask a second confirm before removing them
   from this machine. A declined removal is recorded as `keepLocalMcp`.
2. **Replace the repo with this machine** — the manifest's server set becomes
   this machine's set. List, by name, every server only other machines have,
   and confirm: the next sync on those machines will offer to remove them. On
   yes, remember to run Phase 3.75 with `MCP_PRUNE_TO_LOCAL=1`. Nothing is
   installed here.
3. **Merge** — install every `INSTALL` server here and keep every `EXTRA` in the
   manifest. No removals anywhere.

Never pick for the user. `NO-CONFIG` and `SKIP` lines are reported, never acted
on.

**Installing** a server uses the manifest entry with its references intact.
Claude Code expands `${VAR}` from the environment at launch, and the secrets
flow below replaces the reference with the value in the live registry when the
user supplies one:

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
name="<name>"
claude mcp add-json -s user "$name" "$(python3 -c '
import json, sys
entry = json.load(open(sys.argv[1]))["servers"][sys.argv[2]]
print(json.dumps({k: v for k, v in entry.items() if k != "machines"}))
' "$repo/mcp.manifest.json" "$name")"
```

If the command exits non-zero, report `install failed: <name>` as an unresolved
finding and never write it to overrides.

**Removing** a server from this machine (match, after the confirm):

```bash
claude mcp remove -s user "<name>"
```

A non-zero exit is `remove failed: <name>`, an unresolved finding.

**Secrets.** After installs, for every `NEEDS-SECRET <name> <VAR>` line, say
once that pasted values pass through this session's transcript, then print the
command to run on a machine that has the values:

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
echo "On the other machine, run:  \"$harness/scripts/mcp-secrets.sh\" export \"$repo/mcp.manifest.json\" \"\${CLAUDE_CONFIG_DIR:-\$HOME}/.claude.json\""
```

Then ask for the values. The user may paste the whole export block at the first
prompt; feed everything received to `import`, which skips empty values and
names it does not find, and then skip the remaining prompts for names it
covered:

```bash
runtime_mcp="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/mcp-secrets.sh" import "$runtime_mcp" <<'EOF'
<NAME=value lines>
EOF
```

`import` prints counts only. Never echo a value back. A variable the user
leaves empty stays a `NEEDS-SECRET` finding in the report.

**Unresolved commands.** Whenever `UNRESOLVED <name>` lines exist, rerun the
reconcile block after installs if there were any, otherwise go directly to this
follow-up: list them once and ask a single question:
skip these on this machine? On yes, remove each with `claude mcp remove -s user
"<name>"` and record it as `skipMcp` (see Overrides in Phase 2.6), so a machine
without Blender does not keep a blender server. On no, they stay as
`<name> command unavailable on this machine` findings.

Servers present here but absent from the manifest after a choice, except those
recorded in `keepLocalMcp`, are picked up by Phase 3.75's regeneration, which
stamps this host into `machines`.

---

## Phase 2.6: Reconcile third-party skills

**The store.** `npx skills` (vercel-labs) hardcodes its install directory to
`$HOME/.agents/skills` — it never looks at `$AGENTS_REPO`. When this
developer's repo *is* `$HOME/.agents` (the default), `$repo/skills/<name>`
holds the real code for a skill and `$claude/skills` is a symlink to it, so
other agent config already reads it directly (Phase 1 covers that link like
any other tracked entry). Some skills are authored right here in the repo;
others are installed from elsewhere with `npx skills` and should be
*declared*, not vendored. `npx skills list -g --json` reports every skill on
this machine across every agent, each with a `source` field — `null` for
locally-authored skills, `"owner/repo"` for an installed third-party one.
That field is the only thing that tells the two apart; a skill's own files
don't say where it came from.

`$repo/skills.manifest` is the developer's **declared** set of third-party
skills — one `name<TAB>source` line each, sorted, generated, never
hand-edited. It's regenerated from reality at the end of this phase, so a
skill removed by any means (this machine, another machine, or by hand)
simply disappears from the next regeneration. Other agents (Cursor, Pi, …)
symlink into the same store and manage themselves — never touch `~/.cursor`
or `~/.pi`. Codex reads the store natively, so it needs no registration and
this plugin writes nothing under `~/.codex/skills`; the only thing it manages
under `~/.codex` is the `AGENTS.md` link (Phase 1). The manifest only ever
covers entries whose `path` falls under `$HOME/.agents/skills/`.

### 0. One-time migration: untrack `.skill-lock.json`

`npx skills` writes its own lockfile, `.skill-lock.json`, and reads a
skill's `source` back *from that lockfile* — not by inspecting the skill
itself. If this repo tracks it, the failure mode is silent and exactly the
kind this phase exists to prevent: machine A removes a skill, its lock
entry goes with it and that removal gets committed; machine B pulls, but
`skills/<name>` is gitignored so the pull can't delete the now-untracked
directory that's still sitting there from before; `npx skills list` on B
now reports that skill's `source` as `null` (nothing in *its* lockfile
mentions it); this phase's filter correctly drops null-source entries,
so regeneration silently removes it from `.gitignore` — and the next
`git add -A` vendors the third-party code right back into the repo.
Untracked, each machine's lockfile reflects only its own reality, so a
removal shows up as exactly what it is: a manifest entry that's gone while
the skill is still on disk here, i.e. an `EXTRA` — offered for removal like
any other, in step 2 below.

**Detect first — read-only, dry-run safe:**

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
gitignore="$repo/.gitignore"

git -C "$repo" ls-files --error-unmatch .skill-lock.json >/dev/null 2>&1 \
  && echo "TRACKED" || echo "not tracked"

for line in ".fleet-local.json" ".skill-lock.json"; do
  grep -qxF "$line" "$gitignore" 2>/dev/null && echo "gitignored: $line" || echo "missing from .gitignore: $line"
done
```

If it printed `not tracked` and both lines `gitignored: ...`, this repo has
already migrated (or never vendored it) — move on, nothing to fix.

Otherwise, explain the above and fix everything this step is responsible
for in one write:

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
gitignore="$repo/.gitignore"
for line in ".fleet-local.json" ".skill-lock.json"; do
  grep -qxF "$line" "$gitignore" 2>/dev/null || printf '%s\n' "$line" >> "$gitignore"
done

git -C "$repo" add .gitignore
git -C "$repo" rm --cached .skill-lock.json --ignore-unmatch -q
```

Leave both changes staged with every other reconciliation result. Phase 3.75
performs the only transaction after the final scans pass.

**The gitignore lines are written here, unconditionally — not only by step
3.** Step 3 (and the gitignore lines it maintains) is skipped whenever
`npx`/`node` is missing or `$repo` isn't `$HOME/.agents`. On such a
machine, untracking `.skill-lock.json` without also gitignoring it here
would leave it an untracked file sitting in the worktree — the final transaction's
`git add -A` would stage and commit it right back, every single run. Step 0 runs
unconditionally, so its fix has to be self-contained rather than depend on
a step that might not run this time. `--ignore-unmatch` keeps the fix block
safe to run even when only the `.gitignore` lines were missing and
`.skill-lock.json` was never tracked. `skills-manifest.sh` (step 3 below)
also ensures both lines are present as a second, idempotent pass whenever
it does run — harmless overlap, not a second source of truth.

### Guard — the rest of this phase needs `npx`, `node`, and `$repo` at exactly `$HOME/.agents`

```bash
command -v npx >/dev/null 2>&1 && command -v node >/dev/null 2>&1 \
  || echo "SKILLS_STATE=skipped: npx/node not on PATH"
```

If that printed, skip everything below, carry `SKILLS_STATE=skipped: ...`
into the Phase 4 report, and move on to Phase 3. Never let a missing `npx`
traceback into the middle of a sync.

`skills-manifest.sh` and `skills-reconcile.sh` each carry a second guard
internally: if `$repo` isn't exactly `$HOME/.agents` (an overridden
`$AGENTS_REPO`), every real install's `path` fails to match the hardcoded
store from the section above, which would otherwise make everything look
uninstalled and regenerate an empty manifest. Both scripts print their own
`SKILLS_STATE=skipped: ...` and exit 0 without touching any file in that
case — surface that line the same way.

**Order matters, which is why this phase is numbered steps run in this
exact sequence, not whatever order is convenient:**

1. Read the committed manifest and compare it to reality.
2. Offer to install what it declares that isn't here, and offer to resolve
   what's here that it doesn't declare.
3. Only now, regenerate the manifest and `.gitignore` block from reality.

Regeneration has to come **last**. It captures whatever `npx skills list`
reports *at the moment it runs* — if that moment is before step 2 has
changed this machine to match the developer's choices (the common case: a
fresh machine with an empty `skills/` directory), regenerating would
capture that empty state, overwrite the committed manifest with nothing,
and the developer's declaration is gone. Step 2 has to change reality
first; step 3 only ever records reality as it now stands.

### 1. Read the manifest, compare to reality

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
if ! listing="$(npx skills list -g --json 2>/dev/null)"; then
  echo "SKILLS_STATE=failed: npx skills list -g --json exited non-zero"
elif [ -z "$listing" ] || ! printf '%s' "$listing" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
  echo "SKILLS_STATE=failed: npx skills list -g --json produced no parseable output"
else
  printf '%s' "$listing" | "$harness/scripts/skills-reconcile.sh" "$repo"
fi
```

Check the `npx` exit status before trusting its output, then check `$listing`
is valid JSON before piping it anywhere. Parseable stdout from a nonzero
command is still a failure; offline, a registry error, or a truncated pipe can
also leave `$listing` empty or garbage. Piping any of those straight into a
script that calls `json.load` could rewrite state or traceback instead of
failing cleanly. If `SKILLS_STATE=failed` printed, stop — do not proceed to
step 2 or step 3 this run.

Otherwise, `skills-reconcile.sh` reads the committed `skills.manifest`
(absent file → treated as empty — a first run, not an error) and
`.fleet-local.json` (absent → no overrides), diffs both against `listing`,
and prints one line per finding, tab-separated:

| kind | means |
|---|---|
| `INSTALL <name> <source>` | manifest declares it, not on this machine — offer to install |
| `SKIP-INSTALL <name>` | same, but a previous decline (or a hand-edit) says leave it |
| `EXTRA <name> <source>` | on this machine, not in the manifest — offer add/remove |
| `KEEP-LOCAL <name>` | same, but a previous decline says leave it undeclared |

It writes nothing — the same read-only-report role `link-plan.sh` plays for
Phase 1. **This is the entire plan.** Read it here; don't try to carry it
in a shell variable into a later command block — nothing set in one block
persists into the next (see Phase 0), and a block that references a `$plan`
set two blocks ago runs against an empty variable with no error. Every
action below either runs in this same block or uses the literal `name`/
`source` values already visible in this output.

### 2. Offer, don't assume — installs and extras are symmetric

Both `INSTALL` and `EXTRA` lines are **offers**, not automatic actions —
the same shape either way: this machine's third-party skills disagree with
the manifest, and only the developer knows which side is right this time.

**For each `INSTALL <name> <source>` line**, ask whether to install it. If
yes:

```bash
npx skills add "<source>" -s "<name>" -a claude-code -g -y
```

`-a claude-code` matters, and the value is exact — verified against the
installed CLI: without an explicit agent, `npx skills add` registers the skill
with every agent it detects, writing into `~/.cursor`, `~/.pi`, and others that
manage their own registrations. Codex needs no registration at all: it
reads the shared store `~/.agents/skills` natively, so every skill this manifest
installs is already available to Codex (verified live — Codex lists the store's
skills with nothing under `~/.codex/skills`). Never seed `~/.codex/skills`
with copies (`--copy`); they go stale. `-a claude` (no `-code`) is **not** a
valid agent name — it prints `Invalid agents: claude`, exits 1, installs
nothing, and would let step 3 regenerate a 0-byte manifest. Use
`-a claude-code`, exactly. Inside `~/.codex` this plugin touches only the
`AGENTS.md` link (Phase 1); `config.toml`, `hooks.json`, `skills/`, and
Codex-bundled skills are Codex's own.

If the install command fails (network, registry, bad source, or any other
non-zero exit) that's a **failure**, not a decline — report `install
failed: <name> (<source>)` as an unresolved finding, same as an unfixed
lint finding. **Remember this name** — literally, in this conversation, the
same way step 1's plan is read rather than carried in a shell variable —
and pass it to step 3 below so a transient failure doesn't silently
un-declare the skill; don't write anything to overrides for it, since a
decline and a failure must stay distinguishable (see Overrides, below, and
step 3's manifest-preservation rule).

If the developer instead **declines** the install — a deliberate "not on
this machine" — that's not a failure, record it so sync stops asking:
`skipInstall` (see Overrides, below).

**For each `EXTRA <name> <source>` line**, ask whether to add it to the
manifest, remove it, or leave it undeclared. That single fact — installed
here, real source, not declared — has two equally plausible stories behind
it: it was just installed here and never declared, or it *was* declared and
the developer removed it from the manifest on another machine, and this
machine hasn't caught up yet. Nothing in the data distinguishes those two
stories, so this phase doesn't try to — it asks once, with all three
outcomes on the table:

- **Add to the manifest** (the normal case) — no action needed now; the
  skill is already in `listing`, so step 3's regeneration picks it up.
- **Remove it** — `npx skills remove "<name>" -a claude-code -g -y`. If
  this fails, report `remove failed: <name>` as an unresolved finding — a
  different state from a decline, and it should read differently.
- **Leave it undeclared, for now** — a deliberate decline; record it:
  `keepLocal` (see Overrides, below).

**Report every `SKIP-INSTALL` and `KEEP-LOCAL` line too** — a previous
decline, already recorded; do not act on it and do not re-ask.

### Overrides

`$repo/.fleet-local.json` records deliberate per-machine deviations so a
decline doesn't get re-asked forever:

```json
{"skipInstall": ["name", "…"], "keepLocal": ["name", "…"], "skipMcp": ["name", "…"], "keepLocalMcp": ["name", "…"]}
```

- `skipInstall` — declared in the manifest, deliberately not wanted on this
  machine. Reached by declining an install offer above; also fine to
  hand-edit directly when a developer already knows in advance that a
  heavy skill only belongs on one machine.
- `keepLocal` — present on this machine, deliberately left undeclared.
  Reached by declining an extras offer above.
- `skipMcp` — declared in `mcp.manifest.json`, deliberately not on this
  machine. Reached by the unresolved-command follow-up in Phase 2.5.
- `keepLocalMcp` — an MCP server present here, deliberately left undeclared.
  Reached by declining a removal under "match" in Phase 2.5.

An **install failure** or a **remove failure** is never written to either
array — those are unresolved findings that should keep surfacing until
fixed, not silenced. Only an explicit decline goes into overrides.

To add a name, load the file (treat absent as `{"skipInstall": [],
"keepLocal": []}`), append if not already present, keep each array sorted,
and write it back:

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"

override_script='import json, sys

path, kind, name = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
data.setdefault("skipInstall", [])
data.setdefault("keepLocal", [])
data.setdefault("skipMcp", [])
data.setdefault("keepLocalMcp", [])
if name not in data[kind]:
    data[kind].append(name)
    data[kind].sort()
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
'

printf '%s\n' "$override_script" | python3 - "$repo/.fleet-local.json" keepLocal "<name>"
```

Use `kind=skipInstall` for a declined install instead. `.fleet-local.json`
is machine-local by design — it must never be committed; `skills-manifest.sh`
(step 3) keeps both it and `.skill-lock.json` gitignored in the static part
of `.gitignore`, outside the generated block.

**Report deviations once per run, always** — with a `none` fallback when
both arrays are empty, not only when something's there. Otherwise a
standing decline becomes invisible permanent state the moment it stops
being new:

```
Skills local deviations: skipInstall <name>, … | keepLocal <name>, … | none
MCP local deviations:    skipMcp <name>, … | keepLocalMcp <name>, … | none
```

### 3. Regenerate — only after step 2 has run

**The manifest is the shared declaration; `skipInstall` and a this-run
install failure are this machine's local reasons a declared entry isn't
here.** A local reason must never edit the shared declaration. So this
step's output is the *union* of: third-party skills actually present in
the store right now, **plus** entries already in the committed manifest
that are absent here *for a recorded reason* — `skipInstall`, or named as a
failed install in step 2 above. An entry absent with no recorded reason at
all is a genuine removal and correctly drops out — that's the only case
this step is allowed to un-declare something.

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
if ! listing="$(npx skills list -g --json 2>/dev/null)"; then
  echo "SKILLS_STATE=failed: npx skills list -g --json exited non-zero — manifest not regenerated"
elif [ -z "$listing" ] || ! printf '%s' "$listing" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
  echo "SKILLS_STATE=failed: npx skills list -g --json produced no parseable output — manifest not regenerated"
else
  printf '%s' "$listing" | "$harness/scripts/skills-manifest.sh" "$repo" <failed-name> <failed-name> ...
fi
```

Pass every name step 2 reported as `install failed:` this run as a trailing
argument, literally — the same names already visible in this
conversation's step 2 output, not a shell variable carried over from an
earlier block (nothing persists between blocks; see Phase 0). No failures
this run → no trailing arguments.

Deliberately a **fresh** `npx skills list -g --json` call, not anything
captured in step 1 — installs and removals in step 2 changed reality since
then, and regenerating from stale output would write back exactly the
drift this phase exists to fix. Same exit-status and JSON-validity guards as
step 1, for the same reason: a bad `npx` call here — even one that emits
parseable stdout — must not traceback or overwrite a good manifest.
`skills-manifest.sh` never
opens the manifest file for writing until its own JSON parse has already
succeeded, so a failed fetch leaves the existing manifest untouched either
way, but the shell-level check keeps the failure visible instead of a
silent no-op.

`skills-manifest.sh` filters `listing` to entries with a non-null `source`
under `$HOME/.agents/skills/`, reads the *old* manifest and `.fleet-local.json`
before touching either, computes the union described above, writes the
sorted `name<TAB>source` result, and rewrites the `# fleet:skills start` …
`# fleet:skills end` block in `.gitignore` to match — one `skills/<name>/`
line per entry — without touching anything else in that file.

**Backstop.** If the old manifest had at least one entry and the computed
result has none, the script refuses to write and exits non-zero instead —
this exact shape (a good manifest silently replaced by an empty one) has
already caused a silent wipe twice this review, by two different routes.
Report the refusal as an unresolved finding. If every declared skill is
genuinely gone from this machine and that's really intended, rerun with
`SKILLS_ALLOW_EMPTY_MANIFEST=1` to confirm it explicitly — never set that
automatically on the developer's behalf.

**This step depends on Phase 1 having already re-linked `skills`.** `npx
skills` resolves the Claude Code skills directory through `~/.claude/skills`
(or `$CLAUDE_CONFIG_DIR/skills`) to decide where to write; when that path is
the symlink Phase 1 maintains, the install lands in the canonical
`$HOME/.agents/skills` store and this filter keeps it. If that path is ever
a real directory instead — Phase 1 skipped, run out of order, or this phase
invoked standalone — installs land there instead, `npx skills list` reports
that path, `$HOME/.agents/skills/` never matches it, and every install
this phase just offered gets silently dropped and re-offered next run.
Phase 2.6 must always run after Phase 1 in the same sync, never on its own.

---

## Phase 3: Portability lint

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/portability-lint.sh" "$repo"
```

Non-zero exit means something tracked in the repo carries a machine-specific
absolute path. This matters more than it looks: a hardcoded `/Users/<name>` makes
a synced config silently **wrong** on another machine rather than merely absent,
which is much harder to notice than a missing file.

Two findings and their fixes:

- `literal home path` in a file → replace with `$HOME`, or
  `${XDG_CONFIG_HOME:-$HOME/.config}` for config paths.
- `absolute symlink target` → re-point the link relatively, or drop it if it
  reaches outside the repo.

Offer to fix each one, showing the edit. If the user declines, carry the finding
into the report — never fail silently.

**Also check hook guards.** For any hook in `claude/settings.json` invoking a binary
that may not exist on every machine, confirm it is guarded:

```sh
[ -x "$HOME/.tool/bin/hook" ] && "$HOME/.tool/bin/hook" args || true
```

Unguarded, it errors on every event on machines without that tool.

---

## Phase 3.5: Rubric audit

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/rubric-audit.sh" --days 7 || true
```

Read-only. Reports how sub-agents were actually routed over the last week: dispatches
by `model` param, `UNSET` count, haiku count, and codex handoffs. Exit `1` means a
finding — an omitted `model` (routing by inheritance) or a haiku dispatch — carry it
into the report. Exit `3` means python3 is missing; report `skipped: python3 not on
PATH`. Do not try to fix past dispatches; the point is to see drift, and to notice
when bulk work is landing on native sub-agents instead of the codex handoff.

---

## Phase 3.75: Validate and synchronize once

All repo and machine reconciliation must be complete before this phase. Complete
the final idempotent shared-setting, MCP, render, and portability checks here.
Phase 2.6 is the sole skill-manifest writer because only it retains declined and
failed-install context; do not regenerate that manifest here. The finalizer is the
last command; nothing may write the repo after it returns:

If the user chose **Replace the repo with this machine** in Phase 2.5, run this
block with `MCP_PRUNE_TO_LOCAL=1` set in front of the command. Otherwise leave it
unset; the generator then only updates this host's `machines` entries.
The generator skips servers recorded in `.fleet-local.json` `keepLocalMcp` that are not already declared, so a decline recorded in Phase 2.5 survives regeneration.

```bash
set -euo pipefail
repo="${AGENTS_REPO:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
runtime_mcp="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"

[ ! -e "$repo/claude/settings.json" ] || "$harness/scripts/localize-skill-overrides.py" "$repo/claude/settings.json" "$claude/settings.local.json"
[ ! -e "$repo/claude/settings.json" ] || "$harness/scripts/reconcile_shared_settings.py" "$repo/claude/settings.json"
[ ! -f "$runtime_mcp" ] || "$harness/scripts/mcp-manifest.sh" ${MCP_PRUNE_TO_LOCAL:+--prune-to-local} "$runtime_mcp" "$repo/mcp.manifest.json"
"$harness/scripts/render-codex-agents.sh" "$repo"
"$harness/scripts/link-plan.sh" "$repo"
"$harness/scripts/portability-lint.sh" "$repo"
"$harness/scripts/sync-finalize.sh" "$repo" "harness: sync from $(hostname -s) — reconciled portable agent config"
```

`sync-finalize.sh` stages the complete result, checks the staged diff, reruns the
portability gate, validates the MCP inventory, and performs explicit staged secret
and machine-local state scans. Only then does it perform at most one commit and
exactly one push; remote ingestion has already completed before reconciliation, so the
finalizer never pulls.
It fails closed on divergence, a missing remote, any write after staging,
or a rejected compare-and-swap push. Never retry with merge, rebase, or
unconditional force; the finalizer itself uses an exact `--force-with-lease`
expectation captured by preflight for both existing and absent branches.

Success requires both a final clean worktree and a local HEAD equal to the reported
remote SHA. If either proof is absent, Sync is incomplete. Do not run another
generator, installer, formatter, or repo writer after the finalizer.

---

## Phase 4: Report

```
Harness sync — {repo}

  Links:      {N} ok, {M} relinked, {K} need attention
  Derived:    {codex/AGENTS.md unchanged | codex/AGENTS.md regenerated | failed: <reason> |
               [skipped in dry run]}
  Committed:  {nothing local | <short message>: N added, M modified, K deleted}
  Ingest:     {up to date | fast-forwarded N commits: <oneline list> |
               skipped in dry run | DIVERGED — not pushed}
  Push:       {pushed <sha> | skipped: <reason> | no remote configured}
  Final:      {clean worktree, remote SHA <sha> | FAILED: <reason>}
  Plugins:    {up to date | added N marketplace(s), installed M, updated K — restart or
               /reload-plugins to apply | skipped: claude CLI not on PATH | failed: <reason>}
  Orphans:    {none | <name> — remove with: claude plugin marketplace remove <name>}
  MCP:        {up to date | N ok, M remote (no local command) | N ok, M skipped here,
               K need config: <names>, J need secrets: <NAME>, … | not configured}
  MCP local deviations: skipMcp <name>, … | keepLocalMcp <name>, … | none
  Skills:     {N declared, M installed, K extra | up to date |
               skipped: npx/node not on PATH | skipped: repo is not $HOME/.agents |
               failed: <reason>}
  Skills local deviations: skipInstall <name>, … | keepLocal <name>, … | none
  Lint:       {clean | N finding(s), M fixed}
  Rubric:     {N dispatches, all explicit, 0 haiku, K codex handoffs |
               N dispatches: U unset, H haiku — see below | skipped: python3 not on PATH}

{any unresolved finding, one per line}
```

The `Skills local deviations` line always prints, with the `none` fallback
when both override arrays are empty — never omit it just because there's
nothing to show; a standing decline is exactly the kind of state that goes
invisible if it's only reported the first time.

If anything is unresolved, say so in the summary line — do not report success with
open findings buried above. That includes a failed marketplace add or plugin
install from Phase 2.5, `claude` missing from `$PATH`, or `claude plugin list` /
`claude plugin marketplace list` itself failing (report any of these the same as
an unfixed lint finding), any MCP server whose command didn't resolve (list
each as `<name> command unavailable on this machine`, without its local path,
alongside the other
unresolved findings), and any Phase 2.6 `install failed` or `remove failed`
line — both are distinct from a recorded decline (`skipInstall`/`keepLocal`,
reported in the deviations line above, not here) and must stay visible until
fixed. That also includes an MCP install failed: <name> or remove failed: <name>,
a NEEDS-SECRET left empty, and every NO-CONFIG name until a machine with the
config syncs. A server with no `command` (a URL/SSE-style server) is not a finding —
it's counted separately as "remote," never folded into "ok." A rubric-audit finding (any UNSET or haiku dispatch) is unresolved in the same sense — list it, do not fold it into a clean summary.

**Never report a sync as complete when the push did not happen.** A diverged pull,
a rejected push, or a missing remote all mean this machine's changes have not
reached anywhere else, and the next machine to sync will get the old state. That is
the exact failure this skill exists to prevent, so it belongs in the first line of
the report, not buried in a field.

**On a first run only** (Phase 0 reported `absent` and you cloned or adopted), add
two lines after the report:

1. Restart running agent sessions after the links are verified. They can retain old
   settings in memory, and a stale writer can replace a fresh link with a real file.
2. Nothing runs this skill automatically, so drift goes unnoticed until someone
   runs it again. Offer to set up a recurring `/harness:sync` with whichever
   scheduler they already use — their agent tool's scheduled tasks, `cron`, or
   `launchd`. Daily is plenty. Ask which they prefer; do not pick one, and do not
   install anything unasked. Say it once and drop it — repeating this on every sync
   is noise.

---

## Phase 5: Push (optional)

Only if `$repo/machine.yml` exists. Skip this phase entirely otherwise; never
create `machine.yml` unprompted.

**Legacy name.** If `$repo/machine.yml` is absent but `$repo/fleet.yml` exists
(a repo from before this plugin's rename), don't skip silently — tell the
user their push config is still under the old name and offer to rename it:
`mv "$repo/fleet.yml" "$repo/machine.yml"`.

```yaml
# machine.yml
machines:
  - host: studio-mini      # ssh target: a Host from ~/.ssh/config, or user@addr
  - host: laptop
```

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
command -v yq >/dev/null 2>&1 || { echo "yq not found — install it to use Phase 5 (push)."; exit 1; }
yq -r '.machines[].host' "$repo/machine.yml"
```

Confirm the host list with the user, then for each:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" 'cd "${AGENTS_REPO:-$HOME/.agents}" && git pull --ff-only' 2>&1
```

The remote path expression matches Phase 0's local resolution (`$AGENTS_REPO`
if the remote machine has it set, else `$HOME/.agents`) rather than a
hardcoded `~/.agents`, so pushing is consistent with how this machine finds
its own repo.

- Unreachable → report and continue to the next host. One offline machine is not
  a failure of the run.
- Non-zero exit → report that host's output verbatim.

**Be honest about what this proves.** A remote `git pull` says the remote repo
advanced. It does **not** confirm the remote machine re-linked correctly — that
needs `harness:sync` run there. Report what was attempted, not what succeeded:

```
Pushed to {N}/{M} machines. {list}
Unreachable: {list}
A pull is not a relink — run /harness:sync on a machine if its links may have drifted.
```
