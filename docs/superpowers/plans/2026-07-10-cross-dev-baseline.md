# Cross-Developer Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Studio Moser house rules + a personal model-routing rubric to *every* developer on a repo — plugin or not — via a managed AGENTS.md block, fetchable public docs, and a single user-global rubric file.

**Architecture:** Canonical docs live in `studio-baseline/` in the public `skills-n-stuff` repo (raw-fetchable, no auth). Each repo's `AGENTS.md` carries a marker-delimited *managed block* (house-rules essentials + a rubric-load reminder + fetch URLs) that `pm:setup` stamps and refreshes without clobbering the repo's own content. The rubric is one user-global file (`~/.config/studio-moser/model-rubric.yml`) created either by `pm:setup` or by any agent following the public `rubric-setup.md` walkthrough — no plugin required. The PM plugin *authors and maintains*; every dev *consumes* via git + public URLs.

**Tech Stack:** Markdown (skills/docs), bash, bats (existing test harness), `yq`/`jq`, GitHub raw URLs.

## Global Constraints

- Repo: `Studio-Moser/skills-n-stuff` (public). Canonical docs under `studio-baseline/`.
- Rubric store path: `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml` — one per machine-user (not per-repo, not keyed by git email).
- Managed-block markers (exact, byte-for-byte): `<!-- studio-baseline:start -->` and `<!-- studio-baseline:end -->`.
- Public raw URL base: `https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/`.
- No new runtime dependencies. Follow `pm:house-rules` conventions (branch, conventional commits, PR What/Why/Testing).
- Bats tests run via `plugins/pm/tests/run-tests.sh`; keep it green (currently 22 assertions).
- Model-agnostic: the docs name no specific models; the rubric is per-developer.
- Baseline behavior must NOT depend on a successful network fetch — inline the essentials, link the depth.
- **Refresh cadence: 14 days** (AI moves fast). The `reviewed:` staleness threshold in every advisory check is 14 days, not 90.
- **Model data source: the Artificial Analysis API** (structured JSON, not the JS-rendered page). Endpoint `GET https://artificialanalysis.ai/api/v2/language/models/free`, header `x-api-key: $ARTIFICIAL_ANALYSIS_API_KEY` (free key — 100 req/day). Confirm exact free-tier path + field names against https://artificialanalysis.ai/api-reference at build time. Map `price_1m_*` → cost axis, `artificial_analysis_coding_index`/`artificial_analysis_agentic_index` → intelligence axis; taste has no AA benchmark (manual, carried forward across refreshes). If `ARTIFICIAL_ANALYSIS_API_KEY` is unset, fall back to vendor docs / judgment — never hard-fail.

---

## File Structure

**Create (canonical public docs):**
- `studio-baseline/README.md` — explains the baseline system.
- `studio-baseline/house-rules.md` — canonical house rules (relocated from the PM skill body; the single source of truth).
- `studio-baseline/rubric-setup.md` — plugin-free walkthrough an agent follows to create the user-global rubric.
- `studio-baseline/AGENTS-baseline.md` — the exact managed-block content stamped into a repo's `AGENTS.md`.

**Create (scripts + tests):**
- `plugins/pm/scripts/rubric-path.sh` — resolve the rubric store path; `--check` reports set/unset.
- `plugins/pm/scripts/stamp-baseline.sh` — idempotently stamp/refresh the managed block in a target file.
- `plugins/pm/scripts/fetch-model-data.sh` — pull current cost + intelligence from the Artificial Analysis API (gated on `ARTIFICIAL_ANALYSIS_API_KEY`).
- `plugins/pm/tests/rubric-path.bats`
- `plugins/pm/tests/stamp-baseline.bats`
- `plugins/pm/tests/fetch-model-data.bats`

**Modify:**
- `plugins/pm/skills/house-rules/SKILL.md` — defer to `studio-baseline/house-rules.md`; keep a short inline summary.
- `plugins/pm/skills/setup/SKILL.md` — stamp the baseline block; write the rubric to the store (not AGENTS.md); rework Phase 4.5; migrate any in-AGENTS rubric out.
- `plugins/pm/skills/sprint-dev/SKILL.md` — 2B loads the rubric from the store.
- `plugins/pm/skills/dev-task/SKILL.md` — Frame step loads the rubric from the store.
- `plugins/pm/skills/reconcile/SKILL.md` — Phase 5.5 checks the store rubric, not AGENTS.md.
- `plugins/pm/references/model-orchestration.md` — describe the store + baseline-block model.
- `plugins/pm/tests/run-tests.sh` — include the two new bats files.
- `plugins/pm/.claude-plugin/plugin.json` — version bump.

---

## Phase 1 — Canonical public docs

### Task 1: Relocate house-rules to a canonical public doc

**Files:**
- Create: `studio-baseline/house-rules.md`
- Modify: `plugins/pm/skills/house-rules/SKILL.md`

**Interfaces:**
- Produces: the public URL `https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/house-rules.md`, referenced by Tasks 3, 7, and the house-rules skill.

- [ ] **Step 1: Create `studio-baseline/house-rules.md` with the full house rules**

Copy the body of the existing `plugins/pm/skills/house-rules/SKILL.md` (everything below its YAML frontmatter — the Branches / Commits / Pull Requests / File & documentation naming / Implementation discipline / Testing / Verification / Pre-commit security check / Project overrides sections) verbatim into `studio-baseline/house-rules.md`, prefixed with this heading:

```markdown
# Studio Moser House Rules

Conventions for code changes across Studio Moser projects. Canonical source — the `pm:house-rules` skill and every repo's `AGENTS.md` baseline block defer here. Applies to any agent (Claude, Codex, Cursor) and any developer, plugin or not.

<!-- the relocated sections follow verbatim -->
```

This is a *move* of existing content — do not paraphrase; preserve the exact wording of the relocated sections.

- [ ] **Step 2: Replace the house-rules SKILL body with a defer-to-canonical pointer**

In `plugins/pm/skills/house-rules/SKILL.md`, keep the YAML frontmatter unchanged. Replace the body (`# House Rules` and everything after it) with:

```markdown
# House Rules

Studio Moser conventions for code changes. **Canonical source:** [`studio-baseline/house-rules.md`](https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/house-rules.md) — the same rules every repo's `AGENTS.md` baseline block points at, so plugin and non-plugin devs follow one set. Read the canonical doc for the full text; the essentials:

- **Branches:** never commit to `main`/`master`; branch `{type}/{short-desc}` (feature/bugfix/hotfix/release/chore). Sprint batches use `pulse/{cluster}-{date}`.
- **Commits:** Conventional Commits, present tense, one logical change each.
- **PRs:** imperative title < 72 chars; body always `## What` / `## Why` / `## Testing`; one PR per task.
- **File naming:** Title Case with spaces; underscores when spaces can't be used; dashes only for version/topic segments; never default to ALL CAPS; tooling-fixed names (`README.md`, `SKILL.md`, …) keep their form.
- **Implementation discipline:** shortest diff that fully solves it; reuse existing code / stdlib / platform first; no speculative abstractions or unrequested refactors; fix the root cause, not the symptom.
- **Testing:** baseline first, add tests for new behavior, show pasted output — never claim "passing" without evidence.
- **Verification:** self-review is a first draft, not proof; an independent check reproduces the claimed result; dispute wrong findings rather than distorting correct code.
- **Pre-commit security:** no secrets in the diff; validate input; don't disable a security feature to "make it work"; handle errors.
- **Project overrides:** a repo's own `CLAUDE.md`/`AGENTS.md` wins.
```

- [ ] **Step 3: Verify the canonical doc contains every section the skill summarizes**

Run:
```bash
for h in "## Branches" "## Commits" "## Pull Requests" "## File & documentation naming" "## Implementation discipline" "## Testing" "## Verification" "## Pre-commit security check" "## Project overrides"; do
  grep -qF "$h" studio-baseline/house-rules.md && echo "ok: $h" || echo "MISSING: $h"
done
```
Expected: nine `ok:` lines, no `MISSING:`.

- [ ] **Step 4: Commit**

```bash
git add studio-baseline/house-rules.md plugins/pm/skills/house-rules/SKILL.md
git commit -m "feat(baseline): relocate house-rules to canonical public doc; skill defers to it"
```

---

### Task 2: Write the plugin-free rubric-setup walkthrough

**Files:**
- Create: `studio-baseline/rubric-setup.md`

**Interfaces:**
- Consumes: the rubric store path and YAML shape (defined here; reused by Tasks 4, 6, 7, 8).
- Produces: the public URL referenced by the baseline block (Task 3) and setup (Task 8).

- [ ] **Step 1: Create `studio-baseline/rubric-setup.md`**

Write this exact content:

````markdown
# Set up your personal model rubric

You are helping a developer create their **personal model-routing rubric** — how their AI agents pick which model does which work (cheap models for bulk/mechanical work, the strongest for ambiguous or taste-sensitive work). This works with **no plugin installed**; you only need shell + web access.

The rubric is **per developer, user-global** — one file on this machine, used across every repo:

```
${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml
```

## Steps

1. **Check if it already exists.** `cat "${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml"`. If present and current, stop — they're set up.

2. **Discover the current model lineup — prefer the Artificial Analysis API (structured, current).** If `ARTIFICIAL_ANALYSIS_API_KEY` is set, run `fetch-model-data.sh` (or curl `https://artificialanalysis.ai/api/v2/language/models/free` with `x-api-key`) to get names, pricing, and coding/agentic index as JSON — map pricing → cost, coding/agentic index → intelligence. That's 2 of 3 axes objectively. If no key: get names+cost from the dev's vendor docs, sanity-check at `artificialanalysis.ai` / `lmarena.ai` / `aider.chat/docs/leaderboards`; if offline, use your knowledge and add a `(verify names)` note. **Taste is never in AA** — always the dev's judgment; on a refresh, carry forward existing taste scores unchanged.

3. **Ask two things:**
   - Which model families/CLIs they can reach (e.g. "Claude only", "Claude + OpenAI Codex"). Record capabilities.
   - Confirm the axes: default **cost, intelligence, taste** (intelligence = hardest problem handled unsupervised; taste = UI/UX, code quality, API/SDK design, copy).

4. **Draft the table** — one row per model in *their* ecosystem, scored 1–10 on each axis. Show it and let them tweak.

5. **Write the file** to the path above (create the directory), in this shape:

```yaml
# Personal model-routing rubric. Higher = better.
reviewed: 2026-07-10              # today's date; refresh after 14 days
sources: [artificial-analysis]   # what you checked (AA API for cost+intelligence)
capabilities:
  codex: false                # OpenAI Codex CLI / sub available?
models:
  - { name: <cheapest capable coder>, cost: 9, intelligence: 8, taste: 5 }
  - { name: <balanced mid-tier>,      cost: 5, intelligence: 5, taste: 7 }
  - { name: <most capable>,           cost: 2, intelligence: 9, taste: 9 }
routing:
  bulk: <cheapest capable model>      # clear-spec / mechanical work
  taste_min: 7                        # user-facing work needs taste >= this
  review: <strong model>              # plan/implementation reviews
```

6. **How to apply it** (tell the developer, and follow it yourself when dispatching sub-agents):
   - Defaults, not limits — escalate to a stronger model without asking if output misses the bar.
   - Bulk/mechanical/clear-spec → `routing.bulk`.
   - User-facing (UI, copy, API) → a model with `taste >= routing.taste_min`.
   - Reviews → `routing.review`.
   - Keep reasoning effort matched to difficulty; don't default to the top tier.
   - Re-check when a newer model ships or after **14 days**, then update `reviewed`. On refresh, re-pull Artificial Analysis for cost + intelligence and **keep your taste scores and capabilities** — only the AA-sourced axes change.

That's it — the rubric now lives in your user-global config and any repo's baseline reminder can point your agent at it.
````

- [ ] **Step 2: Verify it names the store path and the YAML `models:` key**

Run:
```bash
grep -qF 'studio-moser/model-rubric.yml' studio-baseline/rubric-setup.md && grep -qF 'models:' studio-baseline/rubric-setup.md && echo "ok" || echo "MISSING key content"
```
Expected: `ok`.

- [ ] **Step 3: Commit**

```bash
git add studio-baseline/rubric-setup.md
git commit -m "feat(baseline): add plugin-free rubric-setup walkthrough"
```

---

### Task 3: Write the managed AGENTS.md baseline block + README

**Files:**
- Create: `studio-baseline/AGENTS-baseline.md`
- Create: `studio-baseline/README.md`

**Interfaces:**
- Consumes: the two public URLs (house-rules, rubric-setup) and the store path.
- Produces: `AGENTS-baseline.md`, the exact block body stamped by `stamp-baseline.sh` (Task 5) via `pm:setup` (Task 7). NOTE: this file is the block *body only* — the start/end markers are added by the stamper, not stored here.

- [ ] **Step 1: Create `studio-baseline/AGENTS-baseline.md` (block body only, no markers)**

Write this exact content:

```markdown

## Studio Moser baseline

_Managed block — regenerated by `/pm:setup`. Edit the source at `studio-baseline/AGENTS-baseline.md` in Studio-Moser/skills-n-stuff, not here._

**House rules apply to all changes in this repo.** Full text: https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/house-rules.md . In short: never commit to `main` (branch `{type}/{desc}`); Conventional Commits; PRs use What/Why/Testing; shortest diff / reuse first / root cause; show pasted test output; no secrets in the diff.

**Model routing — load your personal rubric.** Before dispatching sub-agents or picking a model for a task, load your rubric from `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml` and route by it (bulk/mechanical → cheap; user-facing → high-taste; reviews → strong). **If that file does not exist, you have not set up your rubric yet** — fetch and follow https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/rubric-setup.md to create it (no plugin required), then continue. Verify sub-agent output with an independent check rather than trusting a self-report.
```

- [ ] **Step 2: Create `studio-baseline/README.md`**

Write this exact content:

```markdown
# studio-baseline

Canonical, **public, fetchable** baseline that every Studio Moser repo shares — so house rules and personal model-routing reach every developer, whether or not they have the `pm` plugin installed.

- `house-rules.md` — the one set of conventions (the `pm:house-rules` skill defers here).
- `rubric-setup.md` — how any agent helps a dev create their user-global model rubric, no plugin needed.
- `AGENTS-baseline.md` — the managed block `/pm:setup` stamps into a repo's `AGENTS.md` (between `<!-- studio-baseline:start -->` / `<!-- studio-baseline:end -->`).

**Delivery model:** a PM runs `/pm:setup` once per repo to stamp the block (committed). Every dev then inherits it via clone; their agent reads `AGENTS.md` and, if their rubric isn't set, fetches `rubric-setup.md` and walks them through it. The plugin authors and refreshes; everyone consumes via git + these raw URLs.

Raw URL base: `https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/`
```

- [ ] **Step 3: Verify the block references both docs and the store path**

Run:
```bash
grep -qF 'house-rules.md' studio-baseline/AGENTS-baseline.md \
 && grep -qF 'rubric-setup.md' studio-baseline/AGENTS-baseline.md \
 && grep -qF 'studio-moser/model-rubric.yml' studio-baseline/AGENTS-baseline.md \
 && ! grep -qF 'studio-baseline:start' studio-baseline/AGENTS-baseline.md \
 && echo "ok" || echo "FAIL: missing ref or markers wrongly present"
```
Expected: `ok` (the block body must NOT contain the markers — the stamper adds them).

- [ ] **Step 4: Commit**

```bash
git add studio-baseline/AGENTS-baseline.md studio-baseline/README.md
git commit -m "feat(baseline): add managed AGENTS block source and README"
```

---

## Phase 2 — Scripts + tests

### Task 4: `rubric-path.sh` — resolve store path and set/unset state

**Files:**
- Create: `plugins/pm/scripts/rubric-path.sh`
- Test: `plugins/pm/tests/rubric-path.bats`

**Interfaces:**
- Produces: `rubric-path.sh` prints the resolved path (no args) or `set`/`unset` (`--check`). Consumed by Tasks 8/9/10.

- [ ] **Step 1: Write the failing test**

Create `plugins/pm/tests/rubric-path.bats`:

```bash
#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/rubric-path.sh"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/cfg"
  mkdir -p "$XDG_CONFIG_HOME"
}

@test "prints resolved path under XDG_CONFIG_HOME" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "$XDG_CONFIG_HOME/studio-moser/model-rubric.yml" ]
}

@test "--check reports unset when file is missing" {
  run "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}

@test "--check reports set when a valid rubric exists" {
  mkdir -p "$XDG_CONFIG_HOME/studio-moser"
  printf 'models:\n  - { name: x, cost: 1, intelligence: 1, taste: 1 }\n' \
    > "$XDG_CONFIG_HOME/studio-moser/model-rubric.yml"
  run "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [ "$output" = "set" ]
}

@test "--check reports unset when file exists but lacks models key" {
  mkdir -p "$XDG_CONFIG_HOME/studio-moser"
  printf 'reviewed: 2026-01-01\n' > "$XDG_CONFIG_HOME/studio-moser/model-rubric.yml"
  run "$SCRIPT" --check
  [ "$output" = "unset" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats plugins/pm/tests/rubric-path.bats`
Expected: FAIL (script does not exist yet).

- [ ] **Step 3: Write `plugins/pm/scripts/rubric-path.sh`**

```bash
#!/usr/bin/env bash
# Resolve the user-global model-rubric path; --check reports set/unset.
#   rubric-path.sh          -> prints the resolved absolute path
#   rubric-path.sh --check  -> prints "set" if a usable rubric exists, else "unset"
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
rubric_path="$config_home/studio-moser/model-rubric.yml"

if [ "${1:-}" = "--check" ]; then
  if [ -s "$rubric_path" ] && yq -e '.models' "$rubric_path" >/dev/null 2>&1; then
    echo "set"
  else
    echo "unset"
  fi
  exit 0
fi

echo "$rubric_path"
```

Then: `chmod +x plugins/pm/scripts/rubric-path.sh`

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats plugins/pm/tests/rubric-path.bats`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/pm/scripts/rubric-path.sh plugins/pm/tests/rubric-path.bats
git commit -m "feat(pm): add rubric-path.sh store resolver with set/unset check"
```

---

### Task 5: `stamp-baseline.sh` — idempotent managed-block stamp/refresh

**Files:**
- Create: `plugins/pm/scripts/stamp-baseline.sh`
- Test: `plugins/pm/tests/stamp-baseline.bats`

**Interfaces:**
- Consumes: a target file path + a block-body file (e.g. a local copy of `AGENTS-baseline.md`).
- Produces: `stamp-baseline.sh <target> <body-file>` — inserts/replaces the marker-delimited block, preserving all content outside the markers. Consumed by Task 7.

- [ ] **Step 1: Write the failing test**

Create `plugins/pm/tests/stamp-baseline.bats`:

```bash
#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/stamp-baseline.sh"
  TARGET="${BATS_TEST_TMPDIR}/AGENTS.md"
  BODY="${BATS_TEST_TMPDIR}/body.md"
  printf '## Studio Moser baseline\n\nfirst version\n' > "$BODY"
}

@test "stamps a block into an empty/absent target" {
  run "$SCRIPT" "$TARGET" "$BODY"
  [ "$status" -eq 0 ]
  grep -qF "<!-- studio-baseline:start -->" "$TARGET"
  grep -qF "<!-- studio-baseline:end -->" "$TARGET"
  grep -qF "first version" "$TARGET"
}

@test "preserves existing content outside the block" {
  printf '# My Repo\n\nProject-specific notes.\n' > "$TARGET"
  "$SCRIPT" "$TARGET" "$BODY"
  grep -qF "# My Repo" "$TARGET"
  grep -qF "Project-specific notes." "$TARGET"
  grep -qF "first version" "$TARGET"
}

@test "re-stamping is idempotent (exactly one block)" {
  "$SCRIPT" "$TARGET" "$BODY"
  "$SCRIPT" "$TARGET" "$BODY"
  [ "$(grep -cF "<!-- studio-baseline:start -->" "$TARGET")" -eq 1 ]
}

@test "refresh replaces the block body, not the whole file" {
  printf '# My Repo\n' > "$TARGET"
  "$SCRIPT" "$TARGET" "$BODY"
  printf '## Studio Moser baseline\n\nsecond version\n' > "$BODY"
  "$SCRIPT" "$TARGET" "$BODY"
  grep -qF "# My Repo" "$TARGET"
  grep -qF "second version" "$TARGET"
  ! grep -qF "first version" "$TARGET"
  [ "$(grep -cF "<!-- studio-baseline:start -->" "$TARGET")" -eq 1 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats plugins/pm/tests/stamp-baseline.bats`
Expected: FAIL (script does not exist yet).

- [ ] **Step 3: Write `plugins/pm/scripts/stamp-baseline.sh`**

```bash
#!/usr/bin/env bash
# Idempotently stamp/refresh the studio-baseline managed block in a target file.
#   stamp-baseline.sh <target-file> <block-body-file>
# Replaces the content between the markers if present, else appends a fresh block.
# Never touches content outside the markers.
set -euo pipefail

target="$1"
body_file="$2"
start="<!-- studio-baseline:start -->"
end="<!-- studio-baseline:end -->"

touch "$target"

if grep -qF "$start" "$target" && grep -qF "$end" "$target"; then
  # Replace the existing block in place, keeping everything outside the markers.
  awk -v s="$start" -v e="$end" -v bf="$body_file" '
    BEGIN { while ((getline line < bf) > 0) body = body line "\n" }
    $0 == s { print s; printf "%s", body; print e; skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { print }
  ' "$target" > "$target.tmp"
  mv "$target.tmp" "$target"
else
  {
    [ -s "$target" ] && printf '\n'
    printf '%s\n' "$start"
    cat "$body_file"
    printf '%s\n' "$end"
  } >> "$target"
fi
```

Then: `chmod +x plugins/pm/scripts/stamp-baseline.sh`

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats plugins/pm/tests/stamp-baseline.bats`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/pm/scripts/stamp-baseline.sh plugins/pm/tests/stamp-baseline.bats
git commit -m "feat(pm): add idempotent stamp-baseline.sh managed-block writer"
```

---

### Task 6: `fetch-model-data.sh` — pull cost + intelligence from the Artificial Analysis API

**Files:**
- Create: `plugins/pm/scripts/fetch-model-data.sh`
- Test: `plugins/pm/tests/fetch-model-data.bats`

**Interfaces:**
- Consumes: `ARTIFICIAL_ANALYSIS_API_KEY` env var; optional `AA_MODELS_URL` override (for tests/pinning).
- Produces: normalized TSV `name\tcreator\tinput_$/M\toutput_$/M\tcoding_index\tagentic_index`, one row per model. Exit 3 if no key (caller falls back to manual). Consumed by `rubric-setup.md` (Task 2) and setup Phase 4.5 (Task 8).

> **Confirm at build time:** the exact free-tier path and JSON field names against https://artificialanalysis.ai/api-reference — the `jq` accessors below encode the documented shape (`name`, `model_creator`, `price_1m_input_tokens`, `price_1m_output_tokens`, `artificial_analysis_coding_index`, `artificial_analysis_agentic_index`) and the `(.data // .)` / `.model_creator.name // .model_creator` guards absorb wrapper/shape variance, but verify before trusting the numbers.

- [ ] **Step 1: Write the failing test**

Create `plugins/pm/tests/fetch-model-data.bats`:

```bash
#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/fetch-model-data.sh"
}

@test "exits 3 and warns when API key is unset" {
  unset ARTIFICIAL_ANALYSIS_API_KEY
  run "$SCRIPT"
  [ "$status" -eq 3 ]
}

@test "emits normalized TSV from AA-shaped JSON" {
  export ARTIFICIAL_ANALYSIS_API_KEY=dummy
  fixture="${BATS_TEST_TMPDIR}/models.json"
  cat > "$fixture" <<'JSON'
{"data":[{"name":"Model X","model_creator":{"name":"Acme"},"price_1m_input_tokens":1.5,"price_1m_output_tokens":6,"artificial_analysis_coding_index":72,"artificial_analysis_agentic_index":55}]}
JSON
  export AA_MODELS_URL="file://$fixture"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Model X"* ]]
  [[ "$output" == *"Acme"* ]]
  [[ "$output" == *"72"* ]]
  [[ "$output" == *"55"* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats plugins/pm/tests/fetch-model-data.bats`
Expected: FAIL (script does not exist yet).

- [ ] **Step 3: Write `plugins/pm/scripts/fetch-model-data.sh`**

```bash
#!/usr/bin/env bash
# Pull current LLM cost + intelligence from the Artificial Analysis API.
# Requires ARTIFICIAL_ANALYSIS_API_KEY (free key: https://artificialanalysis.ai/data-api).
# Emits TSV: name \t creator \t input_$/M \t output_$/M \t coding_index \t agentic_index
# Exit 3 = no key (caller should fall back to manual/vendor docs).
set -euo pipefail

key="${ARTIFICIAL_ANALYSIS_API_KEY:-}"
if [ -z "$key" ]; then
  echo "ARTIFICIAL_ANALYSIS_API_KEY not set — skipping live model data; fall back to vendor docs/judgment." >&2
  exit 3
fi

url="${AA_MODELS_URL:-https://artificialanalysis.ai/api/v2/language/models/free}"
resp="$(curl -fsS -H "x-api-key: $key" "$url")" || { echo "Artificial Analysis API request failed." >&2; exit 4; }

echo "$resp" | jq -r '
  (.data // .)
  | (if type=="array" then . else [.] end)[]
  | [ .name,
      (.model_creator.name // .model_creator // "?"),
      (.price_1m_input_tokens // "?"),
      (.price_1m_output_tokens // "?"),
      (.artificial_analysis_coding_index // "?"),
      (.artificial_analysis_agentic_index // "?") ]
  | @tsv'
```

Then: `chmod +x plugins/pm/scripts/fetch-model-data.sh`

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats plugins/pm/tests/fetch-model-data.bats`
Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/pm/scripts/fetch-model-data.sh plugins/pm/tests/fetch-model-data.bats
git commit -m "feat(pm): add fetch-model-data.sh (Artificial Analysis API → cost+intelligence TSV)"
```

---

## Phase 3 — pm:setup reshape

### Task 7: Wire the baseline stamp into `pm:setup`

**Files:**
- Modify: `plugins/pm/skills/setup/SKILL.md`

**Interfaces:**
- Consumes: `stamp-baseline.sh` (Task 5), `studio-baseline/AGENTS-baseline.md` (Task 3), the raw URL base.
- Produces: a new "Phase 4.4: Stamp the Studio Moser baseline block" that all repos get.

- [ ] **Step 1: Add Phase 4.4 immediately before `## Phase 4.5`**

In `plugins/pm/skills/setup/SKILL.md`, insert this section directly above the `## Phase 4.5: Establish the Model-Selection Rubric` header:

````markdown
## Phase 4.4: Stamp the Studio Moser baseline block

Every repo — regardless of who works on it — gets the same managed baseline block in its `AGENTS.md`: house-rules essentials + the model-routing reminder that points a plugin-less dev's agent at the public setup walkthrough. This is what reaches developers who never install PM.

1. Resolve the target `AGENTS.md` (per the "Where the project block goes" rule — the repo's agent-instruction source; default `AGENTS.md`, ensure `CLAUDE.md` imports it with `@AGENTS.md`).
2. Fetch the current block body from the canonical source (fall back to the copy bundled in the plugin if offline):

```bash
BODY="$(mktemp)"
curl -fsS "https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/AGENTS-baseline.md" -o "$BODY" \
  || cp "$CLAUDE_PLUGIN_ROOT/../../studio-baseline/AGENTS-baseline.md" "$BODY" 2>/dev/null \
  || { echo "could not obtain baseline body"; }
```

3. Stamp it (idempotent — safe to re-run; never clobbers the repo's own content):

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/stamp-baseline.sh" "$primary_repo_root/AGENTS.md" "$BODY"
```

4. Tell the user the block was stamped/refreshed and that it's committed with the rest of setup, so every teammate inherits it on clone.
````

- [ ] **Step 2: Verify the phase references the stamper and the canonical URL**

Run:
```bash
grep -qF "stamp-baseline.sh" plugins/pm/skills/setup/SKILL.md \
 && grep -qF "studio-baseline/AGENTS-baseline.md" plugins/pm/skills/setup/SKILL.md \
 && echo "ok" || echo "MISSING"
```
Expected: `ok`.

- [ ] **Step 3: Commit**

```bash
git add plugins/pm/skills/setup/SKILL.md
git commit -m "feat(pm): setup stamps the shared studio-baseline block into AGENTS.md"
```

---

### Task 8: Rework Phase 4.5 — rubric goes to the user-global store, not AGENTS.md

**Files:**
- Modify: `plugins/pm/skills/setup/SKILL.md`

**Interfaces:**
- Consumes: `rubric-path.sh` (Task 4), `studio-baseline/rubric-setup.md` (Task 2).
- Produces: a Phase 4.5 that writes/refreshes the rubric at the store path and migrates any legacy in-AGENTS rubric out.

- [ ] **Step 1: Replace the Phase 4.5 body**

In `plugins/pm/skills/setup/SKILL.md`, replace everything between the `## Phase 4.5: Establish the Model-Selection Rubric` header and the next `---` with:

````markdown
The rubric is **per developer, user-global** — one file at `$("$CLAUDE_PLUGIN_ROOT/scripts/rubric-path.sh")` (`${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`), shared across every repo this dev touches — NOT written into the repo's `AGENTS.md`. The repo only carries the *reminder* to load it (stamped in Phase 4.4).

1. **Check whether this dev already has a rubric:**

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/rubric-path.sh" --check
```

- `set` → tell the user their rubric is in place; offer a refresh if its `reviewed:` date is **>14 days** old or it lists a superseded model. A refresh re-pulls Artificial Analysis for cost + intelligence and keeps the dev's taste scores + capabilities. Done.
- `unset` → walk them through creating one (next step).

2. **Create the rubric** by following the canonical walkthrough at `studio-baseline/rubric-setup.md` (read it from `$CLAUDE_PLUGIN_ROOT/../../studio-baseline/rubric-setup.md`, or fetch the raw URL): discover the current lineup **preferring the Artificial Analysis API** (`"$CLAUDE_PLUGIN_ROOT/scripts/fetch-model-data.sh"` when `ARTIFICIAL_ANALYSIS_API_KEY` is set → pricing → cost, coding/agentic index → intelligence; else vendor docs / judgment), score on cost/intelligence/taste for **this dev's** ecosystem, capture `capabilities` (e.g. `codex`), show the table for tweaks, then write the YAML to the path from `rubric-path.sh`. Stamp today's date in `reviewed:`.

3. **Migrate any legacy in-repo rubric.** If a prior setup wrote a "Picking the right models" section into this repo's `AGENTS.md`/`CLAUDE.md`, move its scores into the user-global rubric (if the dev confirms they're theirs) and delete that section from the repo file — the rubric no longer lives in the repo. Leave the Phase 4.4 baseline reminder in place.
````

- [ ] **Step 2: Verify Phase 4.5 now targets the store, not AGENTS.md**

Run:
```bash
awk '/## Phase 4.5/,/^---/' plugins/pm/skills/setup/SKILL.md | grep -qF "rubric-path.sh" \
 && awk '/## Phase 4.5/,/^---/' plugins/pm/skills/setup/SKILL.md | grep -qiF "user-global" \
 && echo "ok" || echo "MISSING"
```
Expected: `ok`.

- [ ] **Step 3: Commit**

```bash
git add plugins/pm/skills/setup/SKILL.md
git commit -m "feat(pm): setup writes the rubric to the user-global store, migrates it out of AGENTS.md"
```

---

## Phase 4 — Consumers + docs

### Task 9: Load the rubric from the store in sprint-dev and dev-task

**Files:**
- Modify: `plugins/pm/skills/sprint-dev/SKILL.md`
- Modify: `plugins/pm/skills/dev-task/SKILL.md`

**Interfaces:**
- Consumes: `rubric-path.sh` (Task 4), `studio-baseline/rubric-setup.md` URL (Task 2).

- [ ] **Step 1: Update the sprint-dev 2B routing note**

In `plugins/pm/skills/sprint-dev/SKILL.md`, replace the first sentence of the "**Pick the model and effort per task altitude.**" paragraph (the clause naming where the rubric lives) with:

```markdown
**Pick the model and effort per task altitude.** Load the current developer's rubric from `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml` (run `"$CLAUDE_PLUGIN_ROOT/scripts/rubric-path.sh" --check`; if `unset`, offer to set it up via `studio-baseline/rubric-setup.md` before dispatching, or fall back to the default model). Route by it:
```

Leave the rest of the paragraph (the "route clear-spec / mechanical … " guidance) unchanged.

- [ ] **Step 2: Update the dev-task Frame step**

In `plugins/pm/skills/dev-task/SKILL.md`, in `### 1. Frame`, add this bullet after the "Read the repo's `CLAUDE.md` / `AGENTS.md`" bullet:

```markdown
- Load your model rubric from `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml` (via `pm:reconcile`/`setup`'s `rubric-path.sh`, or just read the file). If it's missing, offer to set it up (`studio-baseline/rubric-setup.md`) — this is user-global, done once. Use it when choosing models for any sub-agent work.
```

- [ ] **Step 3: Verify both skills reference the store path**

Run:
```bash
grep -qF 'studio-moser/model-rubric.yml' plugins/pm/skills/sprint-dev/SKILL.md \
 && grep -qF 'studio-moser/model-rubric.yml' plugins/pm/skills/dev-task/SKILL.md \
 && echo "ok" || echo "MISSING"
```
Expected: `ok`.

- [ ] **Step 4: Commit**

```bash
git add plugins/pm/skills/sprint-dev/SKILL.md plugins/pm/skills/dev-task/SKILL.md
git commit -m "feat(pm): sprint-dev and dev-task load the rubric from the user-global store"
```

---

### Task 10: Point reconcile + doctrine at the store; register tests; version bump

**Files:**
- Modify: `plugins/pm/skills/reconcile/SKILL.md`
- Modify: `plugins/pm/references/model-orchestration.md`
- Modify: `plugins/pm/tests/run-tests.sh`
- Modify: `plugins/pm/.claude-plugin/plugin.json`

**Interfaces:**
- Consumes: `rubric-path.sh` (Task 4).

- [ ] **Step 1: Update reconcile Phase 5.5 to check the store rubric**

In `plugins/pm/skills/reconcile/SKILL.md`, replace step 1 of "## Phase 5.5: Model-Rubric Freshness (advisory)" with:

```markdown
1. Resolve the developer's rubric with `"$CLAUDE_PLUGIN_ROOT/scripts/rubric-path.sh"`. If `--check` reports `unset`, print `"No personal model rubric set — run /pm:setup or follow studio-baseline/rubric-setup.md to create one."` and end the phase.
```

Also in that same Phase 5.5, change the staleness threshold in step 2 from `~90 days` to **`14 days`** (the plan-wide cadence), so a rubric older than 14 days is flagged for refresh.

- [ ] **Step 2: Update the doctrine reference**

In `plugins/pm/references/model-orchestration.md`, under "## What lives where", replace the first bullet ("Routing philosophy + the rubric → the project's `CLAUDE.md`/`AGENTS.md` …") with:

```markdown
- **Routing philosophy** → the shared `studio-baseline` (house-rules + the `AGENTS.md` reminder block), reaching every dev plugin-free. **The rubric itself** → each developer's user-global store `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`, NOT the repo. The repo's `AGENTS.md` only reminds the agent to load it; `pm:setup`/`rubric-setup.md` create it.
```

In the same file, under "## Project block", replace its opening paragraph so it no longer says the rubric table is written into the project's `CLAUDE.md`; instead state: "`pm:setup` stamps a *reminder* block into the repo's `AGENTS.md` (see `studio-baseline/AGENTS-baseline.md`); the scored rubric table lives in the developer's user-global store (`studio-baseline/rubric-setup.md` defines its shape)."

- [ ] **Step 3: Confirm the new bats files are picked up**

`plugins/pm/tests/run-tests.sh` runs `bats *.bats`, so `rubric-path.bats` and `stamp-baseline.bats` are auto-discovered — no edit needed. Verify: `grep -n 'bats \*.bats' plugins/pm/tests/run-tests.sh` returns the glob line. (Drop `run-tests.sh` from this task's commit `git add` since it's unchanged.)

- [ ] **Step 4: Run the full suite**

Run: `bash plugins/pm/tests/run-tests.sh`
Expected: all prior 22 assertions PASS plus the 10 new ones (4 rubric-path + 4 stamp-baseline + 2 fetch-model-data) = 32 PASS, 0 fail.

- [ ] **Step 5: Bump the plugin version**

In `plugins/pm/.claude-plugin/plugin.json`, change `"version": "0.8.0"` to `"version": "0.9.0"`. Validate:

```bash
python3 -c "import json; json.load(open('plugins/pm/.claude-plugin/plugin.json')); print('valid')"
```
Expected: `valid`.

- [ ] **Step 6: Commit**

```bash
git add plugins/pm/skills/reconcile/SKILL.md plugins/pm/references/model-orchestration.md plugins/pm/tests/run-tests.sh plugins/pm/.claude-plugin/plugin.json
git commit -m "feat(pm): reconcile+doctrine target the rubric store; register tests; v0.9.0"
```

---

## Post-implementation (out of plan scope, for the human)

- Open the PR (What/Why/Testing). After merge, the raw `studio-baseline/*` URLs go live on `main`; run `/pm:setup` on one active repo to stamp the block and create the rubric end-to-end, then confirm a non-PM agent (or a clean session) can read `AGENTS.md` and follow `rubric-setup.md` unaided.
- Get a free Artificial Analysis API key (https://artificialanalysis.ai/data-api) and export `ARTIFICIAL_ANALYSIS_API_KEY` in your shell profile so `fetch-model-data.sh` works. Without it, rubric setup still works — it just falls back to vendor docs / judgment.
- Optional follow-ups (not in this plan): pin the raw URLs to a release tag instead of `main` for stability; add an opt-in SessionStart hook that hard-nudges an unset/stale rubric; **automate the 14-day refresh via a scheduled task** (product-pulse already runs on a cadence — the rubric refresh could piggyback or be its own `scheduled-tasks` job) rather than relying on the advisory nudge; extract house-rules similarly for Codex/Cursor rule files.

## Self-Review notes

- **Spec coverage:** house-rules extraction (T1), plugin-free walkthrough (T2), managed block + delivery model (T3), identity/store resolver (T4), idempotent stamper (T5), Artificial Analysis API fetch (T6), setup stamps block (T7), rubric→store + migration (T8), consumers load store (T9), reconcile/doctrine/tests/version (T10). "Force/help every dev, plugin or not" = T3+T7 (block reaches everyone) + T2 (plugin-free setup). "User-global not per-repo" = T4/T8. "Same basic stuff in every repo" = idempotent stamped block, T5/T7. "Refresh every 14 days from AA reports" = 14-day threshold across T2/T8/T10 + AA API in T6/T2/T8.
- **Type/name consistency:** store path `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`, markers `<!-- studio-baseline:start/end -->`, scripts `rubric-path.sh` / `stamp-baseline.sh`, YAML `models:` key — used identically across all tasks.
- **Fetch-independence:** baseline block inlines house-rules essentials + the store path + what-to-do; URLs are for depth. Setup's curl has an offline fallback to the bundled copy.
