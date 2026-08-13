# Machine Plugin Rename + Synced, Seeded, Effort-Aware Model Rubric — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the `fleet` plugin to `machine`, make the model rubric sync across machines via the agents repo (whole `~/.config/studio-moser/` folder as a sixth tracked symlink), ship a distributable seed rubric with an effort-aware schema, and update every pm consumer to dispatch the new `model@effort` routing values correctly.

**Architecture:** The rubric's *read path* stays the fixed constant `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml` — all 33 existing references keep working, and plugin-free consumers stay decoupled. *Storage* varies: when an agents repo exists, `~/.config/studio-moser/` is a symlink to `$repo/config/studio-moser/` (synced by git, verified by `link-plan.sh`); without one it's a plain directory. The seed carries house judgment (taste, DeepSWE scores, anti-patterns); the interview supplies per-developer facts (cost, capabilities) and *derives* routing from them.

**Tech Stack:** bash, bats, YAML, Claude Code plugin markdown skills.

## Global Constraints

- The rubric read path never changes: `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml` (verbatim, in every reference).
- Repo-side rubric home: `$repo/config/studio-moser/` where `repo="${AGENTS_REPO:-$HOME/.agents}"`.
- Plugin name: `machine`. Env var: `AGENTS_REPO` (replaces `FLEET_REPO`, no back-compat shim — plugin is one day old).
- **Do NOT rename on-disk protocol strings** that live in already-deployed agents repos: `.fleet-local.json`, `# fleet:skills start — generated, do not edit`, `# fleet:skills end`. Renaming them breaks deployed state; they are data-format constants now. (`# ponytail: legacy marker names, migrate only if a breaking format change happens anyway`.)
- **Do NOT edit anything under `docs/superpowers/`** (plans/specs are historical records) except this plan's own checkboxes.
- File naming: new files use Title Case with underscores (`Default_Rubric.yml`); files fixed by tooling convention keep their form (`SKILL.md`, `plugin.json`, `link-plan.sh`, this plans directory's lowercase-dash names).
- Skills-n-stuff is PUBLIC. Nothing personal (real costs, subscriptions, machine inventory) may be committed to it. The personal rubric goes only in the PRIVATE agents repo.
- Tests: `bats plugins/machine/tests/` must pass at the end of every task that touches `scripts/` or `tests/`.
- Work on a branch: `git checkout -b machine-plugin-rubric-sync` before Task 1.

---

### Task 1: Rename the plugin `fleet` → `machine`

**Files:**
- Rename: `plugins/fleet/` → `plugins/machine/` (whole tree, `git mv`)
- Modify: `plugins/machine/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `plugins/machine/README.md`, `plugins/machine/skills/sync/SKILL.md`, `plugins/machine/skills/model-rubric/SKILL.md`, `plugins/machine/scripts/skills-manifest.sh`, `plugins/machine/scripts/skills-reconcile.sh`, `plugins/machine/tests/*.bats`, `studio-baseline/Machine_Setup.md`, `plugins/pm/*` (only the `/fleet:` command strings — pm's substantive edits are Task 7)
- Test: existing `plugins/machine/tests/` suite (rename-safe: tests locate scripts via `$BATS_TEST_DIRNAME`)

**Interfaces:**
- Produces: plugin id `machine`, commands `/machine:sync` and `/machine:model-rubric`, env var `AGENTS_REPO`, cache-path glob `*/machine/*`. Every later task edits files under `plugins/machine/`.

- [ ] **Step 1: git mv the tree**

```bash
cd ~/Projects/skills-n-stuff
git checkout -b machine-plugin-rubric-sync
git mv plugins/fleet plugins/machine
```

- [ ] **Step 2: Sweep the name across live files (NOT docs/, NOT protocol strings)**

Do these as targeted replacements — verify each with the greps in Step 3, don't blind-sed the repo:

1. `plugins/machine/.claude-plugin/plugin.json`: `"name": "fleet"` → `"name": "machine"`, `"version": "0.2.1"` → `"version": "0.3.0"`. In `description`, replace the last sentence `Also owns the per-developer model-routing rubric.` with `Also owns the per-developer model-routing rubric and syncs it through the same repo.`
2. `.claude-plugin/marketplace.json`: in the fleet entry, `"name": "fleet"` → `"name": "machine"`, `"source": "./plugins/fleet"` → `"source": "./plugins/machine"`, `"version": "0.2.1"` → `"version": "0.3.0"`, same description sentence swap.
3. Everywhere in `plugins/machine/` and `studio-baseline/Machine_Setup.md`:
   - `FLEET_REPO` → `AGENTS_REPO`
   - `/fleet:sync` → `/machine:sync`, `/fleet:model-rubric` → `/machine:model-rubric`, `fleet:sync` → `machine:sync`, `fleet:model-rubric` → `machine:model-rubric`
   - the cache-locator line in both SKILL.md files: `cache/*/fleet/*/` → `cache/*/machine/*/` and the variable `fleet=` → `machine=` (with every later `"$fleet/scripts/..."` usage → `"$machine/scripts/..."`)
   - prose `Fleet — Model Rubric` → `Machine — Model Rubric`; `# Fleet` headings → `# Machine`
   - `plugins/fleet/` path mentions → `plugins/machine/`
   - **Skip**: `.fleet-local.json`, `# fleet:skills start/end` markers, and the comment at `plugins/machine/scripts/portability-lint.sh:26` — reword that comment's `mid fleet:sync` → `mid machine:sync` (it's prose, not protocol).
4. `plugins/pm/`: replace command strings only — `/fleet:model-rubric` → `/machine:model-rubric` and `fleet:model-rubric` → `machine:model-rubric` in `skills/setup/SKILL.md`, `skills/dev-task/SKILL.md`, `skills/sprint-dev/SKILL.md`, `references/model-orchestration.md`, `README.md`. Where prose says "the fleet plugin", write "the machine plugin".

- [ ] **Step 3: Verify the sweep**

```bash
cd ~/Projects/skills-n-stuff
# No live references to the old name outside protocol strings and docs/:
grep -rn 'fleet' plugins/ studio-baseline/ .claude-plugin/ README.md \
  | grep -v '.fleet-local.json' | grep -v 'fleet:skills' && echo "LEFTOVERS" || echo "clean"
grep -rn 'FLEET_REPO' plugins/ studio-baseline/ && echo "LEFTOVERS" || echo "clean"
```

Expected: `clean` twice.

- [ ] **Step 4: Run the full test suite**

```bash
bats ~/Projects/skills-n-stuff/plugins/machine/tests/
```

Expected: all pass (tests resolve scripts relative to themselves; the two `.fleet-local.json` / `fleet:skills` fixtures still pass because those strings were deliberately kept).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(machine)!: rename fleet plugin to machine, FLEET_REPO to AGENTS_REPO"
```

---

### Task 2: `link-plan.sh` — root-aware entries + sixth entry for `config/studio-moser`

**Files:**
- Modify: `plugins/machine/scripts/link-plan.sh`
- Test: `plugins/machine/tests/link-plan.bats`

**Interfaces:**
- Consumes: Task 1's rename (paths under `plugins/machine/`).
- Produces: entries format `"<root>|<name>|<repo-rel>"` with roots `claude` (`${CLAUDE_CONFIG_DIR:-$HOME/.claude}`) and `config` (`${XDG_CONFIG_HOME:-$HOME/.config}`); sixth entry `config|studio-moser|config/studio-moser`. Output line format unchanged: `printf '%-24s -> %-32s %s\n' "$name" "$rel" "$state"`. Task 6 documents this; Task 9 relies on the sixth entry reporting `ok`.

- [ ] **Step 1: Write the failing tests**

Append to `plugins/machine/tests/link-plan.bats`, and update `setup()` / `link_all()` / the count test:

```bash
# In setup(), after the existing mkdir line, add:
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/xdg"
  mkdir -p "$REPO/config/studio-moser" "$XDG_CONFIG_HOME"
  : > "$REPO/config/studio-moser/model-rubric.yml"

# In link_all(), add:
  ln -s "$REPO/config/studio-moser" "$XDG_CONFIG_HOME/studio-moser"

# Change the first test's count from 5 to 6:
  [ "$(echo "$output" | grep -c ' ok$')" -eq 6 ]
```

New tests at the end of the file:

```bash
@test "config-root entry: missing studio-moser link reported ABSENT" {
  link_all
  rm "$XDG_CONFIG_HOME/studio-moser"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE '^studio-moser +-> +config/studio-moser +ABSENT$'
}

@test "config-root entry: real directory reported REAL-FILE" {
  link_all
  rm "$XDG_CONFIG_HOME/studio-moser"
  mkdir "$XDG_CONFIG_HOME/studio-moser"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE '^studio-moser +-> +config/studio-moser +REAL-FILE$'
}

@test "config-root entry: repo missing the folder reported MISSING-IN-REPO" {
  link_all
  rm -r "$REPO/config"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE '^studio-moser +-> +config/studio-moser +MISSING-IN-REPO$'
}
```

- [ ] **Step 2: Run tests to verify the new ones fail**

```bash
bats ~/Projects/skills-n-stuff/plugins/machine/tests/link-plan.bats
```

Expected: the 3 new tests FAIL (no `studio-moser` line in output) and the count test FAILS (5 ≠ 6). The four untouched tests still pass.

- [ ] **Step 3: Implement — root field in entries + loop**

In `plugins/machine/scripts/link-plan.sh`, replace the header block:

```bash
repo="${1:-$HOME/.agents}"
repo="${repo%/}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
config="${XDG_CONFIG_HOME:-$HOME/.config}"

# "<root>|<name under that root>|<path under repo>"
# roots: claude = $CLAUDE_CONFIG_DIR (default ~/.claude); config = $XDG_CONFIG_HOME (default ~/.config)
entries="claude|skills|skills
claude|CLAUDE.md|claude/CLAUDE.md
claude|settings.json|claude/settings.json
claude|statusline-command.sh|claude/statusline-command.sh
claude|mcp.json|claude/mcp.json
config|studio-moser|config/studio-moser"
```

And the loop head:

```bash
while IFS='|' read -r root name rel; do
  [ -n "$name" ] || continue
  case "$root" in
    claude) base="$claude" ;;
    config) base="$config" ;;
    *) echo "link-plan.sh: unknown root '$root' in entries" >&2; exit 2 ;;
  esac
  link="$base/$name"
  want="$repo/$rel"
```

Everything from the `MISSING-IN-REPO` comment down is unchanged (it already handles directories — `skills` proves it).

- [ ] **Step 4: Run tests to verify they pass**

```bash
bats ~/Projects/skills-n-stuff/plugins/machine/tests/link-plan.bats
```

Expected: all pass, including the 6-count.

- [ ] **Step 5: Commit**

```bash
git add plugins/machine/scripts/link-plan.sh plugins/machine/tests/link-plan.bats
git commit -m "feat(machine): track ~/.config/studio-moser as a sixth synced entry"
```

---

### Task 3: Seed rubric `Default_Rubric.yml`

**Files:**
- Create: `plugins/machine/skills/model-rubric/Default_Rubric.yml`

**Interfaces:**
- Produces: the seed file Tasks 4 and 5 reference by the path above. Schema: model rows keyed by `(name, effort)` with `swe:` (DeepSWE) and `taste:`; `cost: null`, `capabilities: {}`, `routing: {}` are deliberately unusable placeholders.

- [ ] **Step 1: Write the file**

Create `plugins/machine/skills/model-rubric/Default_Rubric.yml`:

```yaml
# Studio Moser seed rubric — the starting point /machine:model-rubric copies before
# the interview. What's here is distributable: taste scores and anti-pattern notes
# are house judgment; swe: is public DeepSWE benchmark data. What's NOT here is
# per-developer: cost, capabilities, and routing — the interview fills those in.
# The null/empty placeholders are invalid on purpose so an unpersonalized copy
# fails loudly instead of silently mis-routing.
seed: true                  # remove this key when personalized
reviewed: null              # interview sets today's date; refresh after 14 days
sources: [seed-2026-08-13]  # interview appends artificial-analysis / deepswe-vX / judgment
capabilities: {}            # interview: one entry per provider/CLI, each verified with command -v
# cost semantics: score what the developer ACTUALLY pays. On a flat subscription the
# scarce resources are quota (token burn) and wall-clock latency — score those, not
# $/task. On metered API, score dollars. NEVER copy another developer's cost scores:
# they encode that developer's subscriptions.
models:
  # Rows are keyed by (name, effort) — the same model at two efforts is two rows,
  # because effort moves agentic quality more than model tier does.
  # swe: DeepSWE agentic SWE score at that effort (https://deepswe.datacurve.ai — no
  # API; re-read the leaderboard when refreshing). Trust swe over AA's coding index
  # for agent work. taste: 1-10, house judgment. via: <cli> = cross-vendor dispatch.
  # At creation, DROP rows whose provider is absent from this developer's capabilities.
  - { name: gpt-5.6-luna,    effort: max,    cost: null, intelligence: 8,  taste: 5,  swe: 67.3, via: codex }
  - { name: gpt-5.6-sol,     effort: low,    cost: null, intelligence: 6,  taste: 7,  swe: 45.5, via: codex }
  - { name: gpt-5.6-sol,     effort: medium, cost: null, intelligence: 8,  taste: 8,  swe: 61,   via: codex }
  - { name: gpt-5.6-sol,     effort: high,   cost: null, intelligence: 9,  taste: 9,  swe: 69.5, via: codex }
  - { name: claude-sonnet-5, effort: high,   cost: null, intelligence: 6,  taste: 7,  swe: 48.2 }
  - { name: claude-opus-5,   effort: high,   cost: null, intelligence: 9,  taste: 9,  swe: 68.7 }
  - { name: claude-opus-5,   effort: max,    cost: null, intelligence: 10, taste: 10, swe: 73.5 }
  - { name: claude-fable-5,  effort: high,   cost: null, intelligence: 10, taste: 10, swe: 72.7 }
routing: {}
# routing is DERIVED from this developer's capabilities + cost at interview time —
# never copied from a seed or another developer. Values are <model>@<effort>.
# House default once populated: taste_min: 9.
# House anti-patterns (effort-curve facts, safe to distribute):
#   - luna below max is worthless for agentic work (swe ~1.5 low / 11.3 medium /
#     44.3 high / 57 xhigh / 67.3 max); at max it's unattended-batch-only (~158s TTFT).
#   - sonnet-5 tops out ~49.6 swe at max — below sol@medium. Where codex exists,
#     reach for sol before Sonnet at every tier.
#   - fable-5@high is the efficient frontier vs opus-5@max: 72.7 vs 73.5 swe at ~40% less burn.
#   - Effort beats tier: raise a model's effort before reaching for a bigger model.
```

- [ ] **Step 2: Verify it parses and the placeholders are present**

```bash
cd ~/Projects/skills-n-stuff
yq -e '.seed == true and .capabilities == {} and .routing == {} and (.models | length == 8)' \
  plugins/machine/skills/model-rubric/Default_Rubric.yml
```

Expected: `true`, exit 0.

- [ ] **Step 3: Commit**

```bash
git add plugins/machine/skills/model-rubric/Default_Rubric.yml
git commit -m "feat(machine): distributable seed rubric — house taste + DeepSWE, per-dev cost/routing left to interview"
```

---

### Task 4: Rewrite `studio-baseline/Rubric_Setup.md` (DeepSWE, effort-aware schema, derived routing, symlink-safe write)

**Files:**
- Modify: `studio-baseline/Rubric_Setup.md` (full rewrite — the schema changed shape)

**Interfaces:**
- Consumes: seed file path from Task 3 (referenced as optional — this doc must keep working with no plugin installed).
- Produces: the canonical walkthrough Task 5's skill defers to. Key contract for Task 7: `models` rows keyed by `(name, effort)`; `routing` values are `<model>@<effort>` strings; routing keys `default, bulk, quick, batch, taste_min, review, independent`.

- [ ] **Step 1: Replace the file's contents**

Keep the title and opening framing; the new body (replacing everything from `The rubric is **per developer, user-global**` onward):

````markdown
The rubric is **per developer, user-global** — one file on this machine, used across every repo:

```
${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml
```

**If that path (or its parent folder) is a symlink, preserve it.** On machines managed
by the `machine` plugin, `~/.config/studio-moser/` links into the developer's private
agents repo so the rubric syncs across their machines. Write *through* the link
(open/edit the file at the path above); never delete and recreate the folder or do an
atomic replace-the-directory — that severs the sync silently.

## Steps

1. **Check if it already exists.** `cat "${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml"`. If present and current, stop — they're set up. If present but stale (>14 days or a listed model is superseded), this is a **refresh**: skip the interview (step 5), re-pull data (steps 2–4), keep their taste scores and `capabilities` unchanged, and update `reviewed:`.

2. **Get them an Artificial Analysis API key (one-time, free).** Check `[ -n "$ARTIFICIAL_ANALYSIS_API_KEY" ]`. If unset, walk them through it before anything else:
   - Sign up at https://artificialanalysis.ai/data-api and generate a free API key — the free tier covers the models endpoint used here.
   - Have them add it to their shell environment so non-interactive shells (agent tooling) inherit it too — e.g. for zsh: `echo 'export ARTIFICIAL_ANALYSIS_API_KEY="<their key>"' >> ~/.zshenv`, then `source ~/.zshenv`. They paste the key themselves; never ask them to paste it into chat, and never commit it anywhere.
   - They can decline — the rubric still works. Fall back to vendor docs / judgment, note it under `sources:`, and offer the key again on the next refresh.

3. **Pull pricing + latency from Artificial Analysis.** If the key is set, run `fetch-model-data.sh` (or curl `https://artificialanalysis.ai/api/v2/language/models/free` with `x-api-key`) for names and pricing. AA's dollar figures inform `cost` for metered developers, and its latency figures inform latency notes — but see step 6 for why dollars alone mislead.

4. **Pull agentic quality from DeepSWE — per effort level.** Fetch https://deepswe.datacurve.ai (a web leaderboard; there is **no API or bulk export** — read the rendered page/chart). Record each candidate model's score **at each effort level** as `swe:`. Two things DeepSWE shows that AA's indices hide:
   - **Effort moves quality more than tier does.** The same model can span worthless-to-frontier across its effort curve. A rubric row is a *(model, effort)* pair, never a bare model.
   - **DeepSWE disagrees sharply with AA on small models** — for agentic SWE work, trust `swe:` over AA's coding index.
   If DeepSWE is unreachable, note that under `sources:` and lean on AA + judgment; re-pull on the next refresh.

5. **Interview the developer — one focused question at a time.** First-time setup is a short Q&A; do NOT open with a pre-scored table (the table comes at the end, as confirmation). Ask in order, adapting wording and skipping anything already known:

   1. **Providers** — which providers/CLIs do they have: Claude Code, OpenAI Codex, Gemini CLI, others? Ask about subscriptions too. Verify each claimed CLI actually resolves (`command -v codex`, `command -v gemini`, …) and record the full set under `capabilities`. Every later question stays inside this set.
   2. **Cost reality** — metered API or flat subscription, per provider? This picks the cost *semantics*, not just the scores: **metered → score dollars per task; flat sub → dollars are irrelevant, score token burn (quota) and wall-clock latency instead.** Record which semantics apply in a comment at the top of the file.
   3. **Trust for hard problems** — which model would they hand the hardest, most ambiguous problem and not supervise? Any model they'd never use?
   4. **Taste** — which model's UI, copy, and API design would they ship with the least editing?
   5. **Working style** — do they wait on agents interactively (latency matters) or fan out unattended batches (throughput matters)? This decides whether a slow-but-free row (e.g. a max-effort batch model) earns a `batch:` route or gets dropped.

6. **Draft the table** — one row per *(model, effort)* pair worth routing to, scored 1–10 on cost / intelligence / taste, with `swe:` carrying the DeepSWE number. Where a **seed rubric** is available (the `machine` plugin ships one at `plugins/machine/skills/model-rubric/Default_Rubric.yml`), start from it: keep its taste scores and anti-pattern notes, **drop rows whose provider isn't in this developer's `capabilities`**, and fill in `cost` from this developer's semantics. Working plugin-free, build the table from steps 3–4 directly. Mark rows reached through a cross-vendor CLI with `via: <cli>`. Show the table and let them tweak — their edits override the seed.

7. **Derive `routing` from the table — never copy it.** Routing names concrete *(model, effort)* pairs as `<model>@<effort>` strings, so it is only valid for the capabilities it was derived from:
   - `default:` the everyday driver — best swe-per-cost among reachable rows.
   - `bulk:` clear-spec / mechanical multi-step work — usually the same as `default`.
   - `quick:` short single-step turns where latency beats depth — a low-effort row.
   - `batch:` unattended fan-out ONLY, and only if a near-free high-swe row exists (omit otherwise; never route interactive work here).
   - `taste_min:` the floor for user-facing work (house default: 9).
   - `review:` plan/implementation reviews — the highest-swe row that isn't wasteful.
   - `independent:` adversarial read of one's own plan/diff — a *different vendor* than the daily driver, so it shares no context or family bias. Only if 2+ providers are in `capabilities`; omit otherwise.

8. **Write the file** to the path above (create the directory if absent — but see the symlink caution at the top), in this shape:

```yaml
# Personal model-routing rubric. Higher = better.
# cost semantics: <flat-sub: token burn + latency | metered: $/task> — set per step 5.2
reviewed: 2026-08-13              # today's date; refresh after 14 days
sources: [artificial-analysis, deepswe-v1.1]   # or [judgment], [seed-...], as applicable
capabilities:
  claude: true
  codex: false                    # each entry verified with command -v
models:
  # (name, effort) pairs; swe: = DeepSWE score at that effort; via: <cli> = cross-vendor
  - { name: <model>, effort: <low|medium|high|xhigh|max>, cost: <1-10>, intelligence: <1-10>, taste: <1-10>, swe: <n> }
routing:
  default: <model>@<effort>
  bulk: <model>@<effort>
  quick: <model>@<effort>
  # batch: <model>@<effort>       # only if an unattended near-free row exists
  taste_min: 9
  review: <model>@<effort>
  # independent: <model>@<effort> # only with 2+ providers; ask before spawning
```

9. **How to apply it** (tell the developer, and follow it yourself when dispatching sub-agents):
   - **Routing values are `<model>@<effort>` — split them on `@`.** If the named row carries `via: <cli>`, dispatch through that CLI's integration (with the pm plugin: its `codex-*` skills) — an Agent-tool call cannot run a cross-vendor model. Otherwise map the model to the Agent tool's tier (`claude-fable-*`→`fable`, `claude-opus-*`→`opus`, `claude-sonnet-*`→`sonnet`, `claude-haiku-*`→`haiku`) and pass the effort through the Agent `effort` parameter.
   - **Pass model AND effort explicitly on every dispatch** — every Agent-tool call and every `agent()` call inside a workflow script. Omitting either silently inherits the session default, and the routing does nothing. This is the one rule that makes the rest of the rubric real.
   - Defaults, not limits — escalate to a stronger row without asking if output misses the bar.
   - Bulk/mechanical/clear-spec → `routing.bulk`. Short latency-sensitive turns → `routing.quick`. User-facing (UI, copy, API) → a row with `taste >= routing.taste_min`. Reviews → `routing.review`. Unattended fan-out → `routing.batch` if set, and never for work someone is waiting on.
   - **Independence is its own axis.** `routing.independent` is for an adversarial read of *your own* plan or diff by a model that hasn't seen your context. Propose it and wait for a yes rather than spawning one unprompted; run it standalone after a workflow finishes, never as a workflow stage.
   - Raise effort before raising tier — on current data, one effort step buys more agentic quality than one model step.
   - Re-check when a newer model ships or after **14 days**, then update `reviewed:`. On refresh, re-pull AA and DeepSWE; **keep taste scores and `capabilities`** — only data-sourced axes change. No re-interview.

That's it — the rubric now lives in your user-global config (and, on machine-plugin-managed setups, syncs across your machines through your agents repo).
````

- [ ] **Step 2: Verify key content landed**

```bash
cd ~/Projects/skills-n-stuff
grep -qF 'deepswe.datacurve.ai' studio-baseline/Rubric_Setup.md \
 && grep -qF '<model>@<effort>' studio-baseline/Rubric_Setup.md \
 && grep -qF 'Default_Rubric.yml' studio-baseline/Rubric_Setup.md \
 && grep -qF 'studio-moser/model-rubric.yml' studio-baseline/Rubric_Setup.md \
 && grep -qF 'preserve it' studio-baseline/Rubric_Setup.md \
 && echo ok
```

Expected: `ok`.

- [ ] **Step 3: Commit**

```bash
git add studio-baseline/Rubric_Setup.md
git commit -m "feat(baseline): effort-aware rubric walkthrough — DeepSWE data, derived routing, symlink-safe writes"
```

---

### Task 5: Update the `model-rubric` skill (seed copy + repo storage decision)

**Files:**
- Modify: `plugins/machine/skills/model-rubric/SKILL.md`

**Interfaces:**
- Consumes: `Default_Rubric.yml` (Task 3), rewritten walkthrough (Task 4), sixth link entry semantics (Task 2).
- Produces: `/machine:model-rubric` behavior — storage decision + seed usage. Task 9 exercises it manually.

- [ ] **Step 1: Insert a storage-decision section**

In `plugins/machine/skills/model-rubric/SKILL.md`, after the `## 1. Check current state` section, insert:

````markdown
## 1.5 Decide where the rubric physically lives

The read path is always `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`.
Storage depends on whether this developer has an agents repo:

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
if [ -d "$repo/.git" ]; then echo "repo"; else echo "plain"; fi
```

- **`repo`** → the folder belongs in the repo so it syncs across machines. Ensure
  `$config/studio-moser` is a symlink to `$repo/config/studio-moser`:
  - Already a correct symlink → nothing to do.
  - A real directory → move it into the repo, then link:
    `mkdir -p "$repo/config" && mv "$config/studio-moser" "$repo/config/studio-moser" && ln -s "$repo/config/studio-moser" "$config/studio-moser"`.
    Then ensure `$repo/.gitignore` contains `config/studio-moser/*.bak*`, and commit + push the repo.
  - Absent → `mkdir -p "$repo/config/studio-moser" && ln -s "$repo/config/studio-moser" "$config/studio-moser"`.
  `/machine:sync` verifies this link on every run (it is one of the six tracked entries).
- **`plain`** → no repo on this machine; write to `$config/studio-moser/` as a real
  directory (`mkdir -p`). Everything else proceeds identically.

**Never replace the symlink with a real file/folder when writing or refreshing** — edit
the file through the link. An atomic-replace of the directory severs sync silently.
````

- [ ] **Step 2: Add the seed instruction to section 2**

In the same file's `## 2. Follow the canonical walkthrough` section, after the two existing plugin-specific notes, add a third:

```markdown
- Where the walkthrough offers a **seed rubric**, use this plugin's copy:
  `"$machine/skills/model-rubric/Default_Rubric.yml"`. Copy it to the target path
  as the starting table, then follow the walkthrough's rules: drop rows whose
  provider isn't in this developer's `capabilities`, fill `cost` from their cost
  semantics, derive `routing` fresh, remove the `seed:` key, and set `reviewed:`
  to today. A file still containing `seed: true`, `cost: null`, or `routing: {}`
  is NOT set up — `--check` may pass on it, so verify these keys are gone.
```

Also update the frontmatter `description:` — replace `Lives at ${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml, one per developer, shared across every repo.` with `Lives at ${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml, one per developer; on machines with an agents repo the folder is a symlink into it, so the rubric syncs across machines.` (Trigger list already updated to `/machine:model-rubric` by Task 1.)

- [ ] **Step 3: Verify**

```bash
cd ~/Projects/skills-n-stuff
grep -qF 'Default_Rubric.yml' plugins/machine/skills/model-rubric/SKILL.md \
 && grep -qF 'AGENTS_REPO' plugins/machine/skills/model-rubric/SKILL.md \
 && grep -qF 'Never replace the symlink' plugins/machine/skills/model-rubric/SKILL.md \
 && echo ok
```

Expected: `ok`.

- [ ] **Step 4: Commit**

```bash
git add plugins/machine/skills/model-rubric/SKILL.md
git commit -m "feat(machine): model-rubric skill — seed copy + agents-repo storage with symlink read path"
```

---

### Task 6: Update the `sync` skill docs for the sixth entry

**Files:**
- Modify: `plugins/machine/skills/sync/SKILL.md`

**Interfaces:**
- Consumes: Task 2's entries format and output.
- Produces: Phase 1 documentation that matches `link-plan.sh` reality.

- [ ] **Step 1: Update the wording and the Phase 1 mechanics**

All in `plugins/machine/skills/sync/SKILL.md` (line numbers are pre-Task-1; use the quoted strings to locate):

1. Line ~123, in the REAL-FILE table row: replace `` (or directory — `skills` is one of the five tracked entries) `` with `` (or directory — `skills` and `studio-moser` are directories among the six tracked entries) ``.
2. Line ~138: replace `the five states are not independent signals` with `the six states are not independent signals` **only if** that sentence counts entries; read it first — if "five states" refers to the five *state names* (ok/ABSENT/REAL-FILE/RELINK/MISSING-IN-REPO), leave it alone.
3. In the create/re-link section (around the `ln -sfn` block at ~line 225), add after the existing target-must-be-absolute paragraph:

```markdown
**The `studio-moser` entry lives under `${XDG_CONFIG_HOME:-$HOME/.config}`, not `$claude`.**
For it, the link is `"${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser"` and the target is
`"$repo/config/studio-moser"`. Create the parent first — `mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}"` —
a fresh machine may not have it. The REAL-FILE diff/keep/merge procedure applies to it exactly
as it does to `skills` (both are directories). When keeping the machine's copy, also ensure
`$repo/.gitignore` covers `config/studio-moser/*.bak*` so local backup files never sync.
```

4. In Phase 0, after the `repo=` block's explanation, no change needed (Task 1 already renamed `FLEET_REPO`→`AGENTS_REPO`); just verify.

- [ ] **Step 2: Verify**

```bash
cd ~/Projects/skills-n-stuff
grep -qF 'six tracked entries' plugins/machine/skills/sync/SKILL.md \
 && grep -qF 'config/studio-moser/*.bak*' plugins/machine/skills/sync/SKILL.md \
 && grep -qF 'AGENTS_REPO' plugins/machine/skills/sync/SKILL.md \
 && ! grep -qF 'FLEET_REPO' plugins/machine/skills/sync/SKILL.md \
 && echo ok
```

Expected: `ok`.

- [ ] **Step 3: Commit**

```bash
git add plugins/machine/skills/sync/SKILL.md
git commit -m "docs(machine): sync skill — document the studio-moser config entry"
```

---

### Task 7: pm consumers — dispatch `model@effort` routing correctly

**Files:**
- Modify: `plugins/pm/references/model-orchestration.md`, `plugins/pm/references/triage-scorecard.md`, `plugins/pm/skills/dev-task/SKILL.md`, `plugins/pm/skills/sprint-dev/SKILL.md`, `plugins/pm/skills/ingest/SKILL.md`, `plugins/pm/README.md`, `plugins/pm/.claude-plugin/plugin.json`

**Interfaces:**
- Consumes: routing contract from Task 4 (`<model>@<effort>` strings, `(name, effort)`-keyed rows, keys `default/bulk/quick/batch/taste_min/review/independent`).
- Produces: every pm dispatch instruction parses routing values instead of passing them verbatim.

- [ ] **Step 1: Add the canonical dispatch procedure to model-orchestration.md**

In `plugins/pm/references/model-orchestration.md`, after the "What lives where" list, insert a new section:

````markdown
## Dispatching a routing value

Rubric routing values are `<model>@<effort>` strings (e.g. `sol-class-model@medium`), and
`models:` rows are keyed by *(name, effort)* — the same model may appear at several efforts.
To dispatch one:

1. Split the value on `@` → model name + effort.
2. Find the `models:` row matching both. If it carries `via: <cli>` (e.g. `via: codex`),
   dispatch through that CLI's skills (`pm:codex-implementation`, `pm:codex-review`,
   `pm:codex-computer-use`) — the Agent tool cannot run cross-vendor models, and passing
   the raw string as `model` is an error.
3. Otherwise map the name to the Agent tool tier — `claude-fable-*`→`fable`,
   `claude-opus-*`→`opus`, `claude-sonnet-*`→`sonnet`, `claude-haiku-*`→`haiku` — and pass
   the effort through the Agent `effort` parameter (`low|medium|high|xhigh|max`).
4. Pass **both** explicitly on every dispatch. Omitting either inherits the session
   default and silently defeats the routing.

Routing keys: `default` (everyday driver), `bulk` (clear-spec mechanical), `quick`
(latency-sensitive single steps), `batch` (unattended fan-out only — never route work
someone is waiting on), `taste_min` (floor for user-facing work), `review`,
`independent` (cross-vendor adversarial read — ask before spawning).
````

- [ ] **Step 2: Fix each consumer's dispatch sentence**

Exact replacements (locate by the quoted current text):

1. `plugins/pm/references/triage-scorecard.md` (~line 9): replace `pass `model` explicitly, set to `routing.bulk` from the rubric (`${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`). Omitting `model` inherits the session model.` with `dispatch `routing.bulk` from the rubric (`${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`) per the dispatch procedure in `references/model-orchestration.md` — split the `model@effort` value, route `via: codex` rows through the codex skills, and pass model + effort explicitly. Omitting them inherits the session defaults.`
2. `plugins/pm/skills/ingest/SKILL.md` (~line 144): same replacement pattern as (1) — replace the `pass `model` explicitly, set to `routing.bulk` … inherits the session model and burns a frontier tier on mechanical extraction.` sentence with `dispatch `routing.bulk` from the rubric (`${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`) per the dispatch procedure in `references/model-orchestration.md` (split `model@effort`; `via: codex` rows go through the codex skills; pass model + effort explicitly — omitting them burns a frontier tier at frontier effort on mechanical extraction).`
3. `plugins/pm/skills/dev-task/SKILL.md` (~line 58): replace `pass `model` explicitly, set to `routing.review` from the rubric (`${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`); omitting it inherits the session model.` with `dispatch `routing.review` from the rubric (`${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`) per `references/model-orchestration.md`'s dispatch procedure — split the `model@effort` value, honor `via:`, pass model + effort explicitly.`
4. `plugins/pm/skills/sprint-dev/SKILL.md` (~line 271): in the altitude paragraph, replace `Pass the chosen model via the `Agent` `model` parameter;` with `Dispatch the chosen `model@effort` routing value per `references/model-orchestration.md` (split it; `via: codex` rows dispatch through the codex skills; natives pass Agent `model` tier + `effort`);`
5. `plugins/pm/skills/sprint-dev/SKILL.md` (~line 307): replace `**always pass it explicitly** — omitting `model` inherits the session model, which silently defeats the routing. Clear-spec/mechanical batches → `routing.bulk`; user-facing batches (UI, copy, API surface) → a model with `taste >= routing.taste_min`.` with `**always dispatch per `references/model-orchestration.md`** — split each `model@effort` value, honor `via:`, and pass model + effort explicitly; omitting either inherits session defaults and silently defeats the routing. Clear-spec/mechanical batches → `routing.bulk`; latency-sensitive single steps → `routing.quick`; unattended fan-out → `routing.batch` (only if set — never for attended work); user-facing batches (UI, copy, API surface) → a row with `taste >= routing.taste_min`.`
6. `plugins/pm/references/model-orchestration.md` (~line 34): in the illustration paragraph, append after `looked up live at setup time, not from training-cutoff memory):` the sentence ` Rubric rows are keyed by (name, effort) and routing values are `model@effort` — see "Dispatching a routing value" above.`
7. `plugins/pm/README.md` (~line 30): replace `scored on cost/intelligence/taste, and re-checked on a 14-day cadence` with `scored per (model, effort) pair on cost/intelligence/taste plus DeepSWE agentic data, and re-checked on a 14-day cadence`.
8. `plugins/pm/.claude-plugin/plugin.json`: `"version": "0.16.1"` → `"version": "0.17.0"`.

- [ ] **Step 3: Verify no consumer still instructs passing a routing value as `model` verbatim**

```bash
cd ~/Projects/skills-n-stuff
grep -rn 'set to `routing\.' plugins/pm/ && echo "LEFTOVERS" || echo clean
grep -qF 'Dispatching a routing value' plugins/pm/references/model-orchestration.md && echo ok
grep -rn 'routing.quick\|routing.batch' plugins/pm/skills/sprint-dev/SKILL.md | head -3
```

Expected: `clean`, `ok`, and the sprint-dev hits present.

- [ ] **Step 4: Commit**

```bash
git add plugins/pm/
git commit -m "feat(pm): dispatch model@effort routing values — via:codex branch, Agent tier+effort mapping"
```

---

### Task 8: Migrate this machine — rubric folder into the agents repo

**Files (outside this git repo — live machine config):**
- Move: `~/.config/studio-moser/` → `~/.agents/config/studio-moser/`, then symlink
- Modify: `~/.agents/.gitignore`, adopt `~/Desktop/Model Rubric.yml` as the live rubric
- Verify with: `plugins/machine/scripts/link-plan.sh`

**Interfaces:**
- Consumes: Task 2's sixth entry (for verification).
- Produces: a synced rubric — the state every other machine converges to via `/machine:sync`.

- [ ] **Step 1: Adopt the newer rubric from Desktop**

The Desktop file (`reviewed: 2026-08-13`) supersedes the local one (`2026-08-12`); keep the old as a gitignored `.bak`:

```bash
config="${XDG_CONFIG_HOME:-$HOME/.config}"
cp "$config/studio-moser/model-rubric.yml" "$config/studio-moser/model-rubric.yml.bak-pre-sync"
cp "$HOME/Desktop/Model Rubric.yml" "$config/studio-moser/model-rubric.yml"
```

- [ ] **Step 2: Move the folder into the repo and link back**

Run as ONE block (a failure midway leaves the config folder moved but unlinked — if that happens, finish the `ln -s` by hand before anything else):

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
mkdir -p "$repo/config"
mv "$config/studio-moser" "$repo/config/studio-moser"
ln -s "$repo/config/studio-moser" "$config/studio-moser"
grep -qxF 'config/studio-moser/*.bak*' "$repo/.gitignore" || printf 'config/studio-moser/*.bak*\n' >> "$repo/.gitignore"
```

- [ ] **Step 3: Verify link-plan reports six ok and the rubric reads through the link**

```bash
~/Projects/skills-n-stuff/plugins/machine/scripts/link-plan.sh "$HOME/.agents"
grep -q '^reviewed: 2026-08-13' "${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml" && echo rubric-ok
```

Expected: six `ok` lines, exit 0; `rubric-ok`. (grep, not yq — unquoted YAML dates parse as date values, so a string compare false-fails.)

- [ ] **Step 4: Commit and push the agents repo**

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
git -C "$repo" add -A
git -C "$repo" status --short   # expect config/studio-moser/model-rubric.yml + .gitignore, NO .bak files
git -C "$repo" commit -m "config: adopt studio-moser folder — model rubric now syncs across machines"
git -C "$repo" push
```

Expected in `status --short`: exactly the rubric + `.gitignore`; if any `.bak` appears, fix the gitignore before committing.

---

### Task 9: Final verification + ship

**Files:**
- Modify: none new — full-suite run, README check, merge.

- [ ] **Step 1: Full test suite + portability lint**

```bash
cd ~/Projects/skills-n-stuff
bats plugins/machine/tests/
plugins/machine/scripts/portability-lint.sh "$HOME/.agents"
```

Expected: all bats pass; lint clean (the rubric contains no `/Users/<name>` literals — verify, since it now syncs).

- [ ] **Step 2: Self-review greps across the whole change**

```bash
cd ~/Projects/skills-n-stuff
grep -rn 'fleet' plugins/ studio-baseline/ .claude-plugin/ README.md | grep -v '.fleet-local.json' | grep -v 'fleet:skills' && echo LEFTOVERS || echo clean
grep -rc 'studio-moser/model-rubric.yml' plugins/pm/ plugins/machine/ studio-baseline/ | grep -v ':0'   # read path intact everywhere
```

- [ ] **Step 3: Merge and push**

```bash
git checkout main && git merge --no-ff machine-plugin-rubric-sync && git push
```

- [ ] **Step 4: Post-merge actions (manual, per machine — tell the user)**

1. This machine + every other: `/plugin uninstall fleet` then `/plugin install machine@studio-moser` (cache paths are keyed by plugin name; the old cache entry is dead).
2. Other machines: run `/machine:sync` — it pulls the repo, finds `config/studio-moser` in it, sees the local state (`REAL-FILE` if a locally-created rubric exists), and walks the diff/keep/re-link flow. Their old rubric becomes the machine's `.bak`; the synced one takes over.
3. Any shell profile exporting `FLEET_REPO` → rename to `AGENTS_REPO`.
4. Project repos with stamped AGENTS.md baseline blocks still say `/fleet:model-rubric` — re-run `/pm:setup` in each to restamp (stale blocks are cosmetic until then; the rubric path they reference is unchanged).
5. `raw.githubusercontent.com/...` URLs in stamped blocks point at `studio-baseline/Rubric_Setup.md` — path unchanged, nothing to do.
