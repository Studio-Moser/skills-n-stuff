# Fleet Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `fleet` plugin plus a zero-plugin bootstrap doc that keeps a developer's personal agent config (skills, global instructions, shared settings) identical across machines, and move the model-rubric machinery out of `pm`.

**Architecture:** Two surfaces. `studio-baseline/Machine_Setup.md` is fetchable over raw.githubusercontent and works on a bare machine with shell + web only — necessary because fleet's job is setting up a machine, and on a fresh machine no plugin is installed. The `fleet` plugin automates the repeated work once installed: `fleet:sync` (link check → pull → portability lint → report → optional push) and `fleet:model-rubric` (create/refresh). Both lean on small, independently testable shell scripts; the skills are the interactive wrapper.

**Tech Stack:** Bash (POSIX-ish, macOS `/bin/bash` 3.2 compatible), `bats` for tests, `yq`/`jq` for YAML/JSON, `git`, markdown skills with YAML frontmatter.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-08-12-fleet-plugin-design.md`. Read it before starting.
- **Worktree:** work in `/Users/timmoser/Projects/skills-n-stuff-fleet` on `feat/fleet-plugin`. Never `git add -A` — stage explicit paths only (house rule from #22).
- **Commits:** Conventional Commits, present tense, one logical change each.
- **PRs:** imperative title < 72 chars; body always `## What` / `## Why` / `## Testing` with pasted output. One PR per task.
- **No literal `/Users/<name>` in anything committed.** Use `$HOME` or `${XDG_CONFIG_HOME:-$HOME/.config}`.
- **Bash 3.2:** macOS ships bash 3.2. No associative arrays (`declare -A`), no `${var^^}`. Indexed arrays and `case` are fine.
- **`set -euo pipefail`** at the top of every script.
- **Rubric path constant** (used verbatim in several places): `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`
- **Raw URL base:** `https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/`
- `studio-baseline/Rubric_Setup.md` **does not move** and is not edited by this plan.

## File Structure

| File | Responsibility |
|---|---|
| `plugins/fleet/.claude-plugin/plugin.json` | plugin manifest |
| `plugins/fleet/README.md` | what the plugin is, how it relates to the private repo |
| `plugins/fleet/scripts/portability-lint.sh` | fail on machine-specific absolute paths (contents **and** symlink targets) |
| `plugins/fleet/scripts/link-plan.sh` | read-only drift report: intended link map vs actual state |
| `plugins/fleet/scripts/rubric-path.sh` | resolve/check the rubric path (moved from `pm`) |
| `plugins/fleet/scripts/fetch-model-data.sh` | pull cost/intelligence from Artificial Analysis (moved from `pm`) |
| `plugins/fleet/skills/sync/SKILL.md` | `fleet:sync` — the interactive wrapper |
| `plugins/fleet/skills/model-rubric/SKILL.md` | `fleet:model-rubric` — create/refresh |
| `plugins/fleet/tests/portability-lint.bats` | lint tests, incl. the absolute-symlink regression |
| `plugins/fleet/tests/link-plan.bats` | drift-report tests |
| `plugins/fleet/tests/rubric-path.bats` | moved from `pm` |
| `plugins/fleet/tests/run-tests.sh` | runner (mirrors `plugins/pm/tests/run-tests.sh`) |
| `studio-baseline/Machine_Setup.md` | zero-plugin bootstrap walkthrough |

**Task order matters.** Task 6 (pm surgery) must land with or after Task 2, or both plugins will offer to create the rubric.

---

### Task 1: Portability lint

The one piece with a real bug class behind it. During the audit, a symlink at `skills/superpowers -> /Users/timmoser/.codex/superpowers/skills` passed a content-grep lint, because `grep` follows the link and reads the *target's* contents. The lint must inspect symlink targets separately, via the git index.

**Files:**
- Create: `plugins/fleet/scripts/portability-lint.sh`
- Test: `plugins/fleet/tests/portability-lint.bats`
- Create: `plugins/fleet/tests/run-tests.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `portability-lint.sh [repo_dir]` — defaults to `.`; exits `0` clean, `1` on any finding; prints one line per finding to stdout. Task 4 and Task 5 both call it.

- [ ] **Step 1: Write the failing tests**

Create `plugins/fleet/tests/portability-lint.bats`:

```bash
#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/portability-lint.sh"
  REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$REPO"
  cd "$REPO"
  git init -q -b main .
  git config user.email t@example.com
  git config user.name t
}

commit_all() {
  git add -A
  git commit -q -m x
}

@test "clean repo passes" {
  printf 'uses $HOME and nothing else\n' > ok.md
  commit_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
}

@test "literal home path in file contents fails" {
  printf 'command: /Users/alice/.shelby/bin/hook\n' > bad.md
  commit_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad.md"* ]]
}

@test "linux home path in file contents fails" {
  printf 'path: /home/bob/.config/thing\n' > bad.md
  commit_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
}

@test "symlink with absolute target fails" {
  # The regression. A content grep follows this link and reads the target,
  # so a naive lint reports nothing.
  mkdir -p "${BATS_TEST_TMPDIR}/outside"
  printf 'harmless content with no home paths\n' > "${BATS_TEST_TMPDIR}/outside/f.md"
  ln -s "${BATS_TEST_TMPDIR}/outside" linked
  commit_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"linked"* ]]
}

@test "symlink with relative target passes" {
  mkdir -p real
  printf 'fine\n' > real/f.md
  ln -s real alias
  commit_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
}

@test "untracked files are ignored" {
  printf 'ok\n' > tracked.md
  commit_all
  printf '/Users/alice/scratch\n' > untracked.md
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
}
```

Create `plugins/fleet/tests/run-tests.sh` (mirrors pm's):

```bash
#!/usr/bin/env bash
# Run every .bats file under plugins/fleet/tests/.
set -euo pipefail
cd "$(dirname "$0")"
bats *.bats
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
chmod +x plugins/fleet/tests/run-tests.sh
./plugins/fleet/tests/run-tests.sh
```

Expected: all 6 fail — `portability-lint.sh` does not exist. (Three further tests cover the guards below, bringing the file to 9.)

- [ ] **Step 3: Write the implementation**

Create `plugins/fleet/scripts/portability-lint.sh`:

```bash
#!/usr/bin/env bash
# Fail if any tracked file carries a machine-specific absolute path.
#
# Checks BOTH file contents AND symlink targets. This is not belt-and-braces:
# grep follows a symlink and reads its target's contents, so a link pointing at
# /Users/<name>/... passes a contents-only lint silently. Found in the wild.
set -euo pipefail

repo="${1:-.}"
cd "$repo"

git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository: $repo" >&2; exit 1; }

fail=0

# 1. Symlink targets, read from the git index (mode 120000). Any absolute
#    target is non-portable, whatever it points at.
#    core.quotePath=false: non-ASCII names come through raw instead of
#    C-quoted, so readlink sees the real path instead of a literal '"..."'.
while IFS= read -r link; do
  [ -n "$link" ] || continue
  # A tracked symlink can be absent from the worktree (e.g. mid fleet:sync);
  # readlink then fails. Don't let that abort the whole lint under set -e —
  # just skip it and keep scanning everything else.
  target="$(readlink "$link" || true)"
  case "$target" in
    /*) printf 'absolute symlink target: %s -> %s\n' "$link" "$target"; fail=1 ;;
  esac
done <<EOF
$(git -c core.quotePath=false ls-files -s | grep '^120000 ' | cut -f2-)
EOF

# 2. File contents. Skip symlinks — handled above, and grep would follow them.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -L "$f" ] && continue
  [ -f "$f" ] || continue
  if grep -nHE '/(Users|home)/[A-Za-z0-9._-]+' "$f" 2>/dev/null; then
    fail=1
  fi
done <<EOF
$(git -c core.quotePath=false ls-files)
EOF

exit "$fail"
```

Note the `<<EOF` heredocs rather than `< <(...)` process substitution: the latter is a bashism that breaks when the script is invoked via `sh`.

Three guards are load-bearing, each closing a false negative in a lint whose whole job is catching false negatives:

- **`git rev-parse --git-dir`** — without it, `git ls-files` fails inside the heredoc substitution, its status is discarded, both loops get empty input, and a non-git directory reports *clean*. Tasks 4 and 5 use this as a gate.
- **`core.quotePath=false`** on both `ls-files` calls — git's default C-quotes non-ASCII names (`"caf\303\251.md"`), so `[ -f "$f" ]` fails and the file is never scanned.
- **`readlink ... || true`** — a tracked symlink absent from the worktree (plausible mid-`fleet:sync`) otherwise fails under `set -e`, killing the script before the contents pass and exiting 1 with *no output*, violating this script's stated contract.

Each has a regression test; the suite is 9 tests, not 6.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
chmod +x plugins/fleet/scripts/portability-lint.sh
./plugins/fleet/tests/run-tests.sh
```

Expected: `9 tests, 0 failures`. Paste the output into the PR.

- [ ] **Step 5: Commit**

```bash
git add plugins/fleet/scripts/portability-lint.sh plugins/fleet/tests/portability-lint.bats plugins/fleet/tests/run-tests.sh
git commit -m "feat(fleet): portability lint covering contents and symlink targets"
```

---

### Task 2: Plugin scaffold and relocated rubric scripts

**Files:**
- Create: `plugins/fleet/.claude-plugin/plugin.json`, `plugins/fleet/README.md`
- Move: `plugins/pm/scripts/rubric-path.sh` → `plugins/fleet/scripts/rubric-path.sh`
- Move: `plugins/pm/scripts/fetch-model-data.sh` → `plugins/fleet/scripts/fetch-model-data.sh`
- Move: `plugins/pm/tests/rubric-path.bats` → `plugins/fleet/tests/rubric-path.bats`
- Modify: `.claude-plugin/marketplace.json`

**Interfaces:**
- Consumes: `run-tests.sh` from Task 1.
- Produces: `rubric-path.sh` (prints resolved path; `--check` prints `set`/`unset`) and `fetch-model-data.sh` (TSV on stdout; exit 3 = no API key) at their new paths. Tasks 3 and 6 reference them.

- [ ] **Step 1: Move the scripts and their test with history**

Use `git mv` so blame survives. `fetch-model-data.sh` moves at its current head — it was fixed for the Artificial Analysis v2 nested schema in #23, and a hand-copied stale version would silently mis-parse.

```bash
git mv plugins/pm/scripts/rubric-path.sh plugins/fleet/scripts/rubric-path.sh
git mv plugins/pm/scripts/fetch-model-data.sh plugins/fleet/scripts/fetch-model-data.sh
git mv plugins/pm/tests/rubric-path.bats plugins/fleet/tests/rubric-path.bats
```

- [ ] **Step 2: Run both suites to verify the move**

`rubric-path.bats` resolves the script via `${BATS_TEST_DIRNAME}/../scripts/rubric-path.sh`, so it needs no edit — the relative path holds in the new location.

```bash
./plugins/fleet/tests/run-tests.sh
./plugins/pm/tests/run-tests.sh
```

Expected: fleet `13 tests, 0 failures` (9 lint + 4 rubric-path); pm passes with 4 fewer tests than before (32). If pm fails, a pm test referenced the moved script — fix by pointing it at the constant, not by restoring the copy.

- [ ] **Step 3: Write the plugin manifest**

Create `plugins/fleet/.claude-plugin/plugin.json`:

```json
{
  "name": "fleet",
  "version": "0.1.0",
  "description": "Keep personal agent configuration identical across every machine you work on. Links a private repo of skills, global instructions, and shared Claude Code settings into ~/.claude, detects drift and non-portable paths, and optionally pushes to other machines. Also owns the per-developer model-routing rubric.",
  "author": {
    "name": "Studio Moser",
    "url": "https://github.com/Studio-Moser"
  },
  "repository": "https://github.com/Studio-Moser/skills-n-stuff",
  "license": "MIT",
  "keywords": [
    "dotfiles",
    "multi-machine",
    "sync",
    "agent-config",
    "skills",
    "model-routing",
    "bootstrap"
  ]
}
```

- [ ] **Step 4: Write the plugin README**

Create `plugins/fleet/README.md`:

```markdown
# fleet

Keeps your personal agent configuration identical across machines.

Your config lives in **your own private repo** — this plugin never contains it.
The plugin is public and generic; the data is yours.

## Skills

- **`/fleet:sync`** — make this machine match your personal agent repo. Clones on
  first run, pulls after. Re-links anything that drifted, lints for paths that
  would be wrong on another machine, and optionally pushes to other machines.
- **`/fleet:model-rubric`** — create or refresh your user-global model-routing
  rubric at `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`.

## Bootstrapping a bare machine

This plugin can't set up a machine that has no plugins installed. For that, follow
[`studio-baseline/Machine_Setup.md`](https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/Machine_Setup.md),
which needs only a shell and web access. Install this plugin afterwards for the
ongoing work.

## Scripts

| | |
|---|---|
| `scripts/link-plan.sh [repo]` | read-only drift report; exit 1 if any link needs work |
| `scripts/portability-lint.sh [repo]` | fail on machine-specific absolute paths |
| `scripts/rubric-path.sh [--check]` | resolve the rubric path / report `set`\|`unset` |
| `scripts/fetch-model-data.sh` | current model cost + intelligence as TSV (exit 3 = no API key) |

## Tests

```bash
./tests/run-tests.sh
```
```

- [ ] **Step 5: Register in the marketplace**

Add to the `plugins` array in `.claude-plugin/marketplace.json`, after the `pm` entry. Match the surrounding style exactly — `version` last, as `pm` has it:

```json
    {
      "name": "fleet",
      "source": "./plugins/fleet",
      "description": "Keep personal agent configuration identical across every machine you work on. Links a private repo of skills, global instructions, and shared Claude Code settings into ~/.claude, detects drift and non-portable paths, and optionally pushes to other machines. Also owns the per-developer model-routing rubric.",
      "author": {
        "name": "Studio Moser"
      },
      "license": "MIT",
      "keywords": [
        "dotfiles",
        "multi-machine",
        "sync",
        "agent-config",
        "skills",
        "model-routing",
        "bootstrap"
      ],
      "category": "productivity",
      "tags": [
        "dotfiles",
        "multi-machine",
        "sync",
        "agent-config"
      ],
      "version": "0.1.0"
    },
```

- [ ] **Step 6: Verify JSON and commit**

```bash
python3 -c "import json;[json.load(open(f)) for f in ['.claude-plugin/marketplace.json','plugins/fleet/.claude-plugin/plugin.json']];print('JSON OK')"
./plugins/fleet/tests/run-tests.sh
```

Expected: `JSON OK`, then `13 tests, 0 failures`.

```bash
git add plugins/fleet/.claude-plugin/plugin.json plugins/fleet/README.md plugins/fleet/scripts/rubric-path.sh plugins/fleet/scripts/fetch-model-data.sh plugins/fleet/tests/rubric-path.bats .claude-plugin/marketplace.json
git commit -m "feat(fleet): scaffold plugin, relocate rubric machinery from pm"
```

---

### Task 3: Link plan (drift report)

**Files:**
- Create: `plugins/fleet/scripts/link-plan.sh`
- Test: `plugins/fleet/tests/link-plan.bats`

**Interfaces:**
- Consumes: nothing.
- Produces: `link-plan.sh [repo_dir]` — repo defaults to `$HOME/.agents`; honours `CLAUDE_CONFIG_DIR` (default `$HOME/.claude`). Prints one line per link: `<link name> -> <repo path> <STATE>`. States are `ok`, `ABSENT`, `REAL-FILE`, `RELINK`, `MISSING-IN-REPO`. Exit `0` only when every link is `ok`. Task 4's `--dry-run` is this script plus `portability-lint.sh`.

- [ ] **Step 1: Write the failing tests**

Create `plugins/fleet/tests/link-plan.bats`:

```bash
#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/link-plan.sh"
  REPO="${BATS_TEST_TMPDIR}/agents"
  export CLAUDE_CONFIG_DIR="${BATS_TEST_TMPDIR}/claude"
  mkdir -p "$REPO/skills" "$REPO/claude" "$CLAUDE_CONFIG_DIR"
  : > "$REPO/claude/CLAUDE.md"
  : > "$REPO/claude/settings.json"
  : > "$REPO/claude/statusline-command.sh"
}

link_all() {
  ln -s "$REPO/skills" "$CLAUDE_CONFIG_DIR/skills"
  ln -s "$REPO/claude/CLAUDE.md" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
  ln -s "$REPO/claude/settings.json" "$CLAUDE_CONFIG_DIR/settings.json"
  ln -s "$REPO/claude/statusline-command.sh" "$CLAUDE_CONFIG_DIR/statusline-command.sh"
}

@test "all four links correct -> exit 0, every line ok" {
  link_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c ' ok$')" -eq 4 ]
}

@test "missing link is reported ABSENT and exits 1" {
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ABSENT"* ]]
}

@test "a symlink replaced by a real file is reported REAL-FILE" {
  link_all
  rm "$CLAUDE_CONFIG_DIR/settings.json"
  printf '{}' > "$CLAUDE_CONFIG_DIR/settings.json"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"settings.json"* ]]
  [[ "$output" == *"REAL-FILE"* ]]
}

@test "a symlink pointing somewhere else is reported RELINK" {
  link_all
  rm "$CLAUDE_CONFIG_DIR/CLAUDE.md"
  ln -s "${BATS_TEST_TMPDIR}/elsewhere.md" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"RELINK"* ]]
}

@test "file absent from the repo is reported MISSING-IN-REPO" {
  link_all
  rm "$REPO/claude/statusline-command.sh"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING-IN-REPO"* ]]
}

@test "read-only: reports drift without fixing it" {
  run "$SCRIPT" "$REPO"
  [ ! -e "$CLAUDE_CONFIG_DIR/CLAUDE.md" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./plugins/fleet/tests/run-tests.sh
```

Expected: the 6 link-plan tests fail — script does not exist.

- [ ] **Step 3: Write the implementation**

Create `plugins/fleet/scripts/link-plan.sh`:

```bash
#!/usr/bin/env bash
# Report how this machine's ~/.claude compares to a personal agent repo.
# READ-ONLY. Creates nothing, removes nothing — fleet:sync acts on this output.
set -euo pipefail

repo="${1:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# "<name under ~/.claude>|<path under repo>"
entries="skills|skills
CLAUDE.md|claude/CLAUDE.md
settings.json|claude/settings.json
statusline-command.sh|claude/statusline-command.sh"

status=0
while IFS='|' read -r name rel; do
  [ -n "$name" ] || continue
  link="$claude/$name"
  want="$repo/$rel"

  if [ ! -e "$want" ]; then
    state="MISSING-IN-REPO"
  elif [ -L "$link" ]; then
    got="$(readlink "$link")"
    if [ "$got" = "$want" ]; then state="ok"; else state="RELINK(->$got)"; fi
  elif [ -e "$link" ]; then
    state="REAL-FILE"
  else
    state="ABSENT"
  fi

  [ "$state" = "ok" ] || status=1
  printf '%-24s -> %-32s %s\n' "$name" "$rel" "$state"
done <<EOF
$entries
EOF

exit "$status"
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
chmod +x plugins/fleet/scripts/link-plan.sh
./plugins/fleet/tests/run-tests.sh
```

Expected: `19 tests, 0 failures`. Paste into the PR.

- [ ] **Step 5: Commit**

```bash
git add plugins/fleet/scripts/link-plan.sh plugins/fleet/tests/link-plan.bats
git commit -m "feat(fleet): read-only link plan reporting drift in ~/.claude"
```

---

### Task 4: `fleet:sync` skill

**Files:**
- Create: `plugins/fleet/skills/sync/SKILL.md`

**Interfaces:**
- Consumes: `link-plan.sh`, `portability-lint.sh` (Tasks 1 and 3).
- Produces: the `/fleet:sync` command. Task 5's doc points readers here for the post-bootstrap path.

- [ ] **Step 1: Write the skill**

Create `plugins/fleet/skills/sync/SKILL.md`. The description is a routing contract — state when to fire and when not to, following the pattern `pm:triage` and `pm:reconcile` already use:

```markdown
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
```

- [ ] **Step 2: Verify the frontmatter parses and the script paths resolve**

```bash
python3 -c "
import re,yaml
t=open('plugins/fleet/skills/sync/SKILL.md').read()
y=yaml.safe_load(re.match(r'^---\n(.*?)\n---\n',t,re.S).group(1))
print('name:',y['name']); print('desc chars:',len(y['description']))
assert y['name']=='sync'
"
for s in link-plan portability-lint; do test -x "plugins/fleet/scripts/$s.sh" && echo "$s.sh ok"; done
```

Expected: `name: sync`, a description length, then both `ok` lines.

- [ ] **Step 3: Verify the dry-run path end to end against the real repo**

Both scripts are read-only, so this is safe to run against `$HOME/.agents`:

```bash
./plugins/fleet/scripts/link-plan.sh "$HOME/.agents"; echo "link-plan exit: $?"
./plugins/fleet/scripts/portability-lint.sh "$HOME/.agents"; echo "lint exit: $?"
```

Expected: four `ok` lines and exit 0 from link-plan; no output and exit 0 from lint. Paste both into the PR — this is the evidence the skill's dry run works on a real repo, not just fixtures.

- [ ] **Step 4: Commit**

```bash
git add plugins/fleet/skills/sync/SKILL.md
git commit -m "feat(fleet): add sync skill"
```

---

### Task 5: `fleet:model-rubric` skill and `Machine_Setup.md`

Both are documentation deliverables that defer to `studio-baseline/Rubric_Setup.md`, so they share a task — a reviewer would accept or reject them together.

**Files:**
- Create: `plugins/fleet/skills/model-rubric/SKILL.md`
- Create: `studio-baseline/Machine_Setup.md`
- Modify: `studio-baseline/README.md`

**Interfaces:**
- Consumes: `rubric-path.sh`, `fetch-model-data.sh` (Task 2); `link-plan.sh`, `portability-lint.sh` (Tasks 1, 3).
- Produces: `/fleet:model-rubric`. Task 6 points `pm` at it.

- [ ] **Step 1: Write the model-rubric skill**

Create `plugins/fleet/skills/model-rubric/SKILL.md`:

```markdown
---
name: model-rubric
description: >-
  Create or refresh this developer's user-global model-routing rubric — the file
  that decides which model does which work (cheap models for bulk/mechanical work,
  the strongest for ambiguous or taste-sensitive work). Lives at
  ${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml, one per
  developer, shared across every repo. Trigger: "set up my model rubric",
  "refresh my rubric", "which model should agents use", "my rubric is stale",
  or /fleet:model-rubric.
  Do NOT use to route a specific task right now (just read the rubric), or to
  configure a project's issue tracker (that's /pm:setup).
effort: medium
allowed-tools: "Bash Read Write Edit WebFetch"
---

# Fleet — Model Rubric

Owns creating and refreshing the per-developer model-routing rubric.

## 1. Check current state

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/rubric-path.sh" --check
```

- `set` → read the file's `reviewed:` stamp. Current (≤14 days, no superseded
  models listed) → say so and stop. Otherwise offer a refresh.
- `unset` → first-time setup.

## 2. Follow the canonical walkthrough

The full procedure lives in `studio-baseline/Rubric_Setup.md` and is deliberately
**not duplicated here** — it must work for developers with no plugin installed, so
that file is the single source of truth. Read it:

```bash
cat "$CLAUDE_PLUGIN_ROOT/../../studio-baseline/Rubric_Setup.md" 2>/dev/null \
  || echo "fetch https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/Rubric_Setup.md"
```

Follow it exactly. Two notes specific to running it from here:

- Where it calls for live model data, use
  `"$CLAUDE_PLUGIN_ROOT/scripts/fetch-model-data.sh"`. Exit code 3 means no
  `ARTIFICIAL_ANALYSIS_API_KEY` — fall back to vendor docs and judgment, and record
  `sources: [judgment]`.
- Where it calls for the target path, use
  `$("$CLAUDE_PLUGIN_ROOT/scripts/rubric-path.sh")`.

**On a refresh, keep the developer's taste scores and `capabilities` unchanged** —
only the Artificial-Analysis-sourced axes (cost, intelligence) change. Do not
re-interview.

## 3. Confirm

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/rubric-path.sh" --check
```

Expected: `set`. Report the path and the `reviewed:` date.
```

- [ ] **Step 2: Write the bootstrap doc**

Create `studio-baseline/Machine_Setup.md`. It must work with no plugin installed, matching `Rubric_Setup.md`'s voice (instructions addressed to an agent helping a developer):

```markdown
# Set up a machine's agent configuration

You are helping a developer bring a machine in line with their personal agent
configuration. This works with **no plugin installed** — you need only a shell and
git. Once done, the `fleet` plugin automates the repeated work.

The personal layer is **one private git repo per developer**, conventionally at
`~/.agents`, linked into `~/.claude`:

```
~/.agents/
├── skills/                    every skill; flat, every machine gets all of them
└── claude/
    ├── CLAUDE.md
    ├── settings.json          permissions, hooks, statusLine, enabledPlugins
    └── statusline-command.sh  referenced by settings.json — they travel together
```

| link | target |
|------|--------|
| `~/.claude/skills` | `~/.agents/skills` |
| `~/.claude/CLAUDE.md` | `~/.agents/claude/CLAUDE.md` |
| `~/.claude/settings.json` | `~/.agents/claude/settings.json` |
| `~/.claude/statusline-command.sh` | `~/.agents/claude/statusline-command.sh` |

## Steps

1. **Ask which case this is.** Two paths, and they differ in what can destroy work:
   - *This developer already has the repo* → clone it (step 2).
   - *This machine has loose config and there is no repo yet* → build the repo from
     it (step 3). Read that step fully before running anything.

2. **Clone and link.** Ask for the repo URL — never guess one.

   ```bash
   git clone <url> "$HOME/.agents"
   ```

   Before replacing anything, look at what is already there:

   ```bash
   ls -la "$HOME/.claude/skills" "$HOME/.claude/CLAUDE.md" "$HOME/.claude/settings.json" 2>/dev/null
   ```

   Any of those that is a **real file or directory** holds this machine's current
   config. Diff it against the repo's copy and ask the developer which wins before
   removing it. Then link:

   ```bash
   ln -s "$HOME/.agents/skills"                        "$HOME/.claude/skills"
   ln -s "$HOME/.agents/claude/CLAUDE.md"              "$HOME/.claude/CLAUDE.md"
   ln -s "$HOME/.agents/claude/settings.json"          "$HOME/.claude/settings.json"
   ln -s "$HOME/.agents/claude/statusline-command.sh"  "$HOME/.claude/statusline-command.sh"
   ```

   Skip to step 5.

3. **Build the repo from loose config.** Order matters — step 3b is destructive if
   run before 3a.

   a. **Back up first.**

      ```bash
      tar czhf "$HOME/agent-config-backup.tgz" -C "$HOME" .claude/skills .claude/CLAUDE.md .claude/settings.json
      ```

   b. **If skills exist in more than one place, repair before consolidating.**
      Diff every duplicated pair and establish which side is clean **before**
      deleting either. **A newer mtime is not evidence of a newer version** — in one
      observed case the newer timestamp was when a blind find-and-replace corrupted
      that copy. Read the diffs.

   c. **Initialise and commit a restore point** before anything moves:

      ```bash
      mkdir -p "$HOME/.agents/claude"
      cd "$HOME/.agents" && git init -b main
      # move skills in, then:
      git add skills && git commit -m "Initial commit: skills tree"
      ```

   d. **Move the config files in**, then apply the two rules in step 4.

   e. **Replace the originals with symlinks** (commands in step 2). Verify skills
      resolve and settings parse **before** deleting anything unrecoverable.

4. **Apply two rules to everything tracked.** Both prevent silent breakage on the
   *next* machine, which is far harder to diagnose than breakage here.

   - **No literal `/Users/<name>` or `/home/<name>` paths.** Use `$HOME`. A
     hardcoded home directory makes a synced config *wrong* elsewhere rather than
     merely absent. Check contents **and symlink targets** — `grep` follows a
     symlink and reads its target, so an absolute link target passes a naive check:

     ```bash
     cd "$HOME/.agents"
     git ls-files -s | grep '^120000 ' | cut -f2- | while read -r l; do
       case "$(readlink "$l")" in /*) echo "absolute symlink: $l";; esac
     done
     git ls-files | while read -r f; do
       [ -L "$f" ] || grep -nHE '/(Users|home)/[A-Za-z0-9._-]+' "$f"
     done
     ```

   - **Guard hooks calling an optional binary**, so a machine without that tool
     degrades quietly instead of erroring every turn:

     ```sh
     [ -x "$HOME/.tool/bin/hook" ] && "$HOME/.tool/bin/hook" args || true
     ```

5. **Keep machine-local things local.** Do not track these:

   | | why |
   |---|---|
   | `~/.claude/settings.local.json` | machine-local by design; holds `skillOverrides` |
   | `~/.claude/mcp.json` | hardcodes app paths that differ per machine |
   | `~/.claude/projects/` | session state and per-project memory |
   | any tool's own store (e.g. `~/.shelby/`) | credentials and per-machine databases |

   Syncing a memory tool's *configuration* does not sync its *memories*.

6. **Push, then verify.**

   ```bash
   cd "$HOME/.agents" && git remote add origin <url> && git push -u origin main
   ```

   **Confirm the remote is private before pushing** — this repo holds personal
   configuration. If the remote fails to authenticate, check `ssh-add -l` for a
   loaded key and `gh auth status` for the configured protocol; do not silently
   switch protocols.

7. **Restart running agent sessions.** They hold the old settings in memory, and one
   of them writing settings can replace a fresh symlink with a real file.

## Afterwards

Install the `fleet` plugin and use `/fleet:sync` for the ongoing work — it does the
link check, pull, and portability lint above on demand, and can push to other
machines. Set up model routing with `/fleet:model-rubric`, or follow
[`Rubric_Setup.md`](https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/Rubric_Setup.md)
if you have no plugins.
```

- [ ] **Step 3: Add the doc to the studio-baseline README**

In `studio-baseline/README.md`, add a bullet to the existing list, after the `Rubric_Setup.md` line:

```markdown
- `Machine_Setup.md` — how any agent brings a machine in line with a developer's private agent-config repo, no plugin needed.
```

- [ ] **Step 4: Verify**

```bash
python3 -c "
import re,yaml
t=open('plugins/fleet/skills/model-rubric/SKILL.md').read()
y=yaml.safe_load(re.match(r'^---\n(.*?)\n---\n',t,re.S).group(1))
print('name:',y['name'],'| desc chars:',len(y['description']))
"
grep -c "Machine_Setup" studio-baseline/README.md
./plugins/fleet/tests/run-tests.sh
```

Expected: `name: model-rubric`, `1`, and `19 tests, 0 failures`.

Then confirm the doc's own lint snippet works, since it is copy-pasted advice:

```bash
cd "$HOME/.agents" && git ls-files -s | grep '^120000 ' | cut -f2- | wc -l
```

Expected: `0` — no tracked symlinks in the reference repo.

- [ ] **Step 5: Commit**

```bash
git add plugins/fleet/skills/model-rubric/SKILL.md studio-baseline/Machine_Setup.md studio-baseline/README.md
git commit -m "feat(fleet): add model-rubric skill and zero-plugin Machine_Setup doc"
```

---

### Task 6: Make `pm` a pure rubric consumer

Must land **with or after** Task 2, or both plugins offer to create the rubric.

**Files:**
- Modify: `plugins/pm/skills/reconcile/SKILL.md` (remove Phase 5.5 and its two references)
- Modify: `plugins/pm/skills/setup/SKILL.md` (Batch 5, Phase 4.5, summary, config note)
- Modify: `plugins/pm/references/model-orchestration.md`
- Modify: `plugins/pm/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

**Interfaces:**
- Consumes: `fleet:model-rubric` (Task 5) as the referral target.
- Produces: nothing new. `pm` reads the rubric at the constant path and never resolves it via a script.

- [ ] **Step 1: Remove Phase 5.5 from reconcile**

Delete the whole phase — heading through its trailing `---` — leaving the separator above it:

```bash
python3 - <<'PY'
lines = open('plugins/pm/skills/reconcile/SKILL.md').read().split('\n')
start = next(i for i,l in enumerate(lines) if l.startswith('## Phase 5.5:'))
end   = next(i for i,l in enumerate(lines[start:], start) if l == '---')
assert lines[start].startswith('## Phase 5.5'), lines[start]
del lines[start:end+2]           # phase body, its --- , and the blank after
open('plugins/pm/skills/reconcile/SKILL.md','w').write('\n'.join(lines))
PY
```

Then remove its two remaining references:

- The ground rule near line 34 — delete the whole bullet:
  `- **Advisory-only where noted.** The model-rubric freshness check (Phase 5.5) never edits the rubric — it flags staleness and defers the refresh to `/pm:setup`.`
- The summary line in the Phase 7 report block:
  `Model rubric:            {current (reviewed {date}) | STALE — run /pm:setup | not found}`

- [ ] **Step 2: Point `pm:setup` at fleet**

In `plugins/pm/skills/setup/SKILL.md`:

- **Frontmatter (line ~7):** drop `and a model-selection rubric that the dev/sprint skills route sub-agents by` from the description.
- **Batch 5 (~141-151):** replace the body with a check that never creates. Note the inline path — `pm` keeps no copy of `rubric-path.sh`:

```markdown
### Batch 5: Model-Routing Rubric

`pm:sprint-dev` and `pm:dev-task` route each sub-agent to a model by task altitude. That routing reads a **model-selection rubric** from this developer's user-global store — one file per dev, shared across every repo:

```bash
ls "${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml" 2>/dev/null && echo set || echo unset
```

- `set` → `"Found your model rubric — sprint-dev and dev-task will route by it."`
- `unset` → `"No model rubric yet. Run /fleet:model-rubric to create one, or follow studio-baseline/Rubric_Setup.md if you don't have the fleet plugin."`

**pm does not create or refresh the rubric.** That is `fleet:model-rubric`'s job.
```

- **Phase 4.5 (~344-355):** replace the whole phase with a referral, keeping only the legacy migration (which is genuinely pm's, since it edits a repo's `AGENTS.md`):

```markdown
## Phase 4.5: Model-Selection Rubric (referral)

The rubric is per developer and user-global at `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml` — never written into the repo. pm consumes it; it does not own it.

Using Batch 5's result:

- `set` → nothing to do.
- `unset` → tell the user: `"Run /fleet:model-rubric to set up model routing, or follow studio-baseline/Rubric_Setup.md if you don't have the fleet plugin installed."` Do not walk them through it here.

**Migrate any legacy in-repo rubric.** If a prior setup wrote a "Picking the right models" section into this repo's `AGENTS.md`/`CLAUDE.md`, move its scores into the user-global rubric (if the dev confirms they're theirs) and delete that section from the repo file. Leave the Phase 4.4 baseline reminder in place.
```

- **Summary line (~483):** change to
  `Model rubric: {found at user-global path | not set — run /fleet:model-rubric}`
- **Config note (~556):** replace the `rubric-path.sh` reference with the literal path `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`.

- [ ] **Step 3: Update the orchestration reference**

In `plugins/pm/references/model-orchestration.md` line 3, replace `and Phase 4.5 helps each developer create their own user-global rubric` with `and each developer creates their own user-global rubric via `/fleet:model-rubric` (or `studio-baseline/Rubric_Setup.md` with no plugin)`.

- [ ] **Step 4: Verify no dangling references remain**

```bash
grep -rn "rubric-path.sh\|fetch-model-data.sh" plugins/pm/ || echo "no dangling script refs"
grep -rn "Phase 5.5" plugins/pm/ || echo "no dangling Phase 5.5 refs"
grep -rn "CLAUDE_PLUGIN_ROOT/scripts/rubric" plugins/pm/ || echo "clean"
```

Expected: all three print their "clean" message. Any hit is a broken reference — `pm` no longer ships those scripts.

- [ ] **Step 5: Bump versions and run both suites**

`pm` 0.15.2 → 0.16.0 (behavior removed, not just fixed) in **both** `plugins/pm/.claude-plugin/plugin.json` and the `pm` entry in `.claude-plugin/marketplace.json`. A past rebase auto-merged that second file to a stale version without conflicting — check both by reading them back:

```bash
python3 -c "
import json
a=json.load(open('plugins/pm/.claude-plugin/plugin.json'))['version']
b=[p['version'] for p in json.load(open('.claude-plugin/marketplace.json'))['plugins'] if p['name']=='pm'][0]
print('plugin.json',a,'| marketplace',b); assert a==b=='0.16.0', 'version mismatch'
"
./plugins/pm/tests/run-tests.sh
./plugins/fleet/tests/run-tests.sh
```

Expected: the assert passes, pm reports `32 tests, 0 failures`, fleet `19 tests, 0 failures`.

Then verify the trimmed skill still parses and shrank:

```bash
python3 -c "
import re,yaml
t=open('plugins/pm/skills/reconcile/SKILL.md').read()
yaml.safe_load(re.match(r'^---\n(.*?)\n---\n',t,re.S).group(1)); print('reconcile frontmatter ok')"
wc -l plugins/pm/skills/reconcile/SKILL.md
```

Expected: `reconcile frontmatter ok`, and roughly 372 lines (384 minus the phase).

- [ ] **Step 6: Commit**

```bash
git add plugins/pm/skills/reconcile/SKILL.md plugins/pm/skills/setup/SKILL.md plugins/pm/references/model-orchestration.md plugins/pm/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "refactor(pm)!: hand model-rubric ownership to the fleet plugin"
```

---

## Opening the PR

One PR for the whole plan — the tasks are one coherent change and Task 6 cannot ship alone. Confirm the branch holds only your commits first (house rule):

```bash
git log --oneline origin/main..HEAD
./plugins/fleet/tests/run-tests.sh
./plugins/pm/tests/run-tests.sh
```

Paste both suites' output into `## Testing`, plus the real-repo dry run from Task 4 Step 3. In `## Why`, lead with the bootstrap paradox (why a fetchable doc exists alongside the plugin) and the lint bug (why the lint checks symlink targets) — those are the two decisions a reviewer is most likely to question.

Then clean up:

```bash
git worktree remove ../skills-n-stuff-fleet
```
