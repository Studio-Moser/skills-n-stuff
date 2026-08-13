---
name: sync
description: >-
  Make this machine match your personal agent repo — the private repo holding your
  skills, global CLAUDE.md, and shared Claude Code settings. Clones on first run,
  pulls after; re-links anything that drifted back into ~/.claude, lints for paths
  that would be wrong on another machine, and optionally pushes to your other
  machines. Trigger: "sync my config", "sync my machines", "update my skills from
  my repo", "is this machine up to date", or /fleet:sync.
  Do NOT use for setting up a machine that has no plugins yet (follow
  studio-baseline/Machine_Setup.md), for creating the model rubric (that's
  /fleet:model-rubric), or for anything in a project repo — sync only touches this
  developer's user-global agent config.
effort: low
allowed-tools: "Bash Read Edit"
---

# Fleet — Sync

Makes this machine match your personal agent repo.

**Default repo:** `$HOME/.agents`. If `$FLEET_REPO` is set, use that instead.

---

## Dry run

If the user asks what would change, or passes `--dry-run`, run **only the two
read-only scripts** — `link-plan.sh` (Phase 1's command) and
`portability-lint.sh` (Phase 3's command) — then print the report from
Phase 4 and stop. Do **not** follow Phase 1's action column
(create/re-link/remove) or Phase 3's fix suggestions in dry-run mode — those
are writes, not part of the dry run. Nothing is created, moved, or removed.
Both scripts are read-only, so this is safe to offer unprompted when the
user seems unsure.

---

## Phase 0: Locate the repo

```bash
repo="${FLEET_REPO:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[ -d "$repo/.git" ] && echo "found" || echo "absent"
```

`link-plan.sh` resolves `$claude` the same way internally — use this `$claude`
variable everywhere below instead of hardcoding `~/.claude` or `$HOME/.claude`,
so the skill and the script always agree on which directory is being managed.

**absent** — first run on this machine. Ask the user for their private repo URL;
do not guess one. Then:

```bash
git clone <url> "$repo"
```

If the clone fails on authentication, say so plainly and stop — do not fall back
to another protocol without asking. A common cause is an SSH remote with no key
loaded (`ssh-add -l` reports no identities); `gh auth status` will show whether
HTTPS is the configured protocol instead.

**found** — continue.

---

## Phase 1: Link check

**Run this before pulling.** `CLAUDE.md` and `settings.json` are both rewritten by
tooling — a memory tool's bootstrap block edits one, Claude Code writes the other
on plugin toggle. A writer that does atomic-replace (temp file + rename) rather
than write-in-place silently converts a symlink back into a real file, and sync
stops working with no signal. This phase is how that gets noticed.

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/link-plan.sh" "$repo"
```

Each line ends in a state:

| state | meaning | action |
|---|---|---|
| `ok` | correct symlink | nothing |
| `ABSENT` | no such path in `$claude` | create the link |
| `REAL-FILE` | a real file (or directory — `skills` is one of the four tracked entries) sits where the link should be | **diff first** (below) |
| `RELINK(->X)` | symlink points somewhere else | show `X`, confirm, re-link |
| `MISSING-IN-REPO` | the repo has no such file | report; do not create anything |

**`MISSING-IN-REPO` is checked first and masks the other states.** If the
repo lacks the file, `link-plan.sh` reports `MISSING-IN-REPO` for that entry
no matter what `$claude` currently has there (a real file, a drifted
symlink, or nothing) — the five states are not independent signals about
both sides at once. Don't infer "no real file exists on this machine" from a
`MISSING-IN-REPO` line.

**`RELINK(->X)` can be a false positive on a working link.** The script
compares the symlink target to the expected path as a raw string, not a
resolved path, so a symlink using a *relative* target that still resolves to
the right file also reports `RELINK`. Before re-linking, resolve `X` (e.g.
`readlink -f "$claude/<name>"`) and compare it to `$repo/<rel>`; if they
match, leave the link alone — re-linking would just churn a working link.

**On `REAL-FILE`, never overwrite silently.** That file may hold edits made on
this machine since the link broke. `skills` is a *directory*, so the diff must
be recursive, and its exit status must be branched on explicitly rather than
swallowed:

```bash
diff -ru "$repo/<rel>" "$claude/<name>"
status=$?
```

- **`status` = 0 (identical)** → remove the stray file (or `rm -r` the stray
  directory) and re-link.
- **`status` = 1 (differs)** → show the diff and ask: keep the machine's
  version (copy it into the repo, then re-link), or discard it (re-link to
  the repo's version). Never pick for the user.
- **`status` >= 2 (error — e.g. a missing or unreadable path)** → stop and
  report. Do **not** remove or re-link anything; an error is not the same as
  "no differences."

  A plain `diff -u` here is a data-loss trap: non-recursive `diff` against
  two directories prints only `Common subdirectories: …` and exits 0 even
  when their contents differ, so the "no differences" branch would fire and
  delete a `skills` tree that might hold this machine's only copy of local
  edits. `-r` is required, not optional.

To create or re-link, use:

```bash
ln -sfn "$repo/<rel>" "$claude/<name>"
```

The target must be the **absolute** path `"$repo/<rel>"` — `link-plan.sh`
compares symlink targets as raw strings (see the `RELINK` false-positive note
above), so a relative target would report `RELINK` on every future run even
though it resolves correctly. Use `-sfn`, not plain `-sf`: against an
existing symlink-to-directory (`skills` again) `ln -sf` dereferences the old
link and writes the new one *inside* its target instead of replacing it,
silently no-opping while still exiting 0.

---

## Phase 2: Pull

```bash
git -C "$repo" status --short
```

If the tree is dirty, show it and ask whether to commit or stash before pulling.
Do not stash without asking — those may be deliberate local edits.

```bash
git -C "$repo" pull --ff-only
```

If the pull is not fast-forwardable, stop and report. Do not merge or rebase
someone's personal repo on their behalf.

---

## Phase 3: Portability lint

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/portability-lint.sh" "$repo"
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

## Phase 4: Report

```
Fleet sync — {repo}

  Links:      {N} ok, {M} relinked, {K} need attention
  Pull:       {up to date | N commits: <oneline list>}
  Lint:       {clean | N finding(s), M fixed}

{any unresolved finding, one per line}
```

If anything is unresolved, say so in the summary line — do not report success with
open findings buried above.

---

## Phase 5: Push (optional)

Only if `$repo/fleet.yml` exists. Skip this phase entirely otherwise; never
create `fleet.yml` unprompted.

```yaml
# fleet.yml
machines:
  - host: studio-mini      # ssh target: a Host from ~/.ssh/config, or user@addr
  - host: laptop
```

```bash
command -v yq >/dev/null 2>&1 || { echo "yq not found — install it to use Phase 5 (push)."; exit 1; }
yq -r '.machines[].host' "$repo/fleet.yml"
```

Confirm the host list with the user, then for each:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" 'cd "${FLEET_REPO:-$HOME/.agents}" && git pull --ff-only' 2>&1
```

The remote path expression matches Phase 0's local resolution (`$FLEET_REPO`
if the remote machine has it set, else `$HOME/.agents`) rather than a
hardcoded `~/.agents`, so pushing is consistent with how this machine finds
its own repo.

- Unreachable → report and continue to the next host. One offline machine is not
  a failure of the run.
- Non-zero exit → report that host's output verbatim.

**Be honest about what this proves.** A remote `git pull` says the remote repo
advanced. It does **not** confirm the remote machine re-linked correctly — that
needs `fleet:sync` run there. Report what was attempted, not what succeeded:

```
Pushed to {N}/{M} machines. {list}
Unreachable: {list}
A pull is not a relink — run /fleet:sync on a machine if its links may have drifted.
```
