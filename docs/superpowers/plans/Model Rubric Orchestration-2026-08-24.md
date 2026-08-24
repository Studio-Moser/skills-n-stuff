# Model Rubric Orchestration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Separate top-level orchestration preference from delegated execution routing and base implementation efficiency on successful benchmark work while supporting any reachable provider set.

**Architecture:** Extend the existing YAML rubric and prose-owned Harness resolver rather than introducing a second router. `routing.orchestrator` selects the preferred top-level model, delegated HarnessRequests keep their existing semantic routes, and setup derives only routes supported by discovered capabilities. Model rows retain user-owned trust and taste while storing auditable DeepSWE task economics beneath a `benchmark` map.

**Tech Stack:** Markdown skill and contract files, YAML seed configuration, Bash Automated Testing System (Bats), Python 3 assertion helpers, JSON plugin manifests.

**Spec:** `docs/superpowers/specs/Model Rubric Orchestration Design-2026-08-24.md`

## Global Constraints

- Fable is Tim's preferred orchestrator; Opus remains eligible but is not preferred for orchestration.
- Benchmark efficiency governs delegated software implementation, not orchestration, taste, exploration, or review by itself.
- Cost per successful task is `mean_task_cost_usd / pass_at_1`.
- Setup must work with Claude plus Codex, Claude only, Codex only, one reachable model-effort row, or no reachable row.
- `orchestrator`, `default`, `quick`, and `review` are required; all other routes are optional.
- A running agent cannot replace itself; `routing.orchestrator` is actionable only when the host can select the top-level model and advisory otherwise.
- No route may name an unavailable provider or `via` executor.
- Do not add a YAML parser or another runtime dependency; Harness routing remains skill-driven.
- Preserve the existing HarnessRequest and HarnessResult schemas for delegated operations.

---

## File Map

- `plugins/harness/references/routing.md` — canonical meaning of orchestration, delegated routes, fallback, and capability degradation.
- `plugins/harness/references/harness-contract.md` — boundary between the top-level orchestrator and delegated HarnessRequests.
- `plugins/harness/skills/model-rubric/SKILL.md` — live evidence collection, interview, migration, derivation, and validation procedure.
- `plugins/harness/skills/model-rubric/Default_Rubric.yml` — distributable candidate rows and current public benchmark observations; never Tim's personal routes.
- `plugins/harness/tests/reference-contracts.bats` — executable prose contract for orchestration and delegated-request boundaries.
- `plugins/harness/tests/skill-contracts.bats` — executable setup, migration, capability, and validation contract.
- `plugins/harness/tests/model-rubric-contracts.bats` — seed schema and benchmark-arithmetic checks.
- `plugins/harness/tests/run-tests.sh` — includes the new contract test in the suite if test discovery is explicit.
- `plugins/harness/README.md` and `README.md` — public description of capability-driven orchestration.
- `plugins/harness/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` — Harness feature release version.

---

### Task 1: Define the Orchestration Contract

**Files:**
- Modify: `plugins/harness/tests/reference-contracts.bats`
- Modify: `plugins/harness/references/routing.md`
- Modify: `plugins/harness/references/harness-contract.md`

**Interfaces:**
- Consumes: existing `HarnessRequest.route` delegated route set and typed resolution outcomes.
- Produces: canonical `routing.orchestrator` and `routing.fallback` semantics for the rubric skill and documentation.

- [ ] **Step 1: Add failing contract assertions**

Extend the Python assertion block in `reference-contracts.bats` with these exact clauses:

```python
require_clause(
    routing,
    "`orchestrator` selects the preferred model for the top-level session; it is not a delegated HarnessRequest route.",
)
require_clause(
    routing,
    "A running agent never replaces itself to satisfy `routing.orchestrator`.",
)
require_clause(
    routing,
    "`fallback` names an eligible general fallback but never authorizes an automatic fallback or escalation.",
)
require_clause(
    routing,
    "Provider diversity is optional; a single reachable model-effort row may satisfy every required route.",
)
require_clause(
    contract,
    "The top-level orchestrator owns the user conversation, scope, approvals, delegation graph, and final acceptance decision.",
)
```

Keep the parsed `HarnessRequest.route` schema unchanged:

```text
bulk | quick | default | taste | batch | review | independent
```

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```bash
bats plugins/harness/tests/reference-contracts.bats
```

Expected: FAIL with `missing contract clause` for `orchestrator`.

- [ ] **Step 3: Add the minimal contract prose**

In `routing.md`, add a distinct `Top-level orchestration` section before
`Semantic routes` containing the asserted clauses and these rules:

```markdown
- `routing.orchestrator` is used when a host starts a top-level session and supports explicit model selection.
- If the host cannot switch the running model, report the preference as advisory and continue resolving delegated routes.
- The orchestrator retains context and delegates bounded work so expensive judgment tokens do not absorb execution volume.
- `routing.fallback` is optional and still requires caller authorization under the existing typed fallback rules.
```

In `harness-contract.md`, add one paragraph before `HarnessRequest` stating that
the top-level orchestrator owns the user conversation, scope, approvals,
delegation graph, and final acceptance decision, while each HarnessRequest
describes one delegated operation. Do not add `orchestrator` to the request
schema.

- [ ] **Step 4: Run the focused tests**

Run:

```bash
bats plugins/harness/tests/reference-contracts.bats
```

Expected: `1..1` and `ok 1 references define the provider-neutral Harness contract`.

- [ ] **Step 5: Commit the contract**

```bash
git add plugins/harness/references/routing.md \
  plugins/harness/references/harness-contract.md \
  plugins/harness/tests/reference-contracts.bats
git commit -m "feat(harness): separate orchestration from delegated routing"
```

---

### Task 2: Replace Token-Price Scoring with Work Efficiency

**Files:**
- Create: `plugins/harness/tests/model-rubric-contracts.bats`
- Modify: `plugins/harness/skills/model-rubric/Default_Rubric.yml`
- Modify: `plugins/harness/tests/run-tests.sh` only if it enumerates test files rather than running `*.bats`.

**Interfaces:**
- Consumes: current DeepSWE v1.1 fields captured on 2026-08-24.
- Produces: seed rows with `provider`, user-owned `trust`, derived `efficiency`, and auditable `benchmark` evidence.

- [ ] **Step 1: Write a failing seed-schema test**

Create `model-rubric-contracts.bats` with a test that reads
`Default_Rubric.yml` and asserts:

```python
from pathlib import Path
import re

text = Path(seed_path).read_text()
for field in (
    "provider:", "trust:", "efficiency:", "benchmark:", "suite: deepswe",
    "pass_at_1:", "mean_task_cost_usd:", "cost_per_success_usd:",
    "mean_output_tokens:", "mean_duration_seconds:",
):
    assert field in text, f"seed missing {field}"
assert not re.search(r"(?m)^\s+cost:\s", text), "legacy model cost score remains"
assert "gpt-5.6-terra" in text, "current delegated candidate missing"
```

Add a second test that extracts every benchmark block with this expression:

```python
pattern = re.compile(
    r"pass_at_1:\s*([0-9.]+).*?"
    r"mean_task_cost_usd:\s*([0-9.]+).*?"
    r"cost_per_success_usd:\s*([0-9.]+)",
    re.S,
)
rows = pattern.findall(text)
assert rows, "no benchmark observations"
for pass_at_1, task_cost, cost_per_success in rows:
    expected = float(task_cost) / float(pass_at_1)
    assert abs(expected - float(cost_per_success)) <= 0.02
```

- [ ] **Step 2: Run the new test and verify failure**

Run:

```bash
bats plugins/harness/tests/model-rubric-contracts.bats
```

Expected: FAIL because the seed still uses `cost` and lacks benchmark blocks.

- [ ] **Step 3: Rewrite the seed rows**

Use readable block YAML. Every candidate row gets `name`, `effort`, `provider`,
`via` when external, `intelligence`, `taste`, `trust: null`,
`efficiency: null`, and a benchmark block when DeepSWE measured it. Include at
least these current rows and observations:

```yaml
- name: gpt-5.6-luna
  effort: max
  provider: openai
  via: codex
  intelligence: 8
  taste: 5
  trust: null
  efficiency: null
  benchmark: { suite: deepswe, version: "1.1", observed: 2026-08-24, pass_at_1: 0.672, mean_task_cost_usd: 0.61, cost_per_success_usd: 0.91, mean_output_tokens: 73000, mean_duration_seconds: 1122 }
- name: gpt-5.6-sol
  effort: medium
  provider: openai
  via: codex
  intelligence: 8
  taste: 8
  trust: null
  efficiency: null
  benchmark: { suite: deepswe, version: "1.1", observed: 2026-08-24, pass_at_1: 0.611, mean_task_cost_usd: 1.86, cost_per_success_usd: 3.04, mean_output_tokens: 18000, mean_duration_seconds: 426 }
- name: gpt-5.6-terra
  effort: high
  provider: openai
  via: codex
  intelligence: 7
  taste: 7
  trust: null
  efficiency: null
  benchmark: { suite: deepswe, version: "1.1", observed: 2026-08-24, pass_at_1: 0.538, mean_task_cost_usd: 0.91, cost_per_success_usd: 1.69, mean_output_tokens: 22000, mean_duration_seconds: 366 }
- name: claude-fable-5
  effort: high
  provider: anthropic
  intelligence: 10
  taste: 10
  trust: null
  efficiency: null
  benchmark: { suite: deepswe, version: "1.1", observed: 2026-08-24, pass_at_1: 0.686, mean_task_cost_usd: 9.18, cost_per_success_usd: 13.38, mean_output_tokens: 57000, mean_duration_seconds: 1062 }
- name: claude-opus-5
  effort: high
  provider: anthropic
  intelligence: 9
  taste: 9
  trust: null
  efficiency: null
  benchmark: { suite: deepswe, version: "1.1", observed: 2026-08-24, pass_at_1: 0.728, mean_task_cost_usd: 6.08, cost_per_success_usd: 8.35, mean_output_tokens: 64000, mean_duration_seconds: 1164 }
```

Retain the needed Sol low/high and Sonnet high candidate rows using the same
schema. Remove the claim that Fable is cheaper than Opus. Replace it with:

```yaml
# Coding-benchmark efficiency never overrides user-owned orchestration trust or taste.
```

- [ ] **Step 4: Run the seed contract test**

Run:

```bash
bats plugins/harness/tests/model-rubric-contracts.bats
```

Expected: all tests pass and every derived cost differs by no more than `$0.02`.

- [ ] **Step 5: Commit the evidence schema**

```bash
git add plugins/harness/skills/model-rubric/Default_Rubric.yml \
  plugins/harness/tests/model-rubric-contracts.bats \
  plugins/harness/tests/run-tests.sh
git commit -m "feat(harness): score models by successful benchmark work"
```

Do not stage `run-tests.sh` if it required no change.

---

### Task 3: Make Rubric Setup Capability-Driven

**Files:**
- Modify: `plugins/harness/tests/skill-contracts.bats`
- Modify: `plugins/harness/skills/model-rubric/SKILL.md`

**Interfaces:**
- Consumes: the Task 2 model-row schema and capability inventory supplied by `harness:setup`.
- Produces: a validated personalized rubric with required routes and only reachable optional routes.

- [ ] **Step 1: Add failing procedure assertions**

Extend the model-rubric test in `skill-contracts.bats` to require these clauses:

```python
for clause in (
    "cost per successful task",
    "`mean_task_cost_usd / pass_at_1`",
    "`routing.orchestrator`",
    "orchestration preference",
    "`orchestrator`, `default`, `quick`, and `review` are required",
    "Provider diversity is an optimization, not a setup prerequisite",
    "Claude and Codex",
    "Claude only",
    "Codex only",
    "one reachable model-effort row",
    "no reachable model-effort row",
    "Opus remains eligible",
    "A running agent cannot replace itself",
):
    assert clause in normalized, f"model-rubric missing procedure: {clause}"
```

Also assert the completed-rubric example contains `provider`, `trust`,
`efficiency`, `benchmark`, `orchestrator`, and `fallback`.

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```bash
bats plugins/harness/tests/skill-contracts.bats
```

Expected: the model-rubric contract test fails on the first new clause.

- [ ] **Step 3: Update evidence collection and the interview**

Change the skill so list prices are source inputs and DeepSWE's observed
`pass_at_1`, task cost, output tokens, steps, and duration are the software-work
comparison. Define cost per successful task exactly as
`mean_task_cost_usd / pass_at_1` and preserve the source version and observation
date.

Add `orchestration preference` to the first-time interview after trust. State
that benchmark rank cannot override an explicit trust or taste preference for
orchestration, review, or user-facing work.

- [ ] **Step 4: Define derivation and degradation exactly**

Replace the existing route list with:

```markdown
- required `routing.orchestrator`: preferred trusted top-level row;
- required `routing.default`: ordinary delegated work;
- required `routing.quick`: short latency-sensitive delegated work;
- required `routing.review`: strongest trusted non-wasteful fixed-target reviewer;
- optional `routing.bulk`, `routing.explore`, `routing.batch`, `routing.taste`,
  `routing.independent`, and `routing.fallback` when their semantics are reachable.
```

Then add the five capability cases from the spec verbatim. Make these outcomes
explicit:

```text
Claude and Codex -> cross-provider routes are allowed but not required.
Claude only -> derive required routes from Claude and omit impossible independence.
Codex only -> derive required routes from Codex and require no native-Claude explore route.
one reachable model-effort row -> reuse it for required routes and omit optional routes.
no reachable model-effort row -> block and do not write a valid-looking rubric.
```

State that Provider diversity is an optimization, not a setup prerequisite.

- [ ] **Step 5: Add migration and validation behavior**

For rubrics without `routing.orchestrator`, require an explicit preference
question. Preserve capabilities, trust, taste, and billing semantics; refresh
benchmark evidence; replace `cost` with `efficiency`; and rederive routes.

Validation must reject a completed rubric when a required route is absent, a
route lacks an exact row, a `via` executor is unavailable, a benchmark division
is inconsistent beyond rounding, or no row is reachable. Optional unavailable
routes are omitted. State that Opus remains eligible when reachable and trusted,
but never outranks a user's Fable orchestration preference through coding cost
alone. State that a running agent cannot replace itself.

- [ ] **Step 6: Run focused Harness tests**

Run:

```bash
bats plugins/harness/tests/skill-contracts.bats
bats plugins/harness/tests/model-rubric-contracts.bats
```

Expected: all tests pass.

- [ ] **Step 7: Commit setup behavior**

```bash
git add plugins/harness/skills/model-rubric/SKILL.md \
  plugins/harness/tests/skill-contracts.bats
git commit -m "feat(harness): derive rubric routes from available executors"
```

---

### Task 4: Document and Release the New Rubric

**Files:**
- Modify: `plugins/harness/README.md`
- Modify: `README.md`
- Modify: `plugins/harness/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `plugins/harness/tests/version-consistency.bats` only if the current test fixture pins the prior Harness version.

**Interfaces:**
- Consumes: Tasks 1–3 contract and setup behavior.
- Produces: discoverable Harness 0.7.0 release metadata and concise public guidance.

- [ ] **Step 1: Add the user-facing documentation**

In `plugins/harness/README.md`, describe the rubric in one paragraph:

```markdown
The rubric separates the preferred top-level orchestrator from delegated routes.
Setup derives both from the models and executors actually available on that
machine; Claude plus Codex enables cross-provider delegation, while either
provider alone still produces a valid rubric. Software-work efficiency uses
benchmark cost per successful task rather than token list price alone.
```

Update the root README's `/harness:model-rubric` bullet to say it configures
capability-driven orchestration and delegated routing.

- [ ] **Step 2: Bump Harness to 0.7.0**

Set both version fields to `0.7.0`:

```json
"version": "0.7.0"
```

Do not change PM, Product Pulse, or unrelated plugin versions.

- [ ] **Step 3: Run documentation and version tests**

Run:

```bash
bats plugins/harness/tests/documentation-boundary.bats
bats plugins/harness/tests/version-consistency.bats
```

Expected: all tests pass and Harness reports version `0.7.0` in both manifests.

- [ ] **Step 4: Run the complete Harness suite**

Run:

```bash
plugins/harness/tests/run-tests.sh
```

Expected: every test passes; the baseline before implementation was 160 tests.

- [ ] **Step 5: Check the complete diff and secrets boundary**

Run:

```bash
git diff --check origin/main...HEAD
git status --short
git log --oneline origin/main..HEAD
rg -n '(api[_-]?key|token|secret|password)\s*[:=]\s*[^<[:space:]]+' \
  plugins/harness README.md .claude-plugin/marketplace.json || true
```

Expected: no whitespace errors, only planned files changed, only task commits
present, and no credential value in the diff. Words that describe the secret
boundary are allowed.

- [ ] **Step 6: Commit the release metadata**

```bash
git add plugins/harness/README.md README.md \
  plugins/harness/.claude-plugin/plugin.json \
  .claude-plugin/marketplace.json \
  plugins/harness/tests/version-consistency.bats
git commit -m "docs(harness): publish capability-aware routing guidance"
```

Do not stage `version-consistency.bats` if it required no change.

---

### Task 5: Review, Integrate, and Refresh Tim's Synced Rubric

**Files:**
- Review: the fixed feature-branch commit produced by Tasks 1–4.
- Modify after release: `/Users/timmoser/.agents/config/studio-moser/model-rubric.yml`

**Interfaces:**
- Consumes: released Harness 0.7.0 and Tim's confirmed Claude-plus-Codex capabilities.
- Produces: merged public Harness behavior plus Tim's synced personal routing.

- [ ] **Step 1: Freeze and review the implementation target**

Record the feature branch HEAD:

```bash
git rev-parse HEAD
```

Run `harness:review` against that exact SHA using the configured review route.
The review must check spec coverage, capability degradation, benchmark arithmetic,
and the absence of provider assumptions.

- [ ] **Step 2: Reproduce review evidence**

Run:

```bash
plugins/harness/tests/run-tests.sh
git diff --check origin/main...HEAD
```

Expected: the complete suite passes and the diff has no whitespace errors.

- [ ] **Step 3: Open and merge the pull request**

Use this PR structure:

```markdown
## What
- Separate preferred orchestration from delegated execution routes.
- Score implementation models using successful benchmark work.
- Derive valid rubrics for single-provider and multi-provider setups.

## Why
Token price alone does not measure the cost of completed agent work, and the old
default route conflated orchestration with execution.

## Testing
- `plugins/harness/tests/run-tests.sh`
- `git diff --check origin/main...HEAD`
```

Merge only after checks and review are clean.

- [ ] **Step 4: Install Harness 0.7.0 and refresh Tim's rubric**

Install the merged plugin through the existing Studio Moser marketplace, then
run `harness:model-rubric`. Confirm Tim's resulting routes are:

```yaml
routing:
  orchestrator: claude-fable-5@high
  default: gpt-5.6-sol@medium
  bulk: gpt-5.6-terra@high
  quick: gpt-5.6-sol@low
  explore: claude-sonnet-5@high
  batch: gpt-5.6-luna@max
  taste_min: 9
  taste: claude-fable-5@high
  review: claude-fable-5@high
  independent: gpt-5.6-sol@high
  fallback: claude-opus-5@high
```

Keep Opus eligible in `models`. Record Tim's Fable-over-Opus orchestration
preference in the rubric comments. Validate all route rows and benchmark
arithmetic before writing.

- [ ] **Step 5: Sync the private agents repository**

Run `harness:sync` in full mode so the rubric change is committed and pushed
through `/Users/timmoser/.agents`. Confirm the final report shows clean links,
clean lint, a clean worktree, and local HEAD equal to the remote SHA.

- [ ] **Step 6: Verify installed behavior**

Run a final Harness dry run and rubric validation. Expected:

```text
Harness 0.7.0 installed
rubric reviewed: 2026-08-24
Claude capability reachable
Codex capability reachable
all emitted routes resolve
working trees clean
```
