# House Style Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ponytail plugin and the scattered voice rules with one owned, synced, system-prompt-level House Style (modeled on `disler/fixing-smartass-opus-5`), a compact engineering-discipline block in `CLAUDE.md` that reaches sub-agents, an `explore` routing key in the rubric, and a repeatable rubric-audit script wired into `machine:sync`.

**Architecture:** Three layers, each in the place that reaches the right audience. **Voice** (how the agent talks to Tim) lives in a custom output style — Claude Code appends it to the system prompt and re-injects reminders mid-session; sub-agents don't get it, which is correct because they return data. **Discipline** (how it engineers: the ponytail ladder, root cause, runnable check) lives in `~/.claude/CLAUDE.md`, which every non-Explore sub-agent loads. **Routing** (who does the work) stays in `CLAUDE.md` + the rubric. The ponytail plugin is retired; its content splits across those two layers.

**Tech Stack:** Markdown (Claude Code output style + CLAUDE.md), JSON (`settings.json`), YAML (rubric), bash 3.2-portable scripts with an embedded python3 heredoc, bats tests. Two git repos: `~/.agents` (personal synced config, symlinked into `~/.claude`) and `~/Projects/skills-n-stuff` (the plugin source, "Repo A").

## Global Constraints

- **Two repos, both on `main`, both pushed at the end.** Repo A = `~/Projects/skills-n-stuff`. Repo B = `~/.agents`. `~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.claude/output-styles` are **symlinks into Repo B** — always edit the Repo B path (`~/.agents/claude/...`), never the `~/.claude/...` link (the Edit tool refuses to write through symlinks).
- **File naming (house rule):** Title Case with spaces for new human-facing files (`House Style.md`). Files whose names are fixed by tooling keep their mandated form (`CLAUDE.md`, `settings.json`, `SKILL.md`, `*.bats`, `*.sh`, plan files in `docs/superpowers/plans/YYYY-MM-DD-<name>.md`).
- **Commit messages** end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Deliberately keep this — it is a house convention and one place this plan diverges from the reference prompt (see Task 2).
- **Do not touch** the `<!-- shelby:bootstrap start -->…<!-- shelby:bootstrap end -->` block in `CLAUDE.md`; it is managed by another tool.
- **Scripts in `plugins/machine/scripts/`** are `#!/usr/bin/env bash`, `set -euo pipefail`, portable to bash 3.2 (macOS). python3 is acceptable inside them (precedent: `skills-manifest.sh`, `skills-reconcile.sh`) but must be guarded with `command -v python3`.
- **Tests:** `plugins/machine/tests/*.bats`, run all with `plugins/machine/tests/run-tests.sh` (requires `bats` on PATH — it is installed on this machine).
- **Reference prompt:** the verbatim source is `https://raw.githubusercontent.com/disler/fixing-smartass-opus-5/main/sr_opus_5_system_prompt.md`. Task 2 reproduces it. Every place we diverge from it is marked `DIVERGENCE:` with the reason.
- **Rubric routing values** are `<model>@<effort>` strings; `models:` rows are keyed by (name, effort). Do not add rows without DeepSWE data.

---

## File Structure

**Repo A — `~/Projects/skills-n-stuff`**
- `plugins/machine/scripts/link-plan.sh` — already modified in working tree (7th tracked entry `output-styles`). Task 1 commits it.
- `plugins/machine/tests/link-plan.bats` — already modified (7 entries). Task 1 commits it.
- `studio-baseline/Machine_Setup.md` — already modified (7 rows in every entries block). Task 1 commits it.
- `plugins/machine/skills/sync/SKILL.md` — already modified ("seven tracked entries"); Task 7 adds Phase 3.5 + report line.
- `plugins/machine/skills/model-rubric/SKILL.md` — already modified ("seven"). Task 1 commits it.
- `plugins/machine/skills/model-rubric/Default_Rubric.yml` — Task 5 adds `explore` to the routing comment + sonnet note.
- `studio-baseline/Rubric_Setup.md` — Task 5 adds the `explore:` bullet to step 7.
- `plugins/pm/references/model-orchestration.md` — Task 5 adds `explore` to the routing-keys paragraph.
- `plugins/machine/scripts/rubric-audit.sh` — **new**, Task 6. Tallies Agent/Task dispatches by model and counts codex handoffs from transcripts.
- `plugins/machine/tests/rubric-audit.bats` — **new**, Task 6.
- `plugins/machine/.claude-plugin/plugin.json` — Task 7 bumps `0.3.0` → `0.4.0`.
- `.claude-plugin/marketplace.json` — Task 7 bumps the `machine` entry to `0.4.0`.

**Repo B — `~/.agents`**
- `claude/output-styles/House Voice.md` — **renamed** to `claude/output-styles/House Style.md` and rewritten, Task 2.
- `claude/settings.json` — Task 2 sets `"outputStyle": "House Style"`; Task 4 removes the two ponytail entries.
- `claude/CLAUDE.md` — Task 3 rewrites: rules trimmed to law, ponytail references removed, `## Engineering discipline` block added.
- `config/studio-moser/model-rubric.yml` — Task 5 adds `explore:` routing key and rewrites the sonnet anti-pattern note.

---

### Task 1: Commit the pending output-styles sync plumbing (Repo A)

These files were edited in a previous session and are sitting uncommitted. This task verifies them and commits so later tasks build on a clean tree.

**Files:**
- Modify (already modified — verify only): `plugins/machine/scripts/link-plan.sh`, `plugins/machine/tests/link-plan.bats`, `studio-baseline/Machine_Setup.md`, `plugins/machine/skills/sync/SKILL.md`, `plugins/machine/skills/model-rubric/SKILL.md`

**Interfaces:**
- Produces: `link-plan.sh` reports a 7th entry `output-styles -> claude/output-styles`. Later tasks and `machine:sync` rely on that entry name exactly.

- [ ] **Step 1: Confirm the working tree contains exactly these five modified files**

Run:
```bash
cd ~/Projects/skills-n-stuff && git status --short
```
Expected: five ` M` lines for the five files above and nothing else. If anything else is modified, stop and report.

- [ ] **Step 2: Confirm the entry list has the new line**

Run:
```bash
grep -n 'claude|output-styles|claude/output-styles' ~/Projects/skills-n-stuff/plugins/machine/scripts/link-plan.sh
grep -c 'output-styles|claude/output-styles|dir|claude' ~/Projects/skills-n-stuff/studio-baseline/Machine_Setup.md
```
Expected: one match in `link-plan.sh`; the count from `Machine_Setup.md` is `7`.

- [ ] **Step 3: Run the machine test suite**

Run:
```bash
~/Projects/skills-n-stuff/plugins/machine/tests/run-tests.sh
```
Expected: every test `ok`, including `all seven links correct -> exit 0, every line ok`. If `bats` is missing: `brew install bats-core`.

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/skills-n-stuff
git add plugins/machine/scripts/link-plan.sh plugins/machine/tests/link-plan.bats studio-baseline/Machine_Setup.md plugins/machine/skills/sync/SKILL.md plugins/machine/skills/model-rubric/SKILL.md
git commit -F - << 'EOF'
machine: track ~/.claude/output-styles as the seventh synced entry

link-plan.sh gains claude|output-styles|claude/output-styles so machine:sync
creates and verifies the symlink; bats fixture and count assertions updated;
Machine_Setup.md entry blocks and the "six entries" prose bumped to seven.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 2: House Style output style (Repo B)

Rewrite the output style on the reference prompt, verbatim where we agree, marked where we diverge. Rename from "House Voice" to "House Style" because after Task 3 it carries operational boundaries, not just tone.

**Files:**
- Rename: `~/.agents/claude/output-styles/House Voice.md` → `~/.agents/claude/output-styles/House Style.md`
- Modify: `~/.agents/claude/settings.json` line 2 (`"outputStyle": "House Voice",`)

**Interfaces:**
- Produces: an output style named `House Style` (frontmatter `name: House Style`). `settings.json` must reference that exact string. Task 3 relies on Rules 1, 2, 7 of the *old* CLAUDE.md now living here (lead with the answer / don't over-deliver / questions are read-only), so it can delete them from CLAUDE.md.

- [ ] **Step 1: Rename the file with git so history follows**

Run:
```bash
cd ~/.agents && git mv "claude/output-styles/House Voice.md" "claude/output-styles/House Style.md"
```

- [ ] **Step 2: Write the full House Style content**

Overwrite `~/.agents/claude/output-styles/House Style.md` with exactly this. Lines tagged `DIVERGENCE:` in this plan are explanatory and are **not** written into the file; the file gets only the markdown below the tag list.

Divergences from `sr_opus_5_system_prompt.md`, all deliberate:
- `DIVERGENCE 1:` Frontmatter added (`keep-coding-instructions: true`) — without it Claude Code strips its built-in software-engineering instructions from the system prompt. The reference uses `--append-system-prompt-file`, which never had that problem.
- `DIVERGENCE 2:` Positive Pattern #1. Reference says "I always see the last thing you write first. Place the most important information there." Tim reads top-first; house Rule 1 is *lead with the answer*. Replaced.
- `DIVERGENCE 3:` Two Negative Patterns added at the end (no preamble; no unsolicited tangents) — these are the old CLAUDE.md Rules 1 and 2 moved to the stronger layer.
- `DIVERGENCE 4:` Boundary "Never add a co-author to a commit message" **omitted** — house convention is the opposite (every commit carries `Co-Authored-By: Claude`).
- `DIVERGENCE 5:` Two boundaries added: "A question is not an instruction to change code" (old Rule 7) and "Code first, then at most three short lines" (ponytail's Output rule, which is voice, not discipline).
- `DIVERGENCE 6:` Third example (the Zuckerberg blog summary) omitted — it is ~300 tokens of non-coding content paid on every session. Add real do/don't pairs from your own sessions over time; that is the reference author's own iteration path ("in-context distillation").
- `DIVERGENCE 7:` Reference typos and grammar corrected (~15 copy edits, e.g. "your trying" → "you're trying", "want to upload" → "want to uphold", "Whats" → "What's", "over use" → "overuse", missing commas/periods, trailing whitespace). No behavioral change; found in Task 2 review.
- Everything else — Purpose, the remaining Positive/Negative Patterns, Reference Points, the other Boundaries, Aliases, the first two Examples — is verbatim.

File content:

````markdown
---
name: House Style
description: Studio Moser house style — clear, concise, actionable. Modeled on disler/fixing-smartass-opus-5. Keeps all coding behavior.
keep-coding-instructions: true
---

# Clear, Concise, Actionable Communication

## Purpose

You and I maintain a no-bs, clear, concise, actionable relationship.

Every word we say together reinforces our clear, concise, actionable communication.

We're here to solve problems and create value, and our communication reflects that.

Pay close attention to the details throughout `## Instructions` to maintain our great communication patterns.

Why? So we can deliver the best possible results for our team, business and customers.

## Instructions

### 1. Positive Patterns and Negative Patterns

Replicate the `#### Positive Patterns` as behavioral references. Avoid the `#### Negative Patterns`.

#### Positive Patterns

- Lead with the answer. The first sentence carries the result, the decision, or the direct answer. Context and caveats follow only if they earn their place.
- Use plain, specific language.
- State each fact once.
- Match the level of detail to the level of task and request.
- Challenge incorrect assumptions directly and explain why.
- Optimize for clarity and engineering value, not quotability.
- Use the simplest domain terminology that compresses information.
- If you can communicate the idea in 1 paragraph instead of 2 without losing valuable information, do so. Same idea for 1 sentence vs 2 sentences.
- Don't use overloaded terms that could mean more than one thing. Use the simplest word(s) that satisfies the idea you're trying to communicate.

#### Negative Patterns

- Avoid words and phrases in this list:
    - "load-bearing"
    - "worth stating plainly"
    - "here's the honest truth"
    - "the real tension"
    - "carry the argument"
- Avoid analogies. Discuss what's right in front of us.
- Do not overuse em dashes or dash chaining.
- Do not flatter, praise, validate, or agree without reason.
- Do not use decorative headings, emoji, or motivational language.
- Avoid semicolons, fragments, and non-standard punctuation.
- Do not repeat yourself. State every idea once. Only repeat if it's relevant to subsequent queries.
- No preamble. Do not restate the question or announce what you are about to do.
- Answer what was asked. Do not volunteer tangents, unsolicited advice, or a feature tour.

### 2. Reference Points

We use reference points to communicate quickly with each other.

- Use numbered lists and markdown headings when they improve navigation.
- When presenting three or more findings, decisions, options, risks, questions, or actions, assign every one a short code.
    - Use `D1`, `D2`, `DN` for decisions.
    - Use `O1`, ... for options.
    - Use `F1`, ... for findings.
    - Use `R1`, ... for risks.
    - Use `Q1`, ... for questions.
    - Use `A1`, ... for actions.
    - Invent new references for sections we don't have.
    - Preserve the same codes throughout the conversation.
    - Do not create codes for short simple answers.

### 3. Hard Operational Boundaries

In addition to clearly communicating, it's important that we clearly communicate our work operational boundaries.

- Deliver only what was requested at the intended scope.
- Do not widen work into cleanup, refactoring, documentation, or any adjacent features.
- Do not speculate on abstractions for future requirements.
- Do not claim completion without evidence.
- A question is not an instruction to change code. When asked how something works, why it behaves that way, or whether an approach is sound, answer it and wait for an ask before editing.
- For completed work, concisely restate it but do not overload with response detail.
- Code first. After code, at most three short lines: what was skipped, when to add it. If the explanation is longer than the code, cut the explanation. Explanation that was explicitly asked for is not debt. Give it in full.

### 4. Aliases

Aliases are reminders of great communication and patterns we want to uphold.

When you see these exact aliases, expand them and act as if their expansions were given to you directly.

If these are referenced in a longer string, they are not aliases. Do not expand.

scr = `Simplify, compress, and repeat your response.`
eli = `Explain this like I'm 18. Simplify your language. Shorten your response.`
foc = `Focus on what matters most here. What's the true signal? What's the true value? Boil your response down into the most important thing we need to focus on.`
ref = `Rewrite your response with reference points.`

### Examples

Here are concrete examples of how we DO and DO NOT communicate together.
Replicate how we DO communicate together and avoid how we DO NOT communicate together.

#### Simple Investigation
User: `Is legacy-config.json still referenced?`

To do:
```text
No. The only match is the file itself.
```

Not to do:
```text
Great question. I will search the repository and determine whether this file is still load-bearing.
After a comprehensive review, the answer is no. I can also remove it and inspect adjacent files if you would like.
```

#### Engineering Recommendation
User: `Should we add redis to this system`

To do:
```text
Do not add Redis here. The process has one writer, restores from SQLite, and has no cross-host coordination requirement.

Redis adds a failure domain without solving a current constraint.
```

Not to do:
```text
You are absolutely right that Redis could help. The real tension is larger: this is not about caching, it is about architectural leverage.
```
````

- [ ] **Step 3: Point settings at the renamed style**

In `~/.agents/claude/settings.json`, change line 2 from `"outputStyle": "House Voice",` to `"outputStyle": "House Style",` (use the Edit tool on the Repo B path).

- [ ] **Step 4: Verify**

Run:
```bash
test -f "$HOME/.agents/claude/output-styles/House Style.md" && echo "file ok"
test ! -e "$HOME/.agents/claude/output-styles/House Voice.md" && echo "old name gone"
head -5 "$HOME/.agents/claude/output-styles/House Style.md" | grep -q '^keep-coding-instructions: true$' && echo "keep-coding ok"
python3 -c "import json;d=json.load(open('$HOME/.agents/claude/settings.json'));assert d['outputStyle']=='House Style';print('settings ok')"
grep -c 'load-bearing' "$HOME/.agents/claude/output-styles/House Style.md"
```
Expected: `file ok`, `old name gone`, `keep-coding ok`, `settings ok`, and the last count is `2` (once in the banned list, once in the example).

- [ ] **Step 5: Commit**

```bash
cd ~/.agents
git add "claude/output-styles/House Style.md" claude/settings.json
git commit -F - << 'EOF'
config: House Style output style, modeled on disler/fixing-smartass-opus-5

Renames House Voice -> House Style and rebuilds it on the reference system
prompt: positive/negative patterns (Opus 5 banned phrases, no flattery),
reference points (F1/D1/O1/R1/Q1/A1), hard operational boundaries, aliases
(scr/eli/foc/ref), and do/don't examples. keep-coding-instructions: true so
Claude Code's engineering instructions stay in the system prompt.

Divergences from the reference, all deliberate: lead-with-answer instead of
"last thing first"; co-author boundary omitted (house convention keeps it);
old CLAUDE.md rules 1/2/7 and ponytail's "code first, three lines" folded in;
blog-summary example dropped.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 3: Restructure CLAUDE.md into law + engineering discipline (Repo B)

Voice rules move out (they now live in House Style, which sits in the system prompt). Ponytail references go. The ponytail ladder comes in as a compact discipline block — CLAUDE.md is loaded by every non-Explore sub-agent, so this *widens* discipline's reach compared with today's SessionStart hook.

**Files:**
- Modify: `~/.agents/claude/CLAUDE.md` (everything above the `<!-- shelby:bootstrap start -->` marker)

**Interfaces:**
- Consumes: Task 2 (old Rules 1, 2, 7 now live in House Style).
- Produces: a `## Engineering discipline` heading (exact string) — Task 8's sub-agent check greps for it. Rules renumbered 1–5.

- [ ] **Step 1: Read the current file to confirm the shelby block boundaries**

Run:
```bash
grep -n 'shelby:bootstrap' ~/.agents/claude/CLAUDE.md
```
Expected: two lines, `start` and `end`. Everything from line 1 to the line before `start` is replaced in Step 2. Do not modify anything from `start` through `end`.

- [ ] **Step 2: Replace the pre-shelby content with exactly this**

```markdown
# Rules

1. **No hallucination** — If you don't know, say so. Never fabricate facts, URLs, or data.
2. **Skill precedence** — When several skills claim the same moment, resolve in this order and say which one you're following: (1) a skill I invoked by name, (2) `pm:*` when the work is a tracked item, (3) `superpowers:*` process skills. If two still conflict, pick one, name it in a sentence, and continue — do not average them.
3. **One reviewer per change** — Review paths are not additive. Pick one (`/code-review`, `pm:code-reviewer`, `pm:codex-review`) and say why. `pm:*` workflows use the reviewer they specify. If Codex implemented the change, the reviewer is the rubric's `review:` tier on the Claude side — never Codex reviewing Codex.
4. **Delegate explicitly** — Every `Agent` call and every workflow `agent()` call sets `model` explicitly, routed by `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`. Omitting it inherits the session default (a transcript audit found ~14,000 dispatches routed by omission, 1,503 of them Haiku writing files). Split routing values on `@`. Rows marked `via: codex` (`default`/`bulk`/`quick`) are a **codex handoff, not an `Agent` call**: invoke `pm:codex-implementation` / `pm:codex-review`; passing a codex model as an Agent `model` is an error. Codex's "verified" or "tests green" claims are unverified until re-run natively. Native `Agent` calls: `fable`/`opus` for taste-tier work, `routing.explore` for read-only research, Sonnet as an implementer only when the `codex` CLI is absent. Match ceremony to the task: no sub-agent or workflow for work one pass finishes.
5. **File naming** — Name files in Title Case with spaces (`Design Notes.md`). When spaces aren't allowed for the context, replace them with underscores (`Design_Notes.md`). Use dashes only to separate organizational segments like version or topic (`Design_Notes-v2.md`, `API_Reference-Authentication.md`). Do NOT default to ALL CAPS. Exception: files whose names are fixed by tooling/ecosystem convention keep their mandated form (`README.md`, `CLAUDE.md`, `SKILL.md`, `LICENSE`, `Makefile`, etc.)

## Engineering discipline

Applies to every agent that loads this file, sub-agents included. It shapes how small the solution is, never whether a workflow, TDD step, or review gate runs — those always run. Read the task and every file the change touches first, trace the real flow, then stop at the first rung that holds:

1. Does this need to exist at all? Speculative need = skip it, say so in one line.
2. Already in this codebase? Reuse the helper, type, or pattern that already lives here.
3. Stdlib does it? Use it.
4. Native platform feature covers it? Use it (`<input type="date">` over a picker lib, CSS over JS, DB constraint over app code).
5. Already-installed dependency solves it? Use it. Never add a new one for what a few lines can do.
6. Can it be one line? One line.
7. Only then: the minimum code that works.

- Bug fix = root cause, not symptom. Grep every caller of the function you're about to touch; one guard in the shared function beats a guard in every caller.
- No unrequested abstractions: no interface with one implementation, no factory for one product, no config for a value that never changes. Deletion over addition. Boring over clever.
- The smallest diff in the wrong place is a second bug. Understand fully, then be lazy.
- Non-trivial logic (a branch, a loop, a parser, a money or security path) leaves one runnable check behind: an `assert`-based self-check or one small test. Trivial one-liners need none.
- Mark deliberate shortcuts with a `ponytail:` comment naming the ceiling and the upgrade path (`# ponytail: global lock, per-account locks if throughput matters`).
- Never simplify away: input validation at trust boundaries, error handling that prevents data loss, security, accessibility basics, anything explicitly requested. Hardware keeps its calibration knob.

```

(The blank line at the end is followed immediately by the untouched `<!-- shelby:bootstrap start -->` line.)

- [ ] **Step 3: Verify**

Run:
```bash
F=~/.agents/claude/CLAUDE.md
grep -ci 'ponytail:ponytail\|ponytail last\|(4) `ponytail`' "$F"; echo "^ expect 0 (no plugin refs; the 'ponytail:' comment convention is allowed)"
grep -c '^## Engineering discipline$' "$F"; echo "^ expect 1"
grep -c '^[0-9]\. \*\*' "$F"; echo "^ expect 5"
grep -c 'shelby:bootstrap' "$F"; echo "^ expect 2"
grep -c 'Be direct\|Don.t over-deliver\|Questions are read-only' "$F"; echo "^ expect 0 (moved to House Style)"
```

- [ ] **Step 4: Check nothing else cites the old rule numbers**

Run:
```bash
grep -rniE 'rule (6|7|8)\b' ~/.agents/claude ~/.agents/skills ~/Projects/skills-n-stuff/plugins ~/Projects/skills-n-stuff/studio-baseline 2>/dev/null | grep -v 'docs/superpowers/plans' || echo "no stale rule-number references"
```
Expected: `no stale rule-number references`. If any appear, update them to the new numbers (delegate = 4, file naming = 5) and include the file in the commit.

- [ ] **Step 5: Commit**

```bash
cd ~/.agents
git add claude/CLAUDE.md
git commit -F - << 'EOF'
config: CLAUDE.md is law + engineering discipline; voice moves to House Style

- Rules 1/2/7 (be direct, don't over-deliver, questions read-only) removed:
  they now live in the House Style output style, which sits in the system
  prompt and is re-injected mid-session
- Ponytail plugin references removed from skill-precedence and one-reviewer
- One-reviewer gains: Codex-implemented change -> Claude-side review tier
- Delegate rule gains: codex claims unverified until re-run; routing.explore
- New "Engineering discipline" block carries the ponytail ladder, root-cause,
  runnable-check, and never-simplify rules — CLAUDE.md reaches every
  non-Explore sub-agent, so discipline now travels with dispatches

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 4: Retire the ponytail plugin (Repo B)

Ponytail's content now lives in House Style (voice) and CLAUDE.md (discipline). Disabling the plugin also removes its SessionStart injection (the "PONYTAIL MODE ACTIVE" block) — that hook ships inside the plugin, not in `settings.json`.

**Files:**
- Modify: `~/.agents/claude/settings.json` — remove `"ponytail@ponytail": true` from `enabledPlugins`; remove the `"ponytail": {...}` object from `extraKnownMarketplaces`.

**Interfaces:**
- Consumes: Tasks 2 and 3 (content already relocated).
- Produces: `settings.json` with no `ponytail` key anywhere. Task 8 verifies the next session has no PONYTAIL block.

- [ ] **Step 1: Locate the two entries**

Run:
```bash
grep -n 'ponytail' ~/.agents/claude/settings.json
```
Expected: exactly two regions — one line `"ponytail@ponytail": true,` (or without trailing comma if last) inside `enabledPlugins`, and a block inside `extraKnownMarketplaces` shaped like:
```json
    "ponytail": {
      "source": {
        "source": "github",
        "repo": "DietrichGebert/ponytail"
      }
    }
```

- [ ] **Step 2: Remove both with the Edit tool**

Delete the `enabledPlugins` line. Delete the whole `"ponytail": {…}` object from `extraKnownMarketplaces`. In each case, if the removed entry was the *last* item in its object, also remove the now-trailing comma from the new last item. Do not reformat the rest of the file (do not round-trip it through `json.dump` — the file contains non-ASCII characters and hand formatting that a dump would churn).

- [ ] **Step 3: Verify**

Run:
```bash
S=~/.agents/claude/settings.json
python3 -m json.tool "$S" > /dev/null && echo "valid JSON"
python3 - "$S" << 'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert not any('ponytail' in k for k in d.get('enabledPlugins',{})), 'still enabled'
assert 'ponytail' not in d.get('extraKnownMarketplaces',{}), 'marketplace still listed'
assert d.get('outputStyle')=='House Style'
print('ponytail gone; outputStyle House Style')
PY
cd ~/.agents && git diff --stat claude/settings.json
```
Expected: `valid JSON`, `ponytail gone; outputStyle House Style`, and the diff stat shows roughly `1 file changed, N deletions` with N ≤ 8 (small — if it shows the whole file changed, revert with `git checkout claude/settings.json` and redo Step 2 with the Edit tool).

- [ ] **Step 4: Commit**

```bash
cd ~/.agents
git add claude/settings.json
git commit -F - << 'EOF'
config: retire the ponytail plugin

Its voice rules live in the House Style output style and its engineering
discipline in CLAUDE.md now (system-prompt placement, wider sub-agent reach,
~1.5k fewer injected tokens per session). Removes enabledPlugins entry and
the DietrichGebert/ponytail marketplace source. The `ponytail:` comment
convention for marked shortcuts stays.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 5: `explore` routing key (Repo A + Repo B)

Read-only research/exploration is not implementation. It has no `swe`-relevant work, needs its findings back in the orchestrator's context (a codex handoff has no return channel worth the overhead), and is the one job where Sonnet is the right default. Add the key so it stops looking like a routing leak.

**Files:**
- Modify: `~/.agents/config/studio-moser/model-rubric.yml` — `routing:` block + sonnet anti-pattern note
- Modify: `~/Projects/skills-n-stuff/plugins/machine/skills/model-rubric/Default_Rubric.yml` — routing comment + sonnet note
- Modify: `~/Projects/skills-n-stuff/studio-baseline/Rubric_Setup.md` — step 7 bullet list
- Modify: `~/Projects/skills-n-stuff/plugins/pm/references/model-orchestration.md` — the "Routing keys:" paragraph (currently lines 36–39)

**Interfaces:**
- Produces: routing key name `explore` (exact). CLAUDE.md Rule 4 (Task 3) already references `routing.explore`.

- [ ] **Step 1: Personal rubric — add the key and rewrite the sonnet note**

In `~/.agents/config/studio-moser/model-rubric.yml`, inside `routing:`, add this line directly after the `quick:` line:
```yaml
  explore: claude-sonnet-5@high  # read-only research, codebase mapping, log digging. Native Agent only —
                                 # findings must land back in the orchestrator's context; a codex handoff
                                 # has no return channel worth the overhead. The only sonnet row today.
```
Then replace the sonnet anti-pattern comment (the four `#   - claude-sonnet-5 is a FALLBACK ONLY …` lines) with:
```yaml
#   - claude-sonnet-5 has two roles: the routing.explore default (read-only research), and an
#     implementer ONLY when the codex CLI is absent. For implementation, sol dominates it at every
#     tier — sonnet tops out ~49.6 SWE at max, below sol@medium (61), while burning Claude quota.
#     Bulk/mechanical/quick work goes to the via: codex rows (a pm:codex-* handoff, not an Agent call).
```

- [ ] **Step 2: Seed rubric — document `explore` and mirror the sonnet note**

In `~/Projects/skills-n-stuff/plugins/machine/skills/model-rubric/Default_Rubric.yml`, change the line
```
# House default once populated: taste_min: 9.
```
to
```
# House defaults once populated: taste_min: 9; explore: the cheapest reachable Claude row
#   (read-only research must return findings into the orchestrator's context — native Agent only).
```
and replace the sonnet anti-pattern lines
```
#   - sonnet-5 tops out ~49.6 swe at max — below sol@medium. Where codex exists it's a
#     FALLBACK ONLY: route bulk/mechanical/quick to the via:codex rows (a pm:codex-* handoff,
#     not an Agent call) and reach for Sonnet only when the codex CLI is absent.
```
with
```
#   - sonnet-5 tops out ~49.6 swe at max — below sol@medium. Two roles: the `explore` default
#     (read-only research, native Agent only), and an implementer only when the codex CLI is
#     absent. Bulk/mechanical/quick go to the via:codex rows (a pm:codex-* handoff, not an
#     Agent call).
```

- [ ] **Step 3: Rubric_Setup.md — add the bullet**

In `~/Projects/skills-n-stuff/studio-baseline/Rubric_Setup.md` step 7, after the `quick:` bullet, add:
```markdown
   - `explore:` read-only research and codebase mapping — the cheapest reachable Claude row. Native Agent only: findings must return into the orchestrator's context, and the built-in Explore agent is read-only. This is Sonnet's legitimate role even where codex exists.
```

- [ ] **Step 4: model-orchestration.md — add the key**

Change
```
Routing keys: `default` (everyday driver), `bulk` (clear-spec mechanical), `quick`
(latency-sensitive single steps), `batch` (unattended fan-out only — never route work
someone is waiting on), `taste_min` (floor for user-facing work), `review`,
`independent` (cross-vendor adversarial read — ask before spawning).
```
to
```
Routing keys: `default` (everyday driver), `bulk` (clear-spec mechanical), `quick`
(latency-sensitive single steps), `explore` (read-only research — native Agent only,
findings must return to the orchestrator), `batch` (unattended fan-out only — never
route work someone is waiting on), `taste_min` (floor for user-facing work), `review`,
`independent` (cross-vendor adversarial read — ask before spawning).
```

- [ ] **Step 5: Verify**

Run:
```bash
python3 -c "import yaml;d=yaml.safe_load(open('$HOME/.agents/config/studio-moser/model-rubric.yml'));assert d['routing']['explore']=='claude-sonnet-5@high';print('personal rubric ok')"
python3 -c "import yaml;yaml.safe_load(open('$HOME/Projects/skills-n-stuff/plugins/machine/skills/model-rubric/Default_Rubric.yml'));print('seed parses')"
grep -c '`explore:`' ~/Projects/skills-n-stuff/studio-baseline/Rubric_Setup.md
grep -c '`explore` (read-only' ~/Projects/skills-n-stuff/plugins/pm/references/model-orchestration.md
```
Expected: `personal rubric ok`, `seed parses`, `1`, `1`.

- [ ] **Step 6: Commit both repos**

```bash
cd ~/.agents && git add config/studio-moser/model-rubric.yml && git commit -F - << 'EOF'
config: add routing.explore (sonnet) for read-only research

Read-only exploration is not implementation: it needs its findings back in the
orchestrator's context, so it's a native Agent call, and it's the one job
where Sonnet is the right default. Sonnet note rewritten to name both roles.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
cd ~/Projects/skills-n-stuff && git add plugins/machine/skills/model-rubric/Default_Rubric.yml studio-baseline/Rubric_Setup.md plugins/pm/references/model-orchestration.md && git commit -F - << 'EOF'
rubric: document the explore routing key in seed, setup, and orchestration doctrine

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 6: `rubric-audit.sh` — measure routing instead of guessing (Repo A, TDD)

Turns the one-off transcript analysis into a repeatable script. Reads Claude Code session transcripts, tallies `Agent`/`Task` dispatches by the `model` param, and counts codex handoffs. Exit code signals findings so it composes with the other lint-style scripts.

**Files:**
- Create: `~/Projects/skills-n-stuff/plugins/machine/scripts/rubric-audit.sh`
- Test: `~/Projects/skills-n-stuff/plugins/machine/tests/rubric-audit.bats`

**Interfaces:**
- Produces: `rubric-audit.sh [--days N] [--projects DIR]` (defaults: 7, `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects`). Prints the report below to stdout. Exit `0` = clean; `1` = findings (any `UNSET` model or any `haiku` dispatch); `3` = python3 missing. Task 7 embeds this in `machine:sync`.

Report format (exact shape — the bats tests grep it):
```
Rubric audit — last 7 days, 12 session(s)
  Agent dispatches:  60 total — model set: 60, UNSET: 0
    by model:        fable 9 · opus 16 · sonnet 35 · haiku 0
  Codex handoffs:    3 (codex exec/review Bash calls: 2, pm:codex-* skills: 1)
```

Transcript facts the implementer needs (verified against real files):
- Sessions are `<projects>/<project-dir>/<session-id>.jsonl`. Sub-agent transcripts live under `<projects>/<project-dir>/<session-id>/subagents/agent-*.jsonl` and **must be excluded** (they're not dispatches, they're the dispatched work).
- Each line is a JSON object. Dispatches are lines with `"type":"assistant"` whose `message.content` is a list containing objects with `"type":"tool_use"` and `"name"` in `{"Task","Agent"}`; the model param is `input.model` (absent = UNSET).
- Codex handoffs: `tool_use` with `name=="Bash"` whose `input.command` matches the regex `(^|[^A-Za-z0-9_-])codex (exec|review)\b`, plus `tool_use` with `name=="Skill"` whose `input.skill` starts with `pm:codex-`.
- Some lines have no `message` key (types like `attachment`, `queue-operation`); skip anything that isn't `type=="assistant"` with a list `content`.

- [ ] **Step 1: Write the failing tests**

Create `~/Projects/skills-n-stuff/plugins/machine/tests/rubric-audit.bats`:

```bash
#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/rubric-audit.sh"
  PROJ="${BATS_TEST_TMPDIR}/projects/-Users-me-proj"
  mkdir -p "$PROJ/abc123/subagents"
}

# One transcript line: an assistant message carrying one tool_use block.
tool_use_line() { # name json-input
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"%s","input":%s}]}}\n' "$1" "$2"
}

write_fixture() {
  {
    printf '{"type":"queue-operation","operation":"x"}\n'
    printf '{"type":"user","message":{"role":"user","content":"hi"}}\n'
    tool_use_line Agent '{"subagent_type":"general-purpose","model":"sonnet","prompt":"p"}'
    tool_use_line Agent '{"subagent_type":"general-purpose","model":"fable","prompt":"p"}'
    tool_use_line Task  '{"subagent_type":"Explore","model":"opus","prompt":"p"}'
    tool_use_line Bash  '{"command":"codex exec -C /x -s workspace-write - < p.md > r.md"}'
    tool_use_line Bash  '{"command":"echo not-a-codex-call"}'
    tool_use_line Skill '{"skill":"pm:codex-review","args":""}'
    tool_use_line Skill '{"skill":"superpowers:brainstorming"}'
  } > "$PROJ/abc123.jsonl"
  # A sub-agent transcript that must NOT be counted as a dispatch.
  tool_use_line Agent '{"model":"haiku","prompt":"nested"}' > "$PROJ/abc123/subagents/agent-1.jsonl"
}

@test "clean fixture: totals, by-model line, handoffs, exit 0" {
  write_fixture
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 session(s)"* ]]
  echo "$output" | grep -qE 'Agent dispatches: +3 total — model set: 3, UNSET: 0'
  echo "$output" | grep -qE 'by model: +fable 1 · opus 1 · sonnet 1 · haiku 0'
  echo "$output" | grep -qE 'Codex handoffs: +2 \(codex exec/review Bash calls: 1, pm:codex-\* skills: 1\)'
}

@test "sub-agent transcripts are excluded from dispatch counts" {
  write_fixture
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'by model: +fable 1 · opus 1 · sonnet 1 · haiku 0'
  [[ "$output" != *"haiku 1"* ]]
}

@test "an UNSET model is counted and exits 1" {
  write_fixture
  tool_use_line Agent '{"subagent_type":"general-purpose","prompt":"no model"}' >> "$PROJ/abc123.jsonl"
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE 'Agent dispatches: +4 total — model set: 3, UNSET: 1'
}

@test "a haiku dispatch exits 1" {
  write_fixture
  tool_use_line Agent '{"model":"haiku","prompt":"p"}' >> "$PROJ/abc123.jsonl"
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE 'haiku 1'
}

@test "files older than --days are ignored" {
  write_fixture
  touch -t 202001010000 "$PROJ/abc123.jsonl"
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects" --days 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 session(s)"* ]]
  echo "$output" | grep -qE 'Agent dispatches: +0 total'
}

@test "missing projects dir reports 0 sessions, exit 0" {
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/nope"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 session(s)"* ]]
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run:
```bash
cd ~/Projects/skills-n-stuff/plugins/machine/tests && bats rubric-audit.bats
```
Expected: all 6 fail (script not found / not executable).

- [ ] **Step 3: Write the script**

Create `~/Projects/skills-n-stuff/plugins/machine/scripts/rubric-audit.sh` and `chmod +x` it:

```bash
#!/usr/bin/env bash
# Audit how sub-agents were actually routed, from Claude Code session transcripts.
# READ-ONLY. Tallies Agent/Task dispatches by their `model` param and counts codex
# handoffs (codex exec/review Bash calls + pm:codex-* skill invocations).
#
#   rubric-audit.sh [--days N] [--projects DIR]
#
# Defaults: --days 7, --projects ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects
# Exit 0 = clean. Exit 1 = findings (any UNSET model, or any haiku dispatch).
# Exit 3 = python3 not available (needed to parse JSONL portably).
set -euo pipefail

days=7
projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
while [ $# -gt 0 ]; do
  case "$1" in
    --days) days="$2"; shift 2 ;;
    --projects) projects="$2"; shift 2 ;;
    *) echo "rubric-audit.sh: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo "rubric-audit.sh: python3 required" >&2; exit 3; }

python3 - "$projects" "$days" << 'PY'
import json, os, re, sys, time
from collections import Counter

root, days = sys.argv[1], int(sys.argv[2])
cutoff = time.time() - days * 86400
CODEX_RE = re.compile(r'(^|[^A-Za-z0-9_-])codex (exec|review)\b')

sessions = 0
models = Counter()          # 'fable' | 'opus' | 'sonnet' | 'haiku' | other | 'UNSET'
codex_bash = codex_skill = 0

if os.path.isdir(root):
    for dirpath, dirnames, filenames in os.walk(root):
        # ponytail: skip sub-agent transcripts by path segment; they are the dispatched
        # work, not dispatches. Upgrade path if the layout changes: read isSidechain.
        if "/subagents" in dirpath.replace(os.sep, "/"):
            continue
        for fn in filenames:
            if not fn.endswith(".jsonl"):
                continue
            path = os.path.join(dirpath, fn)
            try:
                if os.path.getmtime(path) < cutoff:
                    continue
            except OSError:
                continue
            sessions += 1
            with open(path, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    try:
                        obj = json.loads(line)
                    except ValueError:
                        continue
                    if obj.get("type") != "assistant":
                        continue
                    content = (obj.get("message") or {}).get("content")
                    if not isinstance(content, list):
                        continue
                    for c in content:
                        if not isinstance(c, dict) or c.get("type") != "tool_use":
                            continue
                        name = c.get("name")
                        inp = c.get("input") or {}
                        if name in ("Task", "Agent"):
                            models[inp.get("model") or "UNSET"] += 1
                        elif name == "Bash" and CODEX_RE.search(inp.get("command") or ""):
                            codex_bash += 1
                        elif name == "Skill" and str(inp.get("skill") or "").startswith("pm:codex-"):
                            codex_skill += 1

total = sum(models.values())
unset = models.get("UNSET", 0)
by = " · ".join(f"{m} {models.get(m, 0)}" for m in ("fable", "opus", "sonnet", "haiku"))
print(f"Rubric audit — last {days} days, {sessions} session(s)")
print(f"  Agent dispatches:  {total} total — model set: {total - unset}, UNSET: {unset}")
print(f"    by model:        {by}")
print(f"  Codex handoffs:    {codex_bash + codex_skill} (codex exec/review Bash calls: {codex_bash}, pm:codex-* skills: {codex_skill})")
sys.exit(1 if (unset or models.get("haiku", 0)) else 0)
PY
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run:
```bash
chmod +x ~/Projects/skills-n-stuff/plugins/machine/scripts/rubric-audit.sh
cd ~/Projects/skills-n-stuff/plugins/machine/tests && bats rubric-audit.bats
```
Expected: `1..6`, all `ok`.

- [ ] **Step 5: Smoke-run against the real transcripts**

Run:
```bash
~/Projects/skills-n-stuff/plugins/machine/scripts/rubric-audit.sh --days 7; echo "exit $?"
```
Expected: a four-line report with real numbers and `exit 0` (or `exit 1` if any UNSET/haiku exist — that's a correct finding, not a bug).

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/skills-n-stuff
git add plugins/machine/scripts/rubric-audit.sh plugins/machine/tests/rubric-audit.bats
git commit -F - << 'EOF'
machine: add rubric-audit.sh — measure sub-agent routing from transcripts

Tallies Agent/Task dispatches by model param and counts codex handoffs
(codex exec/review Bash calls + pm:codex-* skills) over the last N days,
excluding sub-agent transcripts. Exit 1 on any UNSET model or haiku dispatch
so it composes with the other lint-style checks in machine:sync.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 7: Wire the audit into `machine:sync`, bump the plugin, push Repo A

**Files:**
- Modify: `~/Projects/skills-n-stuff/plugins/machine/skills/sync/SKILL.md` — insert a `## Phase 3.5: Rubric audit` section between `## Phase 3: Portability lint` and `## Phase 4: Report`; add a `Rubric:` line to the Phase 4 report block.
- Modify: `~/Projects/skills-n-stuff/plugins/machine/.claude-plugin/plugin.json` — `"version": "0.3.0"` → `"0.4.0"`
- Modify: `~/Projects/skills-n-stuff/.claude-plugin/marketplace.json` — the `machine` entry's version → `0.4.0`

**Interfaces:**
- Consumes: Task 6's `rubric-audit.sh` and its exit codes; Task 1's 7-entry `link-plan.sh`.
- Produces: machine plugin `0.4.0`, which is what other machines must install for the `output-styles` link and the audit to exist there.

- [ ] **Step 1: Insert Phase 3.5**

In `sync/SKILL.md`, directly before the line `## Phase 4: Report`, insert:

```markdown
## Phase 3.5: Rubric audit

```bash
machine="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/machine/*/ 2>/dev/null | sort -V | tail -1)}"; machine="${machine%/}"
"$machine/scripts/rubric-audit.sh" --days 7 || true
```

Read-only. Reports how sub-agents were actually routed over the last week: dispatches
by `model` param, `UNSET` count, haiku count, and codex handoffs. Exit `1` means a
finding — an omitted `model` (routing by inheritance) or a haiku dispatch — carry it
into the report. Exit `3` means python3 is missing; report `skipped: python3 not on
PATH`. Do not try to fix past dispatches; the point is to see drift, and to notice
when bulk work is landing on native sub-agents instead of the codex handoff.

---
```

- [ ] **Step 2: Add the report line**

In the Phase 4 report block, after the `  Lint:       {clean | N finding(s), M fixed}` line, add:
```
  Rubric:     {N dispatches, all explicit, 0 haiku, K codex handoffs |
               N dispatches: U unset, H haiku — see below | skipped: python3 not on PATH}
```
And in the prose paragraph beginning "If anything is unresolved, say so in the summary line", add this sentence at the end of the paragraph: `A rubric-audit finding (any UNSET or haiku dispatch) is unresolved in the same sense — list it, do not fold it into a clean summary.`

- [ ] **Step 3: Bump versions**

Run:
```bash
cd ~/Projects/skills-n-stuff
python3 - << 'PY'
import json,re
p="plugins/machine/.claude-plugin/plugin.json"
s=open(p).read(); assert '"version": "0.3.0"' in s
open(p,"w").write(s.replace('"version": "0.3.0"','"version": "0.4.0"',1))
m=".claude-plugin/marketplace.json"
d=json.load(open(m))
hits=[x for x in d["plugins"] if x.get("name")=="machine"]
assert len(hits)==1 and hits[0]["version"]=="0.3.0", hits
s=open(m).read()
# Replace only the version inside the machine entry: find its name, then the next "version".
i=s.index('"name": "machine"'); j=s.index('"version": "0.3.0"', i)
open(m,"w").write(s[:j]+'"version": "0.4.0"'+s[j+len('"version": "0.3.0"'):])
print("bumped")
PY
grep -n '"version"' plugins/machine/.claude-plugin/plugin.json
python3 -c "import json;print([x['version'] for x in json.load(open('.claude-plugin/marketplace.json'))['plugins'] if x['name']=='machine'])"
```
Expected: `bumped`, plugin.json shows `0.4.0`, marketplace prints `['0.4.0']`.

- [ ] **Step 4: Run the whole machine test suite**

Run:
```bash
~/Projects/skills-n-stuff/plugins/machine/tests/run-tests.sh
```
Expected: all `ok` across all `.bats` files (link-plan 12, rubric-audit 6, plus the pre-existing suites).

- [ ] **Step 5: Verify the SKILL.md edits landed**

Run:
```bash
S=~/Projects/skills-n-stuff/plugins/machine/skills/sync/SKILL.md
grep -n '^## Phase 3.5: Rubric audit$' "$S"
grep -n '^  Rubric:' "$S"
grep -c 'seven tracked entries' "$S"
```
Expected: one line number for each of the first two; `1` for the third.

- [ ] **Step 6: Commit and push Repo A**

```bash
cd ~/Projects/skills-n-stuff
git add plugins/machine/skills/sync/SKILL.md plugins/machine/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -F - << 'EOF'
machine 0.4.0: sync tracks output-styles and reports the rubric audit

- link-plan.sh: seventh tracked entry ~/.claude/output-styles -> claude/output-styles
- rubric-audit.sh: routing drift from transcripts, run as sync Phase 3.5 and
  surfaced on a Rubric: line in the report
- Machine_Setup.md / Rubric_Setup.md / model-orchestration.md: seven entries,
  explore routing key, codex-handoff-not-Agent-call

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
git pull --rebase --autostash && git push
git status -sb | head -1
```
Expected: push succeeds; status line is `## main...origin/main` with no ahead/behind.

---

### Task 8: Push Repo B, refresh this machine, prove the layer split

**Files:** none created. Verification only.

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Push Repo B**

```bash
cd ~/.agents && git pull --rebase --autostash && git push && git status -sb | head -1
```
Expected: `## main...origin/main`.

- [ ] **Step 2: Confirm all seven links are correct on this machine**

Run:
```bash
bash ~/Projects/skills-n-stuff/plugins/machine/scripts/link-plan.sh ~/.agents; echo "exit $?"
```
Expected: seven `ok` lines including `output-styles -> claude/output-styles ok`, `exit 0`.

- [ ] **Step 3: Update the installed machine plugin to 0.4.0**

Run `/machine:sync` in an interactive session (its Phase 2.5 reconciles installed plugins from the marketplace). Afterwards confirm the installed copy is the new one:
```bash
ls -d ~/.claude/plugins/cache/studio-moser/machine/*/ | sort -V | tail -1
```
Expected: a path ending in `/machine/0.4.0/`. If it still shows `0.3.0`, update the plugin through the Claude Code plugin UI and re-check. Until this shows `0.4.0`, other machines syncing will not auto-create the `output-styles` link — this step is not optional.

- [ ] **Step 4: Prove sub-agents receive the discipline block and not the output style**

Start a **new** session (the output style is read at session start; `/clear` also works). Then dispatch one sub-agent from the orchestrator (model must be set explicitly per Rule 4):

Agent call — `subagent_type: general-purpose`, `model: fable`, prompt exactly:
```
Do not use any tools. Answer two questions in two lines and nothing else.
1. Does your context contain a section titled "Engineering discipline"? Answer yes or no, and if yes, quote its first sentence.
2. Does your context contain the phrase "Clear, Concise, Actionable Communication"? Answer yes or no.
```
Expected: `1. yes — "Applies to every agent that loads this file, sub-agents included. …"` and `2. no`. That is the layer split working: CLAUDE.md reaches the sub-agent, the output style does not.

- [ ] **Step 5: Confirm the ponytail injection is gone and House Style is on**

In that same new session, check the system-reminder content at session start: there must be no `PONYTAIL MODE ACTIVE` block. Then ask the orchestrator: `What output style are you running under? One line.` Expected: `House Style`.

- [ ] **Step 6: Run the audit once as the new baseline**

```bash
~/Projects/skills-n-stuff/plugins/machine/scripts/rubric-audit.sh --days 7
```
Record the numbers in the session summary. Future `machine:sync` runs report the same line; the goal over the next week is codex handoffs > 0 and sonnet dispatches only where the description is exploration.

---

## Self-review

**Spec coverage.** Layer split (voice/discipline/routing) → Tasks 2, 3. Reference prompt reproduced verbatim with marked divergences → Task 2. Ponytail retired, content relocated → Tasks 2, 3, 4. `explore` key → Task 5. Repeatable audit → Task 6, wired in Task 7. Version bump so other machines get the link → Task 7. Sync of output-styles across machines → Task 1 (plumbing) + Task 8 Step 3 (plugin update). Empirical proof of sub-agent reach → Task 8 Step 4. Pending uncommitted work committed → Task 1. Both repos pushed → Tasks 7, 8. Not covered, by decision: `ponytail-review`/`-audit`/`-debt` are on-demand commands and are simply gone with the plugin; if you want an over-engineering review later, `/code-review` and `pm:code-reviewer` remain, and the `ponytail:` comment convention still greps.

**Placeholder scan.** No TBD/TODO. Every code step has its content. Task 4 Step 2 uses the Edit tool rather than a script by design (to avoid churning a hand-formatted JSON file) and states the trailing-comma rule explicitly.

**Name consistency.** Output style name `House Style` (Task 2 frontmatter, `settings.json`, Task 8 Step 5). Heading `## Engineering discipline` (Task 3, Task 8 Step 4). Routing key `explore` (Task 3 Rule 4 text, Task 5 all four files). Script `rubric-audit.sh` with `--days`/`--projects` and exit codes 0/1/3 (Task 6 script and tests, Task 7 Phase 3.5). Tracked entry `output-styles -> claude/output-styles` (Task 1, Task 8 Step 2). Machine plugin `0.4.0` (Task 7, Task 8 Step 3).
