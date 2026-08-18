# Codex Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Codex under the same personal-config sync as Claude Code: Codex's global instructions (`~/.codex/AGENTS.md`) become a tracked, *derived* file rendered from House Style + CLAUDE.md's discipline block, verified by `machine:sync` as an 8th tracked entry; and Codex's skills come from the same manifest-managed store as Claude's instead of stale one-off copies.

**Architecture:** One new script, `render-codex-agents.sh`, composes `codex/AGENTS.md` in the agents repo from three existing sources (House Style body, CLAUDE.md's `## Engineering discipline` section, CLAUDE.md's Shelby block) plus two CLAUDE.md rules that apply to a worker agent (no hallucination, file naming) — so House Style stays the single thing you iterate on. `link-plan.sh` gains a third root, `codex` (`${CODEX_HOME:-$HOME/.codex}`), and the entry `codex|AGENTS.md|codex/AGENTS.md`. `machine:sync` gains Phase 1.5 (render, before commit) and a `Derived:` report line, and Phase 2.6's `npx skills add` targets `-a claude-code,codex` so Codex gets per-skill symlinks into the shared `~/.agents/skills` store. **Policy change, stated:** the sync skill previously said it must never touch `~/.codex`; from now on it manages exactly two things there — the `AGENTS.md` symlink and per-skill symlinks — and nothing else (`config.toml`, `hooks.json`, `.system`, Codex-bundled skills stay Codex's).

**Tech Stack:** bash 3.2-portable scripts (`plugins/machine/scripts/`), bats tests, Markdown skill/doc files, `npx skills` CLI, `codex` CLI for the live check.

## Global Constraints

- **Repo A:** `~/Projects/skills-n-stuff`, branch `codex-sync` from `main` (created in Task 1 Step 1). **Repo B:** `~/.agents` (personal config, `main`; edits there happen in Task 4 only, committed directly — the file is generated, not hand-written).
- **Commit messages** end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Scripts:** `#!/usr/bin/env bash`, `set -euo pipefail`, bash 3.2 portable (no arrays, no `[[ ]]` needed, no `mapfile`), no python for this one — pure `awk`/`sed`/`grep`. Tests in `plugins/machine/tests/*.bats`; `plugins/machine/tests/run-tests.sh` must stay green (75 today, more after Task 1/2).
- **`render-codex-agents.sh` contract** (Task 1 defines it; Tasks 3–4 consume it): `render-codex-agents.sh REPO` reads `REPO/claude/output-styles/House Style.md` and `REPO/claude/CLAUDE.md`, writes `REPO/codex/AGENTS.md`, prints exactly one line `RENDER_STATE=unchanged` | `RENDER_STATE=regenerated` | `RENDER_STATE=failed: <reason>`, exit 0 / 0 / 3 respectively (2 = usage). Never writes when a source or required section is missing.
- **Tracked-entry name (exact):** `AGENTS.md -> codex/AGENTS.md`, root `codex` = `${CODEX_HOME:-$HOME/.codex}`. Eight entries total after this plan.
- **`npx skills` agent id for Codex is `codex`** (validated: `npx skills add … -a codex -l` lists without an agent error; the CLI resolves `CODEX_HOME`/`~/.codex/skills`). Combined form: `-a claude-code,codex`. Default behaviour symlinks per-agent dirs into `~/.agents/skills`; `--copy` is what produced today's stale copies — never pass it.
- **What Codex gets and doesn't:** House Style voice + boundaries + aliases, Engineering discipline, Rules "No hallucination" and "File naming", the Shelby block. **Not** the Claude routing rules (skill precedence, one reviewer, delegate) — Codex is the worker, it does not dispatch by our rubric.
- **Never** edit `~/.codex/config.toml`, `~/.codex/hooks.json`, `~/.codex/skills/.system`, or Codex-bundled skill dirs.
- **Machine plugin bump:** `0.4.1` → `0.5.0` in `plugins/machine/.claude-plugin/plugin.json` and its `.claude-plugin/marketplace.json` entry (new tracked entry + new script = feature). No other plugin's version changes.
- **Report-line style** in sync Phase 4: brace-alternative, `{` at column 15, continuation indented 15 spaces.

---

## File Structure

**Repo A**
- `plugins/machine/scripts/render-codex-agents.sh` — **new**, Task 1. Composes `codex/AGENTS.md`.
- `plugins/machine/tests/render-codex-agents.bats` — **new**, Task 1.
- `plugins/machine/scripts/link-plan.sh` — Task 2: third root + 8th entry.
- `plugins/machine/tests/link-plan.bats` — Task 2: fixture + counts 7→8, `CODEX_HOME` export.
- `studio-baseline/Machine_Setup.md` — Task 2: entries blocks 7→8 rows, every `case "$root"` block gains `codex)`, tree + table + root-explanation prose, "seven"→"eight".
- `plugins/machine/skills/sync/SKILL.md` — Task 2: "seven tracked"→"eight"; Phase 1.5 render; Phase 4 `Derived:` line; dry-run note. Task 3: Phase 2.6 `-a claude-code,codex` + policy prose.
- `plugins/machine/skills/model-rubric/SKILL.md` — Task 2: "seven"→"eight".
- `plugins/machine/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — Task 3: machine 0.5.0.
- `docs/superpowers/plans/2026-08-18-codex-sync.md` — this plan; committed in Task 3.

**Repo B (`~/.agents`)** — Task 4 only
- `codex/AGENTS.md` — **new, generated** by the script.

**This machine** — Task 4 only
- `~/.codex/AGENTS.md` — old real file backed up to `~/.codex/AGENTS.md.bak-2026-08-18`, replaced by symlink → `~/.agents/codex/AGENTS.md`.
- `~/.codex/skills/` — 13 stale Jul-14 copies of pm/product-pulse skills removed (list in Task 4); manifest skills re-registered for codex as symlinks.

---

### Task 1: `render-codex-agents.sh` (TDD)

**Files:**
- Create: `plugins/machine/scripts/render-codex-agents.sh`
- Test: `plugins/machine/tests/render-codex-agents.bats`

**Interfaces:**
- Produces: the contract in Global Constraints. Output file layout (exact order):
  1. one HTML comment header line: `<!-- GENERATED by machine:sync (render-codex-agents.sh) from claude/output-styles/House Style.md and claude/CLAUDE.md — edit those; this file is overwritten on every sync. -->`
  2. blank line, `# Rules`, blank line, then the two extracted rule lines renumbered `1.` and `2.` (source lines are `^[0-9]+\. \*\*No hallucination\*\*…` and `^[0-9]+\. \*\*File naming\*\*…` in CLAUDE.md, any original number).
  3. blank line, then CLAUDE.md's `## Engineering discipline` section: from that heading line up to (not including) the `<!-- shelby:bootstrap start -->` line, trailing blank lines trimmed to one.
  4. blank line, then the House Style body: everything after the closing `---` of the YAML frontmatter (frontmatter = from the first line `---` to the next line `---`), leading blank lines stripped.
  5. blank line, then the Shelby block: from `<!-- shelby:bootstrap start -->` through `<!-- shelby:bootstrap end -->` inclusive, verbatim.
  6. final newline.
- Failure conditions (exit 3, `RENDER_STATE=failed: <reason>`, no write): House Style file missing; CLAUDE.md missing; `No hallucination` rule line not found; `File naming` rule line not found; `## Engineering discipline` heading not found; shelby start or end marker not found; frontmatter not closed.

- [ ] **Step 1: Create the branch**

```bash
cd ~/Projects/skills-n-stuff && git checkout main && git pull --rebase && git checkout -b codex-sync
```

- [ ] **Step 2: Write the failing tests**

Create `plugins/machine/tests/render-codex-agents.bats`:

```bash
#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/render-codex-agents.sh"
  REPO="${BATS_TEST_TMPDIR}/agents"
  mkdir -p "$REPO/claude/output-styles"
  cat > "$REPO/claude/output-styles/House Style.md" << 'EOF'
---
name: House Style
description: test style
keep-coding-instructions: true
---

# Clear, Concise, Actionable Communication

## Purpose

Say less.
EOF
  cat > "$REPO/claude/CLAUDE.md" << 'EOF'
# Rules

1. **No hallucination** — If you don't know, say so.
2. **Skill precedence** — claude-only rule.
3. **One reviewer per change** — claude-only rule.
4. **Delegate explicitly** — claude-only rule.
5. **File naming** — Title Case with spaces.

## Engineering discipline

Applies to every agent. Stop at the first rung that holds:

1. Does this need to exist at all?

- Bug fix = root cause.

<!-- shelby:bootstrap start -->
## Shelby memory
Use Shelby.
<!-- shelby:bootstrap end -->
EOF
}

@test "renders header, two renumbered rules, discipline, style body, shelby block — in that order" {
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "RENDER_STATE=regenerated" ]
  out="$REPO/codex/AGENTS.md"
  [ -f "$out" ]
  head -1 "$out" | grep -q '^<!-- GENERATED by machine:sync (render-codex-agents.sh)'
  grep -qE '^1\. \*\*No hallucination\*\*' "$out"
  grep -qE '^2\. \*\*File naming\*\*' "$out"
  [ "$(grep -c 'Skill precedence' "$out")" -eq 0 ]
  [ "$(grep -c 'Delegate explicitly' "$out")" -eq 0 ]
  grep -q '^## Engineering discipline$' "$out"
  grep -q '^# Clear, Concise, Actionable Communication$' "$out"
  [ "$(grep -c '^keep-coding-instructions' "$out")" -eq 0 ]
  [ "$(grep -c '^name: House Style' "$out")" -eq 0 ]
  grep -q '<!-- shelby:bootstrap start -->' "$out"
  grep -q '<!-- shelby:bootstrap end -->' "$out"
  # order: rules < discipline < style < shelby
  r=$(grep -n '^# Rules$' "$out" | cut -d: -f1)
  d=$(grep -n '^## Engineering discipline$' "$out" | cut -d: -f1)
  s=$(grep -n '^# Clear, Concise' "$out" | cut -d: -f1)
  m=$(grep -n 'shelby:bootstrap start' "$out" | cut -d: -f1)
  [ "$r" -lt "$d" ] && [ "$d" -lt "$s" ] && [ "$s" -lt "$m" ]
}

@test "second run with no source change reports unchanged and leaves the file byte-identical" {
  "$SCRIPT" "$REPO" > /dev/null
  cp "$REPO/codex/AGENTS.md" "${BATS_TEST_TMPDIR}/first.md"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "RENDER_STATE=unchanged" ]
  cmp -s "$REPO/codex/AGENTS.md" "${BATS_TEST_TMPDIR}/first.md"
}

@test "a source edit regenerates" {
  "$SCRIPT" "$REPO" > /dev/null
  printf '\nSay even less.\n' >> "$REPO/claude/output-styles/House Style.md"
  run "$SCRIPT" "$REPO"
  [ "$output" = "RENDER_STATE=regenerated" ]
  grep -q 'Say even less.' "$REPO/codex/AGENTS.md"
}

@test "missing discipline heading fails with exit 3 and writes nothing" {
  sed -i.bak '/^## Engineering discipline$/d' "$REPO/claude/CLAUDE.md"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 3 ]
  [[ "$output" == RENDER_STATE=failed:* ]]
  [ ! -e "$REPO/codex/AGENTS.md" ]
}

@test "missing House Style file fails with exit 3" {
  rm "$REPO/claude/output-styles/House Style.md"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 3 ]
  [[ "$output" == *"House Style"* ]]
}

@test "usage error exits 2" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}
```

- [ ] **Step 3: Run tests — expect all 6 to fail (script absent)**

```bash
cd ~/Projects/skills-n-stuff/plugins/machine/tests && bats render-codex-agents.bats
```

- [ ] **Step 4: Write the script**

Create `plugins/machine/scripts/render-codex-agents.sh` and `chmod +x`:

```bash
#!/usr/bin/env bash
# Render the personal repo's codex/AGENTS.md from the Claude-side sources, so
# House Style stays the one file you iterate on and Codex follows.
#
#   render-codex-agents.sh REPO
#
# Reads  REPO/claude/output-styles/House Style.md   (body, frontmatter stripped)
#        REPO/claude/CLAUDE.md                       (two rules, the
#                                                    "## Engineering discipline"
#                                                    section, the Shelby block)
# Writes REPO/codex/AGENTS.md  — only if the rendered content differs.
# Prints one line: RENDER_STATE=unchanged | regenerated | failed: <reason>
# Exit 0 for unchanged/regenerated, 3 for failed (nothing written), 2 usage.
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: render-codex-agents.sh REPO" >&2; exit 2; }
repo="${1%/}"
style="$repo/claude/output-styles/House Style.md"
claude_md="$repo/claude/CLAUDE.md"
out="$repo/codex/AGENTS.md"

fail() { echo "RENDER_STATE=failed: $1"; exit 3; }

[ -f "$style" ]     || fail "missing $style"
[ -f "$claude_md" ] || fail "missing $claude_md"

# --- pieces from CLAUDE.md -------------------------------------------------
rule_halluc="$(grep -E '^[0-9]+\. \*\*No hallucination\*\*' "$claude_md" | head -1 || true)"
rule_naming="$(grep -E '^[0-9]+\. \*\*File naming\*\*' "$claude_md" | head -1 || true)"
[ -n "$rule_halluc" ] || fail "no 'No hallucination' rule in $claude_md"
[ -n "$rule_naming" ] || fail "no 'File naming' rule in $claude_md"
rule_halluc="$(printf '%s' "$rule_halluc" | sed -E 's/^[0-9]+\./1./')"
rule_naming="$(printf '%s' "$rule_naming" | sed -E 's/^[0-9]+\./2./')"

grep -q '^## Engineering discipline$' "$claude_md" || fail "no '## Engineering discipline' section in $claude_md"
grep -q '<!-- shelby:bootstrap start -->' "$claude_md" || fail "no shelby:bootstrap start marker in $claude_md"
grep -q '<!-- shelby:bootstrap end -->' "$claude_md"   || fail "no shelby:bootstrap end marker in $claude_md"

# discipline: heading up to (not incl.) shelby start; trim trailing blank lines
discipline="$(awk '
  /^## Engineering discipline$/ { on=1 }
  /<!-- shelby:bootstrap start -->/ { on=0 }
  on { print }
' "$claude_md" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"

shelby="$(awk '
  /<!-- shelby:bootstrap start -->/ { on=1 }
  on { print }
  /<!-- shelby:bootstrap end -->/ { on=0 }
' "$claude_md")"

# --- House Style body (frontmatter stripped) -------------------------------
first="$(head -1 "$style")"
[ "$first" = "---" ] || fail "House Style.md does not start with YAML frontmatter"
# body = after the second '---' line; then drop leading blank lines
body="$(awk 'NR==1{next} !seen && /^---$/ {seen=1; next} seen {print}' "$style" | sed '/./,$!d')"
[ -n "$body" ] || fail "House Style.md frontmatter never closes (no second ---)"

# --- compose ---------------------------------------------------------------
rendered="$(printf '%s\n\n%s\n\n%s\n%s\n\n%s\n\n%s\n\n%s\n' \
  '<!-- GENERATED by machine:sync (render-codex-agents.sh) from claude/output-styles/House Style.md and claude/CLAUDE.md — edit those; this file is overwritten on every sync. -->' \
  '# Rules' \
  "$rule_halluc" \
  "$rule_naming" \
  "$discipline" \
  "$body" \
  "$shelby")"

if [ -f "$out" ] && [ "$(cat "$out")" = "$rendered" ]; then
  echo "RENDER_STATE=unchanged"
  exit 0
fi
mkdir -p "$(dirname "$out")"
printf '%s\n' "$rendered" > "$out"
echo "RENDER_STATE=regenerated"
```

- [ ] **Step 5: Run tests — expect 6/6**

```bash
cd ~/Projects/skills-n-stuff/plugins/machine/tests && bats render-codex-agents.bats
```

- [ ] **Step 6: Dry-render against the real repo into a scratch dir (do NOT write into ~/.agents yet)**

```bash
cd ~/Projects/skills-n-stuff
S=$(mktemp -d); mkdir -p "$S/claude"; cp -R ~/.agents/claude/output-styles "$S/claude/"; cp ~/.agents/claude/CLAUDE.md "$S/claude/"
plugins/machine/scripts/render-codex-agents.sh "$S"; echo "exit $?"; wc -l "$S/codex/AGENTS.md"; sed -n '1,8p' "$S/codex/AGENTS.md"; grep -c '^## Engineering discipline$\|^# Clear, Concise\|shelby:bootstrap start' "$S/codex/AGENTS.md"
```
Expected: `RENDER_STATE=regenerated`, exit 0, header line first, `# Rules` then `1. **No hallucination**` and `2. **File naming**`, and the last count is `3`.

- [ ] **Step 7: Commit**

```bash
cd ~/Projects/skills-n-stuff
git add plugins/machine/scripts/render-codex-agents.sh plugins/machine/tests/render-codex-agents.bats
git commit -F - << 'EOF'
machine: add render-codex-agents.sh — derive codex/AGENTS.md from House Style + CLAUDE.md

Composes Codex's global instructions from the Claude-side sources (House
Style body, the Engineering discipline section, the two worker-relevant rules,
the Shelby block) so there is one house style to iterate on. Idempotent;
fails loudly (exit 3, nothing written) when a source or section is missing.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 2: Eighth tracked entry (`codex` root) across link-plan, tests, docs, and the sync skill

**Files:**
- Modify: `plugins/machine/scripts/link-plan.sh` (roots comment ~line 12, `entries` ~13–20, `case "$root"` ~46–50; add `codex=` variable after `config=` at ~line 9)
- Modify: `plugins/machine/tests/link-plan.bats` (setup, link_all, two count assertions)
- Modify: `studio-baseline/Machine_Setup.md` (tree ~12–20, table ~22–30, "seven"→"eight" at 47/52/72, root-explanation ~64–68, all seven `entries=` blocks, all six `case "$root"` blocks at ~92/149/249/289/370/401)
- Modify: `plugins/machine/skills/sync/SKILL.md` (line 124 "seven tracked entries"; new `## Phase 1.5: Render derived files` before `## Phase 2: Commit, pull, push`; Phase 4 report `Derived:` line after `Links:`; Dry run section note)
- Modify: `plugins/machine/skills/model-rubric/SKILL.md` line 51 "seven"→"eight"

**Interfaces:**
- Consumes: Task 1's script and `RENDER_STATE` contract.
- Produces: entry `AGENTS.md -> codex/AGENTS.md` (root `codex`); env `CODEX_HOME` honoured; report line `Derived:`.

- [ ] **Step 1: link-plan.sh**

After `config="${XDG_CONFIG_HOME:-$HOME/.config}"` add:
```bash
codex="${CODEX_HOME:-$HOME/.codex}"
```
Change the roots comment to:
```bash
# roots: claude = $CLAUDE_CONFIG_DIR (default ~/.claude); config = $XDG_CONFIG_HOME (default ~/.config);
#        codex = $CODEX_HOME (default ~/.codex)
```
Append to the `entries` string (after the `config|studio-moser|config/studio-moser` line, keeping the closing quote on the new last line):
```
codex|AGENTS.md|codex/AGENTS.md
```
In the `case "$root"` add, before the `*)` line:
```bash
    codex) base="$codex" ;;
```

- [ ] **Step 2: link-plan.bats**

In `setup()`: add `export CODEX_HOME="${BATS_TEST_TMPDIR}/codex"` and `mkdir -p "$REPO/codex" "$CODEX_HOME"` and `: > "$REPO/codex/AGENTS.md"`. In `link_all()`: add `ln -s "$REPO/codex/AGENTS.md" "$CODEX_HOME/AGENTS.md"`. Rename the test `all seven links correct` → `all eight links correct` and change both `-eq 7` count assertions to `-eq 8`. Add one test:
```bash
@test "codex-root entry: missing AGENTS.md link reported ABSENT" {
  link_all
  rm "$CODEX_HOME/AGENTS.md"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE '^AGENTS\.md +-> +codex/AGENTS\.md +ABSENT$'
}
```

- [ ] **Step 3: Machine_Setup.md**

(a) Tree: after the `└── config/` block's `studio-moser/` line, the tree currently ends. Add a `codex/` sibling of `claude/` and `config/`. Concretely, change
```
└── config/
    └── studio-moser/          model-rubric.yml and other cross-machine config
```
to
```
├── config/
│   └── studio-moser/          model-rubric.yml and other cross-machine config
└── codex/
    └── AGENTS.md              GENERATED by machine:sync from House Style + CLAUDE.md — Codex's global instructions
```
(b) Table: add after the `studio-moser` row:
```
| `${CODEX_HOME:-$HOME/.codex}/AGENTS.md` | `~/.agents/codex/AGENTS.md` |
```
(c) Prose: "The seven rows above" → "The eight rows above"; `"the seven"` → `"the eight"`; "these seven entries" → "these eight entries". In the root-explanation paragraph, change `root` is `claude` (`~/.claude`) for every entry except `studio-moser`, which is `config` (`${XDG_CONFIG_HOME:-$HOME/.config}`). to: `root` is `claude` (`~/.claude`) for every entry except `studio-moser`, which is `config` (`${XDG_CONFIG_HOME:-$HOME/.config}`), and `AGENTS.md`, which is `codex` (`${CODEX_HOME:-$HOME/.codex}` — Codex's global instructions file; the directory may not exist yet on a fresh machine, `mkdir -p` it before linking).
(d) Every `entries="…"` block (seven copies): append the row `AGENTS.md|codex/AGENTS.md|file|codex` as the new last line, matching that block's indentation, and move the closing `"` onto it. Use a python one-off if you like; verify with `grep -c 'AGENTS.md|codex/AGENTS.md|file|codex' studio-baseline/Machine_Setup.md` = 7 and `awk` that no `entries=` block is followed by a blank line.
(e) Every `case "$root"` block (six): add a line after the `config)` line: `codex) base="${CODEX_HOME:-$HOME/.codex}" ;;` — and where the `config)` line carries `; mkdir -p "$base"` (line ~249), the `codex)` line carries it too: `codex) base="${CODEX_HOME:-$HOME/.codex}"; mkdir -p "$base" ;;`. Match indentation.

- [ ] **Step 4: sync/SKILL.md**

(a) Line 124: `among the seven tracked entries` → `among the eight tracked entries`.
(b) Directly before `## Phase 2: Commit, pull, push`, insert:
````markdown
## Phase 1.5: Render derived files

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
machine="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/machine/*/ 2>/dev/null | sort -V | tail -1)}"; machine="${machine%/}"
"$machine/scripts/render-codex-agents.sh" "$repo"
```

`codex/AGENTS.md` is Codex's global instructions and is **generated** from the
Claude-side sources (`claude/output-styles/House Style.md` and `claude/CLAUDE.md`)
so House Style stays the one file you edit. This runs before Phase 2 so a
regenerated file is committed with everything else. `RENDER_STATE=unchanged` and
`regenerated` are both fine; `RENDER_STATE=failed: <reason>` (exit 3) means a
source or a required section is missing — nothing was written; carry the reason
into the report. Never hand-edit `codex/AGENTS.md`; the next sync overwrites it.

---

````
(c) Phase 4 report: after the `  Links:` line add
```
  Derived:    {codex/AGENTS.md unchanged | codex/AGENTS.md regenerated | failed: <reason>}
```
(d) Dry run section: in the "Skip everything else, explicitly:" list add a bullet: `- **Phase 1.5** (render `codex/AGENTS.md`) — a write; report `Derived: [skipped in dry run]`.`

- [ ] **Step 5: model-rubric/SKILL.md line 51**: `one of the seven tracked entries` → `one of the eight tracked entries`.

- [ ] **Step 6: Verify**

```bash
cd ~/Projects/skills-n-stuff
plugins/machine/tests/run-tests.sh 2>&1 | grep -c '^ok'; plugins/machine/tests/run-tests.sh 2>&1 | grep -c '^not ok'
grep -c 'AGENTS.md|codex/AGENTS.md|file|codex' studio-baseline/Machine_Setup.md      # 7
grep -c 'codex) base=' studio-baseline/Machine_Setup.md                                # 6
grep -c 'seven' studio-baseline/Machine_Setup.md plugins/machine/skills/sync/SKILL.md plugins/machine/skills/model-rubric/SKILL.md   # 0 0 0
grep -n '^## Phase 1.5: Render derived files$\|^  Derived:' plugins/machine/skills/sync/SKILL.md
CODEX_HOME=$(mktemp -d) bash plugins/machine/scripts/link-plan.sh ~/.agents | tail -1   # AGENTS.md -> codex/AGENTS.md MISSING-IN-REPO (repo has no codex/ yet — expected until Task 4)
```
Expected: all `ok` (82 = 75 + 6 render + 1 link-plan), 0 `not ok`; 7; 6; 0/0/0; two line numbers; last line `MISSING-IN-REPO`.

- [ ] **Step 7: Commit**

```bash
cd ~/Projects/skills-n-stuff
git add plugins/machine/scripts/link-plan.sh plugins/machine/tests/link-plan.bats studio-baseline/Machine_Setup.md plugins/machine/skills/sync/SKILL.md plugins/machine/skills/model-rubric/SKILL.md
git commit -F - << 'EOF'
machine: track ~/.codex/AGENTS.md as the eighth synced entry; sync renders it

link-plan.sh gains a codex root (${CODEX_HOME:-$HOME/.codex}) and the entry
codex|AGENTS.md|codex/AGENTS.md; bats + Machine_Setup blocks/table/tree/case
blocks follow. machine:sync gains Phase 1.5 (render-codex-agents.sh before
commit) and a Derived: report line.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 3: Codex skills via the manifest (`-a claude-code,codex`), policy prose, version bump

**Files:**
- Modify: `plugins/machine/skills/sync/SKILL.md` — Phase 2.6 step 2 install command (line ~719) and the paragraph beneath it (~721–729)
- Modify: `plugins/machine/.claude-plugin/plugin.json` (`0.4.1` → `0.5.0`), `.claude-plugin/marketplace.json` (machine → `0.5.0`)
- Add: `docs/superpowers/plans/2026-08-18-codex-sync.md` (this plan)

- [ ] **Step 1: Phase 2.6 command + prose**

Change
```
npx skills add "<source>" -s "<name>" -a claude-code -g -y
```
to
```
npx skills add "<source>" -s "<name>" -a claude-code,codex -g -y
```
Replace the paragraph that begins `` `-a claude-code` matters, and the value is exact `` and ends `Use `-a claude-code`, exactly.` with:
```markdown
`-a claude-code,codex` matters, and the values are exact — verified against the
installed CLI: without an explicit agent, `npx skills add` registers the skill
with every agent it detects, writing into `~/.cursor`, `~/.pi`, and others that
manage their own registrations. This plugin manages exactly two agents' skill
registrations — Claude Code and Codex — and both read the same store,
`~/.agents/skills`, through per-skill symlinks the CLI creates (never pass
`--copy`; copies go stale). `-a claude` (no `-code`) is **not** a valid agent
name — it prints `Invalid agents: claude`, exits 1, installs nothing, and would
let step 3 regenerate a 0-byte manifest. Use `-a claude-code,codex`, exactly.
Inside `~/.codex` this plugin touches only `skills/<name>` symlinks and the
`AGENTS.md` link (Phase 1); `config.toml`, `hooks.json`, `skills/.system`, and
Codex-bundled skills are Codex's own.
```

Also change the Phase 2.6 removal command (a few paragraphs later) from `npx skills remove "<name>" -a claude-code -g -y` to `npx skills remove "<name>" -a claude-code,codex -g -y` — removals must unregister both agents or Codex symlinks linger.

- [ ] **Step 2: Bump machine to 0.5.0**

```bash
cd ~/Projects/skills-n-stuff
python3 - << 'PY'
p="plugins/machine/.claude-plugin/plugin.json"; s=open(p).read(); assert '"version": "0.4.1"' in s
open(p,"w").write(s.replace('"version": "0.4.1"','"version": "0.5.0"',1))
m=".claude-plugin/marketplace.json"; s=open(m).read()
i=s.index('"name": "machine"'); j=s.index('"version": "0.4.1"', i)
open(m,"w").write(s[:j]+'"version": "0.5.0"'+s[j+len('"version": "0.4.1"'):]); print("machine 0.5.0")
PY
python3 -c "import json;print({x['name']:x.get('version') for x in json.load(open('.claude-plugin/marketplace.json'))['plugins'] if x['name'] in ('machine','pm')})"
```
Expected `machine 0.5.0`; `{'machine': '0.5.0', 'pm': '0.17.1'}`.

- [ ] **Step 3: Verify, commit, push**

```bash
cd ~/Projects/skills-n-stuff
grep -c 'a claude-code,codex' plugins/machine/skills/sync/SKILL.md     # 4 (add + remove commands, prose twice)
grep -c 'a claude-code -g' plugins/machine/skills/sync/SKILL.md         # 0
plugins/machine/tests/run-tests.sh 2>&1 | grep -c '^not ok'            # 0
git add plugins/machine/skills/sync/SKILL.md plugins/machine/.claude-plugin/plugin.json .claude-plugin/marketplace.json docs/superpowers/plans/2026-08-18-codex-sync.md
git commit -F - << 'EOF'
machine 0.5.0: Codex under sync — AGENTS.md rendered + tracked, skills registered for codex

Phase 2.6 registers manifest skills for both claude-code and codex (per-skill
symlinks into ~/.agents/skills). States the policy change: this plugin now
manages exactly the AGENTS.md link and skills/<name> symlinks in ~/.codex,
nothing else there. Adds the codex-sync plan.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
git push -u origin codex-sync
```

---

### Task 4: Apply to this machine (Repo B + `~/.codex`) and prove Codex loads it

Controller-run verification and one-time local migration. Nothing here is a Repo A change.

- [ ] **Step 1: Render into ~/.agents and commit**

```bash
cd ~/Projects/skills-n-stuff
plugins/machine/scripts/render-codex-agents.sh ~/.agents; echo "exit $?"
cd ~/.agents && git add codex/AGENTS.md && git commit -F - << 'EOF'
config: add codex/AGENTS.md — generated from House Style + CLAUDE.md

Codex's global instructions, rendered by machine:sync (render-codex-agents.sh).
Do not hand-edit; edit claude/output-styles/House Style.md or claude/CLAUDE.md.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
git push
```
Expected: `RENDER_STATE=regenerated`, exit 0; commit and push succeed.

- [ ] **Step 2: Back up the old file and link**

```bash
mv ~/.codex/AGENTS.md ~/.codex/AGENTS.md.bak-2026-08-18 && ln -s ~/.agents/codex/AGENTS.md ~/.codex/AGENTS.md
readlink ~/.codex/AGENTS.md
bash ~/Projects/skills-n-stuff/plugins/machine/scripts/link-plan.sh ~/.agents; echo "exit $?"
```
Expected: link target `/Users/timmoser/.agents/codex/AGENTS.md`; link-plan shows **eight** `ok` lines incl. `AGENTS.md -> codex/AGENTS.md ok`, exit 0.

- [ ] **Step 3: Prove Codex loads it**

```bash
cd ~ && codex exec --skip-git-repo-check -s read-only "Do not use tools. In two lines: (1) quote the exact first heading of your global AGENTS.md instructions; (2) does that file contain a section titled 'Engineering discipline'? yes/no." 2>/dev/null | tail -3
```
Expected: line 1 quotes `# Rules`; line 2 `yes`.

- [ ] **Step 4: Codex skills — remove stale copies, register manifest skills for codex**

The 13 stale copies (all dated Jul 14, pm/product-pulse content, Claude-orchestration workflows Codex doesn't run) — remove exactly these and nothing else:
```bash
cd ~/.codex/skills && for s in codex-computer-use codex-implementation codex-review daily-research deep-dive dev-task house-rules ingest reconcile setup sprint-dev triage weekly-strategist; do [ -d "$s" ] && [ ! -L "$s" ] && rm -r "$s" && echo "removed $s"; done
ls ~/.codex/skills
```
Expected: 13 `removed` lines; remaining: `.system codex-primary-runtime figma-implement-design gh-address-comments playwright use-railway` (Codex-bundled / third-party — untouched).

Then register the manifest's skills for codex (this is exactly what sync Phase 2.6 will do from now on; running it once by hand here proves the agent id and the symlink behaviour):
```bash
cd ~ && while IFS=$'\t' read -r name source; do [ -n "$name" ] && npx -y skills add "$source" -s "$name" -a claude-code,codex -g -y 2>&1 | tail -1; done < ~/.agents/skills.manifest
ls -la ~/.codex/skills | grep -E '^l' 
```
Expected: for `impeccable` (the one manifest entry today) a symlink `~/.codex/skills/impeccable -> …/.agents/skills/impeccable`; `~/.claude/skills/impeccable` unchanged.

- [ ] **Step 5: Baseline sync report**

Run `/machine:sync --dry-run` in a Claude session and confirm the report has `Links: 8 ok` and `Derived: [skipped in dry run]`; then a real `/machine:sync` → `Derived: codex/AGENTS.md unchanged`, `Links: 8 ok`, `Skills: up to date`.

---

## Self-review

**Spec coverage.** D1 (derived, tracked, linked Codex AGENTS.md as 8th entry, rendered by sync) → Tasks 1, 2, 4. D2 (skills from the shared store via `-a claude-code,codex`; stale copies removed; policy stated) → Tasks 3, 4. D3 (leave config/hooks local) → Global Constraints "Never edit". Machine bump → Task 3. Proof Codex loads the file → Task 4 Step 3. Runnable checks: render script has 6 bats; link-plan gains 1; live `codex exec`.

**Placeholder scan.** None. Task 2 Step 3(d) permits a python one-off but states the exact row and the verifying greps.

**Name consistency.** Script `render-codex-agents.sh` + `RENDER_STATE=` (Task 1 contract, Task 2 Phase 1.5 + `Derived:` line, Task 4). Entry `AGENTS.md -> codex/AGENTS.md`, root `codex`, env `CODEX_HOME` (Task 2 script/tests/docs, Task 4 link-plan expectation). Agent ids `claude-code,codex` (Task 3 command + prose, Task 4 Step 4). Version 0.5.0 (Task 3 both manifests).
