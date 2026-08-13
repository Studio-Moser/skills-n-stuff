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

If the user asks what would change, or passes `--dry-run`, run Phases 1 and 3
only, print the report from Phase 4, and stop. Nothing is created, moved, or
removed. Both scripts are read-only, so this is safe to offer unprompted when
the user seems unsure.

---

## Phase 0: Locate the repo

```bash
repo="${FLEET_REPO:-$HOME/.agents}"
[ -d "$repo/.git" ] && echo "found" || echo "absent"
```

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
| `ABSENT` | no such path in `~/.claude` | create the link |
| `REAL-FILE` | a real file sits where the link should be | **diff first** (below) |
| `RELINK(->X)` | symlink points somewhere else | show `X`, confirm, re-link |
| `MISSING-IN-REPO` | the repo has no such file | report; do not create anything |

**On `REAL-FILE`, never overwrite silently.** That file may hold edits made on this
machine since the link broke:

```bash
diff -u "$repo/<rel>" "$HOME/.claude/<name>" || true
```

- **No differences** → remove the stray file and re-link.
- **Differences** → show the diff and ask: keep the machine's version (copy it into
  the repo, then re-link), or discard it (re-link to the repo's version). Never pick
  for the user.

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
  Skills:     {count} available

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
yq -r '.machines[].host' "$repo/fleet.yml"
```

Confirm the host list with the user, then for each:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" 'cd ~/.agents && git pull --ff-only' 2>&1
```

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
